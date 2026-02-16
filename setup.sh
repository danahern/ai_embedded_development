#!/bin/bash
# Embedded Workspace Setup Script
# Sets up Zephyr RTOS, ESP-IDF, Saleae Logic, and MCP servers for Claude Code.

set -euo pipefail

# Resolve workspace to absolute path
WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Flags ───────────────────────────────────────────────────────────────────

INSTALL_ZEPHYR=true
INSTALL_ESP_IDF=true
INSTALL_SALEAE=true
INSTALL_DOCKER=false
RUN_TESTS=true

ZEPHYR_CI_IMAGE="ghcr.io/zephyrproject-rtos/ci:v0.28.7"

# ── Tracking ────────────────────────────────────────────────────────────────

WARNINGS=()
COMPONENTS=()        # ("name:status") pairs
MCP_SERVERS=()       # ("name:path") pairs
TEST_PASS=0
TEST_FAIL=0

# ── Argument Parsing ───────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: ./setup.sh [OPTIONS]

Options:
  --no-zephyr    Skip Zephyr RTOS setup (west, SDK, venv)
  --no-esp-idf   Skip ESP-IDF setup
  --no-saleae    Skip Saleae Logic analyzer setup
  --with-docker  Set up Docker for reproducible builds (pulls Zephyr CI image)
  --skip-tests   Skip test verification after build
  --help         Show this help message

Examples:
  ./setup.sh                              # Install everything (no Docker)
  ./setup.sh --with-docker                # Install everything + Docker builds
  ./setup.sh --no-zephyr --no-esp-idf     # Only embedded-probe + saleae-logic
  ./setup.sh --skip-tests                 # Install everything, skip tests
EOF
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --no-zephyr)   INSTALL_ZEPHYR=false ;;
        --no-esp-idf)  INSTALL_ESP_IDF=false ;;
        --no-saleae)   INSTALL_SALEAE=false ;;
        --with-docker) INSTALL_DOCKER=true ;;
        --skip-tests)  RUN_TESTS=false ;;
        --help)        usage ;;
        *)
            echo "Unknown option: $arg"
            usage
            ;;
    esac
done

# ── Helper Functions ───────────────────────────────────────────────────────

section() { echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}"; }
info()    { echo -e "  ${BOLD}→${NC} $1"; }
success() { echo -e "  ${GREEN}✓${NC} $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS+=("$1"); }
error()   { echo -e "  ${RED}✗${NC} $1"; }

check_tool() {
    local tool="$1"
    local hint="${2:-}"
    if command -v "$tool" &> /dev/null; then
        success "$tool found: $(command -v "$tool")"
        return 0
    else
        error "$tool not found"
        if [ -n "$hint" ]; then
            info "Install with: $hint"
        fi
        return 1
    fi
}

# ── Prerequisites ──────────────────────────────────────────────────────────

section "Prerequisites"

# git (required)
if ! check_tool git; then
    echo "git is required. Aborting."
    exit 1
fi

# python3 >= 3.10
PYTHON_OK=false
if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PY_MAJOR=$(echo "$PY_VERSION" | cut -d. -f1)
    PY_MINOR=$(echo "$PY_VERSION" | cut -d. -f2)
    if [ "$PY_MAJOR" -ge 3 ] && [ "$PY_MINOR" -ge 10 ]; then
        success "python3 $PY_VERSION found"
        PYTHON_OK=true
    else
        warn "python3 $PY_VERSION found but >= 3.10 required"
        info "Install with: brew install python@3.12"
    fi
else
    warn "python3 not found"
    info "Install with: brew install python@3.12"
fi

# cargo / rustc
RUST_OK=false
if check_tool cargo; then
    RUST_OK=true
else
    warn "Rust not found — MCP servers cannot be built"
    info "Install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

# macOS: libusb (needed for probe-rs)
if [[ "$(uname)" == "Darwin" ]]; then
    if brew list libusb &> /dev/null 2>&1; then
        success "libusb found (via Homebrew)"
    else
        warn "libusb not found — needed for embedded-probe build"
        info "Install with: brew install libusb"
    fi
fi

# Docker (optional, for reproducible builds)
DOCKER_OK=false
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        success "Docker found and running"
        DOCKER_OK=true
    else
        if [ "$INSTALL_DOCKER" = true ]; then
            warn "Docker found but daemon not running — start Docker Desktop first"
        else
            info "Docker found but not running (use --with-docker to set up Docker builds)"
        fi
    fi
else
    if [ "$INSTALL_DOCKER" = true ]; then
        warn "Docker not found — install Docker Desktop first"
        info "Download: https://www.docker.com/products/docker-desktop/"
    fi
fi

# ── Submodules ─────────────────────────────────────────────────────────────

section "Submodules"

info "Updating git submodules..."
cd "$WORKSPACE_DIR"
git submodule update --init --recursive
success "Submodules up to date"

# ── Zephyr Setup ───────────────────────────────────────────────────────────

if [ "$INSTALL_ZEPHYR" = true ]; then
    section "Zephyr RTOS"

    # West init
    if [ -d "$WORKSPACE_DIR/.west" ]; then
        success "West workspace already initialized"
    else
        info "Initializing west workspace..."
        cd "$WORKSPACE_DIR/zephyr-apps"
        west init -l .
        cd "$WORKSPACE_DIR"
        success "West workspace initialized"
    fi

    # West update
    info "Running west update (this downloads ~2GB on first run)..."
    cd "$WORKSPACE_DIR"
    west update
    success "West dependencies up to date"

    # Python venv
    if [ "$PYTHON_OK" = true ]; then
        ZEPHYR_VENV="$WORKSPACE_DIR/zephyr-apps/.venv"
        if [ -d "$ZEPHYR_VENV" ]; then
            success "Zephyr venv already exists"
        else
            info "Creating Zephyr Python venv..."
            python3 -m venv "$ZEPHYR_VENV"
            success "Venv created at zephyr-apps/.venv"
        fi

        info "Installing Python dependencies..."
        "$ZEPHYR_VENV/bin/pip" install --upgrade pip --quiet
        "$ZEPHYR_VENV/bin/pip" install west --quiet
        if [ -f "$WORKSPACE_DIR/zephyr-apps/requirements.txt" ]; then
            "$ZEPHYR_VENV/bin/pip" install -r "$WORKSPACE_DIR/zephyr-apps/requirements.txt" --quiet
        fi
        if [ -f "$WORKSPACE_DIR/zephyr/scripts/requirements.txt" ]; then
            "$ZEPHYR_VENV/bin/pip" install -r "$WORKSPACE_DIR/zephyr/scripts/requirements.txt" --quiet
        fi
        success "Python dependencies installed"
    else
        warn "Skipping Zephyr venv — python3 >= 3.10 required"
    fi

    # Zephyr SDK detection: env var → cmake registry → filesystem scan
    SDK_FOUND=false
    SDK_REGISTERED=false
    SDK_PATH=""

    # 1. Check env var
    if [ -n "${ZEPHYR_SDK_INSTALL_DIR:-}" ] && [ -d "${ZEPHYR_SDK_INSTALL_DIR}" ]; then
        SDK_PATH="$ZEPHYR_SDK_INSTALL_DIR"
        SDK_FOUND=true
    fi

    # 2. Check cmake package registry (populated by SDK's setup.sh)
    if [ -d "$HOME/.cmake/packages/Zephyr-sdk" ]; then
        for reg_file in "$HOME/.cmake/packages/Zephyr-sdk"/*; do
            if [ -f "$reg_file" ]; then
                cmake_dir="$(cat "$reg_file" | tr -d '[:space:]')"
                sdk_dir="$(dirname "$cmake_dir")"
                if [ -f "$sdk_dir/sdk_version" ]; then
                    SDK_PATH="$sdk_dir"
                    SDK_FOUND=true
                    SDK_REGISTERED=true
                fi
            fi
        done
    fi

    # 3. Scan common install locations if not found yet
    if [ "$SDK_FOUND" = false ]; then
        for candidate in "$HOME"/zephyr-sdk-* /opt/zephyr-sdk-*; do
            if [ -d "$candidate" ] && [ -f "$candidate/sdk_version" ]; then
                SDK_PATH="$candidate"
                SDK_FOUND=true
                break
            fi
        done
    fi

    if [ "$SDK_FOUND" = true ]; then
        SDK_VER="$(cat "$SDK_PATH/sdk_version")"
        success "Zephyr SDK $SDK_VER found at $SDK_PATH"

        # Ensure SDK is registered with cmake (required for twister/west to find it)
        if [ "$SDK_REGISTERED" = false ] && [ -f "$SDK_PATH/setup.sh" ]; then
            info "SDK not registered with cmake — running SDK setup.sh..."
            "$SDK_PATH/setup.sh"
            success "SDK registered with cmake"
        fi
    else
        warn "Zephyr SDK not found — needed for building and testing firmware"
        info "Install from: https://docs.zephyrproject.org/latest/develop/getting_started/index.html"
        info "After installing, run the SDK's setup.sh to register with cmake"
    fi

    COMPONENTS+=("Zephyr RTOS:installed")
else
    info "Skipping Zephyr setup (--no-zephyr)"
    COMPONENTS+=("Zephyr RTOS:skipped")
fi

# ── ESP-IDF Setup ──────────────────────────────────────────────────────────

if [ "$INSTALL_ESP_IDF" = true ]; then
    section "ESP-IDF"

    # Clone esp-dev-kits examples if not present
    if [ -d "$WORKSPACE_DIR/esp-dev-kits" ]; then
        success "esp-dev-kits already cloned"
    else
        info "Cloning esp-dev-kits examples..."
        git clone https://github.com/espressif/esp-dev-kits.git "$WORKSPACE_DIR/esp-dev-kits"
        success "esp-dev-kits cloned"
    fi

    # Detect ESP-IDF installation
    IDF_FOUND=false
    if [ -n "${IDF_PATH:-}" ] && [ -d "$IDF_PATH" ]; then
        success "ESP-IDF found at \$IDF_PATH: $IDF_PATH"
        IDF_FOUND=true
    elif [ -d "$HOME/esp/esp-idf" ]; then
        success "ESP-IDF found at ~/esp/esp-idf"
        IDF_FOUND=true
    elif [ -d "$HOME/.espressif/esp-idf" ]; then
        success "ESP-IDF found at ~/.espressif/esp-idf"
        IDF_FOUND=true
    fi

    if [ "$IDF_FOUND" = false ]; then
        warn "ESP-IDF not found — install separately (too large to auto-clone)"
        info "Install guide: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/get-started/"
        info "Quick: mkdir -p ~/esp && cd ~/esp && git clone --recursive https://github.com/espressif/esp-idf.git && cd esp-idf && ./install.sh all"
    fi

    COMPONENTS+=("ESP-IDF:installed")
else
    info "Skipping ESP-IDF setup (--no-esp-idf)"
    COMPONENTS+=("ESP-IDF:skipped")
fi

# ── Saleae Logic Setup ────────────────────────────────────────────────────

if [ "$INSTALL_SALEAE" = true ]; then
    section "Saleae Logic"

    if [ "$PYTHON_OK" = true ]; then
        SALEAE_VENV="$WORKSPACE_DIR/claude-mcps/saleae-logic/.venv"
        if [ -d "$SALEAE_VENV" ]; then
            success "Saleae venv already exists"
        else
            info "Creating Saleae Logic Python venv..."
            python3 -m venv "$SALEAE_VENV"
            success "Venv created at claude-mcps/saleae-logic/.venv"
        fi

        info "Installing saleae-logic package..."
        "$SALEAE_VENV/bin/pip" install --upgrade pip --quiet
        "$SALEAE_VENV/bin/pip" install -e "$WORKSPACE_DIR/claude-mcps/saleae-logic" --quiet
        "$SALEAE_VENV/bin/pip" install pytest pytest-asyncio --quiet
        success "saleae-logic installed with dependencies"
    else
        warn "Skipping Saleae venv — python3 >= 3.10 required"
    fi

    info "Saleae Logic 2 desktop app required for live captures"
    info "Download: https://www.saleae.com/downloads/"
    info "Enable automation: Preferences → Enable scripting API"

    COMPONENTS+=("Saleae Logic:installed")
else
    info "Skipping Saleae Logic setup (--no-saleae)"
    COMPONENTS+=("Saleae Logic:skipped")
fi

# ── Docker Setup ──────────────────────────────────────────────────────────

if [ "$INSTALL_DOCKER" = true ]; then
    section "Docker Builds"

    if [ "$DOCKER_OK" = true ]; then
        info "Pulling Zephyr CI container ($ZEPHYR_CI_IMAGE)..."
        if docker pull "$ZEPHYR_CI_IMAGE" 2>&1; then
            success "Zephyr CI container pulled"
        else
            warn "Failed to pull Zephyr CI container"
        fi

        info "Docker builds available via Makefile in zephyr-apps/"
        info "  make build APP=<app> BOARD=<board>   # Build in container"
        info "  make test                              # Run unit tests on QEMU"
        info "  make shell                             # Interactive container"

        COMPONENTS+=("Docker Builds:installed")
    else
        warn "Skipping Docker setup — Docker not available"
        info "Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
        info "Then re-run: ./setup.sh --with-docker"
        COMPONENTS+=("Docker Builds:failed")
    fi
else
    COMPONENTS+=("Docker Builds:skipped")
fi

# ── MCP Server Builds ─────────────────────────────────────────────────────

section "MCP Server Builds"

if [ "$RUST_OK" = true ]; then
    # embedded-probe (always)
    info "Building embedded-probe..."
    cd "$WORKSPACE_DIR/claude-mcps/embedded-probe"
    if cargo build --release 2>&1; then
        EP_BIN="$WORKSPACE_DIR/claude-mcps/embedded-probe/target/release/embedded-probe"
        success "embedded-probe built"
        MCP_SERVERS+=("embedded-probe:$EP_BIN")
    else
        error "embedded-probe build failed"
        MCP_SERVERS+=("embedded-probe:FAILED")
    fi

    # zephyr-build (if Zephyr)
    if [ "$INSTALL_ZEPHYR" = true ]; then
        info "Building zephyr-build..."
        cd "$WORKSPACE_DIR/claude-mcps/zephyr-build"
        if cargo build --release 2>&1; then
            ZB_BIN="$WORKSPACE_DIR/claude-mcps/zephyr-build/target/release/zephyr-build"
            success "zephyr-build built"
            MCP_SERVERS+=("zephyr-build:$ZB_BIN")
        else
            error "zephyr-build build failed"
            MCP_SERVERS+=("zephyr-build:FAILED")
        fi
    fi

    # esp-idf-build (if ESP-IDF)
    if [ "$INSTALL_ESP_IDF" = true ]; then
        info "Building esp-idf-build..."
        cd "$WORKSPACE_DIR/claude-mcps/esp-idf-build"
        if cargo build --release 2>&1; then
            EI_BIN="$WORKSPACE_DIR/claude-mcps/esp-idf-build/target/release/esp-idf-build"
            success "esp-idf-build built"
            MCP_SERVERS+=("esp-idf-build:$EI_BIN")
        else
            error "esp-idf-build build failed"
            MCP_SERVERS+=("esp-idf-build:FAILED")
        fi
    fi

    cd "$WORKSPACE_DIR"
else
    warn "Skipping MCP builds — Rust not installed"
fi

# saleae-logic (Python, no cargo build needed)
if [ "$INSTALL_SALEAE" = true ] && [ "$PYTHON_OK" = true ]; then
    SALEAE_PY="$WORKSPACE_DIR/claude-mcps/saleae-logic/.venv/bin/python"
    if [ -f "$SALEAE_PY" ]; then
        MCP_SERVERS+=("saleae-logic:$SALEAE_PY")
    fi
fi

# ── .mcp.json Generation ──────────────────────────────────────────────────

section ".mcp.json Generation"

info "Generating .mcp.json with absolute paths..."

python3 -c "
import json, sys

workspace = '$WORKSPACE_DIR'
servers = {}

# embedded-probe (always included if built)
ep_bin = workspace + '/claude-mcps/embedded-probe/target/release/embedded-probe'
servers['embedded-probe'] = {'command': ep_bin}

# zephyr-build
if $( [ "$INSTALL_ZEPHYR" = true ] && echo "True" || echo "False" ):
    zb_bin = workspace + '/claude-mcps/zephyr-build/target/release/zephyr-build'
    servers['zephyr-build'] = {
        'command': zb_bin,
        'args': ['--workspace', workspace]
    }

# esp-idf-build
if $( [ "$INSTALL_ESP_IDF" = true ] && echo "True" || echo "False" ):
    ei_bin = workspace + '/claude-mcps/esp-idf-build/target/release/esp-idf-build'
    servers['esp-idf-build'] = {
        'command': ei_bin,
        'args': ['--projects-dir', workspace + '/esp-dev-kits/examples']
    }

# saleae-logic
if $( [ "$INSTALL_SALEAE" = true ] && echo "True" || echo "False" ):
    sl_py = workspace + '/claude-mcps/saleae-logic/.venv/bin/python'
    servers['saleae-logic'] = {
        'command': sl_py,
        'args': ['-m', 'saleae_logic'],
        'cwd': workspace + '/claude-mcps/saleae-logic'
    }

config = {'mcpServers': servers}
with open(workspace + '/.mcp.json', 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

print(f'  Wrote {len(servers)} servers to .mcp.json')
"

success ".mcp.json generated"

# ── Claude Code Commands ─────────────────────────────────────────────────

section "Claude Code Commands"

CLAUDE_DIR="$WORKSPACE_DIR/.claude"
mkdir -p "$CLAUDE_DIR"

# Symlink the entire commands directory so new commands are picked up automatically
if [ -L "$CLAUDE_DIR/commands" ]; then
    success "commands symlink already exists"
elif [ -d "$CLAUDE_DIR/commands" ]; then
    info "Replacing per-file symlinks with directory symlink..."
    rm -rf "$CLAUDE_DIR/commands"
    ln -s "$WORKSPACE_DIR/claude-config/commands" "$CLAUDE_DIR/commands"
    success "commands directory symlinked"
else
    ln -s "$WORKSPACE_DIR/claude-config/commands" "$CLAUDE_DIR/commands"
    success "commands directory symlinked"
fi

# ── Test Verification ──────────────────────────────────────────────────────

if [ "$RUN_TESTS" = true ]; then
    section "Test Verification"

    # Rust MCP server tests
    if [ "$RUST_OK" = true ]; then
        for server in embedded-probe zephyr-build esp-idf-build; do
            # Skip servers that weren't built
            if [ "$server" = "zephyr-build" ] && [ "$INSTALL_ZEPHYR" = false ]; then continue; fi
            if [ "$server" = "esp-idf-build" ] && [ "$INSTALL_ESP_IDF" = false ]; then continue; fi

            info "Testing $server..."
            cd "$WORKSPACE_DIR/claude-mcps/$server"
            if cargo test 2>&1; then
                success "$server tests passed"
                TEST_PASS=$((TEST_PASS + 1))
            else
                warn "$server tests failed"
                TEST_FAIL=$((TEST_FAIL + 1))
            fi
        done
    fi

    # saleae-logic tests
    if [ "$INSTALL_SALEAE" = true ] && [ "$PYTHON_OK" = true ]; then
        SALEAE_DIR="$WORKSPACE_DIR/claude-mcps/saleae-logic"
        SALEAE_PYTEST="$SALEAE_DIR/.venv/bin/pytest"
        if [ -f "$SALEAE_PYTEST" ]; then
            info "Testing saleae-logic..."
            cd "$SALEAE_DIR"
            if "$SALEAE_PYTEST" tests/test_analysis.py tests/test_server_startup.py -q 2>&1; then
                success "saleae-logic tests passed"
                TEST_PASS=$((TEST_PASS + 1))
            else
                warn "saleae-logic tests failed"
                TEST_FAIL=$((TEST_FAIL + 1))
            fi
        fi
    fi

    cd "$WORKSPACE_DIR"
    info "Tests: $TEST_PASS passed, $TEST_FAIL failed"
else
    info "Skipping tests (--skip-tests)"
fi

# ── Summary ────────────────────────────────────────────────────────────────

section "Setup Complete"

echo ""
echo -e "${BOLD}Components:${NC}"
printf "  %-20s %s\n" "Component" "Status"
printf "  %-20s %s\n" "─────────" "──────"
for entry in "${COMPONENTS[@]}"; do
    name="${entry%%:*}"
    status="${entry##*:}"
    if [ "$status" = "installed" ]; then
        printf "  %-20s ${GREEN}%s${NC}\n" "$name" "$status"
    else
        printf "  %-20s ${YELLOW}%s${NC}\n" "$name" "$status"
    fi
done

echo ""
echo -e "${BOLD}MCP Servers:${NC}"
printf "  %-20s %s\n" "Server" "Binary"
printf "  %-20s %s\n" "──────" "──────"
for entry in "${MCP_SERVERS[@]}"; do
    IFS=':' read -r name path <<< "$entry"
    if [ "$path" = "FAILED" ]; then
        printf "  %-20s ${RED}%s${NC}\n" "$name" "BUILD FAILED"
    else
        printf "  %-20s ${GREEN}%s${NC}\n" "$name" "$path"
    fi
done

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo ""
    echo -e "${BOLD}${YELLOW}Warnings:${NC}"
    for w in "${WARNINGS[@]}"; do
        echo -e "  ${YELLOW}⚠${NC} $w"
    done
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
if [ "$INSTALL_ZEPHYR" = true ]; then
    echo "  1. Activate Zephyr env: source zephyr-apps/.venv/bin/activate"
fi
echo "  2. Open workspace in Claude Code — MCP servers auto-register from .mcp.json"
echo "  3. Try: \"Build the blinky app for nrf52840dk\""
echo ""
