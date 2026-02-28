---
paths: ["**/*.dtb", "**/*.dts", "**/appkit-e7*", "**/freertos/thread.c", "**/freertos/workqueue.c", "**/local.conf", "alif_arm-tf/**/*.c", "alif_arm-tf/**/*.h", "alif_arm-tf/**/*.mk", "yocto-build/build-alif-e7/**"]
---
# Toolchain Learnings

- **Never round-trip DTB through dtc decompile/recompile — corrupts clock values** — **NEVER** decompile a DTB and recompile it via `dtc -I dtb -O dts | dtc -I dts -O dtb`. This round-trip corrupts data:
- **ESP32 FreeRTOS StackType_t is uint8_t — stack sizes in bytes not words** — On Xtensa ESP32, `StackType_t` is `uint8_t` (not `uint32_t` like ARM Cortex-M). This means `xTaskCreate()` stack_depth parameter is in BYTES, not words. A value of 2048 gives only 2KB of stack, not 8KB.
- **Alif E7 Yocto: BSP source variables must be set manually with poky distro** — When using `DISTRO = "poky"` (not `apss-tiny`), the Alif BSP source variables are not auto-configured. These must be set in `local.conf`:
- **Alif E7 TF-A build command — full flags for arm-linux-gnueabihf-gcc** — TF-A for the Alif E7 DevKit must be built with specific flags. The build uses `arm-linux-gnueabihf-gcc` from the `alif-e7-sdk` Docker container (the Zephyr SDK's `arm-zephyr-eabi-gcc` also works but needs the same flags).
