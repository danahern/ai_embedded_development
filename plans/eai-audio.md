# eai_audio — Portable Audio HAL

**Status:** In-Progress
**Created:** 2026-02-18

## Implementation Progress

### Phase 1: Core API + POSIX backend — COMPLETE
- All headers (types, port, stream, gain, route)
- POSIX stub backend (fake ports, buffer write/read, test helpers)
- Native Unity tests (31 tests: lifecycle, port enumeration, stream I/O, gain, routes, profiles)
- CLAUDE.md documentation
- **Verified:** 31 native tests pass on macOS (with ASan + UBSan)

### Phase 2: Mini-flinger — COMPLETE
- `mixer.c` — platform-independent, uses eai_osal (thread, mutex, semaphore)
- Ring buffer per slot, int16 mix with int32 accumulator, Q16 volume, hard clip
- Underrun detection with silence insertion
- 12 native tests (init/deinit, slot management, single/multi stream mixing, clipping, volume, mute, underrun)
- **Verified:** 12 mixer tests pass on macOS (with ASan + UBSan)

### Phase 3: Zephyr backend — NOT STARTED
- I2S device enumeration from devicetree
- DMA buffer management
- Codec gain control

### Phase 4: ESP-IDF backend — NOT STARTED

### Phase 5: ALSA backend — NOT STARTED

### Phase 6: Routing — NOT STARTED
- Port connection validation with audio switching

## Files Created
- `firmware/lib/eai_audio/include/eai_audio/` — 6 headers
- `firmware/lib/eai_audio/src/posix/` — types.h, audio.c
- `firmware/lib/eai_audio/src/mixer.h` — internal mixer API
- `firmware/lib/eai_audio/src/mixer.c` — mini-flinger implementation
- `firmware/lib/eai_audio/tests/native/` — CMakeLists.txt, main.c, mixer_tests.c
- `firmware/lib/eai_audio/CMakeLists.txt`, `Kconfig`, `zephyr/module.yml`
- `firmware/lib/eai_audio/CLAUDE.md`
