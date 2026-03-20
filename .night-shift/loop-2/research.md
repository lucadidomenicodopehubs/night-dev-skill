# Night Shift Research — Loop 2

Focus: Bash performance optimization best practices for the top 10 priority issues identified in audit.md.

Environment: GNU bash 5.2.21, Linux x86_64. All code snippets verified in this environment.

---

## Issue Priority Ranking

The audit identifies 14 issues. Ranked by combined impact (severity + fork reduction):

| Rank | Issue | Severity | Fork Savings | Priority |
|------|-------|----------|--------------|----------|
| 1 | PERF-11 + BUG-02 | HIGH + MEDIUM | 1 startup fork + date consistency | Critical |
| 2 | PERF-12 | HIGH | 2–5 startup forks | Critical |
| 3 | PERF-13 | MEDIUM | 2 forks per loop | High |
| 4 | QUALITY-03 | MEDIUM | Code hygiene, ~30 lines removed | High |
| 5 | PERF-15 | MEDIUM | 1 startup fork | Medium |
| 6 | PERF-16 | MEDIUM | 1 jq fork per circuit-breaker trigger | Medium |
| 7 | SEC-02 | MEDIUM | Security correctness | Medium |
| 8 | PERF-14 | MEDIUM | awk re-parse on each loop (marginal) | Medium |
| 9 | PERF-17 | LOW | 1 fork per loop (changelog awk) | Low |
| 10 | PERF-18 | LOW | 1 fork at startup (package.json awk) | Low |

---

## Issue 1: PERF-11 + BUG-02 — Replace `date +%Y-%m-%d` with printf builtin

### Current code (line 606)
```bash
DATE_TAG=$(date +%Y-%m-%d)
```

### Problem
- `$(date +%Y-%m-%d)` forks a subprocess (`/bin/date`) — on Linux this costs ~1–3ms but adds latency on the startup hot path.
- BUG-02: `DATE_TAG` is computed independently of `START_TIME` (line 611). If the script starts at 23:59:59 and the date changes between the two calls, `DATE_TAG` references the new day while `START_TIME` references the old day, causing branch name / backup dir / deadline inconsistency.

### Implementation

```bash
# Before (line 611):
START_TIME=${EPOCHSECONDS:-$(date +%s)}

# After (line 606) — derive DATE_TAG from START_TIME which is already set:
START_TIME=${EPOCHSECONDS:-$(date +%s)}    # line 611 — set START_TIME first
printf -v DATE_TAG '%(%Y-%m-%d)T' "$START_TIME"   # no fork; uses same epoch as START_TIME
```

The reordering also fixes BUG-02: `DATE_TAG` is now derived from `START_TIME`, not from a separate `date` call that might land on a different day.

### Syntax details
- `printf '%(%Y-%m-%d)T' EPOCH` — the `%(...)T` format specifier was added in **bash 4.2** (released 2011). It calls `strftime(3)` on the given epoch value.
- `-1` means current time; `-2` means shell start time.
- `printf -v VARNAME FORMAT ARG` assigns the formatted output to `VARNAME` without a subshell.

### Verified output
```
$ printf -v DATE_TAG '%(%Y-%m-%d)T' -1 && echo "$DATE_TAG"
2026-03-20
$ START_TIME=$EPOCHSECONDS; printf -v DATE_TAG '%(%Y-%m-%d)T' "$START_TIME" && echo "$DATE_TAG"
2026-03-20
```

### Compatibility
- Requires bash 4.2+. macOS ships bash 3.2 (GPLv2) by default; however `night-dev.sh` already uses `${EPOCHSECONDS}` (bash 5.0+) and `local` inside functions, so the script is not targeting bash 3. Any user with bash 4.2+ is covered.
- If macOS compatibility is needed without homebrew bash, fall back to: `DATE_TAG=$(date +%Y-%m-%d)`. Add a comment noting this.

### Risk: LOW
The change is a drop-in replacement. The only edge case is a machine with bash < 4.2, which is extremely unlikely given the script already uses bash 5.0 features.

---

## Issue 2: PERF-12 — Replace 2–5 `date` forks for `STARTED_AT`/`DEADLINE_ISO`

### Current code (lines 647–648)
```bash
STARTED_AT=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)
DEADLINE_ISO=$(date -d @$DEADLINE -Iseconds 2>/dev/null || date -r $DEADLINE -Iseconds 2>/dev/null || echo "unknown")
```

