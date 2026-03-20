# Night Shift Plan — Loop 1 (Performance Focus)

Total tasks: 6 (approved: 6, skipped: 4, urgent: 0)

---

## TASK-1
- **Category:** performance
- **Description:** Batch multiple jq status.json read-modify-write calls into a single compound jq expression per loop iteration. Merge `update_score()`, `append_score_history()`, and stats updates (phase, test results, stats counters) into one jq invocation. This eliminates 3-4 subprocess forks and 3-4 file I/O cycles per loop.
- **Files:** scripts/night-dev.sh
- **Risk level:** medium
- **Verification:** Run the script through a full night-dev cycle (5 loops) with `strace -c` to verify subprocess count is reduced by ~20 forks. Verify output status.json has correct phase, scores, history, and stats.
- **Estimated complexity:** medium
- **Verdict:** APPROVED

---

## TASK-2
- **Category:** performance
- **Description:** Replace awk float comparison on line 1007 with pure bash arithmetic. Split current_score and PREVIOUS_SCORE on decimal point and compare as scaled integers. Eliminates 1 awk fork per loop iteration.
- **Files:** scripts/night-dev.sh
- **Risk level:** low
- **Verification:** Run night-dev cycle and verify `improved` variable is set correctly (should be "yes" if current_score > PREVIOUS_SCORE). Check edge cases: negative scores, whole numbers, scores with trailing zeros.
- **Estimated complexity:** small
- **Verdict:** APPROVED

---

## TASK-3
- **Category:** performance
- **Description:** Merge 4-5 sequential awk invocations in `parse_test_results()` (lines 357-429) into a single awk script that parses pytest, jest, cargo, coverage, and duration patterns in one pass. Output all values on a single line to be split by the caller.
- **Files:** scripts/night-dev.sh
- **Risk level:** medium
- **Verification:** Run test suite for each supported test framework (pytest, jest, cargo) and verify parse_test_results returns correct {passing, failing, total, coverage, time_s} tuples. Compare output before/after on same test logs.
- **Estimated complexity:** medium
- **Verdict:** APPROVED

---

## TASK-4
- **Category:** performance
- **Description:** Optimize `check_dirty_state()` (line 244) to avoid buffering full git output into a variable. Replace `[[ -n "$(git ... status --porcelain)" ]]` with `git diff --quiet HEAD && git diff --cached --quiet HEAD` or pipe output to `read` to detect changes on first byte without full capture.
- **Files:** scripts/night-dev.sh
- **Risk level:** low
- **Verification:** Run night-dev on a repo with various dirty states: staged changes, unstaged changes, untracked files, clean repo. Verify early-exit logic triggers correctly.
- **Estimated complexity:** small
- **Verdict:** APPROVED

---

## TASK-5
- **Category:** performance
- **Description:** Remove `--no-hardlinks` flag from git clone backup command (line 648). Git objects are immutable; hardlinks are safe for the short-lived backup window. This halves backup disk usage and speeds up the backup operation.
- **Files:** scripts/night-dev.sh
- **Risk level:** low
- **Verification:** Run pre-run backup sequence and verify the backup directory is created successfully. Check disk usage is reduced compared to before. Verify backup can be restored correctly if needed.
- **Estimated complexity:** small
- **Verdict:** APPROVED

---

## TASK-6
- **Category:** performance
- **Description:** Cache parsed changelog test counts between loop iterations. Store the result of changelog parse (line 1020-1027) in a variable, then reuse it in the early-exit check (line 886-891) of the next iteration instead of re-parsing. Eliminates 1 awk fork per loop after loop 1.
- **Files:** scripts/night-dev.sh
- **Risk level:** low
- **Verification:** Add debug logging to confirm changelog is parsed once per iteration and cached value is reused in early-exit check. Run multi-loop cycle and verify score improvement/stagnation detection works correctly.
- **Estimated complexity:** small
- **Verdict:** APPROVED

---

## SKIPPED TASKS

### PERF-02 (SKIPPED)
- **Reason:** Already efficient on bash 5+ (majority of modern systems). EPOCHSECONDS builtin prevents command substitution evaluation. Low priority for optimization.

### PERF-04 (SKIPPED)
- **Reason:** detect_test_runner sequential file checks are fine. The `find` fallback for Go already uses `-quit` flag. No performance impact in practice.

### SEC-01 (SKIPPED)
- **Reason:** Architectural decision (autonomous agent permissions in .claude/settings.json). Scoping permissions requires human review of security implications and design intent. Escalate to maintainer decision.

### QUALITY-01, QUALITY-02 (SKIPPED)
- **Reason:** Low impact, not performance-related. Inline polling backoff and follow mode result sorting are out of scope for performance focus mode.

---

## Summary

**Performance focus achieved:** 6 of 6 approved tasks target performance improvements
**Total reduction in subprocess forks per cycle:** ~25-35 forks eliminated across 5 loops
**High-priority tasks:** TASK-1 (jq batching) is critical; addresses the highest-impact performance bottleneck
**Risk profile:** 5 low-risk, 1 medium-risk. No urgent or high-risk tasks requiring escalation.
**Estimated total effort:** 2-3 hours implementation + testing
