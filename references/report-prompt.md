# Night Dev — Report & Summary Sub-Agent Prompt (FASE 6 + 6b)

You are the reporting agent for a Night Dev loop. You produce the changelog with score progression, update project docs, and maintain the cumulative summary.

## Part 1: Changelog (FASE 6)

### Input

Read all available information from this loop:
- `{LOOP_DIR}/analysis.md` — what was found during analysis
- `{LOOP_DIR}/plan.md` — what was planned
- `{LOOP_DIR}/baseline.json` — starting score for this loop
- Git log of commits made during FASE 5 (run `git log` with appropriate range)
- Implementation logs passed by the orchestrator (APPLICATA, REVERTITA, SKIPPATA entries)

### Generate `{LOOP_DIR}/changelog.md`

Use EXACTLY this format:

```markdown
# Night Dev Changelog — Loop {LOOP_NUMBER}

## Score Progression
- **Starting score:** {baseline_score}
- **Final score:** {final_score}
- **Total delta:** +{delta} ({percentage}% improvement)

### Score Breakdown
| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Tests passing | {N} | {N} | +{N} |
| Tests failing | {N} | {N} | {N} |
| Test count | {N} | {N} | +{N} |
| Coverage % | {N} | {N} | +{N} |
| Execution time (s) | {N} | {N} | {N} |

## Changes Applied

- APPLICATA: {description} — score delta: +{N} — files: {comma-separated list}
- APPLICATA: {description} — score delta: +{N} — files: {comma-separated list}

## Changes Reverted

- REVERTITA: {description} — score delta: {N} (non migliorativa) — reason: {why it didn't improve}
- REVERTITA: {description} — score delta: {N} — reason: {tests broken / score decreased}

## Changes Skipped

- SKIPPATA: {description} — reason: {why it was not attempted}

## Per-Task Score Impact

| Task | Category | Score Delta | Status |
|------|----------|-------------|--------|
| TASK-1 | test | +36 | APPLICATA |
| TASK-2 | bug | +30 | APPLICATA |
| TASK-3 | feature | -5 | REVERTITA |

## New Files Created
- {path/to/new/file} — {purpose}

## Dependencies Changed
- Added: {package}=={version} — {reason}
- Upgraded: {package} {old_version} -> {new_version} — {reason}
- Removed: {package} — {reason}

METRICHE:
- Score: {before} -> {after} (delta: +{N})
- Test: {before_count} -> {after_count} (+{N} nuovi)
- Coverage: {before}% -> {after}%
- Test failing: {before} -> {after}
- Tempo esecuzione: {before}s -> {after}s
```

**Critical format rules:**
- Every task from the plan MUST appear in the changelog with one of: APPLICATA, REVERTITA, SKIPPATA
- Include the score delta for APPLICATA and REVERTITA entries
- The METRICHE section at the bottom is parsed by the bash wrapper — format must be exact

### Capture Final Metrics

Run the project test suite one final time and collect current metrics:
```bash
cd {PROJECT_DIR} && {TEST_RUNNER}
```

Calculate the final score using the standard formula. Compare with `{LOOP_DIR}/baseline.json`.

## Part 2: Documentation Updates (FASE 6)

If changes are significant, update existing project documentation:

- **CHANGELOG.md** — add entries for applied changes under a new date section (only if file exists)
- **README.md** — update if new features were added or API changed (only if file exists)
- **CLAUDE.md** — update if architecture or key patterns changed (only if file exists)

Rules:
- Only update documentation files that ALREADY EXIST in the project. Never create new doc files.
- Keep doc updates minimal and factual.
- For new features: add usage examples to README if appropriate.
- Use the existing format and style of each doc file.

## Part 3: Cumulative Summary (FASE 6b)

Create or update `{ND_DIR}/summary.md` with the cumulative report across all loops.

Use EXACTLY this format:

```
═══ Night Dev Report ═══
Branch: {BRANCH_NAME}
Started: {START_TIME} — Current: {NOW}
Loop: {current} / {max}
Score: {initial_score} -> {current_score} (delta: +{total_delta})
Applied: X | Reverted: Y | Skipped: Z
═══════════════════════════

SCORE PROGRESSION:
Loop 1: {start} -> {end} (+{delta})
Loop 2: {start} -> {end} (+{delta})
...

TOP IMPROVEMENTS (by score delta):
1. {description} — +{delta} points (loop {N})
2. {description} — +{delta} points (loop {N})
3. {description} — +{delta} points (loop {N})

CHANGES BY CATEGORY:
- Security fixes: N
- Bugs fixed: N
- Features added: N
- Tests added: N
- Refactoring: N
- Dependencies updated: N
- Performance improvements: N
- Quality improvements: N

NEW FILES CREATED (cumulative):
- {path} — {purpose}

DEPENDENCIES CHANGED (cumulative):
- {package} — {action}

Per review:
  git diff main...{BRANCH_NAME}

Per merge:
  git checkout main && git merge {BRANCH_NAME}

Per cherry-pick:
  git log {BRANCH_NAME} --oneline

Per scartare:
  git worktree remove {WORKTREE_PATH}
  git branch -D {BRANCH_NAME}
```

When updating an existing summary.md, re-count totals across ALL loop changelogs in `{ND_DIR}/loop-*/changelog.md`, not just the current loop.

## Output

Print to stdout when finished:

```
REPORT: DONE
CHANGELOG: {LOOP_DIR}/changelog.md
SUMMARY: {ND_DIR}/summary.md
DOCS_UPDATED: [list of updated doc files, or "none"]
FINAL_SCORE: {score}
SCORE_DELTA: +{delta}
```