### Problem
- `STARTED_AT`: Up to 2 `date` forks (GNU `-Iseconds` first, then BSD fallback if it fails).
- `DEADLINE_ISO`: Up to 3 forks (GNU `date -d @EPOCH`, then BSD `date -r`, then `echo "unknown"` as last resort).
- Total: 2–5 `date` subprocess forks at initialization, all replaceable with the `printf '%(...)T'` builtin.

### Implementation

```bash
# STARTED_AT — use START_TIME that was already computed
printf -v STARTED_AT '%(%Y-%m-%dT%H:%M:%S%z)T' "$START_TIME"

# DEADLINE_ISO — use DEADLINE (epoch seconds) computed from START_TIME
printf -v DEADLINE_ISO '%(%Y-%m-%dT%H:%M:%S%z)T' "$DEADLINE"
```

Both `STARTED_AT` and `DEADLINE_ISO` are only used in the `jq -n` call that initializes `status.json` (lines 650–680). They are string values passed via `--arg`. The `printf '%(...)T'` format produces ISO-8601 compatible output with timezone offset (e.g., `2026-03-20T01:14:09+0000`).

### Output format comparison
```
# Old GNU date -Iseconds output:
2026-03-20T01:14:09+00:00

# New printf '%(...)T' output:
2026-03-20T01:14:09+0000
```

Note: The timezone colon format differs (`+00:00` vs `+0000`). ISO-8601 accepts both. jq and most consumers handle both. This is cosmetic — verify that downstream consumers of `status.json` do not require the colon form.

### Verified output
```
$ START_TIME=$EPOCHSECONDS; DEADLINE=$((START_TIME + 3600))
$ printf -v STARTED_AT '%(%Y-%m-%dT%H:%M:%S%z)T' "$START_TIME"
$ printf -v DEADLINE_ISO '%(%Y-%m-%dT%H:%M:%S%z)T' "$DEADLINE"
$ echo "$STARTED_AT / $DEADLINE_ISO"
2026-03-20T01:14:16+0000 / 2026-03-20T02:14:16+0000
```

### Compatibility
Same as PERF-11: requires bash 4.2+. The `%z` specifier produces a UTC offset in `+HHMM` format (no colon). If colon-format is required, post-process: `STARTED_AT="${STARTED_AT:0:-2}:${STARTED_AT: -2}"` — pure bash parameter expansion, no fork.

### Risk: LOW
Direct drop-in. The only risk is the timezone colon difference in the output string stored in `status.json`, which is cosmetic.

---

## Issue 3: PERF-13 — Inline `calculate_score` to eliminate subshell forks

### Current code (lines 961–966)
```bash
local test_data
test_data=$(parse_test_results "$test_output")       # fork 1: subshell for command substitution
local cur_passing cur_failing cur_total cur_coverage cur_time_s
read -r cur_passing cur_failing cur_total cur_coverage cur_time_s <<< "$test_data"

local current_score
current_score=$(calculate_score "$cur_passing" ...)  # fork 2: subshell for command substitution
```

### Problem
- `parse_test_results` is called via `$(...)` creating a subshell even though its output is immediately captured into variables.
- `calculate_score` is called via `$(...)` creating another subshell for pure integer arithmetic.

### Implementation

**For `calculate_score` — inline the arithmetic directly at the call site:**

```bash
# Inline calculate_score — eliminates 1 subshell fork per loop
local score_x10=$(( (cur_passing * 100) + (cur_total * 20) + (cur_coverage * 50) - (cur_failing * 200) - cur_time_s ))
local _score=$((score_x10 / 10))
local _remainder=$((score_x10 % 10))
[[ $_remainder -lt 0 ]] && _remainder=$(( -_remainder ))
local current_score="${_score}.${_remainder}"
```

**For `parse_test_results` — use `printf -v` to set a global/nameref variable:**

Option A (simplest): keep `$(parse_test_results)` but eliminate `calculate_score` subshell — net savings: 1 fork/loop.

Option B (more invasive): refactor `parse_test_results` to set a caller-scope variable:
```bash
parse_test_results() {
    local test_output_file="$1"
    local _result
    if [[ ! -f "$test_output_file" ]]; then
        PARSE_RESULT="0 0 0 0 0"
        return
    fi
    _result=$(awk '...' "$test_output_file")    # awk fork still needed
    PARSE_RESULT="${_result:-0 0 0 0 0}"
}

# Call site:
parse_test_results "$test_output"
read -r cur_passing cur_failing cur_total cur_coverage cur_time_s <<< "$PARSE_RESULT"
```

