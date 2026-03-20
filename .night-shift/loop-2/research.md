# Night Shift Research — Loop 2

## Summary
- Issues researched: 10 of 12 total
- External references found: 0 (WebSearch unavailable — all guidance based on authoritative bash/POSIX knowledge)
- Issues without external references: 10

---

## Issue 1: SEC-01 — Scoped Bash permissions missing commands sub-agents need
**Category:** SECURITY
**Severity:** MEDIUM
**Search queries used:**
- "claude code settings.json bash permission allowlist scoped commands" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on Claude Code permission model behavior.

### Solution 1 (recommended)
- **Source:** Internal analysis (Claude Code permission model)
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** In `claude -p` (non-interactive prompt mode), missing permissions cause silent failures since there is no user to approve. Every command a sub-agent needs must be explicitly allowlisted.
- **Recommended approach:** Add these entries to the `allow` array in the generated `settings.json`:
  ```json
  "Bash(npx *)",
  "Bash(echo *)",
  "Bash(find *)",
  "Bash(mkdir *)",
  "Bash(head *)",
  "Bash(tail *)",
  "Bash(printf *)",
  "Bash(cloc *)",
  "Bash(pip *)",
  "Bash(npm audit *)",
  "Bash(cargo audit *)"
  ```
  For tighter scoping on CodeIntel: `"Bash(npx tsx *)"` instead of `"Bash(npx *)"`. Note that `Read(*)` and `Write(*)` already cover file I/O, so `echo` is mainly needed for piped output.

---

## Issue 2: SEC-02 — Unquoted heredoc allows variable injection from DETECTED_RUNNER
**Category:** SECURITY
**Severity:** LOW
**Search queries used:**
- "bash heredoc quoting variable expansion prevention" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash manual section 3.6.6 (Here Documents).

### Solution 1 (recommended)
- **Source:** Internal analysis (bash manual, Here Documents)
- **Date:** 2026-03-20
- **Reliability:** internal analysis (based on official bash specification)
- **Summary:** With unquoted heredoc delimiter (`<<EOSETTINGS`), bash performs parameter expansion, command substitution, and arithmetic expansion. If `DETECTED_RUNNER` contains `"`, `}`, or newlines, the generated JSON would be malformed or could inject additional permissions. Validating against an allowlist is simpler and more robust than quoting the heredoc and using `sed`/`jq` for interpolation.
- **Recommended approach:** Add a validation guard after `detect_test_runner()` returns:
  ```bash
  case "$DETECTED_RUNNER" in
    pytest|"npm test"|"cargo test"|"go test ./..."|"make test"|tox) ;;
    *) echo "ERROR: Unknown test runner: $DETECTED_RUNNER" >&2; exit 1 ;;
  esac
  ```

### Solution 2
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** Alternatively, use `jq` to construct the JSON safely, avoiding shell interpolation entirely.
- **Recommended approach:** Replace the heredoc with:
  ```bash
  jq -n --arg runner "$DETECTED_RUNNER" '{
    permissions: {
      allow: [
        ("Bash(\($runner))"),
        ("Bash(\($runner) *)"),
        "Bash(git *)", "Bash(cd *)", "Bash(ls *)", "Bash(wc *)", "Bash(cat *)",
        "Read(*)", "Write(*)", "Edit(*)", "Grep(*)", "Glob(*)", "Agent(*)"
      ],
      defaultMode: "auto"
    }
  }' > "$wt_claude_dir/settings.json"
  ```
  This is injection-proof but adds a `jq` dependency for settings generation (already required elsewhere).

---

## Issue 3: BUG-01 — Score comparison broken for negative scores
**Category:** BUG
**Severity:** MEDIUM
**Search queries used:**
- "bash integer arithmetic negative numbers signed comparison" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash arithmetic evaluation rules.

### Solution 1 (recommended)
- **Source:** Internal analysis (bash arithmetic)
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** The bug: `IFS=. read -r ci cf <<< "-1.5"` gives `ci="-1"`, `cf="5"`. Then `ci * 10 + cf` = `-10 + 5` = `-5`, but the correct x10 value is `-15`. The fractional part should be subtracted when the integer is negative. Additionally, `ci="-0"` loses its sign in arithmetic (`-0 == 0`). The root fix is to avoid re-parsing formatted strings -- compare the raw `score_x10` integers that were already computed.
- **Recommended approach:** Store `score_x10` for comparison instead of re-parsing:
  ```bash
  # After computing score_x10 (line 958), keep it:
  local current_score_x10=$score_x10

  # Replace lines 973-977:
  local improved="no"
  if (( current_score_x10 > PREVIOUS_SCORE_X10 )); then
    improved="yes"
  fi
  ```
  Initialize `PREVIOUS_SCORE_X10=0` alongside `PREVIOUS_SCORE="0.0"` and update with `PREVIOUS_SCORE_X10=$current_score_x10` at line 987. This eliminates the split-and-recombine roundtrip entirely.

