# Night Shift Audit — Loop 2

Focus: **PERFORMANCE** (80%) | Other (20%)

Previous loop applied: PERF-01, PERF-03, PERF-05, PERF-06, PERF-07, PERF-08
Previous loop skipped: PERF-02, PERF-04, SEC-01, QUALITY-01, QUALITY-02

---

## Metrics
- Tests: 27 passed, 0 failed, 2 skipped
- Coverage: not available
- Files: 5 source | LOC: ~1550 | TODO/FIXME/HACK: 0
- Security audit: no tool available (bash project)
- Execution time: N/A (no regression from loop 1)

## Issues Found

Total: 14 issues (1 security, 1 bug, 9 performance, 0 cost, 3 quality)

### SECURITY

1. **SEC-02 [MEDIUM]** `scripts/night-dev.sh:583` — Unsanitized jq output interpolated into echo. The line `echo -e "$(jq -r '...' "$status_file")"` in `follow_night_dev()` passes raw jq output through `echo -e`, which interprets escape sequences. If `status.json` contains crafted values (e.g., `\x1b[...` ANSI escape sequences in a field), they will be interpreted by the terminal. **Fix:** Use `printf '%s\n'` instead of `echo -e` for data output, or pipe jq output directly to stdout without echo interpolation.

### BUG

1. **BUG-02 [MEDIUM]** `scripts/night-dev.sh:606` — `DATE_TAG` uses `date +%Y-%m-%d` which forks a subprocess, but more importantly it is computed independently of `START_TIME`. If the script starts at 23:59:59 and `date` is called a fraction of a second later, `DATE_TAG` could be tomorrow while `START_TIME` is today. This causes the branch name (`night-dev/2025-03-21`) and backup dir to reference a different date than `DEADLINE` calculations. **Fix:** Derive `DATE_TAG` from `START_TIME` using `printf '%(%Y-%m-%d)T' "$START_TIME"` (bash 4.2+ builtin, no fork) to ensure consistency and eliminate a subprocess.

### PERFORMANCE

1. **PERF-11 [HIGH]** `scripts/night-dev.sh:606` — `date +%Y-%m-%d` forks a subprocess for `DATE_TAG`. Bash 4.2+ has `printf '%(%Y-%m-%d)T'` as a builtin that avoids the fork entirely. This is on the startup hot path. **Fix:** Replace `DATE_TAG=$(date +%Y-%m-%d)` with `printf -v DATE_TAG '%(%Y-%m-%d)T' -1` (or use `$START_TIME` after it is set, which also fixes BUG-02).

2. **PERF-12 [HIGH]** `scripts/night-dev.sh:647-648` — Three `date` subprocess forks for `STARTED_AT` and `DEADLINE_ISO`. Line 647 has up to 2 forks (try GNU date, fallback to manual format). Line 648 has up to 3 forks (try GNU `-d`, then BSD `-r`, then fallback). Total: 2-5 `date` forks at initialization. **Fix:** Use `printf '%(%Y-%m-%dT%H:%M:%S%z)T'` for `STARTED_AT` (bash builtin, zero forks). For `DEADLINE_ISO`, use `printf '%(%Y-%m-%dT%H:%M:%S%z)T' "$DEADLINE"`. This eliminates all `date` forks in initialization.

3. **PERF-13 [MEDIUM]** `scripts/night-dev.sh:961,966` — `parse_test_results` and `calculate_score` are called via command substitution (`$(...)`) which creates subshell forks. Both functions only produce a single line of output consumed by `read`. **Fix:** Use `printf -v` inside the functions to set variables directly, or pipe output to `read` without capturing in a subshell. For `calculate_score`, the function is trivial bash arithmetic — inline it at the call site to avoid both the function call overhead and the subshell: `local score_x10=$(( (cur_passing*100) + (cur_total*20) + (cur_coverage*50) - (cur_failing*200) - cur_time_s )); current_score="$((score_x10/10)).$((score_x10%10<0 ? -(score_x10%10) : score_x10%10))"`.

4. **PERF-14 [MEDIUM]** `scripts/night-dev.sh:367-401` — `parse_test_results` spawns awk via `$(awk ...)` command substitution. The awk invocation reads the entire test output file. For large Claude output logs (can be 10K+ lines), this is a significant read. The function could first check file size and skip parsing if empty. More importantly, the awk script could be stored in a variable at script startup instead of being re-parsed by bash on each invocation. **Fix:** Store the awk script in a variable (`PARSE_AWK_SCRIPT='...'`) at the top of the script and reference it: `awk "$PARSE_AWK_SCRIPT" "$test_output_file"`. This avoids bash re-parsing the heredoc/string on each call.

5. **PERF-15 [MEDIUM]** `scripts/night-dev.sh:228-231` — `readlink -f` and fallback `cd ... && pwd` both fork subprocesses to resolve the project path. The `readlink -f` test on line 227 forks a subprocess just to check if readlink works, then line 228 forks again to actually use it. **Fix:** Combine into a single attempt: `PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null) || PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)`. This eliminates one redundant fork.

