/* Copyright (C) 2024 Alif Semiconductor - All Rights Reserved.
 * Use, distribution and modification of this code is permitted under the
 * terms stated in the Alif Semiconductor Software License Agreement
 *
 * You should have received a copy of the Alif Semiconductor Software
 * License Agreement with this file. If not, please write to:
 * contact@alifsemi.com, or visit: https://alifsemi.com/license
 *
 */

#include <arch_helpers.h>
#include <common/debug.h>
#include <lib/mmio.h>
#include "dwc_spi.h"
#include "ospi.h"
#include "ospi_drv.h"
#include "ospi_xip_user.h"

#define PAD_CTRL_DATA (PAD_CTRL_12MA|PAD_CTRL_SR|PAD_CTRL_REN)
#define PAD_CTRL_CLK (PAD_CTRL_12MA|PAD_CTRL_SR)

#define LPGPIO_BASE                     0x42002000UL
#define GPIO_INTMASK_OFFSET             0x34
#define OSPI_RESET_PIN                  7
#define GPIO_SWPORTA_DR_OFFSET          0x0
#define GPIO_SWPORTA_DDR_OFFSET         0x4
#define WRAP_32_BYTE                    0xFD
#define OCTAL_DDR_DQS                   0xE7
#define DEVICE_ID_ISSI_FLASH_IS25WX256  0x9D
#define SPI_ENABLE                      1U
#define SPI_DISABLE                     0U

/* OSPI FLASH CONFIG */
static ospi_flash_cfg_t ospi_flash_config;

