# Night Dev — Project Intent (Loop 3)

**Date:** 2026-03-20
**Focus Mode:** PERFORMANCE (80%) | Other (20%)
**Previous Loop Status:** Loop 2 applied 12 tasks (total: 18 across 2 loops)

---

## Summary

Project intent unchanged from Loop 2. Night Dev is an autonomous evolutionary software development agent (Claude Code skill). The codebase consists of:
- `scripts/night-dev.sh` (1053 lines) — main orchestrator
- `SKILL.md` — phase definitions
- `references/` — 5 prompt templates
- `Makefile` — test suite (29 tests)

## Loop 2 Results

All 12 tasks applied successfully:
- Eliminated 6-8 startup subprocess forks (date, readlink, awk)
- Eliminated 2-3 per-loop forks (calculate_score inline, changelog bash, awk constant)
- Removed 31 lines dead code
- Fixed date consistency bug (BUG-02)
- Fixed ANSI injection vulnerability (SEC-02)

## Loop 3 Focus

With most easy fork-elimination wins taken in loops 1-2, Loop 3 should focus on:
1. Remaining subprocess forks in startup path (grep calls in detect_test_runner)
2. Dead code from loop 2 inlining (calculate_score function still defined)
3. Unnecessary git stash operations in backup flow
4. Any remaining echo-to-printf conversions for consistency
5. Follow mode polling optimizations
