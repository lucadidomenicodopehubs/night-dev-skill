# Night Shift Research — Loop 1

**Date:** 2026-03-20
**Issues Researched:** 10
**External Sources Found:** 0 (WebSearch unavailable — permissions not granted)
**Internal Knowledge Applied:** 10/10

---

## SEC-01 [MEDIUM] — Wildcard permissions in .claude/settings.json (prompt injection risk)

**Category:** SECURITY
**Severity:** MEDIUM
**Search Queries Attempted:** `bash script .claude settings.json wildcard permissions security prompt injection mitigation`

### Analysis

The file at line 712-727 grants `Bash(*)`, `Read(*)`, `Write(*)`, `Edit(*)` with `defaultMode: auto`. This means any content within the analyzed project (comments, test data, documentation) could contain prompt injection payloads that instruct the Claude sub-agent to execute arbitrary commands.

### Solutions

**Source:** Internal knowledge (principle of least privilege, defense in depth)
**Date:** N/A
**Reliability:** HIGH (well-established security principle)
**Summary:** The principle of least privilege dictates that permissions should be scoped to the minimum necessary. For an autonomous coding agent, `Bash` should be restricted to the specific commands needed (test runners, git, build tools). `Write` and `Edit` should ideally be scoped to the worktree path. `Read` is lower risk but could still be scoped.

**Recommended approach:**
Replace the wildcard `Bash(*)` with an explicit allowlist based on the detected test runner and standard dev tools:
```json
{
  "permissions": {
    "allow": [
      "Bash(make *)",
      "Bash(npm *)",
      "Bash(git *)",
      "Bash(cd *)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Grep(*)",
      "Glob(*)",
      "Agent(*)"
    ],
    "defaultMode": "auto"
  }
}
```
The `Bash` permissions should be dynamically generated based on `$DETECTED_RUNNER`. Since the settings are generated at runtime (line 712), this is straightforward. Keep `Read(*)`, `Write(*)`, `Edit(*)` as wildcards since Claude needs to read/write project files freely, and these are sandboxed to the worktree by Claude's own constraints.

**Trade-off:** Over-restricting `Bash` may cause the implementation agent to fail when it needs to run unexpected but legitimate commands (e.g., `python -c`, `cargo fmt`). Consider a broader but still bounded allowlist rather than a fully open wildcard.

---

## SEC-02 [LOW] — git clone URL validation

**Category:** SECURITY
**Severity:** LOW
**Search Queries Attempted:** `bash git clone URL injection attack prevention validation 2025`

### Analysis

The `resolve_project_path` function (line 96) runs `git clone "$input" "$clone_dir"` where `$input` is user-supplied. The existing protections are:
1. URL must match `https://github.com/` or `git@github.com:` prefix
2. Repo name validated against `^[a-zA-Z0-9._-]+$`
3. The variable is properly quoted

The main attack vector for git clone injection is `--upload-pack` or other flag injection, but since `$input` is quoted and starts with `https://` or `git@`, it cannot be interpreted as a flag (flags start with `-`).

### Solutions

**Source:** Internal knowledge (git security best practices)
**Date:** N/A
**Reliability:** HIGH
**Summary:** The current protections are adequate. The URL regex prevents path traversal and the quoting prevents word splitting. Git itself validates URLs before cloning.

**Recommended approach:** No changes needed. The audit itself notes "No immediate action needed. Current protections are sufficient." If additional hardening is desired, add `--` before the URL argument to explicitly end flag parsing: `git clone -- "$input" "$clone_dir"`.

---

## PERF-01 / ARCH-01 [HIGH/MEDIUM] — update_status() individual jq calls in cleanup

**Category:** PERFORMANCE / ARCHITECTURE
**Severity:** HIGH
**Search Queries Attempted:** `jq batch multiple field updates single call bash performance`

### Analysis

`update_status()` (line 735-741) does a full jq read-modify-write cycle per field. It is called twice in `cleanup()`: line 759 (`circuit_breaker = "OPEN"`) and line 773 (`phase = "COMPLETED"`). Each call forks jq, reads the entire JSON, modifies one field, writes to temp file, and renames. This is 2 unnecessary process forks during cleanup.

The main loop already uses a batched jq call (lines 1006-1027), so the pattern is established.

### Solutions

**Source:** Internal knowledge (jq pipe operator for batch updates)
**Date:** N/A
**Reliability:** HIGH (standard jq usage)
**Summary:** jq supports chaining multiple updates with the pipe operator `|` in a single expression. Replace two `update_status` calls with one jq invocation.

