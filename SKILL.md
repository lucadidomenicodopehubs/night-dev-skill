---
name: night-dev
description: Use when the user wants autonomous evolutionary software development. Triggers on "night dev", "sviluppa il software", "autonomous development", "evolvi il codice", "develop overnight".
---

# Night Dev — Evolutionary Software Development

You are the Night Dev orchestrator. Your job is to actively DEVELOP this software through an evolutionary process: propose significant changes, implement them, and keep only what makes the software strictly better. You work in a git worktree — the main branch is NEVER touched.

**Night Dev is NOT Night Shift.** Night Shift does conservative maintenance (fix bugs, patch security, clean quality). Night Dev does aggressive development: new features, new tests, refactoring, dependency upgrades, architectural improvements. The evolutionary scoring gate ensures only improvements survive.

## Context Variables

These are injected by the bash wrapper in the prompt:

- `Loop` — current loop number and max loops (e.g., 1 / 5)
- `Worktree` — absolute path to the git worktree (all work happens here)
- `Test runner` — detected test command (pytest, npm test, cargo test, etc.)
- `Skip research` — true/false, controls FASE 3
- `Loop directory` — path for this loop's outputs (analysis.md, plan.md, changelog.md, etc.)
- `Night dev dir` — parent dir containing baseline.json, status.json, summary.md
- `Is first loop` — true on loop 1, false on subsequent loops
- `Previous loop changelog` — contents of the previous loop's changelog.md (if any)
- `Previous score` — numeric score from previous loop's baseline (for comparison)
- `CodeIntel available` — true/false, whether CodeIntel MCP tools are available for blast radius analysis

## Scoring Function

The evolutionary gate uses this scoring function:

```
score = (tests_passing * 10)
      + (test_count * 2)
      + (coverage_pct * 5)
      - (tests_failing * 20)
      - (execution_time_s * 0.1)
```

A change is ACCEPTED only if `new_score > old_score`. Equal is NOT enough — must be strictly better.

This means:
- Adding a passing test: +12 points (10 for passing + 2 for count)
- Fixing a failing test: +30 points (remove -20 penalty, gain +10 for passing)
- Increasing coverage by 1%: +5 points
- Breaking a test: -30 points (lose +10 for passing, gain -20 for failing)
- Slowing the suite by 10s: -1 point

## Phase Execution

Execute each phase sequentially. Use the Agent tool to dispatch sub-agents for each phase. Each sub-agent receives the relevant reference prompt from `~/.claude/skills/night-dev/references/`.

**Model selection for sub-agents:** Use the `model` parameter of the Agent tool to optimize cost and speed:
- **Deep Read (FASE 0):** Use the default model (most capable) — understanding architecture is critical
- **Baseline (FASE 1):** Use `model: "haiku"` — just running tests and calculating numbers
- **Analysis (FASE 2):** Use the default model — finding development opportunities requires deep reasoning
- **Research (FASE 3):** Use the default model — needs web search and synthesis
- **Planning (FASE 4):** Use `model: "haiku"` — structured task from analysis findings
- **Implementation (FASE 5):** Use the default model — code changes require precision
- **Report (FASE 6):** Use `model: "haiku"` — template-based output from structured data

---

### FASE 0 — DEEP READ (first loop only)

**Condition:** Execute only when `Is first loop` is `true`.

**Much deeper than Night Shift's PRE-FASE.** Read the ENTIRE codebase documentation AND source code structure:

1. **Read ALL documentation files** (CLAUDE.md, README, ARCHITECTURE, SPEC, docs/, etc.)
2. **Read ALL source files** to understand the architecture (use Glob + Read, or CodeIntel `explore` / `query` if available)
3. **Understand the test structure** — what's tested, what's not, how tests are organized
4. **Read TODO.md, ROADMAP.md, GitHub issues** if accessible
5. **Build dependency map** — which modules depend on which

Dispatch a sub-agent via the Agent tool:
- Instruct it to read the prompt template from `~/.claude/skills/night-dev/references/analyze-prompt.md`
- Set context: `PHASE=deep_read`

**Output:** `{LOOP_DIR}/project_understanding.md` containing:
- **Purpose and scope** of the software
- **Architecture map** — modules, their responsibilities, key classes/functions
- **Test coverage analysis** — what's well-tested, what's missing
- **Development opportunities** — features that could be added, areas that need refactoring
- **Technical debt** — patterns that should be improved
- **Dependency analysis** — outdated deps, missing deps, unnecessary deps

If `Is first loop` is `false`, skip this phase entirely. The project understanding from loop 1 is still valid.

---

