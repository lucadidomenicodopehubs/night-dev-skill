# Loop 1 Changelog

## Applied Changes

- APPLICATA: TASK-5 — Remove --no-hardlinks from backup git clone, halving disk usage (PERF-08) — files: scripts/night-dev.sh
- APPLICATA: TASK-4 — Optimize check_dirty_state with pipe-to-read pattern (PERF-03) — files: scripts/night-dev.sh
- APPLICATA: TASK-2 — Replace awk float comparison with pure bash arithmetic (PERF-05) — files: scripts/night-dev.sh
- APPLICATA: TASK-3 — Merge parse_test_results 4-5 awk calls into single-pass awk (PERF-06) — files: scripts/night-dev.sh
- APPLICATA: TASK-6 — Cache changelog parse results between loop iterations (PERF-07) — files: scripts/night-dev.sh
- APPLICATA: TASK-1 — Batch all per-loop jq status updates into single invocation (PERF-01) — files: scripts/night-dev.sh

## Skipped Items

- SKIPPATA: PERF-02 (already efficient)
- SKIPPATA: PERF-04 (negligible impact)
- SKIPPATA: SEC-01 (needs human review)
- SKIPPATA: QUALITY-01/02 (out of scope)

## Test Results

- Passed: 27
- Failed: 0
- Skipped: 2

All tests passing. No regressions detected.