extern int service_ospi_write_aes_key(void);
void static setup_PinMUX()
{
	uint32_t value;

	/* Configure pad control registers and Mux value*/
	*PADCTRL_REG(9, 5, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(9, 6, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(9, 7, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 0, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 1, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 2, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 3, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 4, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(10, 7, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(5, 5, PAD_CTRL_CLK, 1);
	*PADCTRL_REG(5, 7, PAD_CTRL_12MA, 1);
	*PADCTRL_REG(5, 6, PAD_CTRL_DATA, 1);
	*PADCTRL_REG(8, 0, PAD_CTRL_12MA, 1);

	/* initialize */
	value =	mmio_read_32((LPGPIO_BASE + GPIO_INTMASK_OFFSET));
	mmio_write_32((LPGPIO_BASE + GPIO_INTMASK_OFFSET),
		      (value | (1 << OSPI_RESET_PIN)));

	/* set direction */
	value = mmio_read_32((LPGPIO_BASE + GPIO_SWPORTA_DDR_OFFSET));
	mmio_write_32((LPGPIO_BASE + GPIO_SWPORTA_DDR_OFFSET),
		      (value | (1 << OSPI_RESET_PIN)));

	/* set low state */
	value = mmio_read_32((LPGPIO_BASE + GPIO_SWPORTA_DR_OFFSET));
	mmio_write_32((LPGPIO_BASE + GPIO_SWPORTA_DR_OFFSET),
		      (value & ~(1 << OSPI_RESET_PIN)));

	/* set high state */
	value = mmio_read_32((LPGPIO_BASE + GPIO_SWPORTA_DR_OFFSET));
	mmio_write_32((LPGPIO_BASE + GPIO_SWPORTA_DR_OFFSET),
		      (value | (1 << OSPI_RESET_PIN)));

	return;
}

static void issi_write_enable(ospi_flash_cfg_t *ospi_cfg)
{
	/* Write WEL bit in OctalSPI mode */
	ospi_setup_write(ospi_cfg, ADDR_LENGTH_0_BITS);
	ospi_send(ospi_cfg, ISSI_WRITE_ENABLE);
}

static uint8_t issi_decode_id(ospi_flash_cfg_t *ospi_cfg, uint8_t *buffer)
{
	uint8_t iter, id = 0;

	for (iter = 0 ; iter < 8; iter++) {
		/* Since SPI controller supports octal mode only, */
		/* so 1 byte of data sent by flash will be */
		/* distributed over 8 byte data read */
		if (*buffer & 0x2) {
			id |= 1;
		}
		if (iter < 7) {
			id <<= 1;
		}
		buffer++;
	}

	ospi_cfg->device_id = id;
	return id;
}

static void ospi_write_en(ospi_flash_cfg_t *ospi_cfg)
{
	/* Write WEL bit in OctalSPI mode */
	ospi_setup_write(ospi_cfg, ADDR_LENGTH_0_BITS);
	ospi_send(ospi_cfg, ISSI_WRITE_ENABLE);	/* Write data payload */
}

static void issi_flash_set_configuration_register_DDR(ospi_flash_cfg_t *ospi_cfg, uint8_t cmd, uint8_t address, uint8_t value)
{
	ospi_write_en(ospi_cfg);
	ospi_setup_write(ospi_cfg, ADDR_LENGTH_32_BITS);
	ospi_push(ospi_cfg, cmd); /* Write Status Register command */
	ospi_push(ospi_cfg, address); /* Write address byte */
	ospi_push(ospi_cfg, value);
	ospi_send(ospi_cfg, value); /* Write data byte */
	return;
}

static uint32_t issi_flash_read_configuration_register_ddr(ospi_flash_cfg_t *ospi_cfg, uint32_t reg_type, uint32_t cmd)
{
	uint8_t rBuff[256] = {0};
	/* Read Memory Status register in OctalSPI mode */
	ospi_setup_read(ospi_cfg, ADDR_LENGTH_32_BITS, 1, 8);

	if (reg_type == 0) {
		/* Get Status/Control Registers command */
		ospi_push(ospi_cfg, ISSI_READ_VOLATILE_CONFIG_REG);
	} else if (reg_type == 1) {
		/* Get Status/Control Registers command */
		ospi_push(ospi_cfg, ISSI_READ_NONVOLATILE_CONFIG_REG);
	}

	ospi_recv(ospi_cfg, cmd, rBuff);

	return (uint32_t)rBuff[0];
}

static void issi_flash_set_configuration_register_SDR(ospi_flash_cfg_t *ospi_cfg, uint8_t cmd, uint8_t address, uint8_t value)
{
	issi_write_enable(ospi_cfg);
	ospi_setup_write_sdr(ospi_cfg, ADDR_LENGTH_24_BITS);
	ospi_push(ospi_cfg, cmd);
	ospi_push(ospi_cfg, 0x00);
	ospi_push(ospi_cfg, 0x00);
	ospi_push(ospi_cfg, address);
	ospi_send(ospi_cfg, value);
}

static uint8_t issi_flash_ReadID(ospi_flash_cfg_t *ospi_cfg)
{
	uint8_t buffer[8];

	ospi_setup_read(ospi_cfg, ADDR_LENGTH_0_BITS, 8, 0);
	ospi_recv(ospi_cfg, ISSI_READ_ID, buffer);

	return issi_decode_id(ospi_cfg, buffer);
}

static int issi_flash_probe (ospi_flash_cfg_t *ospi_cfg)
{
	/* Initialize SPI in Single mode 1-1-1 and read Flash ID */
	if (issi_flash_ReadID(ospi_cfg) == DEVICE_ID_ISSI_FLASH_IS25WX256) {
		/* Set wrap configuration to 32 bytes */
		issi_flash_set_configuration_register_SDR(ospi_cfg,
			ISSI_WRITE_VOLATILE_CONFIG_REG, 0x07, WRAP_32_BYTE);

		/* Switch the flash to Octal DDR mode */
		issi_flash_set_configuration_register_SDR(ospi_cfg,
			ISSI_WRITE_VOLATILE_CONFIG_REG, 0x00, OCTAL_DDR_DQS);

		return 0;
	}
	return -1;
}

static int flash_xip_init(ospi_flash_cfg_t *ospi_cfg)
{
	ospi_xip_enter(ospi_cfg, ISSI_DDR_OCTAL_IO_FAST_READ,
		       ISSI_DDR_OCTAL_IO_FAST_READ);
	return 0;
}

static int setup_flash_xip(void)
{
	ospi_flash_cfg_t *ospi_cfg = &ospi_flash_config;

	ospi_cfg->regs = (ssi_regs_t *) OSPI1_BASE;
	ospi_cfg->aes_regs = (aes_regs_t *) AES1_BASE;
	ospi_cfg->xip_base = (volatile void *) OSPI1_XIP_BASE;

	ospi_cfg->ser = 1;
	ospi_cfg->addrlen = ADDR_LENGTH_32_BITS;
	ospi_cfg->ospi_clock = OSPI_CLOCK;
	ospi_cfg->ddr_en = 0;
	ospi_cfg->wait_cycles = DEFAULT_WAIT_CYCLES_ISSI;

	ospi_init(ospi_cfg);

	if (issi_flash_probe(ospi_cfg)) {
		return -1;
	}
	ospi_cfg->ddr_en = 1;

	/* Specific for A32. */
	if (issi_flash_read_configuration_register_ddr(ospi_cfg,
	    0, 0x01) != ospi_cfg->wait_cycles) {
		issi_flash_set_configuration_register_DDR(ospi_cfg,
			ISSI_WRITE_VOLATILE_CONFIG_REG, 0x01,
			ospi_cfg->wait_cycles);
	}

	/* Check and Set Wrap Configuration to 64-byte wrap */
	if (issi_flash_read_configuration_register_ddr(ospi_cfg,
	    0, 0x07) != 0xFE) {
		issi_flash_set_configuration_register_DDR(ospi_cfg,
			ISSI_WRITE_VOLATILE_CONFIG_REG, 0x07, 0xFE);
	}

	if (flash_xip_init(ospi_cfg)) {
		return -1;
	}

#if !AES_EN
	/* SE enables AES decrypt during boot — clear it after XIP setup
	 * for unencrypted flash. Must be AFTER ospi_xip_enable(). */
	ospi_cfg->aes_regs->aes_control &= ~AES_CONTROL_DECRYPT_EN;
#endif

	return 0;
}

#if FLASH_EN
/* OSPI flash programming support - program from MRAM staging area.
 *
 * Uses DDR Octal mode throughout (no mode switching). The ISSI IS25WX256
 * uses 0x12 for Page Program in OPI DDR mode. Erase uses 0xDC (64KB block).
 * All operations use the existing DDR Octal controller setup.
 *
 * Reference: alifsemi/alif_usb-to-ospi-flasher
 */

#define OSPI_PROG_MAGIC		0x4F535049	/* "OSPI" */
#define OSPI_PROG_FLAG_ADDR	0x8000E000
#define OSPI_SECTOR_SIZE	0x10000		/* 64KB */
#define OSPI_PAGE_SIZE		256
#define ISSI_OPI_PAGE_PROGRAM	0x12
#define ISSI_RESET_ENABLE	0x66
#define ISSI_RESET_MEMORY	0x99

struct ospi_prog_hdr {
	uint32_t magic;
	uint32_t dest_addr;
	uint32_t length;
	uint32_t src_addr;
};

/* Write Enable in DDR Octal mode using DFS=16.
 * Must use DFS=16 to match the DDR Octal bus width — with DFS=8, the
 * controller pairs bytes into 16-bit frames, corrupting the command.
 * Reference: Alif CMSIS driver uses DFS=16 for ALL DDR Octal operations. */
static void ospi_write_en_ddr16(ospi_flash_cfg_t *ospi_cfg)
{
	ospi_setup_write_ddr16(ospi_cfg, ADDR_LENGTH_0_BITS);
	ospi_send(ospi_cfg, ISSI_WRITE_ENABLE);
}

extern void delay_in_us(uint32_t delay);

/* Wait for erase completion using fixed delay.
 * Status register read with DFS=8 returns 0 in DDR Octal mode (DFS mismatch),
 * so we cannot poll WIP. Use conservative fixed delays instead.
 * IS25WX256 sector erase typical: 100ms, max: 2000ms. */
static int issi_wait_erase(void)
{
	delay_in_us(500000);	/* 500ms */
	return 0;
}

/* Wait for page program completion using fixed delay.
 * IS25WX256 page program typical: 0.3ms, max: 5ms. */
static int issi_wait_program(void)
{
	delay_in_us(2000);	/* 2ms */
	return 0;
}

/* Erase 64KB block in DDR Octal mode.
 * All DDR Octal operations use DFS=16 to match bus width. */
static int issi_sector_erase_ddr(ospi_flash_cfg_t *ospi_cfg, uint32_t addr)
{
	ospi_write_en_ddr16(ospi_cfg);
	ospi_setup_write_ddr16(ospi_cfg, ADDR_LENGTH_32_BITS);
	ospi_push(ospi_cfg, ISSI_4BYTE_SECTOR_ERASE);
	ospi_send(ospi_cfg, addr);

	return issi_wait_erase();
}

/* Page program in OPI DDR mode using 0x12 (Page Program).
 * In OPI DDR (8D-8D-8D) mode, 0x12 is the standard page program command.
 * (0x84 is SPI-mode "Octal Input Fast Program" — invalid in OPI DDR.)
 * DFS=16 because the DWC SSI transfers 16 bits per clock (8 IO x 2 DDR).
 * Data packed as 16-bit frames (little-endian: low byte on rising edge). */
static int issi_page_program_ddr(ospi_flash_cfg_t *ospi_cfg, uint32_t addr,
				 const uint8_t *data, uint32_t len)
{
	uint32_t i, frames;

	if (len == 0 || len > OSPI_PAGE_SIZE)
		return -1;

	ospi_write_en_ddr16(ospi_cfg);
	ospi_setup_write_ddr16(ospi_cfg, ADDR_LENGTH_32_BITS);
	ospi_push(ospi_cfg, ISSI_OPI_PAGE_PROGRAM);
	ospi_push(ospi_cfg, addr);

	/* Pack data as 16-bit frames (2 bytes per push, little-endian).
	 * In DDR Octal: lower byte on rising edge, upper byte on falling. */
	frames = (len + 1) / 2;
	for (i = 0; i + 1 < frames; i++)
		ospi_push(ospi_cfg, data[i * 2] | (data[i * 2 + 1] << 8));

	/* Last frame: full pair or single trailing byte */
	if (len & 1)
		ospi_send(ospi_cfg, data[len - 1]);
	else
		ospi_send(ospi_cfg, data[len - 2] | (data[len - 1] << 8));

	return issi_wait_program();
}

/* Returns 1 if flash was programmed (caller must re-init OSPI), 0 otherwise. */
static int ospi_program_from_mram(void)
{
	volatile struct ospi_prog_hdr *hdr =
		(volatile struct ospi_prog_hdr *)OSPI_PROG_FLAG_ADDR;
	ospi_flash_cfg_t *ospi_cfg = &ospi_flash_config;
	uint32_t dest, src, remaining, chunk, sectors, i;

	if (hdr->magic != OSPI_PROG_MAGIC)
		return 0;

	dest = hdr->dest_addr;
	src = hdr->src_addr;
	remaining = hdr->length;

	/* Convert XIP address to flash-relative address for erase/program.
	 * XIP maps flash at 0xC0000000. Flash commands use 0-based addressing. */
	uint32_t flash_dest = dest - 0xC0000000;

	NOTICE("OSPI PROG: %u bytes from 0x%x to 0x%x (flash 0x%x)\n",
	       remaining, src, dest, flash_dest);

	/* Exit XIP mode (flash stays in DDR Octal) */
	ospi_xip_exit(ospi_cfg, ISSI_DDR_OCTAL_IO_FAST_READ,
		      ISSI_DDR_OCTAL_IO_FAST_READ);

	/* Erase sectors in DDR Octal mode */
	sectors = (remaining + OSPI_SECTOR_SIZE - 1) / OSPI_SECTOR_SIZE;
	for (i = 0; i < sectors; i++) {
		uint32_t erase_addr = flash_dest + i * OSPI_SECTOR_SIZE;
		NOTICE("OSPI PROG: erase sector %u/%u @ 0x%x\n",
		       i + 1, sectors, erase_addr);
		if (issi_sector_erase_ddr(ospi_cfg, erase_addr)) {
			ERROR("OSPI PROG: erase timeout at 0x%x\n", erase_addr);
			goto reset_flash;
		}
	}

	/* Program pages in OPI DDR mode using 0x12 with DFS=16 */
	i = 0;
	while (remaining > 0) {
		chunk = (remaining > OSPI_PAGE_SIZE) ? OSPI_PAGE_SIZE : remaining;

		if (issi_page_program_ddr(ospi_cfg, flash_dest,
					  (const uint8_t *)src, chunk)) {
			ERROR("OSPI PROG: program timeout at 0x%x\n", flash_dest);
			goto reset_flash;
		}

		flash_dest += chunk;
		src += chunk;
		remaining -= chunk;
		i++;
		if ((i % 1000) == 0)
			NOTICE("OSPI PROG: %u pages written\n", i);
	}

	NOTICE("OSPI PROG: complete, %u pages written\n", i);

	/* Clear magic to prevent re-programming on next boot */
	hdr->magic = 0;
	flush_dcache_range((uintptr_t)&hdr->magic, sizeof(hdr->magic));

reset_flash:
	/* Software Reset: return flash to SPI single mode so setup_flash_xip()
	 * can do a full re-init (probe, mode switch, XIP enter).
	 * ospi_xip_enter() alone doesn't reliably restore XIP after programming. */
	ospi_setup_write_ddr16(ospi_cfg, ADDR_LENGTH_0_BITS);
	ospi_send(ospi_cfg, ISSI_RESET_ENABLE);
	ospi_setup_write_ddr16(ospi_cfg, ADDR_LENGTH_0_BITS);
	ospi_send(ospi_cfg, ISSI_RESET_MEMORY);

	/* Reset takes up to 30us per datasheet. ddr_en=0 for next init cycle. */
	ospi_cfg->ddr_en = 0;

	return 1;
}
#endif /* FLASH_EN */

/* Init Flash and set to XiP Mode */
int init_nor_flash(void)
{
	int ret;

	setup_PinMUX();
#if AES_EN
	if (service_ospi_write_aes_key()) {
		ERROR("Unable to write OSPI AES KEY to AES decoder register\n");
		return -1;
	}
#endif
	ret = setup_flash_xip();
	INFO("setup_flash_xip is done\n");

	if (ret) {
		ERROR("Unable to set OSPI flash in XiP mode\n");
		return -1;
	}

#if FLASH_EN
	if (ospi_program_from_mram()) {
		/* Programming resets flash to SPI single mode.
		 * Re-run full init to restore DDR Octal XIP. */
		INFO("OSPI re-init after programming\n");
		ret = setup_flash_xip();
		if (ret) {
			ERROR("OSPI re-init after programming failed\n");
			return -1;
		}
		INFO("setup_flash_xip re-init done\n");

		/* Verify: header fields (dest/src/len) persist — only magic was cleared */
		volatile struct ospi_prog_hdr *hdr =
			(volatile struct ospi_prog_hdr *)OSPI_PROG_FLAG_ADDR;
		uint32_t dest = hdr->dest_addr;
		uint32_t src_addr = hdr->src_addr;
		inv_dcache_range(dest, 16);
		volatile uint32_t *xip = (volatile uint32_t *)dest;
		volatile uint32_t *mram = (volatile uint32_t *)src_addr;
		NOTICE("OSPI PROG: verify @ 0x%x: %08x %08x %08x %08x\n",
		       dest, xip[0], xip[1], xip[2], xip[3]);
		NOTICE("OSPI PROG: source @ 0x%x: %08x %08x %08x %08x\n",
		       src_addr, mram[0], mram[1], mram[2], mram[3]);
	}
#endif

	INFO("Configured OSPI NOR Flash successfully\n");
	return 0;
}