### Solution 2
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** If the formatted-string path must be kept, handle the sign explicitly.
- **Recommended approach:**
  ```bash
  local cv pv
  if [[ "$ci" == -* ]]; then
    cv=$(( ci * 10 - ${cf:-0} ))
  else
    cv=$(( ci * 10 + ${cf:-0} ))
  fi
  # Same for pi/pf -> pv
  if (( cv > pv )); then improved="yes"; fi
  ```
  This is more fragile than Solution 1 and should only be used if `score_x10` cannot be preserved across iterations.

---

## Issue 4: BUG-02 — Changelog pattern `*APPLICATA*` too broad
**Category:** BUG
**Severity:** MEDIUM
**Search queries used:**
- "bash case pattern matching anchored glob best practice" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash glob pattern matching best practices.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** The `case` glob `*APPLICATA*` matches any line containing the substring, including table headers, summary lines, and comments. Adding a structural anchor (list bullet prefix or colon suffix) eliminates most false positives while remaining more lenient than the original over-strict pattern.
- **Recommended approach:** Replace the case patterns at lines 994-998:
  ```bash
  case "$_cl_line" in
    *"- APPLICATA"*|*"APPLICATA:"*)   APPLIED=$((APPLIED + 1)) ;;
    *"- SKIPPATA"*|*"SKIPPATA:"*)     SKIPPED=$((SKIPPED + 1)) ;;
    *"- REVERTITA"*|*"REVERTITA:"*)   REVERTED=$((REVERTED + 1)) ;;
    *"- ESCALATED"*|*"- URGENTE"*|*"ESCALATED:"*|*"URGENTE:"*)
      ESCALATED=$((ESCALATED + 1)) ;;
  esac
  ```
  The `*"- KEYWORD"*` pattern requires a markdown list item prefix. The `*"KEYWORD:"*` pattern handles `STATUS: APPLICATA` formats. Both exclude bare mentions in prose or table cells.

---

## Issue 5: BUG-03 — Claude failure path skips status.json update
**Category:** BUG
**Severity:** LOW
**Search queries used:**
- "bash continue statement skip cleanup pattern" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash control flow best practices.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** The `continue` at line 941 skips the batched status.json update at lines 1032-1053. If the script is killed before the next successful loop, `consecutive_zero_applied` is stale in status.json.
- **Recommended approach:** Add a minimal status update before `continue`:
  ```bash
  if [[ $claude_exit -ne 0 ]] || [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
    echo -e "${YELLOW}WARNING: Claude invocation failed (exit=$claude_exit).${NC}" >&2
    CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
    APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
    if [[ "$HAS_JQ" == "true" ]]; then
      local tmp="${ND_DIR}/status.tmp.json"
      jq --argjson cz "$CONSECUTIVE_ZERO" \
         '.stats.consecutive_zero_applied = $cz' \
         "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
    fi
    continue
  fi
  ```

---

## Issue 6: QUALITY-01 — Verbose mode tee pipeline masks Claude exit code
**Category:** QUALITY
**Severity:** MEDIUM
**Search queries used:**
- "bash PIPESTATUS capture exit code tee pipeline" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash manual section 3.4.2 (`PIPESTATUS` array).

### Solution 1 (recommended)
- **Source:** Internal analysis (bash manual, PIPESTATUS)
- **Date:** 2026-03-20
- **Reliability:** internal analysis (based on official bash specification)
- **Summary:** In bash, `$?` after a pipeline returns the exit status of the last command (`tee`). `PIPESTATUS` is an array capturing all pipeline component exit codes. `${PIPESTATUS[0]}` gives the first command's exit code. The array is only valid immediately after the pipeline -- any subsequent command overwrites it. Note: `set -o pipefail` makes `$?` reflect the rightmost failing command, but the `|| claude_exit=$?` construct means the compound command always succeeds (the `||` branch runs), so `pipefail` does not help here.
- **Recommended approach:** Replace lines 928-931:
  ```bash
  local claude_exit=0
  if [[ "$VERBOSE" == "true" ]]; then
    set +e
    (cd "$WORKTREE_PATH" && "${claude_cmd[@]}" 2>"$LOOP_DIR/claude_stderr.log") \
      | tee "$LOOP_DIR/claude_output.log"
    claude_exit=${PIPESTATUS[0]}
    set -e
  else
    (cd "$WORKTREE_PATH" && "${claude_cmd[@]}") \
      > "$LOOP_DIR/claude_output.log" 2>"$LOOP_DIR/claude_stderr.log" || claude_exit=$?
  fi
  ```
  Key: do NOT combine `|| claude_exit=$?` with `PIPESTATUS` -- let the pipeline run, then read `PIPESTATUS[0]` on the very next line. The `set +e`/`set -e` wrapper prevents `set -o pipefail` from exiting the script on Claude failure.

