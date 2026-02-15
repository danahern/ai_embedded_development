# Phase 1: Testing MCP Tools

Status: Complete
Target: Add test execution and result parsing to zephyr-build MCP server

## Problem

Twister (Zephyr's test runner) is invoked via raw CLI only:
```bash
python3 zephyr/scripts/twister -T zephyr-apps/lib -p qemu_cortex_m3 -O .cache/twister -v
```

No structured output, no background execution, no result parsing. Engineers must manually interpret test output.

## Approach

Extend `zephyr-build` MCP server (not a new server) because:
- Twister is a Zephyr/west tool
- zephyr-build already has workspace path config
- Keeps MCP server count manageable
- Same pattern as `build` + `build_status`

## Tools to Add

### 1. `run_tests` — Execute twister test suite
```rust
RunTestsArgs {
    path: Option<String>,        // Test path filter (e.g., "lib/crash_log")
    board: String,               // Platform (e.g., "qemu_cortex_m3")
    filter: Option<String>,      // Test name filter (-k pattern)
    extra_args: Option<String>,  // Additional twister args
    background: bool,            // Run in background (default: false)
    workspace_path: Option<String>,
}

RunTestsResult {
    success: bool,
    test_id: Option<String>,     // For background tests
    summary: TestSummary,        // Parsed results (if not background)
    output: String,              // Raw twister output
    duration_ms: u64,
}
```

### 2. `test_status` — Check background test progress
```rust
TestStatusArgs {
    test_id: String,
}

TestStatusResult {
    status: String,              // "running", "completed", "failed"
    summary: Option<TestSummary>,
    output: String,
    duration_ms: u64,
}
```

### 3. `test_results` — Parse detailed test results
```rust
TestResultsArgs {
    test_id: Option<String>,     // From background run
    results_dir: Option<String>, // Or point to existing results
}

TestResultsResult {
    summary: TestSummary,
    test_cases: Vec<TestCase>,
    failures: Vec<TestFailure>,
}

TestSummary {
    total: u32,
    passed: u32,
    failed: u32,
    skipped: u32,
    errors: u32,
}

TestCase {
    name: String,
    platform: String,
    status: String,              // "passed", "failed", "skipped", "error"
    duration_ms: u64,
    reason: Option<String>,      // Failure/skip reason
}

TestFailure {
    test_name: String,
    platform: String,
    log: String,                 // Build/run output for failed test
}
```

## Implementation Notes

- Twister outputs results to `twister.json` in the output dir — parse this for structured results
- Use same background task pattern as `build`/`build_status`
- Default output dir: `.cache/twister` (already in .gitignore)
- Twister command: `python3 {workspace}/zephyr/scripts/twister -T {path} -p {board} -O {output_dir} --inline-logs`
- `--inline-logs` captures test output for failure reporting

## Files to Modify

| File | Changes |
|------|---------|
| `claude-mcps/zephyr-build/src/tools/types.rs` | Add RunTests/TestStatus/TestResults args/result structs |
| `claude-mcps/zephyr-build/src/tools/build_tools.rs` | Add 3 tool implementations |
| `claude-mcps/zephyr-build/README.md` | Update tool count, add test docs |
| `claude-mcps/zephyr-build/CLAUDE.md` | Update tool listing |
