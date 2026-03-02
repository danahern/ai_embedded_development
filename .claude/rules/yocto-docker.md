---
paths: ["**/meta-eai/**", "**/yocto/**/*.cfg", "**/yocto/**/*.bbappend", "**/yocto/**/*.bb", "**/yocto/**/*.inc", "**/yocto/**/*.conf"]
---

# Yocto Docker Build Rules

## meta-eai is bind-mounted — host edits propagate automatically

The `yocto-build` container mounts `firmware/linux/yocto/meta-eai/` directly into `/home/builder/yocto/meta-eai/`. Edits on the host are immediately visible inside the container — no `docker cp` needed.

**Container creation command** (if container needs to be recreated):
```bash
docker run -dit --name yocto-build \
  -v yocto-data:/home/builder/yocto \
  -v /Users/danahern/code/claude/work/yocto-build:/home/builder/artifacts \
  -v /Users/danahern/code/claude/work/firmware/linux/yocto/meta-eai:/home/builder/yocto/meta-eai \
  yocto-builder \
  bash -c "sleep infinity"
```

## Kernel config changes: use `kernel_rebuild` tool

For `.cfg` fragment changes, use `kernel_rebuild` — it runs `configure -f && compile -f && deploy -f` in the correct order and verifies the result.

```
linux-build.kernel_rebuild(
  container="yocto-build",
  image="alif-tiny-image",
  verify_configs=["CONFIG_JFFS2_FS=y", "CONFIG_MTD_PHRAM=y"]
)
```

Use `yocto_build` for recipe-only changes (bbappend, bb files) that don't need a forced kernel reconfig.

## Why `cleansstate` + `compile -f` fails for kernel config changes

`cleansstate` does not delete build artifacts in `work-shared/devkit-e8/kernel-source/`. The subsequent `do_compile -f` runs Make with stale `.o` files whose timestamps are newer than the new `.config`, so Make does nothing. The binary is NOT rebuilt even though `.config` shows the new options.

The `kernel_rebuild` tool avoids this by running `configure -f` first, which regenerates `include/config/auto.conf` and forces kbuild to see the new config options.

## Nuclear option (if kernel_rebuild fails)

Delete the shared source tree to defeat Make's kbuild timestamp cache, then do a full rebuild:

```bash
linux-build.run_command(container="yocto-build",
  command="rm -rf /home/builder/yocto/build-alif-e7/tmp/work-shared/devkit-e8/kernel-source/")

linux-build.yocto_build(container="yocto-build", build_dir="build-alif-e7",
  image="alif-tiny-image")
```

This is slower (~20-40 min full kernel rebuild) but always works.

## SOURCE_DATE_EPOCH note

The compile date in the Linux version banner (e.g., "Fri Feb 13 ...") is **not** the wall-clock build time. Yocto pins it to `SOURCE_DATE_EPOCH` (last kernel source commit date). Use vmlinux mtime instead — `kernel_rebuild` checks this automatically.
