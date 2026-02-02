#!/bin/bash
# Convert existing folders to git submodules
# Run this AFTER creating GitHub repos and setting remotes

set -e

echo "=== Converting to Submodules ==="
echo ""
echo "This script converts existing folders to git submodules."
echo "Prerequisites:"
echo "  1. Create GitHub repos for: claude-config, claude-mcps, zephyr-apps"
echo "  2. Add remotes to each folder first:"
echo "     cd claude-config && git remote add origin <url> && git push -u origin main"
echo "     (repeat for claude-mcps, zephyr-apps)"
echo ""

# Check if remotes are set
check_remote() {
    local dir=$1
    local remote=$(git -C "$dir" remote get-url origin 2>/dev/null || echo "")
    if [ -z "$remote" ]; then
        echo "Error: $dir has no 'origin' remote set"
        echo "  Run: cd $dir && git remote add origin <github-url>"
        exit 1
    fi
    echo "$dir -> $remote"
}

echo "Checking remotes..."
check_remote "claude-config"
check_remote "claude-mcps"
check_remote "zephyr-apps"

echo ""
read -p "Remotes look correct? Convert to submodules? (y/N) " confirm
if [ "$confirm" != "y" ]; then
    echo "Aborted"
    exit 0
fi

# Get URLs
CONFIG_URL=$(git -C claude-config remote get-url origin)
MCPS_URL=$(git -C claude-mcps remote get-url origin)
APPS_URL=$(git -C zephyr-apps remote get-url origin)

# Move folders aside
echo "Moving folders aside..."
mv claude-config claude-config.bak
mv claude-mcps claude-mcps.bak
mv zephyr-apps zephyr-apps.bak

# Add as submodules
echo "Adding submodules..."
git submodule add "$CONFIG_URL" claude-config
git submodule add "$MCPS_URL" claude-mcps
git submodule add "$APPS_URL" zephyr-apps

# Clean up backups
echo "Cleaning up..."
rm -rf claude-config.bak claude-mcps.bak zephyr-apps.bak

echo ""
echo "=== Done ==="
echo "Submodules added. Commit with:"
echo "  git add .gitmodules claude-config claude-mcps zephyr-apps"
echo "  git commit -m 'Add submodules'"
