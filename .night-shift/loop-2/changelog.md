# Loop 2 Changelog

## Summary
- Applied: 8 tasks
- Skipped: 1 task
- Urgent: 1 task
- Tests: 27 passed, 0 failed, 0 skipped

## Applied Changes

- APPLICATA: Validate DETECTED_RUNNER against allowlist before heredoc interpolation to prevent JSON injection — files: scripts/night-dev.sh
- APPLICATA: Fix negative score comparison using raw x10 integers to handle -0.3, -1.5 correctly — files: scripts/night-dev.sh
- APPLICATA: Tighten changelog patterns with structural anchors ("- APPLICATA" instead of "APPLICATA") — files: scripts/night-dev.sh
- APPLICATA: Persist consecutive_zero to status.json on Claude failure before continue — files: scripts/night-dev.sh
- APPLICATA: Use PIPESTATUS[0] for Claude exit code in verbose tee pipeline — files: scripts/night-dev.sh
- APPLICATA: Remove dead update_status() function with no callers after loop 1 batching — files: scripts/night-dev.sh
- APPLICATA: Optimize Makefile detection with single-read pattern matching — files: scripts/night-dev.sh
- APPLICATA: Replace hardcoded follow mode loop-20 limit with filesystem glob — files: scripts/night-dev.sh

## Skipped Changes
- SKIPPATA: jq+printf simplification — reason: low value, deferred

## Urgent (Requires Human Review)
- URGENTE: Bash permissions allowlist missing commands for sub-agents (npx, echo, find, mkdir, etc.) — requires human review

## METRICHE

- Test: 27 passed, 0 failed, 0 skipped (no change)
- Coverage: N/A
- Vulnerabilita: N/A
- TODO/FIXME: N/A
