# Night Shift Audit — Loop 3 (Final)

**Date:** 2026-03-20
**Project:** night-dev-skill (autonomous evolutionary development agent)
**Main file:** scripts/night-dev.sh (1073 lines)
**Focus:** Final incremental audit — regressions, remaining bugs, security, quality
**Prior work:** 23 changes applied across loops 1-3 (this session), 0 rollbacks

---

## Metrics

- Tests: 29 passed, 0 failed, 0 skipped
- Coverage: N/A (no bash coverage tooling)
- LOC: ~1073 (night-dev.sh)
- Score: 328.0 (stable across all loops)

---

## Regression Check

All 23 previously applied changes verified — no regressions detected:
- Score comparison uses raw x10 integers (line 977): correct
- PIPESTATUS[0] captured in verbose mode (line 926): correct
- Changelog patterns use structural anchors (lines 996-1000): correct
- DETECTED_RUNNER allowlist validated before heredoc (lines 712-715): correct
- Dead functions removed (update_status, calculate_score): confirmed absent
- Subprocess forks eliminated in detect_test_runner: confirmed (bash patterns for pyproject, setup.cfg, package.json, Makefile; find|read for Go)
- Backup no longer uses git stash/pop (line 616): confirmed clean

---

## Issues Found

### BUG

#### BUG-01 [MEDIUM] scripts/night-dev.sh:915

**Inline mode writes "DONE" to inline_status even after timeout.**

When inline mode hits the deadline (lines 909-912), it writes "TIMEOUT" to inline_status and breaks out of the wait loop. However, line 915 unconditionally writes "DONE" to inline_status, overwriting the "TIMEOUT" marker. Any external orchestrator polling this file will see "DONE" instead of "TIMEOUT", masking the timeout condition.

**Fix:** Wrap line 915 in a condition: only write "DONE" if `[[ -f "$LOOP_DIR/done" ]]` (the marker actually exists). Alternatively, move the "DONE" write inside an `else` block after the while loop.

#### BUG-02 [MEDIUM] scripts/night-dev.sh:950-952

**Inline mode falls through to score calculation without Claude output.**

After inline mode finishes (or times out), execution continues to line 950 which looks for `$LOOP_DIR/claude_output.log`. In inline mode, the orchestrator is expected to produce this file, but there is no check that it actually exists or is non-empty before calling `parse_test_results`. If the orchestrator only creates the `done` marker without writing `claude_output.log`, `parse_test_results` will return "0 0 0 0 0" and the score will be 0.0 — the stagnation detector will then trigger an early exit after 2 loops of this.

**Fix:** After the inline mode block, add a guard similar to the non-inline Claude failure path (lines 933-944): check that `claude_output.log` exists and is non-empty, and `continue` to the next loop if not.

#### BUG-03 [LOW] scripts/night-dev.sh:961

**Score formula diverges from SKILL.md specification.**

SKILL.md line 39 specifies `execution_time_s * 0.1` as the time penalty. The implementation at line 961 uses `- cur_time_s` (i.e., multiplied by 1.0, not 0.1). In x10 representation, `execution_time_s * 0.1` should be `- cur_time_s` (since score_x10 is already scaled by 10), so the multiplication is `0.1 * 10 = 1`. This is actually **correct** — the x10 scaling cancels the 0.1. However, the SKILL.md also specifies `code_quality` and `architecture_quality` components (lines 41-48) that are not implemented at all in the bash scoring. The implementation only covers `test_health`. This means the documented scoring formula and the actual scoring formula disagree significantly.

**Fix:** Either update SKILL.md to document that only `test_health` is scored by the bash wrapper (code_quality and architecture_quality are scored by the Claude agent in analysis.md), or add a comment in the script explaining the intentional divergence. This is a documentation/intent issue rather than a code bug.

### SECURITY

#### SEC-01 [MEDIUM] scripts/night-dev.sh:718-739

**Sub-agent Bash permissions allowlist is too narrow for real operations.**

Carried forward from loop 2 audit (SEC-01). The allowlist grants permissions for the test runner, git, cd, ls, wc, cat. Sub-agents dispatched by SKILL.md also need:
- `mkdir` — creating directories for new files
- `find` — codebase scanning in analyze-prompt.md
- `head`/`tail` — log inspection
- `npm`/`pip`/`cargo` (non-test invocations) — dependency operations referenced in SKILL.md

The `defaultMode: auto` setting will prompt for these, but `claude -p` runs non-interactively, so missing permissions cause silent failures or hangs.

**Fix:** Add `"Bash(mkdir *)"`, `"Bash(find *)"`, `"Bash(head *)"`, `"Bash(tail *)"` to the allowlist. For broader operations, consider `"Bash(npm *)"` (scoped to npm only, not arbitrary commands).

#### SEC-02 [LOW] scripts/night-dev.sh:453

**Follow mode find command searches $HOME/night-dev-repos with -maxdepth 4.**

The `find "$search_path" "$HOME/night-dev-repos" -maxdepth 4` command always searches both the user-specified path and `$HOME/night-dev-repos`, even if the user pointed to a specific directory. If `$HOME/night-dev-repos` contains multiple cloned repositories with `.night-dev/status.json` files, the follow mode may attach to the wrong instance. The "most recent by mtime" heuristic helps, but if two instances are running concurrently, the user's intent may be misread.

