═══ Night Shift Report ═══
Branch: night-shift/2026-03-20
Started: 2026-03-20T15:36:36+00:00
Loops completed: 3 / 3

SECURITY:
- Fix applicate: 4 (scoped permissions, git clone hardening, DETECTED_RUNNER validation, sub-agent allowlist expansion)
- Vulnerabilita escalated: 0 (all resolved)

MODIFICHE CUMULATIVE:
- Applicate: 23 (loop-1: 10, loop-2: 8, loop-3: 5)
- Skippate (rischio): 10 (loop-1: 1, loop-2: 1, loop-3: 6, previous-session: 2)
- Rollbackate (test falliti): 0

METRICHE (baseline → attuale):
- Test: 27 → 29 (no regressions)
- Coverage: N/A
- Vulnerabilita note: N/A
- TODO/FIXME: N/A

Per review:
  git diff main...night-shift/2026-03-20

Per merge:
  git checkout main && git merge night-shift/2026-03-20

Per cherry-pick:
  git log night-shift/2026-03-20 --oneline

Per scartare:
  git worktree remove /root/night-dev-skill/.night-shift-worktree
  git branch -D night-shift/2026-03-20
═══════════════════════════
