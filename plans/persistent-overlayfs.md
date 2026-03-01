# Plan: Persistent OverlayFS — MRAM or OSPI

**Status**: Planned

## Context

The Alif E7 runs cramfs-xip from OSPI NOR flash — read-only. We added tmpfs overlayfs (Option 1) for volatile `adb push` support, but changes are lost on reboot. This plan adds **persistent** writes so `adb push` changes survive power cycles.

**Problem**: Iterative development requires reflashing the entire rootfs image for every change.

## Two Paths Discovered

Research revealed two viable paths. Path A (MRAM) is dramatically simpler.

### Path A: JFFS2 on MRAM (Simple — preferred)

The kernel defconfig already defines a 2 MB physmap MTD device on MRAM:
```
CONFIG_MTD_PHYSMAP_START=0x80380000   (MRAM)
CONFIG_MTD_PHYSMAP_LEN=0x200000       (2 MB)
```

MRAM is **non-volatile** and **byte-writable** (no erase cycles). The physmap driver's `map_write()` does direct memory stores, which work on MRAM. No SPI NOR driver needed. No XIP conflict.

**Advantages**: Zero kernel driver work. No OSPI conflict. Just enable JFFS2 + mount it.
**Limitation**: 2 MB storage (enough for dev overlay — config files, small binaries).

### Path B: JFFS2 on OSPI via SPI NOR Driver (Complex — more storage)

Use the existing DWC SSI SPI driver (`spi-dw-mmio.c`) + ISSI SPI NOR support to write to a 2+ MB OSPI partition. Requires:
- DTS node for OSPI1 at 0x83002000 (not currently in device tree)
- OSPI clock added to Alif clock driver (not currently exposed)
- Pivot-root to release OSPI XIP before SPI NOR driver takes over
- `CONFIG_SPI_DW_MMIO=y` + `CONFIG_SPI_MEM=y` + `CONFIG_MTD_SPI_NOR=y`

**Advantages**: Up to 22 MB of persistent storage on OSPI NOR.
**Risks**: XIP conflict, clock driver work, pivot-root complexity.

## Memory Map Reference

```
MRAM 0x80000000 (5.75 MB):
  0x80002000  TF-A BL32       (~30 KB)
  0x80010000  DTB              (~48 KB)
  0x80020000  Kernel XIP       (~3 MB, copied from OSPI by TF-A)
  0x80320000  (gap)            (~384 KB)
  0x80380000  MRAM MTD         (2 MB — CONFIG_MTD_PHYSMAP)  <- Path A target
  0x80580000  (free)           (~256 KB)
  0x805C0000  End of MRAM

OSPI 0xC0000000 (32 MB IS25WX256):
  0xC0000000  rootfs cramfs    (1.8 MB, XIP via physmap-flash.0)
  0xC0800000  kernel stored    (~3.5 MB, copied to MRAM by TF-A at boot)
  0xC1000000  (free)           (22 MB)  <- Path B target
```

## Experiments

All experiments on a **worktree branch** to isolate kernel changes from working OSPI boot config.

### Experiment 1: Verify MRAM MTD exists during OSPI boot (no kernel changes)

**Goal**: Confirm the physmap at 0x80380000 (MRAM) shows up alongside the OSPI physmap.

**Method**:
```sh
cat /proc/mtd
# Expected:
#   mtd0: 00800000 00010000 "physmap-flash.0"   (OSPI, 8 MB)
#   mtd1: 00200000 00000001 "physmap-flash.1"   (MRAM, 2 MB)

cat /sys/class/mtd/mtd*/name
cat /sys/class/mtd/mtd*/size
cat /sys/class/mtd/mtd*/erasesize
```

**Fallback if MRAM MTD missing**: Add kernel cmdline `phram=mram_overlay,0x80380000,0x200000`.

### Experiment 2: MRAM write + read test

**Goal**: Verify MRAM is writable via the MTD device.

**Method**:
```sh
dd if=/dev/urandom of=/tmp/pattern bs=256 count=1
dd if=/tmp/pattern of=/dev/mtdblock1 bs=256 count=1
dd if=/dev/mtdblock1 of=/tmp/readback bs=256 count=1
cmp /tmp/pattern /tmp/readback
```

### Experiment 3: MRAM persistence across power cycle

**Goal**: Verify MRAM content survives power cycle.

**Method**:
```sh
echo "MRAM_PERSIST_$(date +%s)" | dd of=/dev/mtdblock1 bs=64 count=1
sync
# === POWER CYCLE ===
dd if=/dev/mtdblock1 of=/dev/stdout bs=64 count=1
# Should show the same value
```

