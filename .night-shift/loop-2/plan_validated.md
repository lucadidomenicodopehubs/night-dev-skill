# Night Shift Task Plan — Loop 2 (Validated)

Focus: **PERFORMANCE** (max 12 of 15 tasks allowed)

## Task Priority & Risk Analysis

### Risk Gate Results

All 14 issues passed risk gate evaluation:
- **0 SKIPPED** (no issues met skip criteria: high risk + >5 files, API changes, architectural decisions)
- **0 URGENT** (no security issues requiring manual human review before auto-apply)
- **14 APPROVED** (all safe for automated implementation)

---

## Ordered Task List

### TASK-1: Fix date consistency bug (BUG-02) + eliminate startup date fork (PERF-11)
- **Category**: bug + performance
- **Priority**: CRITICAL
- **Description**: Move `DATE_TAG` derivation after `START_TIME` is set and use `printf -v DATE_TAG '%(%Y-%m-%d)T'` builtin instead of `date` fork. Fixes date mismatch when script starts at day boundary; eliminates 1 startup fork.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Run script and verify `DATE_TAG` matches `START_TIME` date component
  - Confirm no `date +%Y-%m-%d` subprocess in tracing (can use `strace -e trace=execve`)
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 fork saved at startup; correctness bug fixed

---

### TASK-2: Eliminate 2–5 date forks for STARTED_AT / DEADLINE_ISO initialization (PERF-12)
- **Category**: performance
- **Priority**: CRITICAL
- **Description**: Replace `date -Iseconds` and fallback `date` calls with `printf -v` builtin format specifiers. Currently 2–5 date forks at startup; reduce to 0.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Confirm `STARTED_AT` and `DEADLINE_ISO` are set to ISO-8601 format
  - Verify `status.json` contains valid ISO timestamps in those fields
  - Timezone format may change from `+00:00` to `+0000` (both valid ISO-8601); verify downstream consumers accept this
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 2–5 forks saved at startup; net time: -2 LOC

---

### TASK-3: Inline calculate_score arithmetic to eliminate loop subshell fork (PERF-13)
- **Category**: performance
- **Priority**: HIGH
- **Description**: Replace `current_score=$(calculate_score ...)` with direct bash arithmetic at call site (lines 961–966). Saves 1 subshell fork per loop iteration.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Run script and verify `current_score` is set correctly (format: `NNN.N`)
  - Compare output score value before/after; should be identical
  - Validate test cases continue to pass (27 passed, 0 failed)
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 fork saved per loop iteration

---

### TASK-4: Remove dead helper functions (QUALITY-03)
- **Category**: quality
- **Priority**: HIGH
- **Description**: Remove `update_status_nested()`, `update_score()`, and `append_score_history()` functions (lines 752–783). These are dead code left over from PERF-01 batching optimization; their logic is now in the batched jq block (lines 1031–1051).
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Grep for `update_status_nested`, `update_score`, `append_score_history` — only definitions should appear (zero call sites)
  - Run full test suite; all 27 tests should pass
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: Code hygiene; -31 LOC removed

---

### TASK-5: Consolidate readlink forks in PROJECT_PATH initialization (PERF-15)
- **Category**: performance
- **Priority**: HIGH
- **Description**: Combine redundant `readlink -f` test (line 227) and use (line 228) into a single attempt with fallback. Eliminates 1 startup fork.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Run with valid project path; confirm `PROJECT_PATH` is set to absolute path
  - Run with invalid path; confirm error handling falls back to `cd ... && pwd`
  - No regression in startup time
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 fork saved at startup; net LOC: -3

---

### TASK-6: Replace unsafe echo -e with printf for jq output (SEC-02)
- **Category**: security
- **Priority**: HIGH
- **Description**: In `follow_night_dev()` (line 583), replace `echo -e "$(jq ...)"` with `printf '%s\n'` to prevent ANSI escape sequence injection from `status.json` into terminal.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Create `status.json` with crafted ANSI escape in a field (e.g., `\x1b[31m`)
  - Run in follow mode; verify escape sequences are NOT interpreted (output is literal, not colored)
  - Normal (non-crafted) status output should appear identical
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: Security hardening; blocks ANSI injection from untrusted status.json

---

### TASK-7: Pre-store awk script constant and add empty-file optimization (PERF-14)
- **Category**: performance
- **Priority**: MEDIUM
- **Description**: Move inline awk script from `parse_test_results` (lines 367–401) to a module-level constant `_PARSE_AWK_SCRIPT`. Add early-exit for empty files to avoid awk invocation on uninitialized logs.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Verify `parse_test_results` output on non-empty test logs matches previous behavior
  - Verify empty test logs return "0 0 0 0 0" without awk fork
  - Check that the awk script variable is readonly and not accidentally modified
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: Marginal bash parse overhead reduction; ~1 awk fork avoided on empty logs per loop

---

### TASK-8: Replace changelog awk with pure bash while-read loop (PERF-17)
- **Category**: performance
- **Priority**: MEDIUM
- **Description**: Replace awk subprocess (lines 992–999) with bash `while IFS= read -r` loop using glob pattern matching. Eliminates 1 awk fork per loop iteration.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Verify `APPLIED`, `SKIPPED`, `REVERTED`, `ESCALATED` counts match previous awk output on test changelog
  - Test edge cases: empty changelog, missing patterns, multiple occurrences per line
  - Pattern matching: `APPLICATA`, `SKIPPATA`, `REVERTITA` glob matches; `ESCALATED|URGENTE` regex match
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 fork saved per loop iteration

