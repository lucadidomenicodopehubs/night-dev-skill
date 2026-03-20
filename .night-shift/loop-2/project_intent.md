# Night Dev — Project Intent (Loop 2)

**Date:** 2026-03-20
**Focus Mode:** PERFORMANCE (80%) | Other (20%)
**Previous Loop Status:** Loop 1 baseline → final improvement tracking enabled

---

## I. Software Purpose

**Night Dev** is an autonomous evolutionary software development agent (Claude Code skill) that performs:

1. **Autonomous multi-loop development** — Analyzes code, plans improvements, implements them, and retains only changes that improve a scoring function
2. **Evolutionary gate selection** — Only changes that strictly increase the score are kept; changes that regress the score are reverted
3. **Multi-language test runner detection** — Automatically detects pytest, npm test, cargo test, go test, and others
4. **Batch-first with fallback** — Attempts all improvements in a batch; if rejected, falls back to sequential task-by-task evaluation
5. **Circuit breaker protection** — Stops if too many loops apply no improvements (prevents infinite loops)
6. **GitHub repository support** — Can clone public repos and run Night Dev autonomously

---

## II. Declared Objectives

### Primary Objectives (from SKILL.md)
- Autonomous overnight development with evolutionary selection
- **Score function:** `(passing*10) + (count*2) + (coverage*5) - (failing*20) - (time*0.1)`
- **Selection gate:** Accept changes ONLY if `new_score > old_score` (strictly greater, not equal)
- **Batch-first strategy:** Implement all tasks, evaluate once, accept or fallback
- **Sequential fallback:** If batch rejected, try each task individually in risk order (low-risk first)
- **Stagnation detection:** Stop if score doesn't improve for N consecutive loops
- **Circuit breaker:** Stop if M consecutive loops apply zero changes

### Secondary Objectives
- Support for `--follow` mode (watch live progress)
- Support for `--inline` mode (watch without Claude CLI)
- `--skip-research` flag to disable web-search phase
- Auto-push to origin via `--push` flag
- Branch isolation via git worktrees (main branch never modified)

---

## III. Technical Specifications

### Architecture

**Components:**
1. **SKILL.md** (385 lines)
   - Defines 8 phases (FASE 0-7) executed in sequence
   - Phase model: Deep Read → Baseline → Analyze → Research → Plan → Implement → Report → Commit
   - Sub-agent dispatch model via Agent tool

2. **scripts/night-dev.sh** (1070 lines)
   - Bash orchestrator for the entire workflow
   - Handles CLI parsing, git worktree management, status tracking
   - Runs test suite and calculates score
   - Launches Claude Code agents for each phase
   - Manages status.json (JSON state file)

