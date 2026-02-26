# Flash Linux to OSPI on Alif E7 DevKit

You are flashing Linux images to OSPI NOR flash on an Alif E7 DevKit via the TF-A MRAM-staging OSPI programmer. Read `plans/alif-e7-ospi-boot/plan.md` and `plans/alif-e7-ospi-boot/context.md` for full technical details.

## Instructions

Check what phase you're on by reading `plans/alif-e7-ospi-boot/plan.md` and looking at which checkboxes are checked. Pick up where you left off.
Only update the summary.md after each loop and Always append data, never edit.

### Phase 1: ATOC + MRAM (TFA, DTB)

Artifacts must be in the setools image directory before gen_toc. Copy them:

```
# Required files in tools/setools/build/images/:
# - bl32-ospi.bin, appkit-e7-ospi.dtb, m55_stub_hp.bin, app-device-config.bin
# Source: firmware/linux/alif-e7/images/
```

Then:
1. Copy the ATOC config: `firmware/linux/alif-e7/setools/linux-boot-e7-ospi.json` → `tools/setools/build/config/linux-boot-e7-ospi.json`
2. Run `alif-flash.gen_toc(config="build/config/linux-boot-e7-ospi.json")`
3. Run `alif-flash.flash(config="linux-boot-e7-ospi.json", maintenance=true)`
4. If maintenance fails, ask user to enter maintenance manually, then retry `flash` without `maintenance=true`
5. After flash succeeds, ask user to power cycle
6. Check the box in `plan.md`: `- [x] TF-A boots after ATOC flash`

### Phase 2: Kernel to OSPI (1 pass)

Write kernel data + header to MRAM, then power cycle for TF-A to program OSPI:

1. Enter maintenance mode: `alif-flash.maintenance()` or ask user
2. Write kernel to MRAM staging:
   - Use SE-UART ISP to write `firmware/linux/alif-e7/images/xipImage-ospi` to address `0x80020000`
   - Use SE-UART ISP to write `firmware/linux/alif-e7/images/ospi-hdr-kernel.bin` to address `0x8000E000`
3. Ask user to power cycle
4. TF-A should show "OSPI PROG:" messages on UART2 (kernel programming ~15s)
5. Check the box in `plan.md`: `- [x] Kernel programmed to OSPI`

**How to write raw data to MRAM via SE-UART:** The `alif-flash.flash` tool writes ATOC configs. For raw binary writes to arbitrary MRAM addresses, you need the ISP write_image function. Check if `alif-flash` has a raw write tool, or use Python directly:

```python
# From workspace root:
import sys; sys.path.insert(0, 'claude-mcps/alif-flash/src')
from alif_flash.isp import ISPConnection
conn = ISPConnection('/dev/cu.usbmodem*')  # auto-detect
conn.write_image('firmware/linux/alif-e7/images/xipImage-ospi', 0x80020000)
conn.write_image('firmware/linux/alif-e7/images/ospi-hdr-kernel.bin', 0x8000E000)
```

### Phase 3: Rootfs to OSPI (2 passes)

**Pass 1 (5MB → 0xC0000000):**
1. Enter maintenance mode
2. Write `rootfs-ospi-part1.bin` (5MB) to MRAM 0x80020000
3. Write `ospi-hdr-rootfs1.bin` to MRAM 0x8000E000
4. Power cycle → TF-A programs rootfs part 1
5. Check the box: `- [x] Rootfs part 1 programmed to OSPI`

**Pass 2 (1.3MB → 0xC0500000):**
6. Enter maintenance mode
7. Write `rootfs-ospi-part2.bin` (1.36MB) to MRAM 0x80020000
8. Write `ospi-hdr-rootfs2.bin` to MRAM 0x8000E000
9. Power cycle → TF-A programs rootfs part 2
10. Check the box: `- [x] Rootfs part 2 programmed to OSPI`

### Phase 4: Verify Linux boot + ADB

1. After final power cycle, Linux should boot from OSPI
2. Monitor UART2 for kernel boot messages
3. Check `adb devices` on Mac host
4. Check `adb shell` for root shell
5. Check the boxes in `plan.md`
6. Update plan status to `Complete` if all checks pass

## Completion

When ALL verification checkboxes in `plan.md` are checked, output:

```
<promise>OSPI BOOT COMPLETE</promise>
```

## Notifying the User

When you need the user to do something physical (power cycle, enter maintenance, check UART output), run the notification helper via Bash:

```bash
./plans/alif-e7-ospi-boot/notify-and-wait.sh "Power cycle the board" "Unplug and replug PRG_USB"
./plans/alif-e7-ospi-boot/notify-and-wait.sh "Enter maintenance mode" "Hold BOOT button during power-on"
./plans/alif-e7-ospi-boot/notify-and-wait.sh "Check UART2 console" "Look for OSPI PROG messages"
```

This sends a **macOS notification + terminal bell** and **blocks until the user presses Enter**. Always use this instead of just printing a message — it ensures the user sees the request and confirms before you continue.

## Important Notes

- **Always read plan.md first** to see current progress — don't repeat completed steps
- **Power cycles require user interaction** — use `notify-and-wait.sh` and wait for confirmation
- **SE-UART maintenance can be flaky** — if `alif-flash.maintenance()` fails, notify user to enter maintenance manually
- **Each MRAM staging pass**: enter maintenance → write data → write header → notify power cycle → wait for OSPI programming
- **UART2 monitoring**: After each power cycle, notify user to check console output
- Use MCP tools (`alif-flash.*`) for all flash operations — never shell out to CLI equivalents
- The `alif-flash.flash` tool handles ATOC configs. For raw MRAM writes (kernel/rootfs staging + headers), check available `alif-flash` tools or use Python ISP directly
