# ELF Analysis MCP Server

Status: In-Progress
Created: 2026-02-15

## Problem

No ROM/RAM tracking. After a build, there's no way to answer "how much flash/RAM am I using?", "which module is consuming the most memory?", or "did this change bloat the binary?" At scale, bloat creeps in undetected.

This should be a **standalone MCP server** — ELF analysis is framework-agnostic (works on any ELF, not just Zephyr) and will grow with features like memory mapping, symbol analysis, and trending. Claude orchestrates: build with zephyr-build → analyze with elf-analysis.

## Approach

New `elf-analysis` MCP server in Rust (rmcp 0.3.2), following the zephyr-build pattern. Wraps Zephyr's `size_report` Python script for the heavy lifting (DWARF parsing, section classification, source file attribution).

Why standalone MCP:
- Framework-agnostic — works on any ELF, not just Zephyr
- Room to grow (memory maps, symbol lookup, struct layout, trending)
- Serves both zephyr-build and esp-idf-build outputs
- Clean separation of concerns

Why wrap `size_report`:
- Full DWARF-based source file attribution ("kernel/sched.c uses 4KB")
- Battle-tested on all targets, handles XIP and edge cases
- Least implementation code (~200 lines Rust, mostly JSON parsing)
- Python deps already installed (pyelftools, anytree, colorama, packaging)
- Pure Rust (goblin/gimli) available as future upgrade

CI size tracking deferred to a separate future plan.

## Solution

### Tool 1: `analyze_size`

Full ROM/RAM breakdown with per-file/module attribution. Answers "how much flash/RAM am I using?" and "where is memory going?"

```rust
AnalyzeSizeArgs {
    elf_path: String,               // path to ELF file
    target: Option<String>,         // "rom", "ram", or "all" (default: "all")
    depth: Option<u32>,             // tree depth limit (default: unlimited)
    workspace_path: Option<String>, // override Zephyr workspace
}

AnalyzeSizeResult {
    elf_path: String,
    rom: Option<SizeReport>,        // present if target is "rom" or "all"
    ram: Option<SizeReport>,        // present if target is "ram" or "all"
}

SizeReport {
    total_size: u64,
    used_size: u64,                 // sum of all symbols (may be < total due to gaps)
    tree: SizeNode,                 // recursive breakdown
}

SizeNode {
    name: String,                   // file path or symbol name
    size: u64,
    children: Vec<SizeNode>,        // empty for leaf symbols
}
```

Runs:
```
python3 {zephyr}/scripts/footprint/size_report \
    -k {elf_path} -z {zephyr} -o {tmpdir} --json {tmpdir}/{target}.json -q {targets...}
```

Parses the JSON (`{"symbols": {tree}, "total_size": N}`) directly into `SizeReport`.

### Tool 2: `compare_sizes`

Diff two ELFs to track size growth. Answers "did this change bloat the binary?" and "what grew?"

```rust
CompareSizesArgs {
    elf_path_a: String,             // "before" ELF
    elf_path_b: String,             // "after" ELF
    workspace_path: Option<String>,
}

CompareSizesResult {
    rom: Option<SizeDelta>,
    ram: Option<SizeDelta>,
}

SizeDelta {
    before: u64,
    after: u64,
    delta: i64,
    percent_change: f64,
    top_increases: Vec<NodeDelta>,  // biggest growers, sorted by delta desc
    top_decreases: Vec<NodeDelta>,  // biggest shrinkers, sorted by delta asc
}

NodeDelta {
    path: String,                   // e.g., "zephyr/kernel/sched.c"
    before: u64,
    after: u64,
    delta: i64,
}
```

Runs size_report on both ELFs, walks both trees, computes deltas at each leaf node, returns top changers.

### Tool 3: `top_consumers`

Quick "show me the biggest files/symbols" view. Flattens the tree and sorts by size.

```rust
TopConsumersArgs {
    elf_path: String,
    target: String,                 // "rom" or "ram"
    limit: Option<u32>,             // top N (default: 20)
    level: Option<String>,          // "file" (default) or "symbol"
    workspace_path: Option<String>,
}

TopConsumersResult {
    target: String,
    total_size: u64,
    consumers: Vec<Consumer>,
}

Consumer {
    path: String,                   // file path or symbol name
    size: u64,
    percent: f64,                   // percentage of total
}
```

