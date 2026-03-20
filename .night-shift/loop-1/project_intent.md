# Night Dev — Project Intent Analysis

**Date:** 2026-03-20
**Loop:** 1 (refreshed with comprehensive documentation review)
**Scope:** Full project documentation review + code structure analysis

---

## Executive Summary

**Night Dev** is an autonomous evolutionary software development agent — a Claude Code skill that implements a multi-phase loop for aggressive development with rigorous quality gating. Unlike Night Shift (conservative bug fixes and maintenance), Night Dev proposes significant architectural changes, new features, refactoring, and dependency upgrades, accepting only those changes that measurably improve a composite quality score.

The project consists of:
- **Main orchestrator:** `scripts/night-dev.sh` (1084 lines) — bash script that coordinates 7 phases
- **Phase definitions:** `SKILL.md` (384 lines) — specification for each phase (FASE 0-7)
- **Reference prompts:** `references/*.md` (887 lines across 5 templates) — instructions for sub-agents
- **Skill registration:** `commands/night-dev.md` (98 lines) — interactive setup guide
- **Test suite:** `Makefile` (29 tests, 27 passing, 2 skipped, 100% pass rate)

**Current state:** Production-ready, undergoing optimization (3 loops of performance/quality improvements completed).

---

## Declared Objectives

### Primary Goals
1. **Autonomous development with quality gates** — automatically propose and implement improvements, but ONLY if they increase an objective score
2. **Evolutionary selection** — reject changes that don't strictly improve the system (equal is not good enough)
3. **Multi-dimensional quality** — optimize across test health + code quality + architecture quality, not just test farming
4. **Production readiness** — run against real projects with confidence that changes are beneficial

### Core Distinctions from Night Shift
- **Night Shift:** Conservative (fix bugs, patch security, improve quality)
- **Night Dev:** Aggressive (new features, new tests, refactoring, dependency upgrades, architecture improvements)
- **Common:** Both use score-based gating to ensure only improvements are kept

---

## Technical Specifications

### Scoring Function (Multi-Dimensional v2)

```
score = test_health + code_quality + architecture_quality

test_health:
  + (tests_passing × 5)
  + (coverage_pct × 3)
  - (tests_failing × 20)
  - (execution_time_s × 0.1)

code_quality:
  - (todo_fixme_hack_count × 1)
  - (cyclomatic_complexity_avg × 2)
  - (duplicate_blocks × 1)

architecture_quality:
  + (architecture_score × 10)  [0-10 rating from FASE 2 analysis]
```

**Key insight:** Architectural improvements are worth 10x a single passing test, incentivizing high-impact design changes.

### Phase Architecture (7 phases)

**FASE 0 — DEEP READ** (first loop only)
Reads entire codebase + documentation to understand:
- Purpose and scope
- Architecture map (modules, responsibilities)
- Test coverage analysis
- Development opportunities
- Technical debt
- Dependency analysis
Output: `project_understanding.md`

**FASE 1 — BASELINE CAPTURE** (every loop)
Run tests, extract metrics, calculate score.
Output: `baseline.json`

**FASE 2 — CRITICAL ANALYSIS**
Performs three-level analysis:
1. Code problems (security, bugs, performance, quality)
2. Development opportunities (missing features, test gaps, refactoring)
3. Architectural critique (dependency fitness, design patterns, abstraction quality, scalability, state-of-the-art gaps)

Produces 0-10 architecture_score.
Output: `analysis.md`

**FASE 3 — DEEP RESEARCH**
Web research + academic papers for:
- State-of-the-art improvements
- Reference implementations
- Best practices and alternatives

Output: `research.md` (skippable via `--skip-research`)

**FASE 4 — PLAN**
Creates implementation plan from analysis + research findings.
All tasks ordered by risk (low → high).
Output: `plan.md`

**FASE 5 — IMPLEMENT**
Batch-first strategy:
1. Implement ALL tasks in one pass
2. Test and score
3. If score improves: commit everything, skip fallback
4. If score doesn't improve: revert all, enter fallback mode
5. Fallback: implement one task at a time, test each, keep only what improves score

Output: Git commits (one per accepted change or batch)

