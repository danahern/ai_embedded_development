/* Copyright (C) 2022 Alif Semiconductor - All Rights Reserved.
 * Use, distribution and modification of this code is permitted under the
 * terms stated in the Alif Semiconductor Software License Agreement
 *
 * You should have received a copy of the Alif Semiconductor Software
 * License Agreement with this file. If not, please write to:
 * contact@alifsemi.com, or visit: https://alifsemi.com/license
 *
 */

/**************************************************************************//**
 * @file     ospi_drv.h
 * @version  V1.0.0
 * @brief    Header file for OSPI driver to set up flash in XIP mode.
 * @bug      None.
 * @Note     None
 ******************************************************************************/

#ifndef OSPI_DRV_H
#define OSPI_DRV_H

#ifdef  __cplusplus
extern "C"
{
#endif

#include <stdint.h>
#include "ospi_private.h"

typedef struct {
    ssi_regs_t *regs;                  ///< Pointer to OSPI0 or OSPI1 base address
    aes_regs_t *aes_regs;              ///< Pointer to AES0 or AES1 decryption module & XIP enable line registers
    volatile void *xip_base;           ///< Pointer to OSPI0 or OSPI1 XIP base address
    uint32_t    ospi_clock;            ///< Octal SPI clock - Device and Bus characteristics defined
    uint32_t    ser;                   ///< Slave Select / Enable register - application defined (to drive ospiN_ss0 or ospiN_ss1)
    uint32_t    addrlen;               ///< Address length 3 or 4 bytes depending on the device capacity
    uint32_t    ddr_en;                ///< DDR enable if set to 1, default 0
    uint32_t    rx_req;                ///< Requested data to receive
    uint32_t    rx_cnt;                ///< Received data count
    uint32_t    device_id;             ///< Manufacturer Device ID
    uint32_t    wait_cycles;           ///< Wait cycles - Device defined for switching from Rx to Tx
} ospi_flash_cfg_t ;

/* Function Prototypes */
void ospi_init(ospi_flash_cfg_t *ospi_cfg);
void ospi_xip_enter(ospi_flash_cfg_t *ospi_cfg, uint16_t incr_command, uint16_t wrap_command);
void ospi_recv(ospi_flash_cfg_t *ospi_cfg, uint32_t command, uint8_t *buffer);
void ospi_push(ospi_flash_cfg_t *ospi_cfg, uint32_t data);
void ospi_send(ospi_flash_cfg_t *ospi_cfg, uint32_t data);
void ospi_setup_write(ospi_flash_cfg_t *ospi_cfg, uint32_t addr_len);
void ospi_setup_write_ddr16(ospi_flash_cfg_t *ospi_cfg, uint32_t addr_len);
void ospi_setup_write_sdr(ospi_flash_cfg_t *ospi_cfg, uint32_t addr_len);
void ospi_setup_read(ospi_flash_cfg_t *ospi_cfg, uint32_t addr_len, uint32_t read_len, uint32_t wait_cycles);
void ospi_setup_read_sdr(ospi_flash_cfg_t *ospi_cfg, uint32_t addr_len, uint32_t read_len, uint32_t wait_cycles);
void ospi_xip_exit(ospi_flash_cfg_t *ospi_cfg, uint16_t incr_command, uint16_t wrap_command);



typedef struct {
	/* Control Register */
	volatile uint32_t ctrlr0; /* SPI Control Register 0  (0x0) */
	volatile uint32_t ctrlr1; /* SPI Control Register 1  (0x4) */

	/* Enable Register */
	volatile uint32_t ssienr; /* SPI Enable Register  (0x8) */
	volatile uint32_t mwcr;   /* SPI Microwire Control Register  (0xC) */
	volatile uint32_t ser;    /* SPI Slave Enable Register  (0x10) */
	volatile uint32_t baudr;  /* SPI Baud Rate Select Register  (0x14) */

	/* TX and RX FIFO Control Register */
	volatile uint32_t txftlr; /* SPI Transmit FIFO Threshold Level Register (0x18) */
	volatile uint32_t rxftlr; /* SPI Receive  FIFO Threshold Level Register (0x1C) */
	volatile uint32_t txflr;  /* SPI Transmit FIFO Level Register  (0x20)*/
	volatile uint32_t rxflr;  /* SPI Receive  FIFO Level Register  (0x24)*/
	volatile uint32_t sr;     /* SPI Status   Register  (0x28) */

	/* Interrupt Enable/Disable Control Registers */
	volatile uint32_t imr;		/* SPI Interrupt Mask Register  (0x2C) */
	volatile uint32_t isr;		/* SPI Interrupt Status Register  (0x30) */
	volatile uint32_t risr;		/* SPI Raw Interrupt Status Register (0x34)*/
	volatile uint32_t txoicr;	/* SPI Transmit FIFO Overflow Interrupt Clear Register  (0x38) */
	volatile uint32_t rxoicr;	/* SPI Receive  FIFO Overflow Interrupt Clear Register  (0x3C) */
	volatile uint32_t rxuicr; 	/* SPI Receive FIFO Underflow Interrupt Clear Register  (0x40) */
	volatile uint32_t msticr;	/* SPI Multi-Master Interrupt Clear Register (0x44) */
	volatile uint32_t icr;		/* SPI Interrupt Clear Register  (0x48) */
	volatile uint32_t dmacr;	/* DMA Control Register  (0x4C) */
	volatile uint32_t dmatxdlr;   	/* DMA Transmit Data Level  (0x50) */
	volatile uint32_t dmarxdlr;   	/* DMA Receive Data Level  (0x54) */
	volatile uint32_t spi_idr;    	/* SPI Identification Register  (0x58) */
	volatile uint32_t spi_ver_id; 	/* Synopsys component version (0x5C) */

	/* Data Register */
	volatile uint32_t datareg;		/* SPI DATA Register for both Read and Write  (0x60) */
	volatile uint32_t drs[35];		/* SPI DATA Register for both Read and Write  (0x64-0xEC) */
	volatile uint32_t rx_sample_dly;	/* Rx Sample Delay Register (0xF0) */
	volatile uint32_t spi_ctrlr0;		/* SPI Control Register 0 (0xF4) */
	volatile uint32_t txd_drive_edge;	/* Transmit Drive Edge Register (0xF8) */
	volatile uint32_t xip_mode_bits;	/* eXecute in Place - Mode bits (0xFC) */

    /* XiP instruction register address block SSIC MEMORY MAP */
	volatile uint32_t xip_incr_inst;	/* XiP INCR transfer opcode (0x100) */
	volatile uint32_t xip_wrap_inst;	/* XiP WRAP transfer opcode (0x104) */
	volatile uint32_t xip_ctrl;		/* XiP Control Register (0x108) */
	volatile uint32_t xip_ser;		/* XiP Slave Enable Register (0x10C) */
	volatile uint32_t xip_xrxoicr;		/* XiP Receive FIFO Overflow Interrupt Clear Register (0x110) */
	volatile uint32_t xip_cnt_time_out; 	/* XiP time out register for continuous transfers (0x114) */
	volatile uint32_t spi_ctrlr1;		/* SPI Control Register 1 (0x118) */
	volatile uint32_t spitecr;		/* SPI Transmit Error Interrupt Clear Register (0x11C) */
	volatile uint32_t spidr;		/* SPI Device Register (0x120) */
	volatile uint32_t spiar;		/* SPI Device Address Register (0x124) */
	volatile uint32_t axiar0;		/* AXI Address Register 0 (0x128) */
	volatile uint32_t axiar1;		/* AXI Address Register 1 (0x12C) */
	volatile uint32_t axiecr;		/* AXI Master Error Interrupt Clear Register (0x130) */
	volatile uint32_t donecr;		/* Transfer Done Clear Interrupt Clear Register (0x134) */
    volatile uint32_t rsvd[2];
	volatile uint32_t xip_write_incr_inst;	/* XiP Write INCR transfer opcode (0x140) */
	volatile uint32_t xip_write_wrap_inst;	/* XiP Write WRAP transfer opcode (0x144) */
	volatile uint32_t xip_write_ctrl;	/* XiP Write Control Register (0x148) */
} ospi_regs_t;


/* Bit fields in CTRLR0 based on DWC_ssi_databook.pdf v1.02a */
#define DWC_SSI_CTRLR0_SPI_HE_OFFSET		24		/* hyperbus enable */
#define DWC_SSI_CTRLR0_SPI_FRF_OFFSET		22		/* spi frame format - std/dual/quad/octal */
#define DWC_SSI_CTRLR0_CFS_OFFSET		16		/* control frame size - Microwire only - ignore */
#define DWC_SSI_CTRLR0_SSTE_OFFSET		14		/* slave select toggle enable */
#define DWC_SSI_CTRLR0_SRL_OFFSET		13		/* shift register loop - ignore */
#define DWC_SSI_CTRLR0_SLV_OE_OFFSET		12
#define DWC_SSI_CTRLR0_TMOD_OFFSET		10
#define DWC_SSI_CTRLR0_TMOD_MASK		(3 << DWC_SSI_CTRLR0_TMOD_OFFSET) /* read/write, read only, write only, eeprom read*/
#define DWC_SSI_CTRLR0_SCPOL_OFFSET		9
#define DWC_SSI_CTRLR0_SCPH_OFFSET		8
#define DWC_SSI_CTRLR0_FRF_OFFSET		6		/* frame format - spi/ssp/microwire */
#define DWC_SSI_CTRLR0_DFS_OFFSET		0

#define DWC_SSI_CTRLR0_IS_MST			0x80000000
#define DWC_SSI_DEFAULTS			(DWC_SSI_CTRLR0_IS_MST|7)	/* Always master, 8-bit data frame size */

#define	SPI_TMOD_TR				0x0		/* xmit & recv */
#define SPI_TMOD_TO				0x1		/* xmit only */
#define SPI_TMOD_RO				0x2		/* recv only */
#define SPI_TMOD_EPROMREAD			0x3		/* eeprom read mode */

/* Bit fields for SPI FRF */
#define SPI_SINGLE				0x0
#define SPI_DUAL				0x1
#define SPI_QUAD				0x2
#define SPI_OCTAL				0x3

/* Bit fields for Frame Format FRF */
#define SPI_FRF_SPI				0x0
#define SPI_FRF_SSP				0x1
#define SPI_FRF_MICROWIRE			0x2

/* Bit fields in CTRLR1 */
#define SPI_NDF_MASK				0x0000ffff	/* GENMASK(15, 0) */

/* Bit fields in SPI_CTRLR0 */
#define DWC_SPI_CTRLR0_CLK_STRETCH_EN_OFFSET 	30
#define DWC_SPI_CTRLR0_XIP_PREFETCH_EN_OFFSET 	29
#define DWC_SPI_CTRLR0_XIP_MBL_OFFSET 		26
#define DWC_SPI_CTRLR0_SPI_RXDS_SIG_EN_OFFSET 	25
#define DWC_SPI_CTRLR0_SPI_DM_EN_OFFSET 	24
#define DWC_SPI_CTRLR0_XIP_CONT_EN_OFFSET 	21
#define DWC_SPI_CTRLR0_XIP_INST_EN_OFFSET 	20
#define DWC_SPI_CTRLR0_XIP_DFS_HC_OFFSET 	19
#define DWC_SPI_CTRLR0_SPI_RXDS_EN_OFFSET 	18
#define DWC_SPI_CTRLR0_INST_DDR_EN_OFFSET	17
#define DWC_SPI_CTRLR0_SPI_DDR_EN_OFFSET 	16
#define DWC_SPI_CTRLR0_WAIT_CYCLES_OFFSET 	11
#define DWC_SPI_CTRLR0_INST_L_OFFSET 		8
#define DWC_SPI_CTRLR0_XIP_MD_EN_OFFSET 	7
#define DWC_SPI_CTRLR0_ADDR_L_OFFSET 		2
#define DWC_SPI_CTRLR0_TRANS_TYPE_OFFSET 	0

#define DWC_SPI_CTRLR0_TRANS_TYPE_MASK	 	3
#define DWC_SPI_TRANS_TYPE_STANDARD	 	0
#define DWC_SPI_TRANS_TYPE_FRF_DEFINED		2

/* Bit fields in XIP_CTRL */
#define DWC_SPI_XIP_CTRL_RXDS_SIG_EN_OFFSET          25
#define DWC_SPI_XIP_CTRL_XIP_HYPERBUS_EN_OFFSET      24
#define DWC_SPI_XIP_CTRL_RXDS_EN_OFFSET              21
#define DWC_SPI_XIP_CTRL_DDR_EN_OFFSET               19
#define DWC_SPI_XIP_CTRL_DFS_HC_OFFSET               18
#define DWC_SPI_XIP_CTRL_WAIT_CYCLES_OFFSET          13
#define DWC_SPI_XIP_CTRL_INST_L_OFFSET                9
#define DWC_SPI_XIP_CTRL_ADDR_L_OFFSET                4
#define DWC_SPI_XIP_CTRL_TRANS_TYPE_OFFSET            2
#define DWC_SPI_XIP_CTRL_FRF_OFFSET                   0

#define DWC_SPI_XIP_WR_CTRL_WR_FRF                    0
#define DWC_SPI_XIP_WR_CTRL_WR_TRANS_TYPE             2
#define DWC_SPI_XIP_WR_CTRL_WR_ADDR_L                 4
#define DWC_SPI_XIP_WR_CTRL_WR_INST_L                 8
#define DWC_SPI_XIP_WR_CTRL_WR_SPI_DDR_EN             10
#define DWC_SPI_XIP_WR_CTRL_WR_INST_DDR_EN            11
#define DWC_SPI_XIP_WR_CTRL_WR_HYPERBUS_EN            12
#define DWC_SPI_XIP_WR_CTRL_WR_RXDS_SIG_EN            13
#define DWC_SPI_XIP_WR_CTRL_WR_DM_EN                  14
#define DWC_SPI_XIP_WR_CTRL_WR_RSVD                   15
#define DWC_SPI_XIP_WR_CTRL_WAIT_CYCLES               16
#define DWC_SPI_XIP_WR_CTRL_DFS_HC                    21

#define TXBUFF_SIZE		256
#define RXBUFF_SIZE		256

typedef struct {
	ospi_regs_t  		*regs;			/* Pointer to OSPI registers */
	aes_regs_t  		*aes_regs;		/* Pointer to AES registers */
	uint32_t		rx_req;			/* Requested data to receive */
	uint32_t		rx_cnt;			/* Received data count */
	uint32_t		tx_buff[TXBUFF_SIZE];
	volatile uint16_t	rx_buff[RXBUFF_SIZE];	/* Read buffer */
} ospi_cfg_t ;

#define readl(a, r)		(a->regs->r)
#define writel(a, r, v)	    	a->regs->r = (v);

#define ospi_enable(ospi) 	writel(ospi, ssienr, 1)
#define ospi_disable(ospi) 	writel(ospi, ssienr, 0)

#ifdef  __cplusplus
}
#endif

#endif /* OSPI_DRV_H_ */