Derived from `analyze_size` output — flattens the tree to the requested level, sorts descending. This is the "where is all the memory going?" quick answer.

## Implementation Notes

### New MCP server structure

```
claude-mcps/elf-analysis/
├── Cargo.toml
├── CLAUDE.md
├── README.md
├── src/
│   ├── main.rs              # Entry point (clap args, logging, serve)
│   ├── lib.rs               # Public exports
│   ├── config.rs            # Args + Config (workspace_path, zephyr_base)
│   └── tools/
│       ├── mod.rs            # Module exports
│       ├── types.rs          # All arg/result structs
│       ├── handler.rs        # #[tool_router] + #[tool_handler] impl
│       └── size_report.rs    # size_report invocation, JSON parsing, tree ops
└── tests/
    └── fixtures/             # Captured size_report JSON for unit tests
```

### Files to create/modify

| File | Change |
|------|--------|
| `claude-mcps/elf-analysis/Cargo.toml` | **New** — rmcp, tokio, serde, serde_json, schemars, clap, tracing, uuid, tempfile |
| `claude-mcps/elf-analysis/src/main.rs` | **New** — parse args, init logging, serve handler (copy zephyr-build pattern) |
| `claude-mcps/elf-analysis/src/lib.rs` | **New** — re-exports |
| `claude-mcps/elf-analysis/src/config.rs` | **New** — `Args { workspace, zephyr_base, log_level, log_file }`, `Config` |
| `claude-mcps/elf-analysis/src/tools/mod.rs` | **New** — module exports |
| `claude-mcps/elf-analysis/src/tools/types.rs` | **New** — all arg/result structs above |
| `claude-mcps/elf-analysis/src/tools/handler.rs` | **New** — `ElfAnalysisToolHandler` with 3 tools |
| `claude-mcps/elf-analysis/src/tools/size_report.rs` | **New** — `run_size_report()`, `parse_size_json()`, `diff_trees()`, `flatten_tree()`, `truncate_tree()` |
| `claude-mcps/elf-analysis/CLAUDE.md` | **New** — tool documentation |
| `claude-mcps/elf-analysis/README.md` | **New** — setup, usage, troubleshooting |
| `.mcp.json` | Add `elf-analysis` server entry |
| `CLAUDE.md` | Add elf-analysis to MCP server listing |
| `claude-mcps/CLAUDE.md` | Add elf-analysis to server table |
| `plans/elf-analysis.md` | Update status to Complete |

### Key references

- `zephyr/scripts/footprint/size_report` — CLI args (lines 853-874), JSON output (lines 936-943), section classification (lines 231-312)
- `zephyr/scripts/footprint/fpdiff.py` — existing diff logic (93 lines, simple tree walk)
- `claude-mcps/zephyr-build/src/main.rs` — entry point pattern to copy
- `claude-mcps/zephyr-build/src/config.rs` — config pattern to copy
- `claude-mcps/zephyr-build/src/tools/build_tools.rs` — `run_tests` method for subprocess + env var pattern

### Implementation steps

1. **Scaffold** — `cargo init` the new crate, set up Cargo.toml with dependencies, create directory structure.
2. **Config + main.rs** — Copy from zephyr-build, adapt args (workspace + zephyr_base paths).
3. **Types** — All arg/result structs. `SizeNode` needs `#[derive(Deserialize)]` for direct JSON parsing from size_report. size_report JSON uses `identifier` field for the path and `name` for display — map `identifier` to our `name`.
4. **size_report.rs** — Core functions:
   - `run_size_report(elf_path, zephyr_base, workspace, targets) -> HashMap<String, PathBuf>` — runs subprocess, returns paths to JSON files
   - `parse_size_json(path) -> SizeReport` — deserialize JSON into our types
   - `truncate_tree(node, depth) -> SizeNode` — limit tree depth
   - `flatten_tree(node, level) -> Vec<Consumer>` — collect nodes at target depth
   - `diff_trees(a, b) -> (Vec<NodeDelta>, Vec<NodeDelta>)` — walk both trees, return increases and decreases