**FASE 6 — REPORT**
Generate changelog with:
- Score progression
- All APPLICATA (applied) changes with individual deltas
- All REVERTITA (reverted) changes with reasons
- Detailed score breakdown

Output: `changelog.md`

**FASE 6b — SUMMARY**
Update cumulative stats across all loops.
Output: `summary.md`

**FASE 7 — FINAL COMMIT**
Commit any remaining documentation changes.

### Command-Line Interface

```bash
night-dev.sh <project-path-or-github-url> [OPTIONS]

Options:
  --max-loops N        Maximum development loops (default: 5)
  --hours H            Maximum runtime (default: 8)
  --skip-research      Skip FASE 3 (research phase)
  --branch BRANCH      Checkout specific branch after clone
  --push               Auto-push to remote after each loop
  --verbose            Stream Claude output to terminal
  --follow <path>      Attach to running Night Dev instance
  --inline             Run from inside Claude Code session
```

### Project Structure

```
night-dev-skill/
├── scripts/
│   └── night-dev.sh              (1084 lines) — main orchestrator
├── SKILL.md                       (384 lines) — phase definitions
├── references/
│   ├── analyze-prompt.md          (318 lines)
│   ├── implementation-prompt.md   (139 lines)
│   ├── planner-prompt.md          (141 lines)
│   ├── report-prompt.md           (171 lines)
│   └── research-prompt.md         (205 lines)
├── commands/
│   └── night-dev.md               (98 lines) — interactive setup
├── Makefile                       (90 lines) — test suite
└── .night-shift/                  (output directory structure)
```

---

## Quality Standards

### Test Coverage
- **Baseline:** 29 tests (27 passing, 2 skipped)
- **Exit criteria:** Any loop that breaks tests is reverted
- **Test types:** Syntax validation, structural validation (phase completeness), CLI help

### Code Quality Markers
- **TODO/FIXME:** 0 in executable code (only in instruction documents)
- **Target:** Maintain zero code markers across all loops
- **Dead code:** Actively removed (e.g., unused `calculate_score` function in loop 3)

### Performance Standards
- **Goal:** Minimize subprocess forks
- **Loop 1-2 wins:** Eliminated 20+ subprocess forks (date, readlink, awk, echo, git stash)
- **Loop 3 wins:** Eliminated 5-8 more forks (grep calls in detect_test_runner, git stash/pop)
- **Ongoing target:** Batch status.json updates, merge test result parsing

### Architectural Metrics
- **Architecture score:** 0-10 rating assigned by FASE 2 agent
- **Loop 1-3 rating:** Not explicitly documented in current project_intent files
- **Expectation:** Scores should improve as design patterns solidify

---

## Functional Specification

### Core Responsibilities

**Orchestrator (scripts/night-dev.sh):**
- Parse CLI arguments and validate project path
- Clone GitHub URLs if needed
- Initialize worktree and status tracking
- Dispatch sub-agents for each phase
- Manage phase transitions and error handling
- Implement batch-first + fallback-sequential logic
- Track score progression and circuit breaker logic

**FASE 2 (analyze-prompt.md):**
- Identify security vulnerabilities
- Find bugs and logic errors
- Spot performance bottlenecks
- Discover missing features and incomplete implementations
- Recommend architectural improvements
- Produce 0-10 architecture_score

**FASE 3 (research-prompt.md):**
- Search arXiv/Google Scholar for academic papers (2023-2026)
- Search GitHub for reference implementations
- Research best practices and alternatives
- Validate applicability to the project

**FASE 4 (planner-prompt.md):**
- Convert analysis + research into implementation tasks
- Order tasks by risk (low first)
- Estimate score impact for each task
- Provide implementation approach/hints

**FASE 5 (implementation-prompt.md):**
- Implement tasks from plan
- Modify/create files
- Run no git commands (orchestrator handles commits)

---

