# STM32MP1 USB Gadget Networking for macOS

Status: Complete
Created: 2026-02-16

## Problem

The STM32MP157C-DK2 board's USB OTG port (CN7) presents a USB gadget with `usb0` at 192.168.7.2 on the A7 Linux side, but macOS doesn't create a corresponding network interface. This blocks SCP/SSH file deployment to the board, which is the primary development workflow for A7 Linux apps.

**Root cause (networking):** The OpenSTLinux image configures an RNDIS gadget by default via configfs. macOS has zero native RNDIS support (HoRNDIS is dead on Big Sur+). Fixed by switching to a pure CDC-ECM gadget via a systemd service that reconfigures configfs at boot.

**Root cause (SSH):** Even after USB networking works, `ssh root@192.168.7.2` fails with "no matching host key type found. Their offer: ssh-rsa". Dropbear v2018.76 on the OpenSTLinux image only supports RSA host keys, but modern macOS OpenSSH disables ssh-rsa by default.

## Approach

Two-part fix:
1. **CDC-ECM gadget service** on the board — tears down RNDIS, sets up pure ECM at boot
2. **SSH config on Mac** — `~/.ssh/config` entry re-enables ssh-rsa for the board

## Solution

### USB Networking (CDC-ECM + DHCP)
A systemd service (`usb-ecm.service`) at `/etc/systemd/system/` runs `/usr/bin/usb-ecm.sh` at boot to:
- Bring down usb0 (RNDIS) to avoid duplicate IP conflict
- Unbind the UDC, remove RNDIS function, create pure ECM function
- Rebind UDC to `49000000.usb-otg`
- Bring up the ECM interface (usb1) with `192.168.7.2/24`
- Start udhcpd to hand out `192.168.7.1` to macOS via DHCP

macOS auto-configures — no manual `ifconfig` needed.

### SSH (Dropbear ssh-rsa)
`~/.ssh/config`:
```
Host stm32mp1 192.168.7.2
    HostName 192.168.7.2
    User root
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa
```

ECDSA key generation doesn't help — Dropbear v2018.76 doesn't support ECDSA host keys, and the service unit hardcodes `-r dropbear_rsa_host_key`.

## Implementation Notes

- Hot-swapping RNDIS→ECM with cable connected creates a dead data path. Must replug Type-C or do the switch at boot.
- ECM creates a NEW interface (usb1, not usb0) on the board side.
- **Must bring down usb0 before reconfiguring** — stock init gives usb0 the same IP, causing duplicate IP routing conflict where replies go out the RNDIS interface.
- Boot-to-SSH takes ~35-40 seconds (gadget reconfiguration sleeps + DHCP handshake).
- OpenSTLinux rootfs has no `/usr/local/bin/` — scripts go in `/usr/bin/`.
- `dropbearkey` exists at `/usr/sbin/dropbearkey` but isn't in default PATH.
- Works on DK1 (STM32MP157D) and DK2 (STM32MP157C) — same board definition in Zephyr.

## Verification

- [x] `ping 192.168.7.2` from Mac succeeds
- [x] `ssh stm32mp1` works (via ~/.ssh/config alias)
- [x] `scp` file transfer works
- [x] `linux-build.deploy()` successfully SCPs files to the board
- [x] `linux-build.ssh_command()` runs commands on the board
- [x] Full deploy→run cycle works end-to-end
- [x] Zero-touch reboot: macOS auto-gets IP via DHCP, SSH works without manual ifconfig