5. **handler.rs** — `#[tool_router]` impl with `analyze_size`, `compare_sizes`, `top_consumers`. Each validates inputs, calls size_report functions, serializes result.
6. **Tests** — Capture real size_report JSON from a build as fixtures. Unit test: parsing, truncation, flattening, diffing, error cases.
7. **Docs** — CLAUDE.md, README.md, update workspace docs.
8. **Register** — Add to `.mcp.json`, rebuild, verify.

### Config design

```rust
pub struct Args {
    #[arg(short, long)]
    pub workspace: Option<PathBuf>,     // workspace root (for -w flag to size_report)

    #[arg(long)]
    pub zephyr_base: Option<PathBuf>,   // path to zephyr/ (for -z flag to size_report)

    #[arg(long, default_value = "info")]
    pub log_level: String,

    #[arg(long)]
    pub log_file: Option<PathBuf>,
}
```

The `zephyr_base` defaults to `{workspace}/zephyr` if workspace is set. Tools also accept `workspace_path` per-call for override.

### size_report JSON format

```json
{
    "symbols": {
        "identifier": "root_path",
        "name": "Root",
        "size": 12345,
        "children": [
            {
                "identifier": "zephyr/kernel/sched.c",
                "name": "sched.c",
                "size": 2048,
                "children": [
                    {
                        "identifier": "zephyr/kernel/sched.c/k_sched_lock",
                        "name": "k_sched_lock",
                        "size": 64,
                        "children": []
                    }
                ]
            }
        ]
    },
    "total_size": 12345
}
```

Map `identifier` → `SizeNode.name` (the full path is more useful than the display name).

### Error handling

- ELF doesn't exist → `invalid_params` error
- size_report script not found → `internal_error` with guidance ("set --zephyr-base or --workspace")
- ELF has no DWARF info → catch non-zero exit + "has no DWARF" in stderr
- Python deps missing → catch ImportError in stderr, suggest `pip install pyelftools anytree colorama packaging`
- Zephyr workspace not configured → clear error message about --workspace or --zephyr-base

### .mcp.json entry

```json
"elf-analysis": {
    "command": "/Users/danahern/code/claude/work/claude-mcps/elf-analysis/target/release/elf-analysis",
    "args": ["--workspace", "/Users/danahern/code/claude/work"]
}
```

### Gotchas discovered during implementation

- **size_report `all` target**: Generates ONE `all.json`, not separate `rom.json`/`ram.json`. Must pass `rom ram` as separate positional args to get individual files.
- **DWARF required**: size_report asserts ELF has DWARF info. Non-zero exit with assertion in stderr.
- **tmpdir lifetime**: `std::mem::forget(tmpdir)` to keep temp files alive until caller reads them. Acceptable leak since MCP calls are short-lived.
- **`identifier` vs `name`**: size_report's `identifier` is the full path (useful), `name` is just the display name. We map `identifier` → `SizeNode.name`.

## Modifications

- **Standalone MCP** instead of adding to zephyr-build — cleaner separation, room to grow
- **CI size tracking** deferred to a separate `ci-size-tracking` plan
- **Pure Rust implementation** (goblin/gimli) available as future upgrade if Python dep becomes problematic
- **Future tools**: memory map visualization, symbol search, struct layout (pahole), init priority analysis

## Verification

1. `cargo build --release` — compiles clean
2. `cargo test` — all tests pass
3. Build an app: `zephyr-build.build(app="crash_debug", board="nrf54l15dk/nrf54l15/cpuapp", pristine=true)`
4. `elf-analysis.analyze_size(elf_path="...zephyr.elf")` — returns ROM/RAM totals and per-file tree
5. `elf-analysis.top_consumers(elf_path="...zephyr.elf", target="rom")` — shows top 20 ROM consumers with percentages
6. `elf-analysis.compare_sizes(elf_path_a="...before.elf", elf_path_b="...after.elf")` — shows deltas
7. ROM/RAM totals are reasonable for the target (e.g., crash_debug on nRF54L15: ~50-100KB ROM, ~20-40KB RAM)
