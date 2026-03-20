# Night Shift Validated Plan — Loop 2

Approved: 9 | Skipped: 1 | Urgente: 1

## TASK-1 — URGENTE

**Reason:** Critical security issue (SEC-01) — touches 1 file but has wide impact on sub-agent execution; lacks automated test coverage for sub-agent behavior under new permissions; requires human judgment on permission scope

**Action required:** Human review to confirm all necessary commands are included and no overly broad permissions are granted

- **Category:** security
- **Description:** Add missing commands to scoped Bash permissions allowlist — sub-agents silently fail without npx, echo, find, mkdir, head, tail, printf commands needed for CodeIntel indexing, file operations, and diagnostic output
- **Files:** scripts/night-dev.sh:718-739
- **Risk:** medium
- **Verification:** Manually verify settings.json contains all required permission entries: `grep -c "Bash(" .claude/worktree_root/claude-settings/settings.json` should show at least 13 entries; run `claude -p` with test prompt to confirm npx/echo commands work
- **Solution:** Add these entries to the `allow` array in the generated settings.json at lines 728-739:
  ```bash
  "Bash(npx *)",
  "Bash(echo *)",
  "Bash(find *)",
  "Bash(mkdir *)",
  "Bash(head *)",
  "Bash(tail *)",
  "Bash(printf *)",
  "Bash(cloc *)",
  "Bash(npm audit *)",
  "Bash(cargo audit *)"
  ```
  Insert after line 732 (after `Bash(cat *)` entry)
- **Source:** N/A

## TASK-2 — APPROVED

- **Category:** security
- **Description:** Prevent variable injection from DETECTED_RUNNER in heredoc — validate test runner against allowlist before interpolation to prevent JSON malformation if runner name contains special characters
- **Files:** scripts/night-dev.sh:720-730
- **Risk:** low
- **Verification:** Run existing tests: `bash scripts/night-dev.sh --help` should still work; grep for test runner detection: `grep -A5 "detect_test_runner" scripts/night-dev.sh | head -20` to confirm validation guard is present
- **Solution:** Add validation guard after line 717 (after `detect_test_runner()` call):
  ```bash
  case "$DETECTED_RUNNER" in
    pytest|"npm test"|"cargo test"|"go test ./..."|"make test"|tox) ;;
    *) echo "ERROR: Unknown test runner: $DETECTED_RUNNER" >&2; exit 1 ;;
  esac
  ```
- **Source:** N/A

## TASK-3 — APPROVED

- **Category:** bug
- **Description:** Fix score comparison for negative scores — use raw x10 integer comparison instead of re-parsing formatted decimal strings to eliminate sign and fractional part handling errors
- **Files:** scripts/night-dev.sh:950-987
- **Risk:** low
- **Verification:** Create test score of "-1.5" and "-0.3", verify improvement detection works correctly: `echo "Testing negative score comparison..." && bash -c 'PREVIOUS_SCORE_X10=0; current_score="-1.5"; score_x10=-15; if (( score_x10 > PREVIOUS_SCORE_X10 )); then echo "PASS: -1.5 correctly identified as improvement"; else echo "FAIL"; fi'`
- **Solution:** Store score_x10 directly for comparison:
  1. After line 958 (after `score_x10` calculation), add: `local current_score_x10=$score_x10`
  2. Initialize `PREVIOUS_SCORE_X10=0` at line 882 alongside `PREVIOUS_SCORE="0.0"`
  3. Replace lines 973-977 with:
     ```bash
     local improved="no"
     if (( current_score_x10 > PREVIOUS_SCORE_X10 )); then
       improved="yes"
     fi
     ```
  4. Update line 987 to also set `PREVIOUS_SCORE_X10=$current_score_x10`
- **Source:** N/A

## TASK-4 — APPROVED

- **Category:** bug
- **Description:** Tighten changelog pattern matching — require structural anchors (list prefix or colon) around APPLICATA/SKIPPATA/REVERTITA keywords to eliminate false positives from table headers and summary text
- **Files:** scripts/night-dev.sh:994-998
- **Risk:** low
- **Verification:** Run existing changelog parsing tests: `bash scripts/night-dev.sh --status | grep -i "applied\|skipped"` should show correct counts; create a test changelog with mixed content (headers, tables, prose) and verify only properly formatted lines are counted
- **Solution:** Replace case patterns at lines 994-998:
  ```bash
  case "$_cl_line" in
    *"- APPLICATA"*|*"APPLICATA:"*)   APPLIED=$((APPLIED + 1)) ;;
    *"- SKIPPATA"*|*"SKIPPATA:"*)     SKIPPED=$((SKIPPED + 1)) ;;
    *"- REVERTITA"*|*"REVERTITA:"*)   REVERTED=$((REVERTED + 1)) ;;
    *"- ESCALATED"*|*"- URGENTE"*|*"ESCALATED:"*|*"URGENTE:"*)
      ESCALATED=$((ESCALATED + 1)) ;;
  esac
  ```
