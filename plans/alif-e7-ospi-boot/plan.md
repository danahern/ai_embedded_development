# Plan: Flash Linux to OSPI via TF-A Programmer + Verify Boot

**Status:** In-Progress

## Goal

Flash the Yocto-built Linux images (kernel + rootfs with ADB + USB-ECM) to OSPI NOR flash on the Alif E7 DevKit using the TF-A MRAM-staging OSPI programmer. Verify Linux boots from OSPI and ADB is functional.

## Steps

### Phase 1: Flash ATOC + MRAM components (TFA, DTB)

1. Copy OSPI build artifacts to setools image directory
2. Run `gen_toc` with `linux-boot-e7-ospi.json` config
3. Enter maintenance mode on board
4. Flash ATOC + TFA + DTB to MRAM via SE-UART (`alif-flash.flash`)
5. Power cycle — verify TF-A boots (UART2 console output)

### Phase 2: Program kernel to OSPI (one pass)

1. Write `xipImage-ospi` (2.87MB) to MRAM staging at 0x80020000 via SE-UART
2. Write `ospi-hdr-kernel.bin` (16B header) to 0x8000E000 via SE-UART
3. Power cycle — TF-A sees magic, programs kernel to OSPI @ 0xC0800000, clears header
4. Verify via UART2: "OSPI PROG:" messages showing erase + program

### Phase 3: Program rootfs to OSPI (two passes — rootfs > MRAM)

**Pass 1 (5MB):**
1. Write `rootfs-ospi-part1.bin` (5MB) to MRAM staging at 0x80020000
2. Write `ospi-hdr-rootfs1.bin` header to 0x8000E000
3. Power cycle — TF-A programs to OSPI @ 0xC0000000

**Pass 2 (1.3MB):**
4. Write `rootfs-ospi-part2.bin` (1.36MB) to MRAM staging at 0x80020000
5. Write `ospi-hdr-rootfs2.bin` header to 0x8000E000
6. Power cycle — TF-A programs to OSPI @ 0xC0500000

### Phase 4: Final boot + verification

1. Power cycle — TF-A boots, kernel XIP from OSPI, rootfs from OSPI
2. Check UART2 console for full Linux boot
3. Check `adb devices` on Mac
4. Check `adb shell` works
5. Check USB gadget init in dmesg

## Verification Checklist

- [ ] TF-A boots after ATOC flash (UART2 shows TF-A banner)
- [ ] Kernel programmed to OSPI (UART2 shows "OSPI PROG" for kernel)
- [ ] Rootfs part 1 programmed to OSPI
- [ ] Rootfs part 2 programmed to OSPI
- [ ] Linux boots from OSPI (kernel at 0xC0800000, rootfs at 0xC0000000)
- [ ] ADB functional (`adb devices` shows device)
- [ ] `adb shell` gives root shell

## Key Constraint

Each MRAM staging write + power cycle takes ~2-3 minutes. Total expected: ~10-15 minutes for 4 power cycle passes.