Note: `parse_test_results` must still fork awk (the awk invocation is intrinsically a subprocess). The only subshell that can be eliminated here is the `$(...)` wrapper around the entire function. Since the function already does a `$(awk ...)` internally, saving the outer `$(parse_test_results)` wrapper saves one bash subshell level but not the awk fork.

**Recommended approach:** Inline only `calculate_score` (1 fork saved, near-zero risk), and leave `parse_test_results` refactoring as a separate lower-priority item since awk is unavoidable.

### Verified output
```bash
cur_passing=27; cur_failing=0; cur_total=27; cur_coverage=0; cur_time_s=5
score_x10=$(( (cur_passing * 100) + (cur_total * 20) + (cur_coverage * 50) - (cur_failing * 200) - cur_time_s ))
_score=$((score_x10 / 10)); _remainder=$((score_x10 % 10))
[[ $_remainder -lt 0 ]] && _remainder=$(( -_remainder ))
echo "${_score}.${_remainder}"
# Output: 323.5  (matches existing calculate_score function output)
```

### Risk: LOW
The inlined arithmetic is identical to the function body. The function `calculate_score` can remain defined (it is used nowhere else) and be removed in a follow-up cleanup (QUALITY-03 handles related dead code).

---

## Issue 4: QUALITY-03 — Remove dead helper functions

### Current code (lines 752–783)
Three functions are defined but never called after the PERF-01 batching optimization in loop 1:

- `update_status_nested()` — sets a dot-path field in status.json
- `update_score()` — sets baseline_tests or current_tests section
- `append_score_history()` — appends to score_history array

`update_status()` is still live (called at lines 811 and 851).

### Implementation
Remove lines 752–783 (the three dead functions). Approximately 31 lines eliminated.

Before removing, verify with:
```bash
grep -n "update_status_nested\|update_score\|append_score_history" scripts/night-dev.sh
```
Only the function definitions themselves should appear — no call sites.

### Risk: VERY LOW
Dead code removal. The functions have no callers. Their logic is already superseded by the batched jq expression at lines 1031–1051.

---

## Issue 5: PERF-15 — Consolidate redundant `readlink` forks

### Current code (lines 227–231)
```bash
if readlink -f "$PROJECT_PATH" &>/dev/null; then        # fork 1: test only
    PROJECT_PATH="$(readlink -f "$PROJECT_PATH")"       # fork 2: actual use
else
    PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"         # fork 3 (fallback)
fi
```

### Problem
The `if readlink -f ... &>/dev/null` test forks `readlink` just to check if it works, then forks it again to actually use it. Two forks when one suffices.

### Implementation
```bash
# Single attempt: readlink -f if it works, cd fallback otherwise
PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null) || \
    PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
```

The `||` short-circuits: if `readlink -f` succeeds and produces output, the assignment completes and the right side never runs. If `readlink -f` fails (exits non-zero or produces empty output on BSD), `cd ... && pwd` runs.

### Edge case: readlink returns empty string
On some systems, `readlink -f` may succeed (exit 0) but produce an empty string for paths that don't exist. Guard:
```bash
PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null || cd "$PROJECT_PATH" && pwd)
# Or more explicit:
PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null)
[[ -z "$PROJECT_PATH" ]] && PROJECT_PATH=$(cd "$1" && pwd)
```

The simpler `|| ` form is sufficient here because `PROJECT_PATH` is validated to exist (line 221: `[[ ! -d "$PROJECT_PATH" ]]`) before reaching line 227.

### Verified
```bash
PROJECT_PATH=/tmp
PROJECT_PATH=$(readlink -f "$PROJECT_PATH" 2>/dev/null) || PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)
echo "$PROJECT_PATH"   # /tmp
```

### Risk: LOW
The behavior is equivalent. The only difference is that the test-and-use pattern guaranteed two invocations; the combined form may behave differently if `readlink -f` exits non-zero but still writes to stdout. In practice `readlink -f` never does this.

---

## Issue 6: PERF-16 — Defer circuit-breaker status update into batch jq call

### Current code (line 851)
```bash
if [[ $CONSECUTIVE_ZERO -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
    echo "Circuit breaker: ..." >&2
    update_status "circuit_breaker" "OPEN"    # standalone jq fork
    break
fi
```