6. **PERF-16 [MEDIUM]** `scripts/night-dev.sh:744-783` — `update_status()`, `update_status_nested()`, `update_score()`, and `append_score_history()` are defined but only partially used. The main loop correctly batches updates (line 1031-1051), but `update_status` is still called individually on line 811 (cleanup trap) and line 851 (circuit breaker). Each call forks jq, reads/writes the file. **Fix:** The cleanup call (line 811) is unavoidable (runs at exit). But the circuit breaker update (line 851) could be deferred to the batched update block. Add circuit breaker state to the batch jq expression.

7. **PERF-17 [LOW]** `scripts/night-dev.sh:992-998` — Changelog parsing with awk forks a subprocess on every loop iteration. The awk script is simple pattern matching that could be done in pure bash using `while read` + case/pattern matching. For small changelog files (typically <50 lines), the overhead difference is marginal, but it eliminates one fork per loop. **Fix:** Replace with a bash `while IFS= read -r line` loop that counts `APPLICATA`, `SKIPPATA`, `REVERTITA`, `ESCALATED` patterns using `[[ "$line" == *APPLICATA* ]]` checks.

8. **PERF-18 [LOW]** `scripts/night-dev.sh:281` — `detect_test_runner` forks awk to parse `package.json` for the test script. This could use a bash `while read` loop with pattern matching instead, since it only needs to detect two patterns (`"test"` key and `no test specified`). **Fix:** Replace awk with: `local has_test=0 has_placeholder=0; while IFS= read -r line; do [[ "$line" == *'"test"'* ]] && has_test=1; [[ "$line" == *'no test specified'* ]] && has_placeholder=1; done < "$project/package.json"`.

9. **PERF-19 [LOW]** `scripts/night-dev.sh:820` — SKILL.md content is cached via `$(<file)` which is efficient. However, this ~385-line file is then string-interpolated into `LOOP_PROMPT` on every loop iteration (line 917). The entire prompt string (SKILL.md + context) is rebuilt every iteration even though SKILL.md content never changes. **Fix:** Build the static portion of the prompt once before the loop, and only interpolate the dynamic context variables (loop number, score, changelog) on each iteration. Use `printf` with format string to avoid reconstructing the full string.

### BUG

*No additional bugs found beyond BUG-02 above.*

### COST

*No issues found.*

### QUALITY

1. **QUALITY-03 [MEDIUM]** `scripts/night-dev.sh:744-783` — Four helper functions (`update_status`, `update_status_nested`, `update_score`, `append_score_history`) are defined inside `main()` but only `update_status` is called outside the batched block (lines 811, 851). The other three (`update_status_nested`, `update_score`, `append_score_history`) are never called anywhere — they are dead code after the PERF-01 batching optimization in loop 1. **Fix:** Remove `update_status_nested()`, `update_score()`, and `append_score_history()` since their logic is now handled by the inline batched jq expression at lines 1031-1051.

2. **QUALITY-04 [MEDIUM]** `Makefile:9-11` — `REQUIRED_REFS` lists `risk-gate-prompt.md` and `codeintel-reference.md` but both are missing and always SKIP. The test suite never fails on these missing files, making the "required" designation misleading. Either create stub files or remove them from `REQUIRED_REFS` to accurately represent what's actually required. **Fix:** Remove `risk-gate-prompt.md` and `codeintel-reference.md` from `REQUIRED_REFS`, or create minimal placeholder files.

3. **QUALITY-05 [LOW]** `scripts/night-dev.sh:514-520` — Follow mode fallback loop iterates from 20 down to 1 checking for log files. The upper bound of 20 is a magic number with no connection to `MAX_LOOPS` (default 5). If someone runs with `--max-loops 50`, this fallback would miss loops 21-50. **Fix:** Either use `MAX_LOOPS` as the upper bound or use `ls -1d "$nd_dir"/loop-*/claude_output.log 2>/dev/null | sort -t- -k2 -n | tail -1` to find the latest log dynamically.

### INTENT

*No new intent issues found beyond those documented in loop 1 project_intent.md.*

---

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Security | 0 | 0 | 1 | 0 |
| Bugs | 0 | 0 | 1 | 0 |
| Performance | 0 | 2 | 4 | 3 |
| Cost | 0 | 0 | 0 | 0 |
| Quality | 0 | 0 | 2 | 1 |
| **Total** | **0** | **2** | **8** | **4** |

### Top 5 Actionable Items (by impact):

1. **PERF-11 + BUG-02** (HIGH): Replace `date +%Y-%m-%d` with `printf -v DATE_TAG '%(%Y-%m-%d)T'` — eliminates 1 fork and fixes date consistency bug
2. **PERF-12** (HIGH): Replace 2-5 `date` forks in STARTED_AT/DEADLINE_ISO with `printf '%(...) T'` builtins — eliminates all date forks at initialization
3. **PERF-13** (MEDIUM): Inline `calculate_score` at call site — eliminates 2 subshell forks per loop iteration
4. **QUALITY-03** (MEDIUM): Remove 3 dead helper functions left over from PERF-01 batching — reduces code by ~30 lines
5. **PERF-15** (MEDIUM): Combine redundant readlink test+use into single attempt — eliminates 1 fork at startup
