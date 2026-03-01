---
paths: ["**/*.dtb", "**/*.dts", "**/appkit-e7*", "**/freertos/thread.c", "**/freertos/workqueue.c", "**/local.conf", "yocto-build/build-alif-e7/**"]
---
# Toolchain Learnings

- **ESP32 FreeRTOS StackType_t is uint8_t — stack sizes in bytes not words** — On Xtensa ESP32, `StackType_t` is `uint8_t` (not `uint32_t` like ARM Cortex-M). This means `xTaskCreate()` stack_depth parameter is in BYTES, not words. A value of 2048 gives only 2KB of stack, not 8KB.
- **Never round-trip DTB through dtc decompile/recompile — corrupts clock values** — **NEVER** decompile a DTB and recompile it via `dtc -I dtb -O dts | dtc -I dts -O dtb`. This round-trip corrupts data:
- **Alif E7 Yocto: BSP source variables must be set manually with poky distro** — When using `DISTRO = "poky"` (not `apss-tiny`), the Alif BSP source variables are not auto-configured. These must be set in `local.conf`:
