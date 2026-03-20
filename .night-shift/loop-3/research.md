# Night Shift Research — Loop 3 (Final)

**Date:** 2026-03-20
**Source:** Internal knowledge (WebSearch unavailable — no external reference found for all items; proceeding with internal knowledge)

---

## BUG-01: Inline mode overwrites "TIMEOUT" with "DONE" (line 915)

### Pattern: Bash conditional post-loop status

The issue is a classic post-loop unconditional write. The `while` loop at lines 905-914 can exit via two paths: (1) `done` file appears, or (2) deadline hit triggers `break`. Line 915 runs unconditionally after the loop.

### Best practice: Guard post-loop writes with exit-condition check

Standard bash pattern for distinguishing break-exit from normal-exit in a `while` loop:

```bash
local timed_out=false
while [[ ! -f "$LOOP_DIR/done" ]]; do
  sleep 5
  NOW=${EPOCHSECONDS:-$(date +%s)}
  if [[ $NOW -ge $DEADLINE ]]; then
    echo "TIMEOUT" > "$LOOP_DIR/inline_status"
    timed_out=true
    break
  fi
done
if [[ "$timed_out" == "false" ]]; then
  echo "DONE" > "$LOOP_DIR/inline_status"
fi
```

Alternative (simpler, avoids the flag variable):

```bash
# After the while loop, check the actual condition:
if [[ -f "$LOOP_DIR/done" ]]; then
  echo "DONE" > "$LOOP_DIR/inline_status"
fi
# If file doesn't exist, TIMEOUT was already written inside the loop.
```

### Implementation guidance

Use the second (simpler) approach. Replace line 915 with:

```bash
[[ -f "$LOOP_DIR/done" ]] && echo "DONE" > "$LOOP_DIR/inline_status"
```

One line, no new variables, preserves the TIMEOUT status already written at line 911.

---

## BUG-02: Missing guard for claude_output.log in inline mode (lines 950-952)

### Pattern: File existence guard before processing

After inline mode completes, execution falls through to line 950 which assigns `test_output="$LOOP_DIR/claude_output.log"`. In inline mode, the orchestrator is responsible for creating this file. If it doesn't exist or is empty, `parse_test_results` gets garbage input.

### Best practice: Defensive guard matching the non-inline path

The non-inline path already has a guard at lines 933-944:

```bash
if [[ $claude_exit -ne 0 ]] || [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
  # warn and continue
fi
```

### Implementation guidance

After line 946 (the closing `fi` of the inline/non-inline branch), add:

```bash
# Guard: ensure claude_output.log exists for score calculation
if [[ "$INLINE_MODE" == "true" ]] && [[ ! -s "$LOOP_DIR/claude_output.log" ]]; then
  echo -e "${YELLOW}WARNING: Inline mode completed but claude_output.log is missing or empty. Skipping score calculation.${NC}" >&2
  CONSECUTIVE_ZERO=$((CONSECUTIVE_ZERO + 1))
  APPLIED=0; SKIPPED=0; REVERTED=0; ESCALATED=0
  if [[ "$HAS_JQ" == "true" ]]; then
    local tmp
    tmp=$(mktemp "${ND_DIR}/status.tmp.XXXXXX.json")
    jq --argjson cz "$CONSECUTIVE_ZERO" \
       '.stats.consecutive_zero_applied = $cz' \
       "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
  fi
  continue
fi
```

This mirrors the existing non-inline failure path exactly.

---

## SEC-01: Sub-agent Bash permissions allowlist missing commands (lines 718-739)

### Pattern: Claude Code `-p` non-interactive permission model

**How `claude -p` permissions work:**
- `claude -p` runs in non-interactive mode (no user present to approve prompts)
- The `settings.json` `permissions.allow` array is a whitelist of permitted tool invocations
- Pattern format: `"Bash(command *)"` allows `command` with any arguments
- `--permission-mode auto` combined with `defaultMode: "auto"` should auto-accept unlisted tools, but observed behavior shows sub-agents may stall or silently fail on unlisted Bash commands
- Safest approach: explicitly allowlist all commands the sub-agent needs

**No external reference found** for the exact permission resolution in `claude -p --permission-mode auto` mode.

### Implementation guidance

Add to the `allow` array (between the existing `"Bash(cat *)"` and `"Read(*)"` lines):

```json
"Bash(mkdir *)",
"Bash(find *)",
"Bash(head *)",
"Bash(tail *)"
```