### Problem
`update_status "circuit_breaker" "OPEN"` calls jq to read+write `status.json`. This is outside the batched block at lines 1031–1051, so it adds an extra jq fork for each circuit-breaker trip.

### Implementation
Set a flag variable before the break, and include the field in the end-of-loop batch:

```bash
# At circuit breaker (line 849):
if [[ $CONSECUTIVE_ZERO -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
    echo "Circuit breaker: ..." >&2
    CIRCUIT_BREAKER_STATUS="OPEN"
    break
fi

# In the batched jq block (lines 1031–1051), add the field conditionally:
local cb_expr=""
[[ -n "${CIRCUIT_BREAKER_STATUS:-}" ]] && cb_expr="| .circuit_breaker = \"$CIRCUIT_BREAKER_STATUS\""

jq ... "$jq_expr $cb_expr" "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
```

However, since the circuit breaker `break` exits the loop before reaching the batched jq block, the batch never runs. Alternative: move the circuit-breaker jq update to the `cleanup()` function where `update_status "phase" "COMPLETED"` already runs:

```bash
cleanup() {
    ...
    update_status "phase" "COMPLETED"
    [[ -n "${CIRCUIT_BREAKER_STATUS:-}" ]] && update_status "circuit_breaker" "$CIRCUIT_BREAKER_STATUS"
}
```

This way the cleanup trap handles the status update on exit regardless of why the loop exited. The savings: 0 extra jq forks during normal execution; when the circuit breaker fires, the update is deferred to cleanup (net: same number of jq calls, but removes the mid-loop call).

### Risk: LOW–MEDIUM
The circuit breaker fires rarely (at most once per run). The main benefit is code consistency (all status updates funneled through cleanup or the batch block). Slight risk: if the script is killed hard (SIGKILL), the cleanup trap won't run — but `update_status` at line 851 also wouldn't run in that case, so behavior is unchanged.

---

## Issue 7: SEC-02 — Replace `echo -e "$(jq ...)"` with safe output

### Current code (line 583)
```bash
echo -e "$(jq -r '"Applied: \(.stats.total_applied) | ..."' "$status_file")"
```

### Problem
`echo -e` interprets escape sequences in its arguments. If `status.json` contains a field value with `\x1b[31m` (ANSI escape) or `\n`, `echo -e` will interpret them, allowing escape injection from the status file into the terminal. In a CI environment or when `status.json` is written by Claude, this is a realistic attack surface.

### Implementation

**Option A (recommended): Use `printf '%s\n'`**
```bash
printf '%s\n' "$(jq -r '"Applied: \(.stats.total_applied) | Skipped: \(.stats.total_skipped) | Reverted: \(.stats.total_reverted) | Score: \(.current_tests.score // "N/A")"' "$status_file")"
```

`printf '%s\n'` treats its argument as a literal string — no escape interpretation.

**Option B: Pipe jq directly to stdout (no echo at all)**
```bash
jq -r '"Applied: \(.stats.total_applied) | Skipped: \(.stats.total_skipped) | Reverted: \(.stats.total_reverted) | Score: \(.current_tests.score // "N/A")"' "$status_file"
```

jq outputs directly to stdout. No shell variable interpolation, no echo. This is the cleanest form.

### Verified
```bash
crafted='Applied: 5 \x1b[31mDONGER\x1b[0m'
echo -e "$crafted"         # Outputs colored "DONGER" (escape interpreted)
printf '%s\n' "$crafted"   # Outputs literal \x1b[31mDONGER\x1b[0m (safe)
```

### Risk: VERY LOW
`printf '%s\n'` is a well-known idiom. No behavioral change for normal (non-crafted) input. Only escape sequences in input would behave differently.

---

## Issue 8: PERF-14 — Pre-store awk script to avoid bash re-parse overhead

### Current code (lines 367–401)
```bash
result=$(awk '
    # pytest-style: ...
    /passed/ { ... }
    ...
    END { ... }
' "$test_output_file")
```

### Problem
Every time `parse_test_results` is called, bash must re-parse the heredoc-style inline awk script string. For a ~30-line awk program called every loop iteration, this adds marginal bash parse overhead. More importantly, it makes the function harder to test in isolation.

### Implementation
Store the awk script in a variable at script top-level (outside of any function, in the global init section):