---

## Issue 7: QUALITY-02 — Follow mode jq+printf redundant
**Category:** QUALITY
**Severity:** MEDIUM
**Search queries used:**
- "jq raw output printf redundant" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on jq usage best practices.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** `jq -r` outputs raw strings with a trailing newline. Wrapping in `printf '%s\n' "$(jq -r ...)"` adds an unnecessary subshell and command substitution. It also risks word splitting or glob expansion if quoting is imperfect.
- **Recommended approach:** Replace line 581:
  ```bash
  # Before:
  printf '%s\n' "$(jq -r '"Applied: \(.stats.total_applied) | ..."' "$status_file")"

  # After:
  jq -r '"Applied: \(.stats.total_applied) | Skipped: \(.stats.total_skipped) | Reverted: \(.stats.total_reverted) | Score: \(.current_tests.score // "N/A")"' "$status_file"
  ```

---

## Issue 8: QUALITY-03 — Makefile test target detection inconsistent
**Category:** QUALITY
**Severity:** LOW
**Search queries used:**
- "bash read entire file regex match vs while read loop" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash file processing patterns.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** The `while IFS= read -r line` loop is slower than a single-read approach using `$(<file)` and regex matching. For consistency with the package.json detection path (already optimized in loop 1), use the same pattern.
- **Recommended approach:** Replace the Makefile while-read loop (lines 300-308):
  ```bash
  if [[ -f "$project/Makefile" ]]; then
    local makefile_content
    makefile_content=$(<"$project/Makefile")
    if [[ "$makefile_content" =~ (^|$'\n')test[[:space:]]*: ]]; then
      DETECTED_RUNNER="make test"
      return 0
    fi
  fi
  ```
  The `(^|$'\n')` anchor ensures `test:` appears at the start of a line.

---

## Issue 9: ARCH-01 — update_status() is dead code
**Category:** ARCHITECTURE
**Severity:** LOW
**Search queries used:**
- "bash dead code removal maintenance" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on code maintenance best practices.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** Dead code increases cognitive load and can mislead developers. The batched jq approach at lines 1032-1053 fully replaces `update_status()`.
- **Recommended approach:** Verify no callers remain: `grep -n 'update_status' scripts/night-dev.sh`. If only the function definition appears, delete lines 746-753. If there are callers (e.g., circuit-breaker at line 851 still uses `update_status`), those callers must be refactored first (see BUG-03 fix which adds inline jq for the failure path, and the circuit-breaker should similarly be inlined or deferred to cleanup).

---

## Issue 10: PERF-01 — Follow mode fallback hardcoded upper bound of 20
**Category:** PERFORMANCE
**Severity:** LOW
**Search queries used:**
- "bash find latest numbered directory dynamically" (WebSearch unavailable)

**No external reference found** — proceed with internal analysis. Suggested fix is based on bash scripting best practices.

### Solution 1 (recommended)
- **Source:** Internal analysis
- **Date:** 2026-03-20
- **Reliability:** internal analysis
- **Summary:** The hardcoded `for ((i=20; i>=1; i--))` misses logs from loops 21+ when `--max-loops` exceeds 20. The primary jq path handles this correctly, so this is fallback-only. Filesystem globbing removes any upper bound.
- **Recommended approach:** Replace lines 510-518:
  ```bash
  if [[ -z "$latest_log" ]]; then
    local candidate
    candidate=$(ls -1d "$nd_dir"/loop-*/claude_output.log 2>/dev/null \
      | sort -t- -k2 -n | tail -1)
    [[ -n "$candidate" ]] && latest_log="$candidate"
  fi
  ```
  The `sort -t- -k2 -n` sorts numerically by the number after the hyphen, so `loop-2` comes before `loop-10`. `tail -1` picks the highest.
