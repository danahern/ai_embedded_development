#!/bin/bash
# enforce-mcp-first.sh — PreToolUse hook for Bash tool
# Blocks CLI tools that have MCP equivalents.

# Read stdin (tool input JSON)
INPUT=$(cat)

# Extract the command from tool_input
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

deny() {
  cat <<EOF
{"decision":"deny","reason":"$1"}
EOF
  exit 0
}

# JLinkExe — exception for VCOM persistence (compound command with sleep, or CommandFile with persist)
if echo "$COMMAND" | grep -qiE 'JLinkExe|JLink_V[0-9]+/JLinkExe'; then
  if echo "$COMMAND" | grep -qE 'sleep [0-9]{4,}'; then
    exit 0
  fi
  if echo "$COMMAND" | grep -qiE 'CommandFile.*persist|jlink_persist'; then
    exit 0
  fi
  deny "Use embedded-probe or alif-flash.jlink_flash MCP tools instead of JLinkExe."
fi

# nrfjprog
if echo "$COMMAND" | grep -qE '\bnrfjprog\b'; then
  deny "Use embedded-probe.nrfjprog_flash MCP tool instead of nrfjprog."
fi

# west build / west flash (allow west update, west init, west blobs, etc.)
if echo "$COMMAND" | grep -qE '\bwest\s+(build|flash)\b'; then
  deny "Use zephyr-build.build() MCP tool instead of west build/flash."
fi

# idf.py
if echo "$COMMAND" | grep -qE '\bidf\.py\b'; then
  deny "Use esp-idf-build MCP tools instead of idf.py."
fi

# addr2line
if echo "$COMMAND" | grep -qE '\baddr2line\b'; then
  deny "Use embedded-probe.resolve_symbol MCP tool instead of addr2line."
fi

# esptool
if echo "$COMMAND" | grep -qE '\besptool\b'; then
  deny "Use embedded-probe.esptool_flash MCP tool instead of esptool."
fi

# openocd
if echo "$COMMAND" | grep -qE '\bopenocd\b'; then
  deny "Use openocd-debug MCP tools instead of openocd."
fi

# docker exec — use linux-build MCP (run_command, kernel_rebuild, yocto_build, etc.)
if echo "$COMMAND" | grep -qE '\bdocker\s+exec\b'; then
  deny "Use linux-build MCP tools (run_command, kernel_rebuild, yocto_build, etc.) instead of docker exec."
fi

# docker cp — use linux-build MCP (collect_artifacts, list_artifacts, etc.)
if echo "$COMMAND" | grep -qE '\bdocker\s+cp\b'; then
  deny "Use linux-build MCP tools (collect_artifacts, list_artifacts) instead of docker cp."
fi

# Not blocked — allow
exit 0
