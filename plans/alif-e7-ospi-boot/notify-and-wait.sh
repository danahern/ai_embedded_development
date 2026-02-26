#!/usr/bin/env bash
#
# notify-and-wait.sh — Send macOS notification + terminal bell, wait for Enter
#
# Usage:
#   ./notify-and-wait.sh "Power cycle the board"
#   ./notify-and-wait.sh "Enter maintenance mode" "Hold BOOT button during power-on"
#
MSG="${1:-Action needed}"
DETAIL="${2:-}"

# macOS notification
osascript -e "display notification \"$MSG\" with title \"Alif E7\" subtitle \"${DETAIL}\" sound name \"Ping\"" 2>/dev/null || true

# Terminal bell
printf '\a'

# Print to terminal
echo ""
echo "===================================="
echo "  ACTION NEEDED: $MSG"
[ -n "$DETAIL" ] && echo "  $DETAIL"
echo "===================================="
echo ""
read -r -p "Press Enter when done... "
echo "Continuing..."