## Feature Completeness Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-phase orchestration | ✓ Complete | FASE 0-7 all implemented |
| Batch-first with fallback | ✓ Complete | Loop 2 added fallback logic |
| Scoring (v2) | ✓ Complete | Test health + code quality + architecture |
| GitHub auto-clone | ✓ Complete | Supports https:// and git@ URLs |
| Web research phase | ✓ Complete | Optional via --skip-research |
| Interactive setup | ✓ Complete | commands/night-dev.md implemented |
| Follow mode | ✓ Complete | --follow flag for attaching to running instances |
| Inline mode | ✓ Complete | --inline flag for Claude Code integration |
| Circuit breaker | ✓ Complete | Stops after 3 consecutive zero-applied loops |
| Stagnation detection | ✓ Complete | Stops after 2 consecutive loops with no score gain |
| Auto-push | ✓ Complete | --push flag for remote automation |

---

## Known Issues & Technical Debt

### Performance Issues (Identified in Audit)

**PERF-01 (HIGH):** Repeated jq read-modify-write on status.json
- Current: 4-6 separate jq invocations per loop
- Fix: Batch all status updates into single jq pass
- Impact: Eliminate 20-30 subprocess forks across 5-loop run

**PERF-06 (MEDIUM):** parse_test_results spawns 4 awk processes
- Current: 4 separate awk invocations per loop for test parsing
- Fix: Merge into single awk script
- Impact: Eliminate 3-4 forks per loop

**PERF-08 (MEDIUM):** git clone --local --no-hardlinks for backup
- Current: `--no-hardlinks` forces copying instead of hardlinking
- Fix: Remove --no-hardlinks to allow object hardlinking
- Impact: Halve backup disk usage and time

**PERF-05 (MEDIUM):** awk spawned for float comparison
- Current: `awk` used to compare decimal numbers
- Fix: Bash arithmetic with integer/fractional parts
- Impact: Eliminate 1 fork per loop

**PERF-03 (LOW):** git status capture uses subshell
- Current: `[[ -n "$(git status --porcelain)" ]]` buffers all output
- Fix: Use `git diff --quiet` which exits non-zero without output
- Impact: Faster dirty check for large repos

### Security Issues

**SEC-01 (MEDIUM):** .claude/settings.json grants unrestricted permissions
- Current: Worktree sub-agent has `Bash(*)`, `Write(*)`, `Read(*)` with wildcard
- Risk: Prompt injection in analyzed code could execute arbitrary commands
- Mitigation: By design (autonomous agent), but should scope to test runner + git commands
- Status: Documented, not yet fixed

**SEC-02 (FIXED in Loop 2):** ANSI injection vulnerability in output parsing
- Fixed in loop 2 via `process_output` function improvements

### Code Quality Issues

**QUALITY-01 (LOW):** Inline mode polling lacks exponential backoff
- Current: `sleep 5` in every iteration
- Improvement: Exponential backoff to reduce wake-ups for long operations

**QUALITY-02 (LOW):** Follow mode timestamp parsing is arbitrary
- Current: Uses first result from `find`, not most recent
- Fix: Sort results by modification time

---

## Inconsistencies (Docs vs Code)

### Documentation vs Implementation

**SKILL.md Phase Descriptions vs Script Reality:**
- ✓ FASE 0 (Deep Read) — Correctly implemented, runs only on loop 1
- ✓ FASE 1 (Baseline) — Correctly implemented, runs every loop
- ✓ FASE 2 (Analysis) — Correctly implemented, produces architecture_score
- ✓ FASE 3 (Research) — Correctly implemented, skippable
- ✓ FASE 4 (Plan) — Correctly implemented, orders by risk
- ✓ FASE 5 (Implementation) — Correctly implemented, batch-first + fallback
- ✓ FASE 6 (Report) — Correctly implemented, generates changelog
- ✓ FASE 6b (Summary) — Correctly implemented, aggregates loop stats
- ✓ FASE 7 (Final Commit) — Correctly implemented

**No material inconsistencies found.**

### Loop History (Loop Completion Status)

- **Loop 1:** Completed (18 tasks applied, 4 skipped)
- **Loop 2:** Completed (12 tasks applied, many PERF/SEC improvements)
- **Loop 3:** Completed (5 tasks applied, 3 skipped)
- **Total:** 35 changes applied across 3 loops, 23 passed

---

## Architecture Critique (Level 3 Analysis)

### Design Strengths
1. **Phase isolation** — Each phase is self-contained and can be debugged independently
2. **Prompt templating** — Reference prompts allow consistent, documented agent behavior across runs
3. **Score-based gating** — Evolutionary selection ensures only improvements survive
4. **Fallback mechanism** — Batch-first with sequential fallback handles risky multi-task implementations
5. **Worktree isolation** — Main branch never touched; all work in isolated git worktrees

