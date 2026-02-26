# Plan: Add Bind Mounts to Alif Docker Container

**Status:** Planned

## Problem

The `alif-apss-build` container has no bind mounts for config or layer files. Edits to `yocto-build/build-alif-e7/conf/` and `firmware/linux/yocto/meta-eai/` on the host don't appear inside the container — we have to manually `sed` or `docker cp` changes in.

## Changes

1. Recreate container with bind mounts for:
   - `yocto-build/build-alif-e7/conf/` → `/home/apssbuilder/apss-build-setup/build-alif-e7/conf/`
   - `firmware/linux/yocto/meta-eai/` → `/home/apssbuilder/apss-build-setup/layers/meta-eai/`
2. Update `firmware/linux/alif-e7/README.md` docker run command
3. Preserve existing `alif-apss-data` volume (sstate-cache, downloads, tmp)
