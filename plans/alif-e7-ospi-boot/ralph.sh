#!/usr/bin/env bash
#
# ralph.sh — Ralph loop for Alif E7 OSPI boot flashing
#
# Feeds prompt.md to claude repeatedly via -p flag (not pipe),
# keeping stdin free for interactive tool use (AskUserQuestion,
# notify-and-wait.sh, etc).
#
# Usage:
#   ./ralph.sh              # Run (max 10 iterations)
#   MAX_ITER=5 ./ralph.sh   # Custom limit
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"
MAX_ITER="${MAX_ITER:-10}"
PROMISE="OSPI BOOT COMPLETE"

cd "$WORKSPACE_ROOT"

PROMPT_TEXT="$(cat "$PROMPT_FILE")"

for i in $(seq 1 "$MAX_ITER"); do
    echo ""
    echo "=== Ralph iteration $i/$MAX_ITER ==="
    echo ""

    # Use -p to pass prompt as argument, keeping stdin for interaction
    OUTPUT=$(claude --continue -p "$PROMPT_TEXT" 2>&1) || true
    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "$PROMISE"; then
        echo ""
        echo "=== Completion promise detected at iteration $i ==="
        exit 0
    fi
done

echo ""
echo "=== Max iterations ($MAX_ITER) reached without completion ==="
exit 1