- **Source:** N/A

## TASK-5 — APPROVED

- **Category:** bug
- **Description:** Ensure status.json is updated on Claude invocation failure — add minimal status update before continue statement to prevent stale consecutive_zero_applied counter if script is killed before next successful loop
- **Files:** scripts/night-dev.sh:938-941
- **Risk:** low
- **Verification:** Trigger a Claude failure (e.g., timeout or network error) and verify status.json consecutive_zero_applied counter is incremented: `jq '.stats.consecutive_zero_applied' .night-shift/status.json`
- **Solution:** Insert status.json update block before line 941 (before `continue`):
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
- **Source:** N/A

## TASK-6 — APPROVED

- **Category:** quality
- **Description:** Fix verbose mode exit code capture from tee pipeline — use PIPESTATUS[0] to capture Claude exit code instead of $? which returns tee's exit code
- **Files:** scripts/night-dev.sh:926-934
- **Risk:** low
- **Verification:** Run with `--verbose` flag and trigger a Claude failure (exit code != 0); verify claude_exit is set correctly: `bash scripts/night-dev.sh --verbose 2>&1 | grep -i "claude_exit\|WARNING"` should show proper exit code capture
- **Solution:** Replace lines 926-934 with:
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
- **Source:** N/A

## TASK-7 — SKIPPED

**Reason:** Low-value quality improvement with no functional impact; conflicts with practical priority guidance to skip low-value changes like this

- **Category:** quality
- **Description:** Simplify follow mode jq+printf redundancy — remove printf wrapper and use jq -r output directly for cleaner code
- **Files:** scripts/night-dev.sh:581
- **Risk:** low
- **Verification:** Run follow mode: `bash scripts/night-dev.sh --follow` and verify status output displays correctly without printf
- **Solution:** Replace line 581 jq expression to output directly without printf wrapper; remove `printf '%s\n'` and command substitution
- **Source:** N/A

## TASK-8 — APPROVED

- **Category:** quality
- **Description:** Remove dead code update_status() function — no longer called after loop 1 batching optimization; function definition at lines 746-753 can be safely deleted
- **Files:** scripts/night-dev.sh:746-753
- **Risk:** low
- **Verification:** Grep for function calls: `grep -n "update_status" scripts/night-dev.sh` should return only the function definition (lines 746-753); verify no references remain; run existing tests to confirm no breakage
- **Solution:** Delete lines 746-753 (the `update_status()` function definition). Verify with grep that no callers remain in the file.
- **Source:** N/A

## TASK-9 — APPROVED

- **Category:** quality
- **Description:** Optimize Makefile test target detection for consistency — replace while-read loop with single-read pattern matching approach matching package.json optimization from loop 1
- **Files:** scripts/night-dev.sh:300-308
- **Risk:** low
- **Verification:** Run test runner detection on a project with Makefile: `bash scripts/night-dev.sh --analyze path/to/go_project` should correctly detect `make test` runner; verify regex correctly matches `test:` at line start
- **Solution:** Replace lines 300-308 Makefile while-read loop with:
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
- **Source:** N/A

## TASK-10 — APPROVED

- **Category:** performance
- **Description:** Fix follow mode log file discovery hardcoded upper bound — use dynamic filesystem globbing instead of hardcoded loop-20 limit to support --max-loops > 20
- **Files:** scripts/night-dev.sh:510-518
- **Risk:** low
- **Verification:** Set `--max-loops 50` and create test loops up to loop-30; run follow mode and verify it finds the latest log file correctly: `ls -1d .night-shift/loop-*/claude_output.log | tail -1` should match what follow mode finds
- **Solution:** Replace lines 510-518 fallback loop with:
  ```bash
  if [[ -z "$latest_log" ]]; then
    local candidate
    candidate=$(ls -1d "$nd_dir"/loop-*/claude_output.log 2>/dev/null \
      | sort -t- -k2 -n | tail -1)
    [[ -n "$candidate" ]] && latest_log="$candidate"
  fi
  ```
- **Source:** N/A

---

## Parallel Batch Groups

Based on file overlap analysis, these tasks can be executed in parallel batches:

- **Batch 1 (Bash permissions & validation):** TASK-1, TASK-2 (both touch security config at lines 718-739)
- **Batch 2 (Score & changelog logic):** TASK-3, TASK-4 (non-overlapping logic fixes)
- **Batch 3 (Error handling & exit codes):** TASK-5, TASK-6 (Claude invocation flow)
- **Batch 4 (Cleanup & optimization):** TASK-8, TASK-9, TASK-10 (non-overlapping cleanup & perf improvements)
- **Skipped:** TASK-7 (deferred as low-value)

**Total actionable tasks:** 9 approved + 1 urgent (TASK-1) + 1 skipped = 11 issues processed