**Recommended approach:**
Replace the cleanup logic at lines 756-773 with a single batched jq call:
```bash
if [[ "$HAS_JQ" == "true" ]] && [[ -f "$ND_DIR/status.json" ]]; then
  local tmp="${ND_DIR}/status.tmp.json"
  local jq_expr='.phase = "COMPLETED"'
  if [[ "${_CIRCUIT_BREAKER_TRIGGERED:-false}" == "true" ]]; then
    jq_expr='.circuit_breaker = "OPEN" | .phase = "COMPLETED"'
  fi
  local final_score
  final_score=$(jq -r '.current_tests.score // "N/A"' "$ND_DIR/status.json" 2>/dev/null)
  echo "Final score: $final_score"
  jq "$jq_expr" "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
fi
```
This reduces 2-3 jq forks to 2 (one for reading score, one for writing updates). To reduce further to 1 fork, read the score from the same jq call that does the update, but that adds complexity.

Alternatively, the `update_status` function itself could be removed entirely since it's now only used in cleanup, and the inline batched approach is cleaner.

---

## BUG-02 [MEDIUM] — Negative score sign loss in formatting

**Category:** BUG
**Severity:** MEDIUM
**Search Queries Attempted:** `bash integer division negative numbers sign loss fix`

### Analysis

At line 936-940:
```bash
local score_x10=$(( (cur_passing * 100) + ... ))
local current_score=$(( score_x10 / 10 ))
local score_remainder=$(( score_x10 % 10 ))
[[ $score_remainder -lt 0 ]] && score_remainder=$(( -score_remainder ))
current_score="${current_score}.${score_remainder}"
```

For `score_x10 = -3`: `current_score = -3/10 = 0` (bash truncates toward zero), `score_remainder = -3%10 = -3`, abs = `3`. Result: `0.3`. But the correct value is `-0.3`. The sign is lost because `-3/10` rounds to `0`, not `-1`.

This is a well-known behavior of integer division in C/bash: truncation toward zero means negative values between -9 and -1 produce a zero quotient, losing the negative sign.

### Solutions

**Source:** Internal knowledge (bash arithmetic, C99 integer division semantics)
**Date:** N/A
**Reliability:** HIGH (well-understood arithmetic behavior)
**Summary:** Track the sign separately before taking absolute values.

**Recommended approach:**
```bash
local score_x10=$(( (cur_passing * 100) + (cur_total * 20) + (cur_coverage * 50) - (cur_failing * 200) - cur_time_s ))
local sign=""
local abs_score_x10=$score_x10
if [[ $score_x10 -lt 0 ]]; then
  sign="-"
  abs_score_x10=$(( -score_x10 ))
fi
local current_score=$(( abs_score_x10 / 10 ))
local score_remainder=$(( abs_score_x10 % 10 ))
current_score="${sign}${current_score}.${score_remainder}"
```

This also fixes the related BUG-03 (score comparison) since the comparison at line 951 uses the formatted string. With sign handled correctly, the comparison `(ci * 10 + ${cf:-0}) > (pi * 10 + ${pf:-0})` will also need updating to handle the sign — or better, keep `score_x10` as an integer for comparison and only format for display.

---

## BUG-01 [MEDIUM] — Follow mode picks arbitrary worktree

**Category:** BUG
**Severity:** MEDIUM
**Search Queries Attempted:** `bash find sort by modification time most recent file`

### Analysis

At line 454-465, `find` locates `status.json` files and `${worktrees[0]}` is used as "most recent." But `find` returns results in filesystem (inode) order, which is effectively random. With multiple Night Dev instances, the user gets an arbitrary one instead of the most recent.

### Solutions

**Source:** Internal knowledge (POSIX stat, bash sorting)
**Date:** N/A
**Reliability:** HIGH (standard POSIX utilities)
**Summary:** Sort found files by modification time to pick the newest.

**Recommended approach:**
Replace the find + arbitrary pick with a modification-time-sorted selection:
```bash
local newest="" newest_mtime=0
while IFS= read -r -d '' wt; do
  local mtime
  mtime=$(stat -c '%Y' "$wt" 2>/dev/null || stat -f '%m' "$wt" 2>/dev/null || echo 0)
  if [[ $mtime -gt $newest_mtime ]]; then
    newest_mtime=$mtime
    newest="$wt"
  fi
done < <(find "$search_path" "$HOME/night-dev-repos" -maxdepth 4 -name "status.json" -path "*/.night-dev/*" -print0 2>/dev/null)

if [[ -z "$newest" ]]; then
  echo -e "${RED}No Night Dev instances found.${NC}"
  exit 1
fi
local status_file="$newest"
```

