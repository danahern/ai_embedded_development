#!/bin/bash
# Embedded Workspace Setup Script

set -e

echo "=== Embedded Workspace Setup ==="

# Check for required tools
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo "Error: $1 is required but not installed."
        exit 1
    fi
}

check_tool git
check_tool python3

# Initialize submodules if in a git repo with submodules
if [ -f .gitmodules ]; then
    echo "Initializing submodules..."
    git submodule update --init --recursive
fi

# Set up west
echo "Setting up West (Zephyr build system)..."
cd zephyr-apps

if [ ! -d "../zephyr" ]; then
    echo "Initializing west workspace..."
    west init -l .
    echo "Fetching Zephyr dependencies (this may take a while)..."
    west update
else
    echo "West workspace already initialized"
fi

cd ..

# Set up Python environment
echo "Setting up Python environment..."
if [ ! -d "zephyr-apps/.venv" ]; then
    python3 -m venv zephyr-apps/.venv
fi

source zephyr-apps/.venv/bin/activate
pip install --upgrade pip
pip install west
if [ -f "zephyr-apps/requirements.txt" ]; then
    pip install -r zephyr-apps/requirements.txt
fi

# Build MCP server if Rust is available
if command -v cargo &> /dev/null; then
    echo "Building embedded-probe MCP server..."
    cd claude-mcps/embedded-probe
    cargo build --release
    cd ../..
    echo "MCP binary at: claude-mcps/embedded-probe/target/release/embedded-probe"
else
    echo "Rust not found, skipping MCP build (install with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Activate environment: source zephyr-apps/.venv/bin/activate"
echo "  2. Build firmware: cd zephyr-apps && west build -b <board> apps/<app>"
echo "  3. Configure Claude Code MCP settings if using embedded-probe"
echo ""
