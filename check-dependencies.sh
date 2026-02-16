#!/bin/bash
# Workspace Dependency Checker
# Read-only validation — checks that setup completed correctly without modifying anything.

set -uo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Tracking ────────────────────────────────────────────────────────────────

FAILS=0
WARNS=0
PASSES=0

section() { echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}"; }
pass()    { echo -e "  ${GREEN}PASS${NC}  $1"; PASSES=$((PASSES + 1)); }
fail()    { echo -e "  ${RED}FAIL${NC}  $1"; FAILS=$((FAILS + 1)); }
warn()    { echo -e "  ${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS + 1)); }

# ── Prerequisites ───────────────────────────────────────────────────────────

section "Prerequisites"

# git
if command -v git &> /dev/null; then
    pass "git found"
else
    fail "git not found"
fi

# python3 >= 3.10
if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
    if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
        pass "python3 $PY_VERSION"
    else
        fail "python3 $PY_VERSION found but >= 3.10 required"
    fi
else
    fail "python3 not found"
fi

# cargo
if command -v cargo &> /dev/null; then
    pass "cargo found"
else
    fail "cargo not found — needed to build MCP servers"
fi

# libusb (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
    if brew list libusb &> /dev/null 2>&1; then
        pass "libusb found"
    else
        fail "libusb not found (brew install libusb)"
    fi
fi

# ── Submodules ──────────────────────────────────────────────────────────────

section "Submodules"

for submod in claude-config claude-mcps firmware; do
    dir="$WORKSPACE_DIR/$submod"
    if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
        pass "$submod/ populated"
    else
        fail "$submod/ missing or empty — run: git submodule update --init --recursive"
    fi
done

# ── Zephyr ──────────────────────────────────────────────────────────────────

section "Zephyr"

# .west directory
if [ -d "$WORKSPACE_DIR/.west" ]; then
    pass ".west/ exists"
else
    fail ".west/ not found — run setup.sh or: cd firmware && west init -l ."
fi

# Python venv
if [ -d "$WORKSPACE_DIR/firmware/.venv" ]; then
    pass "firmware/.venv exists"
else
    fail "Zephyr venv not found — run setup.sh"
fi

# Zephyr SDK detection (same 3-step logic as setup.sh)
SDK_FOUND=false

# 1. Env var
if [ -n "${ZEPHYR_SDK_INSTALL_DIR:-}" ] && [ -d "${ZEPHYR_SDK_INSTALL_DIR}" ]; then
    SDK_FOUND=true
    SDK_PATH="$ZEPHYR_SDK_INSTALL_DIR"
fi

# 2. cmake registry
if [ "$SDK_FOUND" = false ] && [ -d "$HOME/.cmake/packages/Zephyr-sdk" ]; then
    for reg_file in "$HOME/.cmake/packages/Zephyr-sdk"/*; do
        if [ -f "$reg_file" ]; then
            cmake_dir="$(cat "$reg_file" | tr -d '[:space:]')"
            sdk_dir="$(dirname "$cmake_dir")"
            if [ -f "$sdk_dir/sdk_version" ]; then
                SDK_FOUND=true
                SDK_PATH="$sdk_dir"
                break
            fi
        fi
    done
fi

# 3. Filesystem scan
if [ "$SDK_FOUND" = false ]; then
    for candidate in "$HOME"/zephyr-sdk-* /opt/zephyr-sdk-*; do
        if [ -d "$candidate" ] && [ -f "$candidate/sdk_version" ]; then
            SDK_FOUND=true
            SDK_PATH="$candidate"
            break
        fi
    done
fi

if [ "$SDK_FOUND" = true ]; then
    SDK_VER="$(cat "$SDK_PATH/sdk_version")"
    pass "Zephyr SDK $SDK_VER at $SDK_PATH"
else
    fail "Zephyr SDK not found"
fi

# ── ESP-IDF ─────────────────────────────────────────────────────────────────

section "ESP-IDF (optional)"

IDF_FOUND=false
if [ -n "${IDF_PATH:-}" ] && [ -d "$IDF_PATH" ]; then
    IDF_FOUND=true
    pass "ESP-IDF at \$IDF_PATH: $IDF_PATH"
elif [ -d "$HOME/esp/esp-idf" ]; then
    IDF_FOUND=true
    pass "ESP-IDF at ~/esp/esp-idf"
elif [ -d "$HOME/.espressif/esp-idf" ]; then
    IDF_FOUND=true
    pass "ESP-IDF at ~/.espressif/esp-idf"
fi

if [ "$IDF_FOUND" = false ]; then
    warn "ESP-IDF not found — ESP32 builds won't work"
fi

# ── MCP Binaries ────────────────────────────────────────────────────────────

section "MCP Binaries"

for server in embedded-probe zephyr-build esp-idf-build; do
    bin="$WORKSPACE_DIR/claude-mcps/$server/target/release/$server"
    if [ -x "$bin" ]; then
        pass "$server binary exists"
    else
        fail "$server binary not found — run setup.sh or: cd claude-mcps/$server && cargo build --release"
    fi
done

# ── Saleae Logic (optional) ────────────────────────────────────────────────

section "Saleae Logic (optional)"

SALEAE_VENV="$WORKSPACE_DIR/claude-mcps/saleae-logic/.venv"
if [ -d "$SALEAE_VENV" ]; then
    pass "saleae-logic venv exists"
else
    warn "saleae-logic venv not found — signal analysis won't work"
fi

# ── Config Files ────────────────────────────────────────────────────────────

section "Config"

# .mcp.json
MCP_JSON="$WORKSPACE_DIR/.mcp.json"
if [ -f "$MCP_JSON" ]; then
    if python3 -c "import json; json.load(open('$MCP_JSON'))" 2>/dev/null; then
        pass ".mcp.json exists and is valid JSON"
    else
        fail ".mcp.json exists but is not valid JSON — re-run setup.sh"
    fi
else
    fail ".mcp.json not found — run setup.sh"
fi

# .claude/commands symlink
CMDS_LINK="$WORKSPACE_DIR/.claude/commands"
if [ -L "$CMDS_LINK" ] && [ -d "$CMDS_LINK" ]; then
    pass ".claude/commands symlink valid"
elif [ -d "$CMDS_LINK" ]; then
    pass ".claude/commands exists (directory)"
else
    fail ".claude/commands missing — run setup.sh"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Summary:${NC} ${GREEN}$PASSES passed${NC}, ${RED}$FAILS failed${NC}, ${YELLOW}$WARNS warnings${NC}"

if [ "$FAILS" -gt 0 ]; then
    echo -e "\nRun ${BOLD}./setup.sh${NC} to fix failures."
    exit 1
else
    echo -e "\n${GREEN}${BOLD}Workspace is ready.${NC}"
    exit 0
fi