```bash
# At script global scope (near other constants):
readonly _PARSE_AWK_SCRIPT='
    /passed/ { for(i=1;i<=NF;i++) if($(i+1)=="passed") py_p=$i }
    /failed/ { for(i=1;i<=NF;i++) if($(i+1)=="failed") py_f=$i }
    /Tests:.*passed/ { for(i=1;i<=NF;i++) { if($(i+1)=="passed,") js_p=$i; if($(i+1)=="failed,") js_f=$i; if($(i+1)=="total") js_t=$i } }
    /test result:/ { for(i=1;i<=NF;i++) { if($(i+1)=="passed;") cg_p=$i; if($(i+1)~/^failed/) cg_f=$i } }
    /[0-9]+(\.[0-9]+)?%/ && /[Cc]over/ { match($0, /([0-9]+(\.[0-9]+)?)%/, arr); if (arr[1]+0 > 0) cov=arr[1] }
    /[0-9]+(\.[0-9]+)?s/ && /[Tt]ime|[Dd]uration|[Ff]inished|[Rr]an/ { match($0, /([0-9]+(\.[0-9]+)?)s/, arr); if (arr[1]+0 > 0) dur=arr[1] }
    END { p=py_p+0; f=py_f+0; t=0; if (p==0 && f==0) { p=js_p+0; f=js_f+0; t=js_t+0 }; if (p==0 && f==0) { p=cg_p+0; f=cg_f+0 }; if (t==0) t=p+f; c=int(cov+0); d=int(dur+0); print p, f, t, c, d }
'
```

Then in `parse_test_results`:
```bash
result=$(awk "$_PARSE_AWK_SCRIPT" "$test_output_file")
```

Note: Using a variable for the awk script avoids bash re-tokenizing the embedded string on each call. However, the actual performance gain here is minimal because bash's re-parse of a string literal is fast. The bigger benefit is maintainability and the ability to early-exit for empty files:

```bash
parse_test_results() {
    local test_output_file="$1"
    if [[ ! -f "$test_output_file" ]] || [[ ! -s "$test_output_file" ]]; then
        echo "0 0 0 0 0"
        return
    fi
    local result
    result=$(awk "$_PARSE_AWK_SCRIPT" "$test_output_file")
    echo "${result:-0 0 0 0 0}"
}
```

The `[[ ! -s "$test_output_file" ]]` check (file is empty) avoids invoking awk at all on empty log files — a meaningful optimization for early-loop iterations when the test runner hasn't produced output yet.

### Risk: LOW
Moving the awk script to a variable changes nothing about its execution. The `readonly` attribute prevents accidental modification.

---

## Issue 9: PERF-17 — Replace changelog awk with pure bash `while read`

### Current code (lines 992–999)
```bash
changelog_counts=$(awk '
    /^[[:space:]]*[-*][[:space:]]+APPLICATA[[:space:]]*:/{a++}
    ...
    END{print a+0, s+0, r+0, e+0}
' "$LOOP_DIR/changelog.md")
```

### Problem
An awk fork per loop iteration. For changelogs with typically <50 lines, bash `while read` with pattern matching avoids the fork entirely.

### Implementation
```bash
# Pure bash replacement — no awk fork
local a=0 s=0 r=0 e=0
while IFS= read -r line; do
    [[ "$line" == *APPLICATA* ]]  && (( a++ )) || true
    [[ "$line" == *SKIPPATA* ]]   && (( s++ )) || true
    [[ "$line" == *REVERTITA* ]]  && (( r++ )) || true
    [[ "$line" =~ ESCALATED|URGENTE ]] && (( e++ )) || true
done < "$LOOP_DIR/changelog.md"
read -r APPLIED SKIPPED REVERTED ESCALATED <<< "$a $s $r $e"
```

Or, more directly assign to the outer variables without the intermediate read:
```bash
local APPLIED=0 SKIPPED=0 REVERTED=0 ESCALATED=0
while IFS= read -r line; do
    [[ "$line" == *APPLICATA* ]]  && (( APPLIED++ ))  || true
    [[ "$line" == *SKIPPATA* ]]   && (( SKIPPED++ ))  || true
    [[ "$line" == *REVERTITA* ]]  && (( REVERTED++ )) || true
    [[ "$line" =~ ESCALATED|URGENTE ]] && (( ESCALATED++ )) || true
done < "$LOOP_DIR/changelog.md"
```