Note: `stat -c '%Y'` is GNU/Linux, `stat -f '%m'` is macOS/BSD. The script should try both for portability, or since the project targets Linux (per env), just use `-c '%Y'`.

---

## QUALITY-01 [MEDIUM] — Claude CLI error handling too permissive

**Category:** QUALITY
**Severity:** MEDIUM
**Search Queries Attempted:** (WebSearch unavailable)

### Analysis

Lines 915-919 use `|| true` to suppress Claude CLI errors. If Claude fails (rate limit, crash, permission error), the script continues with empty/truncated output, potentially computing a zero score that triggers false stagnation detection.

### Solutions

**Source:** Internal knowledge (bash error handling best practices)
**Date:** N/A
**Reliability:** HIGH
**Summary:** Check the exit code and output file size after Claude invocation. An empty or very small output file indicates failure.

**Recommended approach:**
```bash
local claude_exit=0
if [[ "$VERBOSE" == "true" ]]; then
  (cd "$WORKTREE_PATH" && "${claude_cmd[@]}" 2>"$LOOP_DIR/claude_stderr.log") \
    | tee "$LOOP_DIR/claude_output.log" || claude_exit=$?
else
  (cd "$WORKTREE_PATH" && "${claude_cmd[@]}") \
    > "$LOOP_DIR/claude_output.log" 2>"$LOOP_DIR/claude_stderr.log" || claude_exit=$?
fi

# Check for Claude failure
if [[ $claude_exit -ne 0 ]] || [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
  echo "WARNING: Claude invocation failed (exit=$claude_exit). Skipping score calculation for loop $CURRENT_LOOP." >&2
  if [[ -f "$LOOP_DIR/claude_stderr.log" ]] && [[ -s "$LOOP_DIR/claude_stderr.log" ]]; then
    tail -5 "$LOOP_DIR/claude_stderr.log" >&2
  fi
  CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
  continue
fi
```

The key insight: `|| true` should be replaced with `|| claude_exit=$?` to capture the exit code without aborting the script (since `set -e` may be active). Then check both the exit code and the output file size before proceeding with score calculation.

**Note on tee pipe:** When using `| tee`, the exit code is from `tee`, not from Claude. Use `set -o pipefail` or `${PIPESTATUS[0]}` to capture the upstream exit code.

---

## QUALITY-02 [MEDIUM] — Fragile changelog parsing

**Category:** QUALITY
**Severity:** MEDIUM
**Search Queries Attempted:** (WebSearch unavailable)

### Analysis

Lines 964-974 parse the changelog using exact `case` patterns like `*[-\*]\ APPLICATA\ :*`. This requires the report agent to produce output in a very specific format. If the agent uses different bullet characters, bold markers, or extra whitespace, the pattern fails silently (counts stay at zero).

### Solutions

**Source:** Internal knowledge (bash pattern matching, defensive parsing)
**Date:** N/A
**Reliability:** HIGH
**Summary:** Use broader patterns that match the keyword regardless of surrounding formatting.

**Recommended approach:**
Broaden the case patterns to be more permissive:
```bash
case "$_cl_line" in
  *APPLICATA*)   APPLIED=$((APPLIED + 1)) ;;
  *SKIPPATA*)    SKIPPED=$((SKIPPED + 1)) ;;
  *REVERTITA*)   REVERTED=$((REVERTED + 1)) ;;
  *ESCALATED*|*URGENTE*)  ESCALATED=$((ESCALATED + 1)) ;;
esac
```

This is simpler and more resilient. The risk of false positives is low because these are Italian-language keywords (APPLICATA, SKIPPATA, REVERTITA) that are unlikely to appear in normal code discussion. If false positives become an issue, add a line-start anchor by checking the line starts with a list marker: `[[ "$_cl_line" =~ ^[[:space:]]*[-\*+] ]]` before the case statement.

---

## PERF-02 [MEDIUM] — package.json line-by-line parsing

**Category:** PERFORMANCE
**Severity:** MEDIUM
**Search Queries Attempted:** (WebSearch unavailable)

### Analysis

Lines 283-293 read `package.json` line-by-line in a `while` loop. For large Node.js projects, `package.json` can be hundreds of lines. The audit suggests reading the entire file into a variable and using bash pattern matching on the whole content.

### Solutions

