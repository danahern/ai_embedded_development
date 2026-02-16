---
paths: ['**/.github/workflows/*.yml', '**/69-probe-rs.rules', '**/setup.sh', '**/west.yml']
---
# Operational Learnings

- **probe-rs udev rules required for flash/debug on Linux (errno 13)** — On Linux, `probe-rs list` works without udev rules (read-only USB enumeration), but all write operations (`download`, `run`, `attach`, `reset`) fail with errno 13 (permission denied).
- **CI west workspace caching: persistent workspace with rsync for self-hosted runners** — For self-hosted GitHub Actions runners running Zephyr CI, avoid running `west init` + `west update` on every workflow run. A full `west update` downloads ~2GB of modules and takes 5-10 minutes.