---

### TASK-9: Replace package.json awk with pure bash while-read loop (PERF-18)
- **Category**: performance
- **Priority**: MEDIUM
- **Description**: In `detect_test_runner()` (lines 279–288), replace awk with bash `while` loop. Detect `"test"` key and `no test specified` patterns using glob/regex matching instead of awk fork.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Test with real `package.json` files from various projects (React, Node, Python with test script)
  - Verify `DETECTED_RUNNER` is set correctly (should be "npm test" for standard projects)
  - Edge case: missing `package.json` should handle gracefully
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 fork saved at startup

---

### TASK-10: Defer circuit-breaker status update to cleanup trap (PERF-16)
- **Category**: performance
- **Priority**: MEDIUM
- **Description**: Move `update_status "circuit_breaker" "OPEN"` (line 851) out of the main loop. Instead, set a flag variable and apply the update in `cleanup()` trap alongside phase completion. Eliminates extra jq fork on circuit-breaker activation.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Trigger circuit breaker condition (`CONSECUTIVE_ZERO >= threshold`)
  - Verify `status.json` has `circuit_breaker: "OPEN"` after script exits
  - Confirm status update happens even if script is interrupted (cleanup trap runs)
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: 1 jq fork deferred per circuit-breaker activation (rare event); code consistency improved

---

### TASK-11: Build prompt once, interpolate dynamics per loop (PERF-19)
- **Category**: performance
- **Priority**: LOW
- **Description**: Cache the static portion of `LOOP_PROMPT` (SKILL.md + fixed text) before the loop. Only interpolate dynamic fields (loop number, current score, changelog summary) per iteration. Reduces string reconstruction overhead.
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**:
  - Verify `LOOP_PROMPT` content is identical to previous behavior per loop iteration
  - Check that dynamic variables (loop number, score, changelog) are correctly interpolated
  - No regression in prompt format or Claude's ability to parse context
- **Estimated complexity**: medium
- **Verdict**: APPROVED
- **Impact**: String allocation overhead reduction; marginal per-iteration savings

---

### TASK-12: Resolve Makefile REQUIRED_REFS inconsistency (QUALITY-04)
- **Category**: quality
- **Priority**: LOW
- **Description**: `Makefile` lists `risk-gate-prompt.md` and `codeintel-reference.md` as required, but both files are missing and never validated. Remove these from `REQUIRED_REFS` or create stub files. Currently misleading to claim they're "required."
- **Files**: `Makefile`
- **Risk level**: low
- **Verification**:
  - `make check-required` should list only actually-required files
  - Verify test suite passes after removal (REQUIRED_REFS change does not affect tests)
- **Estimated complexity**: small
- **Verdict**: APPROVED
- **Impact**: Clarity; accurate representation of actual dependencies

---

## Not Implemented (Deferred)

### SKIPPED: QUALITY-05 — Fix magic number in follow mode fallback
- **Reason**: Low impact; fallback is for an edge case (missing logs). The bound of 20 is a heuristic; using `MAX_LOOPS` would require refactoring fallback logic. Deferred to loop 3 as lower priority.
- **Alternative**: Could use `ls -1d ... | sort | tail -1` for dynamic latest log discovery, but requires testing with edge cases.

---

## Summary

| Category | Count | Issues |
|----------|-------|--------|
| Security | 1 | SEC-02 |
| Bug | 1 | BUG-02 (combined with PERF-11) |
| Performance | 8 | PERF-11, PERF-12, PERF-13, PERF-14, PERF-15, PERF-16, PERF-17, PERF-18, (PERF-19) |
| Quality | 2 | QUALITY-03, QUALITY-04 |
| **Total Approved** | **12** | **All safe for auto-apply** |
| **Total Deferred** | **2** | QUALITY-05, PERF-19 (moved to lower priority) |

### Implementation Order

1. **Startup path optimization** (run once per invocation):
   - TASK-1: Fix DATE_TAG + BUG-02
   - TASK-2: Fix STARTED_AT/DEADLINE_ISO dates
   - TASK-5: Consolidate readlink
   - TASK-9: Replace package.json awk

2. **Loop-iteration optimization** (run per iteration):
   - TASK-3: Inline calculate_score
   - TASK-7: Pre-store awk constant
   - TASK-8: Replace changelog awk
   - TASK-11: Cache prompt template

3. **Error handling + code hygiene**:
   - TASK-4: Remove dead functions
   - TASK-6: Fix echo -e security issue
   - TASK-10: Defer circuit-breaker update
   - TASK-12: Fix Makefile REQUIRED_REFS

### Performance Impact Summary

**Startup (one-time):**
- Eliminated forks: 6–8 (date calls, readlink, package.json awk)
- Estimated savings: ~10–20ms

**Per-loop iteration:**
- Eliminated forks: 2–3 (calculate_score subshell, changelog awk, parse awk on empty files)
- Estimated savings: ~3–8ms per loop (5 loops = 15–40ms total)

**Code quality:**
- Removed dead code: ~31 lines
- Security hardening: 1 escape injection vulnerability closed
- Accuracy: Fixed date consistency bug

**Risk profile:**
- All 12 tasks: LOW risk
- All use well-established bash idioms (printf builtin, parameter expansion, arithmetic)
- Backward compatible with bash 4.2+ (script already requires bash 5.0+ features)

---

**Generated:** 2026-03-20 | **Plan Status:** READY FOR IMPLEMENTATION