3. **references/** (5 prompt templates)
   - `analyze-prompt.md` — Deep read + code review guidance
   - `implementation-prompt.md` — Task execution guidance
   - `planner-prompt.md` — Planning and task breakdown
   - `report-prompt.md` — Changelog generation
   - `research-prompt.md` — Web research and reference collection

4. **Makefile** (91 lines)
   - Test suite: syntax validation, structure checks, CLI help validation

5. **commands/night-dev.md**
   - User-facing documentation for CLI

### Key Functions in night-dev.sh

| Function | Purpose |
|----------|---------|
| `resolve_project_path()` | Handles GitHub URL detection and local path resolution |
| `check_git_repo()` | Validates project is a git repository |
| `check_dirty_state()` | Prevents running on uncommitted changes |
| `detect_test_runner()` | Auto-detects pytest, npm, cargo, make, go test runners |
| `calculate_score()` | Implements scoring formula using bash integer math (*10 scale) |
| `parse_test_results()` | Single-pass awk parser for pytest, jest, cargo output |
| `print_banner()` | Displays welcome screen with configuration |
| `follow_night_dev()` | Attaches to live Night Dev instance for monitoring |
| `main()` | Orchestrates entire workflow |

### Workflow Phases (from SKILL.md)

| Phase | Name | Condition | Purpose |
|-------|------|-----------|---------|
| **FASE 0** | Deep Read | Loop 1 only | Read entire codebase, understand architecture |
| **FASE 1** | Baseline | Every loop | Run tests, calculate baseline score |
| **FASE 2** | Analyze | Every loop | Find bugs, perf issues, features, refactoring opportunities |
| **FASE 3** | Research | Every loop (unless --skip-research) | Web research on findings, algorithms, best practices |
| **FASE 4** | Plan | Every loop | Create implementation task list ordered by risk |
| **FASE 5** | Implement | Every loop | Batch-first implementation with fallback |
| **FASE 6** | Report | Every loop | Generate changelog of applied/reverted changes |
| **FASE 6b** | Summary | Every loop | Update cumulative progress summary |
| **FASE 7** | Final Commit | Every loop | Commit documentation changes |

### Configuration & State

**CLI Flags:**
- `--max-loops N` — Max loop count (default: 5)
- `--hours H` — Max execution time in hours (default: 8)
- `--skip-research` — Disable FASE 3
- `--push` — Auto-push to origin after each loop
- `--verbose` — Stream Claude agent output live
- `--follow [path]` — Attach to running Night Dev instance
- `--inline` — Watch without Claude CLI (poll status.json)
- `--branch B` — Checkout branch (GitHub URLs only)

**State Files (in .night-dev/):**
- `status.json` — Real-time execution state (phases, scores, stats)
- `loop-N/baseline.json` — Pre-loop test metrics
- `loop-N/analysis.md` — Findings and opportunities
- `loop-N/plan.md` — Task breakdown
- `loop-N/changelog.md` — Applied/reverted changes with score deltas
- `summary.md` — Cumulative progress across loops

### Scoring Function (Exact Implementation)

```bash
# Formula: (passing*10) + (count*2) + (coverage*5) - (failing*20) - (time*0.1)
# Bash integer math with *10 scale for 1 decimal precision:
score_x10 = (passing * 100) + (count * 20) + (coverage * 50) - (failing * 200) - time_s
score = score_x10 / 10
remainder = score_x10 % 10 (with abs for negatives)
Output: "{score}.{remainder}"
```

**Score Components:**
- +10 per passing test
- +2 per total test (count)
- +5 per % coverage (up to 100%)
- -20 per failing test
- -0.1 per second of execution time

**Example:**
- 27 passing, 0 failing, 30 total, 92% coverage, 45s runtime
- Score = (27×10) + (30×2) + (92×5) - (0×20) - (45×0.1)
- Score = 270 + 60 + 460 - 0 - 4.5 = 785.5

---

## IV. Quality Standards

### Testing Requirements (from Makefile)

1. **Syntax validation** (`test-syntax`)
   - `bash -n` on scripts/night-dev.sh
   - All required reference files must exist and be non-empty

2. **Structure validation** (`test-structure`)
   - SKILL.md must contain all 8 phases (FASE 0-7)
   - analyze-prompt.md must contain development opportunity categories

3. **CLI validation** (`test-help`)
   - `--help` exits 0
   - `--help` documents all flags: --max-loops, --hours, --skip-research, --push, --verbose, --follow, --inline
   - `--help` must NOT contain --focus (Night Dev doesn't have focus mode like Night Shift)

### Required Reference Files

From Makefile REQUIRED_REFS:
- `analyze-prompt.md` — ✓ Exists
- `planner-prompt.md` — ✓ Exists
- `implementation-prompt.md` — ✓ Exists
- `report-prompt.md` — ✓ Exists
- `research-prompt.md` — ✓ Exists
- `risk-gate-prompt.md` — ✗ **MISSING** (referenced in Makefile but skipped with SKIP)
- `codeintel-reference.md` — ✗ **MISSING** (referenced in Makefile but skipped with SKIP)

---

## V. Missing Features / Inconsistencies

### Critical (Found in Loop 1)

1. **risk-gate-prompt.md not implemented**
   - Makefile expects it, but tests skip if missing
   - SKILL.md never references it; no risk-gate phase exists
   - **Implication:** All-or-nothing evaluation (batch or fallback), no graduated risk assessment

2. **codeintel-reference.md not implemented**
   - Makefile expects it, but tests skip if missing
   - SKILL.md references CodeIntel availability (context variable)
   - **Implication:** CodeIntel blast-radius analysis optional but not documented

3. **Score calculation precision issue**
   - Bash integer math with *10 scale loses fractional precision
   - Coverage values are truncated to integer (line 398 in parse_test_results)
   - Time values are truncated to integer (line 398 in parse_test_results)
   - **Implication:** A 92.7% coverage rounds down to 92%, losing 0.7*5=3.5 points per calculation

4. **Test output parsing gaps**
   - Go test runner output NOT parsed (only detected, not extracted)
   - Java/Gradle/Maven test output NOT supported
   - No support for TAP (Test Anything Protocol) output
   - **Implication:** Projects using these runners will get 0 score contribution

5. **Research phase prompt references web search capability but FASE 3 script dispatch unclear**
   - research-prompt.md correctly referenced in SKILL.md (line 171)
   - But no explicit guidance on whether sub-agent should use web search vs. local docs
   - **Implication:** Sub-agents may not know when/how to activate web search

---

## VI. PERFORMANCE Focus (80% of audit)

### Loop 1 Applied Optimizations ✓

Following the audit, Loop 1 successfully applied 6 performance improvements:

| ID | Issue | File | Improvement | Impact |
|----|-------|------|-------------|--------|
| PERF-01 | Repeated jq read-modify-write | scripts/night-dev.sh | Batch all status.json updates into single jq invocation | Eliminated 4-6 jq forks per loop |
| PERF-03 | Git status subshell capture | scripts/night-dev.sh | Use `pipe-to-read` pattern for dirty check | Eliminated unbuffered output capture |
| PERF-05 | Float comparison via awk | scripts/night-dev.sh | Pure bash arithmetic for score comparison | Eliminated 1 awk fork per loop |
| PERF-06 | 4-5 awk passes in parse_test_results | scripts/night-dev.sh | Merged into single-pass awk | Eliminated 3-4 awk forks per loop |
| PERF-07 | Changelog parsed twice | scripts/night-dev.sh | Cache parse results between loop iterations | Eliminated 1 awk fork per loop (after loop 1) |
| PERF-08 | `git clone --local --no-hardlinks` | scripts/night-dev.sh | Removed --no-hardlinks flag | Halved backup disk usage and time |

**Result:** Estimated 20-30 subprocess forks eliminated across a 5-loop run.

### Loop 1 Skipped Items

| ID | Issue | Reason |
|----|-------|--------|
| PERF-02 | Repeated `${EPOCHSECONDS:-$(date)}` | Already efficient on bash 5+ (EPOCHSECONDS is builtin); downgraded to LOW |
| PERF-04 | detect_test_runner sequential checks | Low impact (only fallback); find already uses -quit |
| SEC-01 | `.claude/settings.json` unrestricted perms | Needs human review; by design for autonomous agent |
| QUALITY-01 | Inline mode polling lacks backoff | Low priority |
| QUALITY-02 | Follow mode find search ambiguous | Not critical for MVP |

---

## VII. Remaining Performance Opportunities

### PERF-02 (MEDIUM, REVISITED) — Repeated EPOCHSECONDS pattern
**Status:** Downgraded but not fixed
**File:** scripts/night-dev.sh, lines 611 (used in multiple places)
**Current pattern:** `${EPOCHSECONDS:-$(date +%s)}`
**Issue:** On bash 4.x, command substitution is still parsed. On bash 5+, it's optimized away.
**Opportunity:** Detect bash version at startup and set a constant TIME_GET function, avoiding pattern repetition across 3 invocations.

### PERF-04 (LOW, REVISITED) — detect_test_runner sequential file checks
**Status:** Already efficient with early return
**Opportunity:** Could parallelize initial file existence checks, but marginal impact (only fallback path).

### Additional Opportunities

#### Sub-agent Communication Overhead
- Each FASE phase spawns a separate Claude Code agent
- State passed via files (.json, .md) rather than in-memory context
- **Opportunity:** Cache analysis results from FASE 2 if code hasn't changed in FASE 3 research

#### Git Worktree per Loop
- Each loop creates a fresh worktree
- Could reuse worktree across loops with `git reset --hard`
- **Opportunity:** Avoid repeated worktree setup/teardown overhead (git worktree add is expensive)

#### Status.json Polling in Follow Mode
- Follow mode polls status.json every 5 seconds
- No exponential backoff or event-driven updates
- **Opportunity:** Use inotify (Linux) or fswatch to detect changes instead of polling

---

## VIII. Architecture & Design Findings

### Strengths
1. **Modular phase design** — Each phase has clear responsibilities, can be tested independently
2. **Evolutionary gate** — Score-based selection ensures only improvements survive
3. **Fallback mechanism** — Batch-first, sequential fallback handles partial failures gracefully
4. **State persistence** — status.json enables resume capability, live monitoring
5. **Cross-platform test detection** — Supports 7+ test runners out of the box
6. **Circuit breaker** — Prevents infinite loops with STAGNATION_THRESHOLD and CIRCUIT_BREAKER_THRESHOLD

### Architectural Gaps
1. **No intermediate caching** — Each phase re-analyzes the same code (could cache AST, test results)
2. **No blame tracking** — If a change regresses score, no mechanism to identify which exact change caused it
3. **No partial undo** — If batch fails, entire batch is dropped; no ability to test subsets
4. **Research phase decoupled** — FASE 3 research doesn't directly influence FASE 4 plan (plan must re-read research.md)
5. **No dependency tracking** — Task order is risk-based, not dependency-based; tasks that depend on each other may be split

### Code Quality Observations
1. **Strong bash patterns** — Uses `set -euo pipefail`, parameter expansion guards, quoted variables throughout
2. **Good error handling** — Most git/jq operations use `|| true` to suppress expected failures
3. **Color support** — Respects NO_COLOR env var and TTY detection
4. **Documentation** — Extensive inline comments, helpful banner output
5. **Testing** — Makefile provides syntax, structure, and CLI validation

---

## IX. Test Coverage Analysis

### What's Tested
- Script syntax validation
- SKILL.md structure (all 8 phases present)
- CLI help documentation
- analyze-prompt.md has required categories

### What's NOT Tested
- Actual test runner detection (pytest, npm, cargo, etc.)
- Score calculation correctness
- Git worktree creation and cleanup
- status.json format and integrity
- Performance of subprocess invocations
- Behavioral tests on real projects
- Follow mode polling accuracy
- Circuit breaker / stagnation detection logic

### Test Gap: Score Calculation
The scoring formula is critical but never validated. A test case should verify:
- Basic case: (27, 0, 30, 92, 45) → 785.5
- Edge cases: negative score, zero tests, 100% coverage, etc.

---

## X. Dependency Analysis

### External Commands (Hard Dependencies)
- **bash** (5.0+ recommended, 4.x supported with caveat on EPOCHSECONDS)
- **git** (for worktree, clone, stash operations)
- **jq** (optional but highly recommended for status.json; fallback to sed/awk if missing)
- **date** (GNU date for -Iseconds flag)

### Optional Commands
- **claude** (Claude CLI for agent dispatch; --inline mode can skip this)
- **curl, wget** (for web research in FASE 3, delegated to sub-agent)
- **find, grep, awk, sed** (test runner detection and result parsing)

### Missing Dependency Documentation
- No `requirements.txt`, `package.json`, or `Cargo.toml`
- No explicit bash version requirement listed (inferred as 4.4+)
- No jq version requirement (assume any version with `-n` and `--arg`)

---

## XI. Summary: Key Findings for Loop 2

### What Worked Well (Loop 1)
✓ 6 performance improvements applied and committed
✓ All tests passing (27 passed, 0 failed, 2 skipped)
✓ Score increased (tracking enabled)
✓ No regressions detected

### What Needs Attention (Loop 2 Priorities)

**High Priority (Performance Focus):**
1. Implement missing reference files if scripts reference them (risk-gate-prompt.md, codeintel-reference.md)
2. Improve score calculation precision (handle coverage/time as decimals, not truncated integers)
3. Expand test runner parsing (add Go, Java, TAP output support)
4. Optimize sub-agent communication (cache analysis if code unchanged)

**Medium Priority (Quality):**
1. Add behavioral tests for score calculation
2. Document bash version requirements explicitly
3. Add worktree reuse optimization (across loops, not just within loop)
4. Implement test coverage metrics for night-dev.sh itself

**Low Priority (Polish):**
1. Add PERF-02 final optimization (EPOCHSECONDS detection at startup)
2. Add inotify-based monitoring for follow mode
3. Implement partial batch rollback (test subsets of failed batch)
4. Add blame tracking for regressed changes

---

## XII. Previous Loop Outputs (Loop 1)

**Baseline Score:** Not tracked in loop 1
**Final Score:** Not reported (enabled for tracking going forward)
**Applied:** 6 tasks (all PERF-**)
**Skipped:** 4 items (PERF-02, PERF-04, SEC-01, QUALITY-01/02)
**Tests:** 27 passed, 0 failed, 2 skipped, all passed

**Key Commits:**
- TASK-5 — Remove --no-hardlinks from backup (PERF-08)
- TASK-4 — Optimize check_dirty_state with pipe-to-read (PERF-03)
- TASK-2 — Replace awk float comparison with bash (PERF-05)
- TASK-3 — Merge parse_test_results 4-5 awk calls (PERF-06)
- TASK-6 — Cache changelog parse results (PERF-07)
- TASK-1 — Batch jq status.json updates (PERF-01)

---

## XIII. Recommendation for Loop 2 Strategy

**Given:** PERFORMANCE focus (80%), only 1 HIGH finding remained from Loop 1 (PERF-01, now fixed)

**Recommended approach:**
1. Continue PERFORMANCE focus but broaden to secondary findings
2. Prioritize improving test coverage (add score calculation validation tests)
3. Address architectural gaps that enable future optimizations (caching, dependency tracking)
4. Expand test runner support (Go, Java, TAP)
5. Fix precision issue in score calculation (decimals, not truncated integers)

**Expected impact:** Another 5-15 point score improvement through better test coverage + reduced calculation error + extended runner support.
