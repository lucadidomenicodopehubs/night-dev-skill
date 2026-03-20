# Night Shift Audit — Loop 2

**Date:** 2026-03-20
**Project:** night-dev-skill (autonomous evolutionary development agent)
**Main file:** scripts/night-dev.sh (1072 lines)
**Focus:** Incremental audit on loop 1 changes + remaining issues

---

## Metrics

- Tests: 27 passed, 0 failed, 2 skipped (29 total)
- Coverage: 0% (no coverage tooling for bash)
- Execution time: ~0.05s
- Files: 10 source | LOC: ~2600 | TODO/FIXME/HACK: 0
- Score: 328.0

---

## Issues Found

### SECURITY

#### SEC-01 [MEDIUM] scripts/night-dev.sh:718-739

**Scoped Bash permissions are insufficient for sub-agent operations.**

Loop 1 correctly replaced `Bash(*)` with a scoped allowlist (TASK-01). However, the current allowlist is missing commands that SKILL.md sub-agents need:

- `npx` — needed for CodeIntel indexing (referenced at analyze-prompt.md for `npx tsx ... analyze`)
- `echo` — sub-agents use `echo` to write files like `research.md` skip markers (SKILL.md line 251: `echo "Research skipped..."`)
- `find` — needed by analyze-prompt.md for codebase scanning (Step 0.2), and by `detect_test_runner` for Go test file discovery
- `mkdir` — agents may need to create directories for new files
- `cloc` — referenced in audit-prompt.md for LOC counting
- `pip audit` / `npm audit` / `cargo audit` — referenced in audit-prompt.md Step 0.4
- `head` / `tail` — common for log inspection by report agents
- `printf` — used by agents for output formatting

The `defaultMode: auto` setting will prompt for these commands, but since `claude -p` (prompt mode) runs non-interactively, missing permissions will cause silent failures or blocks.

**Fix:** Add commonly needed commands to the allowlist: `"Bash(npx *)"`, `"Bash(echo *)"`, `"Bash(find *)"`, `"Bash(mkdir *)"`, `"Bash(head *)"`, `"Bash(tail *)"`, `"Bash(printf *)"`. Alternatively, use `"Bash(npx tsx *)"` for tighter scoping on CodeIntel. Note: `Read(*)` and `Write(*)` permissions handle most file operations, but command-line tools may still be needed.

#### SEC-02 [LOW] scripts/night-dev.sh:718

**Settings.json uses unquoted heredoc, enabling variable injection in DETECTED_RUNNER.**

The heredoc `<<EOSETTINGS` (without quotes) means `${DETECTED_RUNNER}` is expanded by bash. If a malicious `Makefile` or `package.json` causes `detect_test_runner()` to set `DETECTED_RUNNER` to a value containing `"`, `}`, or other JSON-breaking characters, the generated `settings.json` would be malformed or could inject additional permissions. For example, a `package.json` with `"test": "echo 'injected\"], \"Bash(*)\", [\"more"` would break the JSON structure.

Current risk is low because `DETECTED_RUNNER` is set to one of a few hardcoded values (`pytest`, `npm test`, `cargo test`, `go test ./...`, `make test`, `tox`). But the Makefile detection path (lines 300-308) reads the project's Makefile line by line and could be extended in the future.

**Fix:** Validate `DETECTED_RUNNER` against an allowlist of known values before interpolation, or use `jq` to construct the JSON safely: `jq -n --arg runner "$DETECTED_RUNNER" '{permissions: {allow: [("Bash(" + $runner + ")"), ...]}}'`.

---

### BUG

#### BUG-01 [MEDIUM] scripts/night-dev.sh:975-977

**Score comparison still broken for negative scores with fractional parts.**

This was identified as BUG-03 (LOW) in loop 1 but not fixed. The comparison logic at line 977:
```bash
if (( (ci * 10 + ${cf:-0}) > (pi * 10 + ${pf:-0}) )); then
```
fails for negative scores. When `current_score="-1.5"`, `IFS=. read` splits it into `ci="-1"` and `cf="5"`. The expression becomes `(-1 * 10 + 5) = -5`, but the actual value is `-1.5` which should be `-15` in x10 representation. The fractional part should be subtracted, not added, when the integer part is negative.

