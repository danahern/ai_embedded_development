# CI Self-Hosted Runner Setup (danahern-pc)

Status: Planned
Created: 2026-02-15

## Problem

Need a self-hosted GitHub Actions runner on danahern-pc for fast CI builds and hardware-in-the-loop testing. This machine has dev boards plugged in via USB and will serve as the prototype hardware lab.

## Machine Specs

- **Host:** danahern-pc
- **CPU:** Intel i9-9900K (8 cores / 16 threads @ 3.6GHz)
- **RAM:** 64GB
- **Storage:** ~5TB available
- **OS:** Windows 11 Pro 25H2
- **Network:** Always-on, remotely accessible

## Goal

Set up WSL2 with a complete embedded development environment and a GitHub Actions self-hosted runner agent. When done, this machine should:
1. Pick up CI jobs from GitHub Actions automatically
2. Run `cargo test` for all Rust MCP servers
3. Run `pytest` for Python MCP servers and test-tools
4. Run Zephyr twister tests on QEMU
5. Flash firmware to connected boards via probe-rs / nrfjprog
6. Run hardware-in-the-loop tests (BLE discover, WiFi provision, TCP throughput)

## Setup Steps

### 1. WSL2 + Ubuntu

```powershell
# In PowerShell (Admin)
wsl --install -d Ubuntu-24.04
wsl --set-default Ubuntu-24.04
```

After install, launch Ubuntu and create a user account.

### 2. usbipd-win (USB passthrough to WSL2)

```powershell
# In PowerShell (Admin)
winget install usbipd
```

After install, list USB devices and bind the ones we need:
```powershell
usbipd list                    # Find J-Link, nRF DKs, ESP32 serial
usbipd bind --busid <BUSID>   # Bind each device
usbipd attach --wsl --busid <BUSID>  # Attach to WSL2
```

Verify from WSL2:
```bash
lsusb  # Should see J-Link / SEGGER devices
```

Note: USB attach doesn't persist across reboots. Create a PowerShell script or scheduled task to re-attach on boot.

### 3. Core Tools (inside WSL2)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential git cmake ninja-build gperf \
  ccache dfu-util device-tree-compiler wget curl \
  python3-dev python3-pip python3-venv python3-setuptools \
  xz-utils file make gcc gcc-multilib g++-multilib \
  libsdl2-dev libmagic1 unzip qemu-system-arm
```

### 4. Zephyr SDK

```bash
cd ~
wget https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64.tar.xz
tar xf zephyr-sdk-0.17.0_linux-x86_64.tar.xz
cd zephyr-sdk-0.17.0
./setup.sh -t arm-zephyr-eabi  # ARM toolchain only (add others as needed)
```

Verify: `~/zephyr-sdk-0.17.0/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc --version`

### 5. Rust Toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source ~/.cargo/env
rustc --version
```

### 6. probe-rs

```bash
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/probe-rs/probe-rs/releases/latest/download/probe-rs-tools-installer.sh | sh
probe-rs list  # Should see attached probes (after usbipd attach)
```

### 7. Clone Workspace + West Init

```bash
cd ~
git clone --recursive git@github.com:danahern/ai_embedded_development.git work
cd work

# Create Python venv for Zephyr
python3 -m venv .venv
source .venv/bin/activate
pip install west

# Init west workspace
cd zephyr-apps
west init -l .
west update
pip install -r ../zephyr/scripts/requirements.txt
```

### 8. Verify Everything Works

Run these inside WSL2 to confirm the environment is correct:

```bash
cd ~/work

# Rust MCP server tests
cd claude-mcps/zephyr-build && cargo test
cd ../embedded-probe && cargo test
cd ../elf-analysis && cargo test
cd ../esp-idf-build && cargo test
cd ../knowledge-server && cargo test

# Python tests
cd ../saleae-logic && python3 -m pytest tests/
cd ../hw-test-runner && python3 -m pytest tests/

# Zephyr twister
cd ~/work
source .venv/bin/activate
source zephyr/zephyr-env.sh
python3 zephyr/scripts/twister -T zephyr-apps/lib -p qemu_cortex_m3 -v

# probe-rs (with board plugged in and usbipd attached)
probe-rs list
```

### 9. GitHub Actions Self-Hosted Runner

```bash
mkdir ~/actions-runner && cd ~/actions-runner

# Download latest runner (check https://github.com/actions/runner/releases for current version)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Configure — get token from:
# https://github.com/danahern/ai_embedded_development/settings/actions/runners/new
./config.sh --url https://github.com/danahern/ai_embedded_development \
  --token <RUNNER_TOKEN> \
  --name danahern-pc \
  --labels self-hosted,linux,hw-test \
  --work _work

# Install as systemd service (auto-start on WSL boot)
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

### 10. Runner Environment Variables

The runner needs to know where tools are. Create `~/actions-runner/.env`:

```
ZEPHYR_SDK_INSTALL_DIR=/home/<user>/zephyr-sdk-0.17.0
ZEPHYR_TOOLCHAIN_VARIANT=zephyr
PATH=/home/<user>/.cargo/bin:/home/<user>/.local/bin:/usr/local/bin:/usr/bin:/bin
```

### 11. Auto-Start WSL2 on Windows Boot

Create a scheduled task so WSL2 starts automatically when Windows boots (no login required):

```powershell
# In PowerShell (Admin)
$action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu-24.04 -- sudo /home/<user>/actions-runner/svc.sh start"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "WSL-GitHub-Runner" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest
```

### 12. usbipd Auto-Attach on Boot

Create `C:\scripts\attach-usb.ps1`:
```powershell
# Wait for devices to enumerate
Start-Sleep -Seconds 30

# Attach known devices (update BUSIDs after first manual setup)
usbipd attach --wsl --busid <JLINK_BUSID>
usbipd attach --wsl --busid <NRF_BUSID>
# Add more as needed
```

Register as scheduled task:
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\scripts\attach-usb.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Seconds 60)
Register-ScheduledTask -TaskName "USB-Attach-WSL" -Action $action -Trigger $trigger -RunLevel Highest
```

## Verification

- [ ] WSL2 Ubuntu 24.04 running
- [ ] `usbipd list` shows connected boards from Windows
- [ ] `lsusb` in WSL2 shows boards after attach
- [ ] `probe-rs list` sees J-Link / debug probes
- [ ] `cargo test` passes for all Rust MCP servers
- [ ] `pytest` passes for Python MCP servers
- [ ] `twister` passes for Zephyr library tests on qemu_cortex_m3
- [ ] GitHub Actions runner agent is running (`./svc.sh status`)
- [ ] Runner appears in repo Settings → Actions → Runners as "Idle"
- [ ] A test workflow with `runs-on: [self-hosted, hw-test]` picks up on this machine
- [ ] WSL2 + runner auto-start on Windows boot (no manual login needed)
- [ ] USB devices auto-attach after reboot

## Notes

- Runner token expires. Regenerate from GitHub Settings → Actions → Runners if config.sh fails.
- `usbipd attach` is not persistent — that's why the scheduled task is needed.
- WSL2 systemd support requires Windows 11 22H2+. Verify `systemctl` works inside WSL2 (`systemctl status`). If not, enable it in `/etc/wsl.conf` with `[boot] systemd=true`.
- The runner's `_work` directory will grow with each job. With 5TB this isn't urgent, but consider periodic cleanup of old workflow runs.