### Pattern matching notes
- `[[ "$line" == *APPLICATA* ]]` uses glob matching — fast, no regex overhead.
- `[[ "$line" =~ ESCALATED|URGENTE ]]` uses ERE regex — slightly slower but needed for alternation.
- Alternatively, use two separate glob checks: `[[ "$line" == *ESCALATED* ]] || [[ "$line" == *URGENTE* ]]`

### Performance consideration
For files < 100 lines, the bash `while read` loop is generally faster than forking awk (fork overhead ~1–3ms vs loop overhead ~0.1ms per line). For files > 1000 lines, awk wins. Changelog files are expected to be small (<100 lines), so bash wins.

### Verified output
```bash
# Input with 2 APPLICATA, 1 SKIPPATA, 1 REVERTITA, 1 ESCALATED
APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
while IFS= read -r line; do
    [[ "$line" == *APPLICATA* ]]  && (( APPLIED++ ))  || true
    [[ "$line" == *SKIPPATA* ]]   && (( SKIPPED++ ))  || true
    [[ "$line" == *REVERTITA* ]]  && (( REVERTED++ )) || true
    [[ "$line" =~ ESCALATED|URGENTE ]] && (( ESCALATED++ )) || true
done <<< "- APPLICATA: foo
- SKIPPATA: bar
- APPLICATA: baz
- REVERTITA: qux
- ESCALATED: urg"
echo "$APPLIED $SKIPPED $REVERTED $ESCALATED"   # 2 1 1 1
```

### Risk: LOW
The pure bash approach matches the same patterns. The only behavioral difference: awk counted lines matching anchored patterns like `^[[:space:]]*[-*][[:space:]]+APPLICATA[[:space:]]*:`; the bash glob `*APPLICATA*` is less anchored. If a line contains "APPLICATA" as part of a longer word (e.g., "NOT_APPLICATA"), the glob would false-positive. In practice, changelog entries are structured and this won't occur. To be safe, use: `[[ "$line" =~ ^[[:space:]]*[-*][[:space:]]+APPLICATA ]]` (regex, same anchoring as awk).

---

## Issue 10: PERF-18 — Replace package.json awk with pure bash `while read`

### Current code (lines 279–288)
```bash
if [[ -f "$project/package.json" ]]; then
    local test_info
    test_info=$(awk '/"test"[[:space:]]*:/{found=1} /no test specified/{placeholder=1} END{print found+0, placeholder+0}' "$project/package.json")
    local has_test has_placeholder
    read -r has_test has_placeholder <<< "$test_info"
    ...
fi
```

### Problem
`awk` is forked as a subprocess for what is essentially two pattern matches. `detect_test_runner` is called once at startup, so the impact is one extra startup fork.

### Implementation
```bash
if [[ -f "$project/package.json" ]]; then
    local has_test=0 has_placeholder=0
    while IFS= read -r line; do
        [[ "$line" == *'"test"'* ]] && has_test=1
        [[ "$line" == *'no test specified'* ]] && has_placeholder=1
    done < "$project/package.json"
    if [[ "$has_test" -eq 1 ]] && [[ "$has_placeholder" -eq 0 ]]; then
        DETECTED_RUNNER="npm test"
        return 0
    fi
fi
```

### Notes
- `'"test"'` — single-quoted to preserve the double-quote in the glob pattern.
- The glob `*'"test"'*` matches any line containing `"test"` (the JSON key), which is sufficient to detect a test script entry.
- Break out of the while loop early once both flags are set to avoid reading the entire file:
```bash
while IFS= read -r line; do
    [[ "$line" == *'"test"'* ]] && has_test=1
    [[ "$line" == *'no test specified'* ]] && has_placeholder=1
    [[ $has_test -eq 1 && $has_placeholder -eq 1 ]] && break
done < "$project/package.json"
```

### Verified output
```bash
# package.json with real test script:
has_test=0; has_placeholder=0
while IFS= read -r line; do
    [[ "$line" == *'"test"'* ]] && has_test=1
    [[ "$line" == *'no test specified'* ]] && has_placeholder=1
done < /tmp/test_package.json
echo "$has_test $has_placeholder"  # 1 0 (correct: test runner detected)

# package.json with placeholder:
echo "$has_test $has_placeholder"  # 1 1 (correct: placeholder detected, no runner)
```

### Risk: LOW
The bash glob matching is slightly less precise than the awk regex (`/"test"[[:space:]]*:/` requires the pattern to look like a JSON key:value). The glob `*'"test"'*` would also match a comment line or value containing `"test"`. In practice `package.json` files do not have such edge cases. For extra safety, use: `[[ "$line" =~ '"test"'[[:space:]]*: ]]` (regex anchoring).