### Architectural Observations
1. **Status.json as source of truth** — Multiple functions read/write it; bottleneck identified (PERF-01)
2. **Subprocess fork counting** — Core optimization strategy for CLI applications, but not yet fully optimized
3. **Claude Code integration** — Design assumes Claude Code with Agent tool; no fallback for standalone bash
4. **Error handling** — Early exit on any sub-agent failure (set -e); no retry or graceful degradation
5. **Loop termination** — Circuit breaker (3 consecutive zero-applied) + stagnation detection (2 consecutive no-score-gain) both in place

### Technical Coherence
- ✓ Bash choice is appropriate for orchestration (direct git + subprocess control)
- ✓ JSON (status.json) is appropriate for structured state
- ✓ Markdown for outputs (human-readable, version-controlled)
- ✓ Prompt templating pattern is clean and maintainable
- ✓ Model selection (haiku for simple tasks, default for complex) is sensible cost optimization

### Scalability Assessment
- **Strengths:** Can target projects of any size (no repo size limitations identified)
- **Bottlenecks:**
  - Subprocess overhead (20-40 forks per loop) — at scale (100+ loops), could accumulate
  - jq re-reads entire status.json (4-6 times per loop)
  - Test suite runtime is the true bottleneck, not orchestration
- **10x load:** Would increase loop count 10x → proportional increase in subprocess overhead, test time
- **100x load:** Still feasible; the orchestrator is not the limiting factor

---

## Development Opportunities (Identified in Audits)

### High-Impact (Architectural)
1. Batch status.json updates to reduce jq re-reads (PERF-01)
2. Consolidate test result parsing into single awk invocation (PERF-06)

### Medium-Impact (Performance)
1. Remove --no-hardlinks from git backup (PERF-08)
2. Use bash arithmetic for float comparison (PERF-05)
3. Scope .claude/settings.json permissions (SEC-01)

### Low-Impact (Quality)
1. Exponential backoff in inline mode polling (QUALITY-01)
2. Sort follow mode results by timestamp (QUALITY-02)
3. Use git diff --quiet instead of status capture (PERF-03)

### Not Yet Identified
- Dependency upgrades (all bash builtins, no external dependencies beyond git/jq)
- Test gaps (Makefile covers syntax, structure, help — could add integration tests)
- Missing features (all declared objectives implemented)

---

## Current Loop Status

**Loop 3 Completion (2026-03-20):**
- Tests: 29 passed, 0 failed
- Tasks: 5 applied, 3 skipped
- Performance wins: 5-8 subprocess forks eliminated
- Score improvement: Incremental (final score not documented in current project_intent files)

**Next steps (if continued):**
- Implement PERF-01 (batch jq updates) — highest impact remaining
- Implement PERF-06 (merge awk test parsing) — high impact
- Address SEC-01 scoping if security becomes priority

---

## Summary Table

| Dimension | Status | Notes |
|-----------|--------|-------|
| **Purpose** | Clear | Autonomous evolutionary development with quality gates |
| **Objectives** | ✓ Met | All 7 phases implemented, scoring v2 operational |
| **Scope** | Complete | No missing features from SKILL.md |
| **Quality** | Good | 27/29 tests pass, 0 code markers, actively optimized |
| **Documentation** | Excellent | SKILL.md (384 lines), 5 reference prompts, Makefile tests |
| **Consistency** | ✓ Good | Docs match implementation, no material gaps |
| **Performance** | Improving | 3 loops of optimization; 20+ forks eliminated; 6 more opportunities |
| **Architecture** | Solid | Phase isolation, prompt templating, score-based gating; bottleneck in status.json |
| **Security** | Acceptable | Documented issue (SEC-01) in sub-agent permissions; mitigated by design |
| **Scalability** | Good | No repo size limitations; subprocess overhead manageable up to 100x load |
| **Technical Debt** | Low | Actively managed; most issues are performance micro-optimizations |

---

**Analysis completed:** 2026-03-20
**Next review point:** After loop 4 (if loops continue)