**Critical**: TF-A copies kernel to 0x80020000 at boot. Region at 0x80380000 should be untouched (384 KB gap past kernel end ~0x80320000). Must confirm.

### Experiment 4: JFFS2 on MRAM

**Goal**: Mount JFFS2 filesystem on MRAM MTD.

**Prereq**: Kernel rebuild with `CONFIG_JFFS2_FS=y`.

**Method**:
```sh
flash_eraseall /dev/mtd1
mkdir -p /mnt/overlay
mount -t jffs2 /dev/mtdblock1 /mnt/overlay
echo "hello" > /mnt/overlay/test.txt
mkdir -p /mnt/overlay/upper /mnt/overlay/work
```

### Experiment 5: Full persistent overlayfs

**Goal**: End-to-end test — persistent overlay via JFFS2/MRAM + cramfs lower.

**Method**:
```sh
mount -t jffs2 /dev/mtdblock1 /mnt/overlay
mkdir -p /mnt/overlay/upper /mnt/overlay/work
mount -t overlay overlay \
    -o lowerdir=/,upperdir=/mnt/overlay/upper,workdir=/mnt/overlay/work \
    /mnt/merged
echo "persist" > /mnt/merged/tmp/survive_reboot.txt
# === POWER CYCLE ===
mount -t jffs2 /dev/mtdblock1 /mnt/overlay
ls /mnt/overlay/upper/tmp/survive_reboot.txt
```

### Experiment 6 (Stretch): OSPI SPI NOR driver probe

Deferred until Path A is validated. Only needed if 2 MB MRAM proves too small.

## Implementation Plan (after experiments validate Path A)

### Step 1: Kernel config — enable JFFS2

Create `firmware/linux/yocto/meta-eai/recipes-kernel/linux/files/jffs2.cfg`:
```
CONFIG_JFFS2_FS=y
CONFIG_JFFS2_FS_WRITEBUFFER=y
CONFIG_JFFS2_SUMMARY=y
CONFIG_JFFS2_ZLIB=y
```

Add to `firmware/linux/yocto/meta-eai/recipes-kernel/linux/linux-alif_%.bbappend`:
```
SRC_URI += "file://jffs2.cfg"
```

Optionally add mtd-utils for debugging:
```
IMAGE_INSTALL:append = " mtd-utils"
```

### Step 2: Update overlayfs-dev init script

Modify `firmware/linux/yocto/meta-eai/recipes-core/overlayfs-dev/files/overlayfs-dev-init` to:
1. Look for MRAM MTD partition (physmap-flash.1 or named "overlay")
2. If found: mount JFFS2 on it, use as persistent overlayfs upper layer
3. If not found: fall back to volatile tmpfs overlay (current behavior)

### Step 3: Yocto rebuild + flash + test

Build, flash, and run experiments 1-5 on hardware.

## Files to Modify

| File | Change |
|------|--------|
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/files/jffs2.cfg` | New — JFFS2 config fragment |
| `firmware/linux/yocto/meta-eai/recipes-kernel/linux/linux-alif_%.bbappend` | Edit — add jffs2.cfg to SRC_URI |
| `firmware/linux/yocto/meta-eai/recipes-core/overlayfs-dev/files/overlayfs-dev-init` | Edit — add MRAM JFFS2 persistent path |

## Verification

1. `cat /proc/mtd` — shows MRAM MTD device
2. `mount | grep jffs2` — JFFS2 mounted on MRAM MTD
3. `mount | grep overlay` — overlayfs with JFFS2 upper
4. `adb push testfile /usr/bin/testfile` — file appears
5. Power cycle — file still exists
6. Reflash rootfs+kernel — pushed files still exist (MRAM untouched)

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| MRAM physmap not probing during OSPI boot | Medium | Experiment 1; fallback: `phram=` kernel cmdline |
| TF-A/SE clears MRAM at 0x80380000 on boot | Low | Experiment 3; fallback: adjust physmap START past kernel end |
| 2 MB too small for dev overlay | Low for now | JFFS2 compression helps; escalate to Path B (OSPI) if needed |
| JFFS2 overhead on MRAM (wear-leveling unnecessary) | Negligible | JFFS2 still works fine; could switch to ext2 later |
| Kernel XIP overlaps with MRAM MTD | None | Kernel ends at ~0x80320000, MTD starts at 0x80380000 (384 KB gap) |