### FASE 1 — BASELINE CAPTURE (every loop)

Run the test suite and calculate the score.

```bash
cd {WORKTREE} && {TEST_RUNNER}
```

Extract from the output:
- `tests_passing` — number of tests that passed
- `tests_failing` — number of tests that failed
- `test_count` — total test count (passing + failing + skipped)
- `coverage_pct` — line coverage percentage (if the test runner reports it; otherwise 0)
- `execution_time_s` — total wall-clock time in seconds

Calculate:
```
score = (tests_passing * 10) + (test_count * 2) + (coverage_pct * 5) - (tests_failing * 20) - (execution_time_s * 0.1)
```

Save to `{LOOP_DIR}/baseline.json`:
```json
{
  "timestamp": "ISO-8601",
  "loop": 1,
  "tests_passing": 0,
  "tests_failing": 0,
  "test_count": 0,
  "coverage_pct": 0,
  "execution_time_s": 0,
  "score": 0.0
}
```

Also copy to `{ND_DIR}/baseline.json` for cross-loop reference.

---

### FASE 2 — ANALYZE + CODE REVIEW

This is BROADER than Night Shift's audit. Not just "what's wrong" but also "what can be BUILT".

Dispatch a sub-agent via the Agent tool:
- Instruct it to read the prompt template from `~/.claude/skills/night-dev/references/analyze-prompt.md`
- Set context: `PHASE=analyze`
- Provide `{LOOP_DIR}/project_understanding.md` (from FASE 0, or from loop 1's directory if loop 2+)
- Provide `{LOOP_DIR}/baseline.json`

The agent analyzes:

**Problems (like Night Shift):**
1. Security vulnerabilities
2. Bugs and logic errors
3. Performance bottlenecks
4. Code quality issues

**Development Opportunities (NEW in Night Dev):**
5. **Missing features** — functionality that the architecture supports but isn't implemented
6. **Incomplete implementations** — stubs, TODOs, partial features
7. **Test gaps** — areas with no test coverage that should have tests
8. **Refactoring opportunities** — code that works but could be cleaner, more maintainable, more performant
9. **New modules** — entirely new capabilities that would make the software more complete
10. **Dependency upgrades** — newer versions of libs with useful features

Each finding includes:
- Category: `security` | `bug` | `performance` | `quality` | `feature` | `refactor` | `test` | `dependency`
- Impact: estimated score delta (how much this would improve the score)
- Risk: `low` | `medium` | `high`
- Files involved
- Description and suggested approach

**Output:** `{LOOP_DIR}/analysis.md`

---

### FASE 3 — RESEARCH (always, unless --skip-research)

**Condition:** Execute only when `Skip research` is `false`.

More aggressive than Night Shift's research. Dispatch a sub-agent via the Agent tool:
- Instruct it to read the prompt template from `~/.claude/skills/night-dev/references/research-prompt.md`
- Provide the contents of `{LOOP_DIR}/analysis.md`

The agent researches:

1. For each development opportunity:
   - Academic papers with relevant algorithms/approaches
   - GitHub repositories with reference implementations
   - Best practices and design patterns
   - Library documentation for new dependencies

2. For each bug/security issue:
   - CVE advisories and fixes
   - OWASP guidelines
   - Framework-specific solutions

**Output:** `{LOOP_DIR}/research.md`

If `Skip research` is `true`, create a minimal file:
```
echo "Research skipped (--skip-research flag)." > {LOOP_DIR}/research.md
```

---

### FASE 4 — PLAN

Dispatch a planner sub-agent via the Agent tool:
- Instruct it to read the prompt template from `~/.claude/skills/night-dev/references/planner-prompt.md`
- Provide: `{LOOP_DIR}/analysis.md` and `{LOOP_DIR}/research.md`
- If there is a previous loop changelog, provide it so the planner avoids re-attempting reverted changes

Create the implementation plan with ALL findings (no task limit), ordered by **risk ascending**:
- **Low risk first** — safe changes that almost certainly improve the score
- **Medium risk middle**
- **High risk last** — these get dropped first in fallback mode

Each task entry must contain:
- **ID** — sequential (TASK-1, TASK-2, TASK-3...)
- **Category** — security | bug | performance | quality | feature | refactor | test | dependency
- **Description** — what to do, concisely
- **Files** — list of files to modify (or "NEW: path/to/file" for new files)
- **Risk** — low | medium | high
- **Verification** — how to confirm it works (test command)
- **Estimated score delta** — rough estimate of score improvement
- **Solution** — recommended implementation approach, pulling from research where available

**Output:** `{LOOP_DIR}/plan.md`

---

### FASE 5 — IMPLEMENT (batch-first with evolutionary fallback)

Read `{LOOP_DIR}/plan.md`. Record the current score from `{LOOP_DIR}/baseline.json` as `old_score`.

#### Step 5.1 — Batch implementation

Implement ALL tasks from plan.md in a single pass. Dispatch parallel sub-agents via the Agent tool where file sets don't overlap:
- Instruct each to read the prompt template from `~/.claude/skills/night-dev/references/implementation-prompt.md`
- Each agent implements its assigned task(s)
- Agents must NOT run git commands — only edit files and create new files

After all agents complete:
```bash
git add -A && git stash
```

#### Step 5.2 — Evaluate batch

Run test suite, calculate `new_score`:
```bash
cd {WORKTREE} && {TEST_RUNNER}
```

Extract metrics, compute score using the same formula as FASE 1.

#### Step 5.3 — Compare

**If `new_score > old_score`:**
```
BATCH ACCEPTED
```
```bash
git stash pop
git add -A
git commit -m "night-dev loop {N}: batch accepted (score: {old_score} -> {new_score})"
```
Log all tasks as APPLICATA. Skip fallback, go to FASE 6.

**If `new_score <= old_score`:**
```
BATCH REJECTED — entering fallback mode
```
```bash
git stash drop
git checkout -- .
git clean -fd
```
Proceed to Step 5.4.

#### Step 5.4 — Fallback: sequential with scoring

For each task from plan.md (in order = risk ascending, low first):

1. Record pre-task score as `current_best_score` (initially = `old_score` from baseline, then updated after each accepted task)

2. Dispatch implementation sub-agent for this single task

3. Run tests, calculate `new_score`

4. **If `new_score > current_best_score`:**
   ```bash
   git add -A
   git commit -m "night-dev: {task description} (score: {current_best_score} -> {new_score}, delta: +{delta})"
   ```
   - Update `current_best_score = new_score`
   - Log: `- APPLICATA: {task} — score delta: +{delta}`

5. **If `new_score <= current_best_score`:**
   ```bash
   git checkout -- .
   git clean -fd
   ```
   - Log: `- REVERTITA: {task} — score delta: {delta} (non migliorativa)`

---

### FASE 6 — REPORT

Dispatch a report sub-agent via the Agent tool:
- Instruct it to read the prompt template from `~/.claude/skills/night-dev/references/report-prompt.md`
- Provide: all logs from FASE 5, analysis.md, plan.md, baseline.json

Generate `{LOOP_DIR}/changelog.md` with:
- Score progression: start -> end (delta)
- All APPLICATA changes with individual score contributions
- All REVERTITA changes with reasons
- Score breakdown: which metric improved/worsened for each change
- Updated documentation for accepted changes

Use these prefixes for the bash wrapper:
- `- APPLICATA: {description}`
- `- REVERTITA: {description}`
- `- SKIPPATA: {description}`

**Output:** `{LOOP_DIR}/changelog.md`

---

### FASE 6b — SUMMARY

Update `{ND_DIR}/summary.md` with cumulative stats across all loops completed so far.

Format:
```
═══ Night Dev Report ═══
Branch: {branch}
Loop: {current} / {max}
Score: {start_score} -> {current_score} (delta: +{total_delta})
Applied: X | Reverted: Y | Skipped: Z
═══════════════════════════

SCORE PROGRESSION:
Loop 1: {score_start} -> {score_end} (+{delta})
Loop 2: {score_start} -> {score_end} (+{delta})
...

TOP IMPROVEMENTS:
1. {description} — +{delta} points
2. {description} — +{delta} points
...

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

---

### FASE 7 — FINAL COMMIT

Commit any remaining documentation changes produced during FASE 6:
```bash
git add -A
git commit -m "night-dev loop {N}: docs update"
```

After this, your work for this loop is done. The bash wrapper handles the loop/stop decision.

---

## Critical Rules

1. **NEVER** modify files outside the worktree path.
2. **NEVER** use `git push`, `git reset --hard`, `git rebase`, or any force operations.
3. **ALWAYS** calculate score before AND after changes.
4. **ONLY keep changes that STRICTLY improve the score** (new > old, not >=).
5. **CAN create new files and modules** — Night Dev is a developer, not just a maintainer.
6. **CAN add new dependencies** — but prefer stdlib when possible.
7. **CANNOT change public API contracts** without updating all callers and tests.
8. **Write all outputs** to the loop directory.
9. **Never repeat reverted changes** from previous loops.
10. **Batch-first, fallback-sequential** — always try the full batch before falling back.