**Do NOT add** `"Bash(npm *)"`, `"Bash(pip *)"`, `"Bash(cargo *)"` unless the skill explicitly needs dependency installation. The test runner is already allowlisted. Adding broad package manager access is a security surface expansion that should be a conscious decision per-project.

Rationale for each:
- `mkdir`: Sub-agents create new directories when adding features
- `find`: The analyze-prompt.md explicitly references codebase scanning
- `head`/`tail`: Standard log inspection; sub-agents need these to review test output

---

## QUAL-01: Race condition in status.tmp.json between main loop and cleanup trap (lines 765, 855, 939, 1036)

### Pattern: Bash trap signal handling and temp file safety

**The race:** A signal (SIGINT, SIGTERM) can arrive while the main loop is mid-write to `status.tmp.json`. The cleanup trap then also writes to the same file path. Two writers to the same temp file path = potential corruption.

**Bash signal timing:** Bash is single-threaded. Signals are handled between simple commands, not during them. So `jq ... > tmp` will complete before the trap fires. The actual risk window is: `jq > tmp` succeeds, signal arrives before `mv tmp real`. Then the trap writes its own content to the same `tmp` path, overwriting the main loop's output. The trap's `mv` then moves the trap's content. The main loop's write is lost — but more importantly, the `tmp` file had valid content from the trap, so status.json ends up valid. However, if the signal arrives during `jq` (before redirection completes), the `tmp` file may be truncated, and the trap writes to the same truncated file path.

### Best practices

1. **Use mktemp for unique temp files (recommended):**
   ```bash
   local tmp
   tmp=$(mktemp "${ND_DIR}/status.tmp.XXXXXX.json")
   jq '...' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
   ```
   Each call site gets a unique temp file. `mv` is atomic on the same filesystem. Even if the trap fires mid-operation, it writes to a different temp file.

2. **Block signals during critical sections (heavier):**
   ```bash
   trap '' INT TERM   # Block signals
   jq '...' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
   trap cleanup INT TERM  # Restore trap
   ```

3. **Use flock (heaviest, overkill for single-process):**
   ```bash
   (
     flock -n 9 || exit 1
     jq '...' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
   ) 9>"${ND_DIR}/.status.lock"
   ```

### Implementation guidance

Use approach 1 (`mktemp`). Replace at each of the 4 sites (lines 765, 855, 939, 1036):

```bash
# Replace:
local tmp="${ND_DIR}/status.tmp.json"
jq '...' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"

# With:
local tmp
tmp=$(mktemp "${ND_DIR}/status.tmp.XXXXXX.json")
jq '...' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json" || rm -f "$tmp"
```

The `|| rm -f "$tmp"` ensures orphaned temp files are cleaned up if `jq` or `mv` fails.

---

## BUG-03: Score formula divergence between SKILL.md and implementation (line 961)

### Analysis

The implementation computes:
```
score_x10 = (passing * 100) + (total * 20) + (coverage * 50) - (failing * 200) - time_s
```

SKILL.md specifies `test_health`, `code_quality`, and `architecture_quality` components. The bash script only computes `test_health`. The `code_quality` and `architecture_quality` are evaluated by the Claude sub-agent in its analysis output, not by the bash wrapper.

The time penalty arithmetic is correct: `execution_time_s * 0.1` in normal scale becomes `execution_time_s * 1` in x10 scale, which is `- cur_time_s`.

### Implementation guidance

This is a documentation alignment issue. Add a comment in the script near line 961:

```bash
# Score: test_health component only (x10 integer arithmetic).
# code_quality and architecture_quality are evaluated by the Claude
# sub-agent in analysis.md, not by this wrapper. See SKILL.md for full formula.
```

Minimal risk, no behavior change.

---

## Summary: Implementation Priority

| Finding | Fix complexity | Risk if unfixed | Recommended action |
|---------|---------------|-----------------|-------------------|
| BUG-01  | 1 line change | Orchestrator cannot detect timeouts | Apply |
| BUG-02  | 10 line addition | False stagnation exit in inline mode | Apply |
| SEC-01  | 4 lines added to JSON | Sub-agent silent failures in `-p` mode | Apply |
| QUAL-01 | 4 sites, mktemp swap | Low probability status.json corruption | Apply |
| BUG-03  | 2 line comment | Documentation confusion only | Apply |

All 5 fixes are low-risk and independent of each other. They can be applied in any order.