Similarly, for `current_score="-0.3"`, the sign is in `ci="-0"` and `cf="3"`. Expression: `(-0 * 10 + 3) = 3`, but the real value is `-0.3` = `-3` in x10 representation. The sign on `-0` is lost in arithmetic.

While negative scores are unlikely in practice (requires many failing tests or no passing tests), the score formatting was just fixed in loop 1 to correctly produce negative scores, making this comparison path reachable.

**Fix:** Use the `score_x10` integer directly for comparison instead of re-parsing the formatted string. Store `score_x10` alongside `current_score` and compare the raw integers: `if (( current_score_x10 > previous_score_x10 )); then`.

#### BUG-02 [MEDIUM] scripts/night-dev.sh:994-998

**Overly broad changelog pattern matching counts false positives.**

Loop 1 changed the changelog parsing from strict patterns (`*[-\*]\ APPLICATA\ :*`) to very broad ones (`*APPLICATA*`). This was intended to be more resilient (QUALITY-02/TASK-11), but now ANY line containing the word "APPLICATA" increments the counter. This includes:

- Section headers like `## Changes Applied` followed by markdown table headers containing "APPLICATA" as a column value
- The loop 1 changelog itself contains `## Category Breakdown` with a table row `| SECURITY | 2 | Applied |` — while "Applied" does not match, other formatting could
- Lines like `Previously: 10 Applied / 1 Monitoring` or `All tasks verified: APPLICATA` in summary text
- The word appearing in comments, descriptions, or status text

The loop 1 changelog has 10 lines matching `*APPLICATA*`, all legitimate. But a report agent producing a summary table like `| TASK-1 | test | +36 | APPLICATA |` would count the table header AND the data row if both contain the keyword.

**Fix:** Add minimal structure requirements back: match `*- APPLICATA*` or `*APPLICATA:*` to require either a list prefix or a colon suffix. This is still more lenient than the original pattern but eliminates table headers and summary text.

#### BUG-03 [LOW] scripts/night-dev.sh:940

**Claude failure path sets APPLIED/SKIPPED/REVERTED/ESCALATED but does not update status.json.**

When Claude invocation fails (exit != 0 or empty output), line 940 sets `APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0` and continues. However, the batched status.json update at lines 1033-1053 is skipped because `continue` jumps to the next iteration. The `CONSECUTIVE_ZERO` counter is incremented (line 939), but this value is only written to status.json in the next successful loop's batch update. If the script is killed between a failed loop and the next successful one, status.json will show stale data.

**Fix:** Move the status.json update block (or a minimal version of it) before the `continue` statement, or move the `continue` after the status update block.

---

### INTENT

*No new intent issues found. SKILL.md scoring formula was synchronized in loop 1.*

---

### ARCHITECTURE

#### ARCH-01 [LOW] scripts/night-dev.sh:747-753

**`update_status()` function is still defined but only used by cleanup() indirectly.**

After loop 1's batching optimization (TASK-04), the main loop uses a batched jq expression for all status updates. The `update_status()` helper function (lines 747-753) remains defined but is no longer called anywhere in the current code. The cleanup function at lines 768-775 uses its own inline batched jq call. This is dead code.

**Fix:** Remove `update_status()` (lines 744-753) to reduce code complexity. If it's kept as a utility for future use, add a comment indicating it's intentionally retained.

---

### PERFORMANCE

#### PERF-01 [LOW] scripts/night-dev.sh:512

**Follow mode fallback uses hardcoded upper bound of 20 for loop scan.**

The fallback loop `for ((i=20; i>=1; i--))` at line 512 scans for log files from loop-20 down to loop-1. If `--max-loops` is set higher than 20, logs from later loops would be missed. This is a minor issue since the primary path (jq-based lookup at lines 501-507) handles this correctly.

**Fix:** Use a dynamic approach: `ls -1d "$nd_dir"/loop-*/claude_output.log 2>/dev/null | sort -t- -k2 -n | tail -1` or iterate from a reasonable max like 100.

#### PERF-02 [LOW] scripts/night-dev.sh:523-534

**Follow mode wait loop and inline mode wait loop use fixed polling intervals.**

Follow mode polls every 2 seconds (line 533) waiting for the first log file, and inline mode polls every 5 seconds (line 914) waiting for the done marker. Neither uses backoff. For long-running operations, this produces unnecessary I/O.

