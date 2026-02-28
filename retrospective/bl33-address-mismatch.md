# Retrospective: BL33 Address Mismatch Causes Kernel Boot Failure

Date: 2026-02-28
Duration: Multiple debug cycles across one session
Result: Root-caused kernel crash to wrong PRELOADED_BL33_BASE in TF-A build

## Summary

The TF-A (Trusted Firmware-A) binary was built with `PRELOADED_BL33_BASE=0xC0100000` instead of the correct `PRELOADED_BL33_BASE=0xC0800000`. This caused TF-A to jump into the middle of the cramfs rootfs image instead of the kernel entry point, producing an immediate crash to the exception handler at 0xFFBEFFEC. The bug was particularly hard to diagnose because it presented identically to a bad kernel image.

## Root Cause

The OSPI flash memory layout is:

| Address | Content | Size |
|---------|---------|------|
| 0xC0000000 | rootfs (cramfs-xip) | ~1.8MB |
| 0xC0800000 | kernel (xipImage) | ~3.0MB |

The TF-A build command specified `PRELOADED_BL33_BASE=0xC0100000`, a stale value from an earlier MRAM-only configuration where the kernel lived at a different offset. The correct value for OSPI boot is `0xC0800000` — the address where the kernel actually starts, 8MB after the rootfs base.

With the wrong address, TF-A executed cramfs filesystem data as ARM instructions. The CPU hit an illegal instruction or data abort almost immediately and jumped to the exception handler.

## Timeline of Debugging

### Phase 1: Suspected Bad Kernel (wrong direction)
- Kernel crashed immediately on boot — exception at 0xFFBEFFEC
- Initial hypothesis: kernel image was corrupted or had byte-swap issues
- Investigated MX_FLASH_EN byte-swap configuration for OSPI reads
- Found and fixed a real byte-swap problem, but kernel still crashed

### Phase 2: Verified OSPI Content (narrowing down)
- Read back OSPI flash contents via JLink to verify images were correctly programmed
- Confirmed rootfs and kernel bytes matched the source files on disk
- Eliminated "bad flash" as a cause

### Phase 3: Known-Good Kernel Test (key insight)
- Flashed a previously-known-working kernel image to the same OSPI address
- **Same crash** — identical exception at 0xFFBEFFEC
- This proved the kernel image was not the problem
- Something upstream (the loader) was wrong

### Phase 4: Found the Bug (resolution)
- Searched the TF-A binary for the expected BL33 address (0xC0800000) — not found
- Searched for alternative addresses — found 0xC0100000 embedded in the binary
- Traced back to the build command: `PRELOADED_BL33_BASE=0xC0100000`
- Address 0xC0100000 falls at offset 0x100000 into the rootfs (cramfs data, not code)
- Rebuilt TF-A with `PRELOADED_BL33_BASE=0xC0800000`, reflashed, kernel booted

## What Went Well

1. **Testing with a known-good kernel was the breakthrough.** By swapping in an image that had previously booted, we proved the problem was in the loader, not the payload. This eliminated an entire class of hypotheses in one step.

2. **Binary inspection found the answer quickly once we looked.** Searching the TF-A binary for address constants was fast and definitive.

## What Went Wrong

1. **Assumed the boot target was the problem, not the loader.** When the kernel crashes, the natural instinct is to blame the kernel. We spent significant time investigating kernel image integrity, byte-swap, and OSPI read configuration before considering that TF-A itself was jumping to the wrong address.

2. **Did not verify build parameters against the memory map.** The TF-A build command was treated as a known-good artifact. Nobody checked that PRELOADED_BL33_BASE matched the actual OSPI layout after the memory map changed.

3. **The stale address looked plausible.** 0xC0100000 is in the OSPI address range, so it didn't trigger any obvious "that's wrong" reaction during builds. A completely out-of-range address would have been caught sooner.

## Lessons Learned

| Lesson | Category |
|--------|----------|
| When a boot payload crashes, verify the loader jumps to the correct address before debugging the payload | **Debugging pattern** |
| PRELOADED_BL33_BASE must match the OSPI flash layout — rootfs size determines kernel offset | **Build configuration** |
| Test with a known-good payload to isolate loader vs payload bugs | **Debugging pattern** |
| Search binaries for embedded address constants (`xxd` + `grep`) as an early diagnostic step | **Debugging technique** |
| Stale build parameters from previous configurations are a persistent hazard | **Process** |

## Prevention Measures

1. **Document the memory map alongside the build command.** The TF-A build flags should reference the OSPI layout explicitly, so anyone changing the memory map knows to update the build command (and vice versa).

2. **Add a build-time sanity check.** After building TF-A, verify the BL33 address embedded in the binary matches the expected value from the OSPI layout. A simple `xxd bl32-ospi.bin | grep` in the build script catches this class of error.

3. **When kernel crashes at boot, check the jump address first.** Before investigating kernel image integrity, OSPI read correctness, or DTB issues, verify TF-A is jumping to the right address. This takes 30 seconds and eliminates the most common class of "kernel crash that isn't a kernel problem."

4. **Keep a memory map document as the single source of truth.** All build parameters (PRELOADED_BL33_BASE, ATOC offsets, flash tool addresses) should derive from one place. When the layout changes, all downstream values update together.

## Patterns to Reuse

- **Known-good swap test**: When debugging a multi-stage boot chain, replace one stage with a known-good version to isolate which stage is broken. This is faster than deep-diving any single stage.
- **Binary address audit**: After building firmware that contains hardcoded addresses, search the binary to confirm the addresses are what you expect. Catches stale configs, wrong #defines, and linker script errors.
- **Blame the loader before the payload**: In a chain like TF-A -> kernel, if the payload crashes immediately, the loader is more likely wrong than the payload. Verify the handoff first.
