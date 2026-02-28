/* Copyright (C) 2022 Alif Semiconductor - All Rights Reserved.
 * Use, distribution and modification of this code is permitted under the
 * terms stated in the Alif Semiconductor Software License Agreement
 *
 * You should have received a copy of the Alif Semiconductor Software
 * License Agreement with this file. If not, please write to:
 * contact@alifsemi.com, or visit: https://alifsemi.com/license
 *
 */
#ifndef DWC_SPI_H
#define DWC_SPI_H

#include "ospi_private.h"

#define ISSI_READ_ID				0x9E
#define ISSI_WRITE_ENABLE			0x06
#define ISSI_READ_STATUS_REG			0x05
#define ISSI_READ_FLAG_STATUS_REG		0x70
#define ISSI_READ_NONVOLATILE_CONFIG_REG	0xB5
#define ISSI_READ_VOLATILE_CONFIG_REG		0x85
#define ISSI_READ_PROTECTION_MANAGEMENT_REG	0x2B
#define ISSI_WRITE_VOLATILE_CONFIG_REG		0x81
#define ISSI_DDR_OCTAL_IO_FAST_READ		0xFD
#define ISSI_4BYTE_PAGE_PROGRAM			0x12
#define ISSI_4BYTE_SECTOR_ERASE			0xDC

#define DEFAULT_WAIT_CYCLES_ISSI		0x10

/* defines the Length of Address to be transmitted by Host controller */
#define ADDR_LENGTH_0_BITS		0x0
#define ADDR_LENGTH_8_BITS		0x2
#define ADDR_LENGTH_24_BITS		0x6
#define ADDR_LENGTH_32_BITS		0x8

/* defines the mode in which the slave Device is operating in */
#define DEVICE_MODE_SINGLE		1
#define DEVICE_MODE_DUAL		2
#define DEVICE_MODE_QUAD		4
#define DEVICE_MODE_OCTAL		8

/* PINMUX base address*/
#define PINMUX_BASE			0x1A603000

/* Pad Control Register */
#define PAD_CTRL_REN			0x01			/* Read Enable */
#define PAD_CTRL_SMT			0x02			/* Schmitt Trigger Enable */
#define PAD_CTRL_SR			0x04			/* Fast Slew Rate Enable */
#define PAD_CTRL_HIGHZ			0			/* Driver Disabled State Control - High Z - Normal operation */
#define PAD_CTRL_PULLUP			(1<<3)			/* Driver Disabled State Control - Weak Pull-Up */
#define PAD_CTRL_PULLDN			(2<<3)			/* Driver Disabled State Control - Weak Pull-Down */
#define PAD_CTRL_REPEAT			(3<<3)			/* Driver Disabled State Control - Repeater - Bus keeper */
#define PAD_CTRL_2MA			0x00			/* Output Drive Strength 2mA */
#define PAD_CTRL_4MA			(1<<5)			/* Output Drive Strength 4mA */
#define PAD_CTRL_8MA			(2<<5)			/* Output Drive Strength 8mA */
#define PAD_CTRL_12MA			(3<<5)			/* Output Drive Strength 12mA */
#define PAD_CTRL_OPENDRAIN		0x80			/* Open Drain Driver */


#define PADCTRL_REG(PORT,PIN,PAD_VAL,ALT_FUNC) (volatile uint32_t *) \
        ((volatile uint32_t *)PINMUX_BASE + ((PORT *32 + PIN *4) >> 2)) = (PAD_VAL<<16 | ALT_FUNC)


/* Init Flash and set to XiP Mode */
int init_nor_flash(void);

#endif //DWC_SPI_H