**Fix:** Implement simple exponential backoff: start at 2s, double up to 30s max.

---

### COST

*No issues found.*

---

### QUALITY

#### QUALITY-01 [MEDIUM] scripts/night-dev.sh:930-931

**Verbose mode tee pipeline masks Claude exit code.**

In verbose mode, the command `(cd ... && "${claude_cmd[@]}" ...) | tee "$LOOP_DIR/claude_output.log" || claude_exit=$?` captures the exit code of `tee`, not `claude`. In a pipeline, `$?` returns the exit status of the last command (`tee`), which almost always succeeds. So `claude_exit` will be 0 even if Claude fails. The non-verbose path (lines 933-934) correctly captures Claude's exit code because there is no pipeline.

**Fix:** Use `set -o pipefail` (already set via `set -euo pipefail` at line 2) — this should propagate the failure. However, the `|| claude_exit=$?` construct suppresses the pipefail behavior because the overall command succeeds via the `||`. Instead, use `PIPESTATUS`: after the pipeline, check `claude_exit=${PIPESTATUS[0]}` to get the exit code of the first pipeline command (the Claude subshell).

#### QUALITY-02 [MEDIUM] scripts/night-dev.sh:581

**Follow mode completion summary uses complex jq string interpolation.**

Line 581 uses `printf '%s\n' "$(jq -r '...' "$status_file")"` which is correct (fixed from `echo -e` safety). However, the jq expression uses string interpolation inside a single-quoted bash string, making it hard to read and maintain. The double-quoting of the jq output through `$()` and then `printf` is also redundant — jq output can be printed directly.

**Fix:** Simplify to `jq -r '"Applied: ..." ' "$status_file"` without the `printf` wrapper, since `jq -r` already outputs raw strings to stdout.

#### QUALITY-03 [LOW] scripts/night-dev.sh:300-308

**Makefile test target detection reads entire file line-by-line.**

The `detect_test_runner` function reads the project Makefile line by line (lines 300-308) using a `while IFS= read -r line` loop to find `^test:` targets. This is inconsistent with the package.json optimization applied in loop 1 (TASK-07), which switched from line-by-line to single-read pattern matching. For consistency, the Makefile detection could also use a single-read approach.

**Fix:** Replace with: `local content; content=$(<"$project/Makefile"); if [[ "$content" =~ $'\n'test[[:space:]]*: ]]; then DETECTED_RUNNER="make test"; return 0; fi`. Note: the regex approach is slightly different because the match must be at the start of a line, which is harder with glob patterns.

#### QUALITY-04 [LOW] commands/night-dev.md

**Interactive setup guide is entirely in Italian without English alternative.**

Carried forward from loop 1 audit (QUALITY-06). The `commands/night-dev.md` file contains user-facing prompts in Italian only. This limits accessibility for non-Italian-speaking users.

**Fix:** Consider adding English translations or making the language configurable. Low priority as this may be intentional for the target audience.

---

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| SECURITY | 0 | 0 | 1 | 1 |
| BUG | 0 | 0 | 2 | 1 |
| INTENT | 0 | 0 | 0 | 0 |
| ARCHITECTURE | 0 | 0 | 0 | 1 |
| PERFORMANCE | 0 | 0 | 0 | 2 |
| COST | 0 | 0 | 0 | 0 |
| QUALITY | 0 | 0 | 2 | 2 |
| **Total** | **0** | **0** | **5** | **7** |

### Top 5 Actionable Items (by impact):

1. **SEC-01** (MEDIUM): Add missing commands to scoped Bash permissions allowlist -- sub-agents may silently fail on `npx`, `echo`, `find`, `mkdir` operations
2. **BUG-01** (MEDIUM): Fix score comparison for negative scores -- use raw x10 integers instead of re-parsing formatted strings
3. **BUG-02** (MEDIUM): Tighten changelog pattern matching -- `*APPLICATA*` is too broad, use `*- APPLICATA*` to require list prefix
4. **QUALITY-01** (MEDIUM): Fix verbose mode exit code capture -- use `PIPESTATUS[0]` instead of `$?` after tee pipeline
5. **ARCH-01** (LOW): Remove dead `update_status()` function -- no longer called after loop 1 batching optimization
