# Loop 2 Changelog

## Summary
- Applied: 12 tasks
- Skipped: 1 task
- Tests: 29 passed, 0 failed, 0 skipped

## Applied Changes

### Batch 1 (commit fa86524)
- APPLICATA: Fix DATE_TAG date consistency bug + eliminate startup date fork (BUG-02/PERF-11) — files: scripts/night-dev.sh
- APPLICATA: Eliminate 2-5 date forks for STARTED_AT/DEADLINE_ISO (PERF-12) — files: scripts/night-dev.sh
- APPLICATA: Consolidate readlink forks in PROJECT_PATH (PERF-15) — files: scripts/night-dev.sh
- APPLICATA: Replace package.json awk with pure bash (PERF-18) — files: scripts/night-dev.sh
- APPLICATA: Remove non-existent files from Makefile REQUIRED_REFS (QUALITY-04) — files: Makefile

### Batch 2 (commit a9720e3)
- APPLICATA: Inline calculate_score arithmetic (PERF-13) — files: scripts/night-dev.sh
- APPLICATA: Remove dead helper functions (QUALITY-03) — files: scripts/night-dev.sh
- APPLICATA: Replace echo -e with printf for ANSI injection prevention (SEC-02) — files: scripts/night-dev.sh
- APPLICATA: Pre-store awk script constant + empty file early exit (PERF-14) — files: scripts/night-dev.sh
- APPLICATA: Replace changelog awk with pure bash while-read (PERF-17) — files: scripts/night-dev.sh
- APPLICATA: Defer circuit-breaker status update to cleanup trap (PERF-16) — files: scripts/night-dev.sh
- APPLICATA: Cache static prompt template before loop (PERF-19) — files: scripts/night-dev.sh

## Skipped Changes
- SKIPPATA: Magic number in follow mode fallback (deferred, low impact) — QUALITY-05