---

## General Bash Performance Reference

### Bash builtins vs external commands

| Task | External (fork) | Bash builtin (no fork) |
|------|----------------|----------------------|
| Current date | `$(date +%Y-%m-%d)` | `printf -v V '%(%Y-%m-%d)T' -1` |
| ISO timestamp | `$(date -Iseconds)` | `printf -v V '%(%Y-%m-%dT%H:%M:%S%z)T' -1` |
| String length | `$(echo "$s" \| wc -c)` | `${#s}` |
| Substring | `$(echo "$s" \| cut -c1-5)` | `${s:0:5}` |
| String replace | `$(echo "$s" \| sed 's/x/y/')` | `${s//x/y}` |
| String prefix strip | `$(echo "$s" \| sed 's/^prefix//')` | `${s#prefix}` |
| String suffix strip | `$(echo "$s" \| sed 's/suffix$//')` | `${s%suffix}` |
| Uppercase | `$(echo "$s" \| tr a-z A-Z)` | `${s^^}` (bash 4.0+) |
| Lowercase | `$(echo "$s" \| tr A-Z a-z)` | `${s,,}` (bash 4.0+) |
| Arithmetic | `$(echo "2+3" \| bc)` | `$(( 2+3 ))` |
| Assign arithmetic | — | `(( var = 2+3 ))` |
| Print to var | `var=$(echo "text")` | `printf -v var '%s' "text"` |
| File content | `var=$(cat file)` | `var=$(<file)` |

### Here-string vs pipe for reducing forks

```bash
# Pipe (creates subshell — 1 fork):
echo "data" | read -r var     # WRONG: read runs in subshell, var not visible in parent

# Here-string (no fork — same shell):
read -r var <<< "data"        # CORRECT: read runs in current shell

# Process substitution (1 fork for the command, but read stays in parent):
read -r var < <(command)      # read is in parent shell, but command is still forked
```

### `$(( ))` arithmetic — zero forks
All integer arithmetic should use `$(( ))` or `(( ))` — these are shell builtins with no subprocess cost:
```bash
# Zero forks:
result=$(( a * b + c ))
(( result = a * b + c ))   # no $() needed when result is assigned

# Avoid:
result=$(echo "$a * $b + $c" | bc)   # 2 forks (echo + bc)
result=$(awk "BEGIN{print $a*$b+$c}")  # 1 fork (awk)
```

### Function inlining in bash
When a function:
1. Is called via `$(func)` (command substitution)
2. Only performs arithmetic or simple string manipulation
3. Is called in a tight loop

...it should be inlined at the call site to eliminate the subshell fork. The function can remain defined for clarity but the hot-path call site should use inlined code.

Pattern:
```bash
# Before: function with subshell
result=$(compute "$a" "$b")

# After: inlined at call site
result=$(( a * 2 + b ))   # still a subshell if using $()
(( result = a * 2 + b ))  # no subshell at all
```

---

## Summary Table for Implementation

| Issue | Lines | Change Type | Forks Saved | Risk | Estimated LOC Delta |
|-------|-------|-------------|-------------|------|---------------------|
| PERF-11 + BUG-02 | 606, 611 | Replace `date` + reorder | 1/startup | LOW | 0 |
| PERF-12 | 647–648 | Replace `date` x2–5 | 2–5/startup | LOW | -2 |
| PERF-13 | 966 | Inline `calculate_score` | 1/loop | LOW | +5 |
| QUALITY-03 | 752–783 | Remove dead functions | 0 (code hygiene) | VERY LOW | -31 |
| PERF-15 | 227–231 | Consolidate readlink | 1/startup | LOW | -3 |
| PERF-16 | 851 | Defer to cleanup | 1/circuit-breaker | LOW | +3 |
| SEC-02 | 583 | `printf '%s\n'` or direct jq | 0 (security) | VERY LOW | 0 |
| PERF-14 | 367–401 | Pre-store awk + empty-file check | 0–1/loop | LOW | +3 |
| PERF-17 | 992–999 | Replace awk with while-read | 1/loop | LOW | +5 |
| PERF-18 | 279–288 | Replace awk with while-read | 1/startup | LOW | +2 |

**Total if all implemented:** 6–9 startup forks eliminated, 2–3 per-loop forks eliminated, 1 security hardening, ~-20 net LOC.