**Source:** Internal knowledge (bash string operations vs line-by-line I/O)
**Date:** N/A
**Reliability:** HIGH
**Summary:** Reading the entire file into a variable with `$(<file)` is a single read syscall. Then bash `[[ "$content" == *pattern* ]]` is fast in-memory matching — no loop, no line splitting.

**Recommended approach:**
```bash
if [[ -f "$project/package.json" ]]; then
  local content
  content=$(<"$project/package.json")
  if [[ "$content" == *'"test"'* ]] && [[ "$content" != *'no test specified'* ]]; then
    DETECTED_RUNNER="npm test"
    return 0
  fi
fi
```

This replaces the `while IFS= read -r line` loop with two pattern matches on the full file content. It is both faster and simpler. The pattern `*'"test"'*` matches the same content as the original line-by-line check (looking for a `"test"` key in the scripts section). The false positive risk is acceptable since a `package.json` containing `"test"` almost always has a test script.

---

## INTENT-01 [LOW] — Scoring formula mismatch SKILL.md vs implementation

**Category:** INTENT
**Severity:** LOW
**Search Queries Attempted:** (WebSearch unavailable)

### Analysis

Three different scoring formulas exist:

1. **SKILL.md lines 31-47** (v2 multi-dimensional):
   - `tests_passing * 5`, `coverage_pct * 3`, `tests_failing * -20`, `execution_time_s * -0.1`
   - Plus `code_quality` and `architecture_quality` dimensions

2. **SKILL.md line 125** (simplified, in the analyze prompt section):
   - `tests_passing * 10`, `test_count * 2`, `coverage_pct * 5`, `tests_failing * -20`, `execution_time_s * -0.1`

3. **Implementation at line 936:**
   - `cur_passing * 100`, `cur_total * 20`, `cur_coverage * 50`, `cur_failing * -200`, `cur_time_s * -1`
   - (These are x10 scaled: so effectively `passing*10 + total*2 + coverage*5 - failing*20 - time*0.1`)

The implementation matches formula #2 (line 125), not formula #1 (lines 31-47). The v2 formula with `code_quality` and `architecture_quality` is documented but not implemented in the score calculation.

### Solutions

**Source:** Internal knowledge (documentation consistency)
**Date:** N/A
**Reliability:** HIGH
**Summary:** The SKILL.md has two competing formulas. The implementation matches the simplified one. Either update SKILL.md to document the actual formula, or implement the v2 formula.

**Recommended approach:**
Update SKILL.md lines 31-47 to match the actual implementation, or add a note explaining the v2 formula is aspirational/future and the current implementation uses the simplified formula from line 125. The simplest fix is to update the multipliers in the v2 section to match reality:
```
test_health:
  + (tests_passing x 10)
  + (test_count x 2)
  + (coverage_pct x 5)
  - (tests_failing x 20)
  - (execution_time_s x 0.1)
```
And note that `code_quality` and `architecture_quality` are not yet wired into the main loop's score calculation (they may be used by the analyze agent separately).

---

## Summary

| # | Issue | Category | Severity | External Sources | Action |
|---|-------|----------|----------|-----------------|--------|
| 1 | SEC-01 | SECURITY | MEDIUM | 0 | Scope Bash permissions to allowlist based on detected runner |
| 2 | SEC-02 | SECURITY | LOW | 0 | No changes needed; optionally add `--` before URL |
| 3 | PERF-01 | PERFORMANCE | HIGH | 0 | Batch cleanup jq calls into single invocation |
| 4 | BUG-02 | BUG | MEDIUM | 0 | Track sign separately before abs() on score components |
| 5 | BUG-01 | BUG | MEDIUM | 0 | Sort found worktrees by mtime via stat |
| 6 | QUALITY-01 | QUALITY | MEDIUM | 0 | Capture Claude exit code, skip loop on failure |
| 7 | QUALITY-02 | QUALITY | MEDIUM | 0 | Broaden case patterns to match keyword anywhere in line |
| 8 | ARCH-01 | ARCHITECTURE | MEDIUM | 0 | Same as PERF-01 — batch cleanup jq |
| 9 | PERF-02 | PERFORMANCE | MEDIUM | 0 | Read entire package.json into variable, pattern match |
| 10 | INTENT-01 | INTENT | LOW | 0 | Synchronize SKILL.md formulas with implementation |

**Note:** WebSearch was unavailable (permissions not granted). All recommendations are based on internal knowledge of bash scripting best practices, jq usage patterns, POSIX standards, and security principles. These are well-established practices that do not require external validation.