**Fix:** When `$PROJECT_PATH` is explicitly provided via `--follow <path>`, search only that path (skip the `$HOME/night-dev-repos` fallback). Only use the broad search when `--follow` is used without a path argument.

### QUALITY

#### QUAL-01 [MEDIUM] scripts/night-dev.sh:765-766, 855-856, 939, 1036

**Repeated `local tmp="${ND_DIR}/status.tmp.json"` declaration inside loop body.**

The variable `tmp` is declared with `local` four times inside the main loop body (lines 855, 939, 1036) and once in cleanup (line 765). In bash, re-declaring a `local` variable in the same function scope is a no-op but adds noise. More importantly, if two code paths execute close together (e.g., the jq update at line 1036 races with a signal triggering cleanup at line 765), both write to the same temp file path, risking a corrupted status.json.

**Fix:** Declare `local tmp` once before the loop, or use distinct temp file names (e.g., `status.tmp.$$.json` with PID) to prevent any race between the cleanup trap and the main loop.

#### QUAL-02 [LOW] scripts/night-dev.sh:576

**Follow mode completion summary uses unnecessarily complex printf+jq wrapper.**

Line 576: `printf '%s\n' "$(jq -r '...' "$status_file")"` — the `printf` wrapper is redundant since `jq -r` already outputs raw text to stdout. This was noted in the loop 2 audit (QUALITY-02) but not addressed.

**Fix:** Simplify to: `jq -r '"Applied: \(.stats.total_applied) | ..."' "$status_file"`

#### QUAL-03 [LOW] scripts/night-dev.sh:518-529

**Follow mode wait loop redeclares `local current_loop_num` on every iteration.**

Inside the `while true` loop at lines 518-529, `local current_loop_num` is declared on each iteration. In bash, `local` inside a loop does not create a new scope per iteration — it just reassigns. The `local` keyword should be outside the loop.

**Fix:** Move `local current_loop_num` before the while loop (after line 517).

#### QUAL-04 [LOW] scripts/night-dev.sh:543

**Follow mode monitor loop also redeclares `local` variables per iteration.**

Same pattern as QUAL-03: `local current_loop_num current_phase new_log=""` at line 543, `local loop_status_data` at line 545, and `local candidate` at line 553 are all inside a `while` loop body. These should be declared before the loop.

**Fix:** Move all `local` declarations before the while loop at line 541.

### PERFORMANCE

#### PERF-01 [LOW] scripts/night-dev.sh:956

**parse_test_results invoked via subshell fork.**

Line 956: `test_data=$(parse_test_results "$test_output")` creates a subshell to capture the function's stdout. The function itself spawns `awk` (one fork). This could be avoided by having the function set global variables directly instead of echoing. However, the awk invocation itself is the dominant cost, making this a marginal optimization.

**Fix:** Low priority. Could refactor parse_test_results to set `_PARSE_PASSED`, `_PARSE_FAILED`, etc. globals directly, but readability cost outweighs the benefit of eliminating one subshell.

#### PERF-02 [LOW] scripts/night-dev.sh:465

**Follow mode uses `stat -c '%Y'` in a loop — one fork per worktree.**

For each found status.json file, `stat` is invoked as a subprocess (line 465). If many worktrees exist, this is N forks. Could use `ls --sort=time` or `find -printf '%T@ %p'` to get mtimes in a single invocation.

**Fix:** Low priority since the typical case is 1-3 worktrees. Replace loop with: `find ... -printf '%T@ %p\0' | sort -z -rn | head -z -1 | cut -z -d' ' -f2-`.

---

## Summary

| Category    | Critical | High | Medium | Low |
|-------------|----------|------|--------|-----|
| BUG         | 0        | 0    | 2      | 1   |
| SECURITY    | 0        | 0    | 1      | 1   |
| QUALITY     | 0        | 0    | 1      | 3   |
| PERFORMANCE | 0        | 0    | 0      | 2   |
| **Total**   | **0**    | **0** | **4** | **7** |

### Top 5 Actionable Items (by impact):

1. **BUG-01** (MEDIUM): Fix inline mode overwriting "TIMEOUT" with "DONE" — orchestrator cannot detect timeouts
2. **BUG-02** (MEDIUM): Add guard for missing claude_output.log in inline mode — prevents false stagnation exit
3. **SEC-01** (MEDIUM): Add missing commands to sub-agent Bash permissions — prevents silent failures in `claude -p` sessions
4. **QUAL-01** (MEDIUM): Use distinct temp file names or single declaration for status.json tmp — prevents potential race in cleanup trap
5. **BUG-03** (LOW): Document score formula divergence between SKILL.md and implementation — code_quality/architecture_quality not implemented in bash

### Defer (low impact, final loop):
- **QUAL-02**: printf+jq simplification (cosmetic)
- **QUAL-03/04**: local variable declaration placement (cosmetic, no functional impact)
- **PERF-01/02**: Marginal subprocess elimination (< 1ms savings each)
- **SEC-02**: Follow mode search scope (edge case with concurrent instances)
