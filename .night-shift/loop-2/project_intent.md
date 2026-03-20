# Night Dev Skill — Project Intent (Loop 2)

**Date:** 2026-03-20
**Previous Loop:** Loop 1 applied 11 changes (10 applied, 1 skipped/monitoring)
**Tests:** 27 passed, 0 failed, 2 skipped

---

## Purpose

Night Dev is a Claude Code skill implementing an autonomous evolutionary software development agent. It orchestrates multi-loop development sessions where an AI agent analyzes code, plans improvements, implements them, and keeps only changes that strictly improve a composite score. All work happens in a git worktree so the main branch is never touched.

Night Dev is distinct from Night Shift: Night Shift does conservative maintenance (fix bugs, patch security, quality), while Night Dev does aggressive development (new features, tests, refactoring, architectural improvements) gated by evolutionary scoring.

## Architecture

- **Bash orchestrator** (`scripts/night-dev.sh`, ~1070 lines): CLI entry point handling argument parsing, pre-flight checks, worktree creation, backup, main loop with Claude invocation, score calculation, changelog parsing, circuit breaker/stagnation detection, cleanup.
- **SKILL.md** (~430 lines): Prompt specification defining 8 phases (FASE 0-7) that Claude executes within each loop, including scoring formula and critical rules.
- **Reference prompts** (`references/`): 5 sub-agent prompt templates — analyze, plan, research, implement, report.
- **Interactive setup** (`commands/night-dev.md`): Italian-language wizard for launching Night Dev from Claude Code.
- **Makefile** (~88 lines): Test suite with syntax, structure, and CLI validation (29 tests total).

## Scoring Formula (synchronized in loop 1)

```
score = (tests_passing * 10) + (test_count * 2) + (coverage_pct * 5) - (tests_failing * 20) - (execution_time_s * 0.1)
```

Plus optional code_quality and architecture_quality dimensions.

## Key Design Decisions

- Batch-first implementation with sequential fallback
- Circuit breaker (3 consecutive zero-applied loops) and stagnation detection (2 loops without improvement)
- Model selection optimization (haiku for simple tasks, default for complex)
- CodeIntel MCP integration for blast radius analysis (optional)
- Worktree isolation ensures main branch safety
- Pure bash with minimal dependencies (git, jq)

## Loop 1 Changes Applied

1. Scoped .claude/settings.json Bash permissions (SEC-01)
2. Fixed negative score sign loss bug (BUG-02)
3. Fixed follow mode worktree selection by mtime (BUG-01)
4. Batched cleanup jq calls (PERF-01/ARCH-01)
5. Synchronized SKILL.md scoring formula (INTENT-01)
6. Hardened git clone with -- flag terminator (SEC-02)
7. Optimized package.json detection to single read (PERF-02)
8. Consolidated Makefile test-help to single invocation (QUALITY-05)
9. Added Claude CLI error handling (QUALITY-01)
10. Made changelog parsing more resilient (QUALITY-02)

## Remaining Known Issues from Loop 1 Audit

- ARCH-02 (LOW): Single 1045-line file — monitoring, threshold 1200
- ARCH-03 (LOW): Awk script constant not independently testable
- QUALITY-03 (LOW): Inline mode polling lacks backoff
- QUALITY-04 (LOW): Follow mode polling lacks backoff
- QUALITY-06 (LOW): Italian-only interactive setup
- BUG-03 (LOW): Score comparison edge case with negative fractional parts
