---
paths: ["**/.github/workflows/*.yml", "**/setup.sh", "**/west.yml", ".claude/commands/**", ".mcp.json"]
---
# Operational Learnings

- **MCP setup on new machine: build servers, symlink skills, restart** — When setting up the workspace on a new machine:
- **CI west workspace caching: persistent workspace with rsync for self-hosted runners** — For self-hosted GitHub Actions runners running Zephyr CI, avoid running `west init` + `west update` on every workflow run. A full `west update` downloads ~2GB of modules and takes 5-10 minutes.
- **GitHub Actions runner requires restart after .env changes** — The self-hosted GitHub Actions runner reads `~/actions-runner/.env` at startup only. Adding new environment variables (like `IDF_PATH`) requires restarting the runner service:
