# Night Shift Task Plan — Loop 3 (Validated)

Focus: **PERFORMANCE** (remaining optimizations after 18 tasks in loops 1-2)

## Risk Gate Results

- **5 APPROVED** (safe for automated implementation)
- **3 SKIPPED** (low impact, large diff, or cosmetic)
- **0 URGENT**

---

## Ordered Task List

### TASK-1: Replace grep forks in detect_test_runner for pyproject.toml/setup.cfg (PERF-20)
- **Category**: performance
- **Description**: Replace `grep -q` calls with bash `$(<file)` + glob pattern matching, eliminating 2 potential grep forks at startup
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**: `make test` passes; detect_test_runner still correctly identifies pytest
- **Estimated complexity**: small
- **Verdict**: APPROVED

### TASK-2: Replace grep in Makefile test target detection (PERF-21)
- **Category**: performance
- **Description**: Replace `grep -qE '^test[[:space:]]*:'` with bash while-read + regex matching
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**: `make test` passes; Makefile test runner detection still works
- **Estimated complexity**: small
- **Verdict**: APPROVED

### TASK-3: Replace find|grep with find|read in Go test detection (PERF-22)
- **Category**: performance
- **Description**: Replace `find ... | grep -q .` with `find ... | read -r _` to eliminate 1 grep fork
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**: `make test` passes
- **Estimated complexity**: small
- **Verdict**: APPROVED

### TASK-4: Remove redundant git stash/pop around backup clone (PERF-23)
- **Category**: performance
- **Description**: Remove `git stash` and `git stash pop` calls that are no-ops since check_dirty_state guarantees a clean worktree
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**: `make test` passes; backup still created correctly
- **Estimated complexity**: small
- **Verdict**: APPROVED

### TASK-5: Remove dead calculate_score function (QUALITY-06)
- **Category**: quality
- **Description**: Remove the `calculate_score` function (lines 368-388) that was inlined in loop 2 and has no remaining callers
- **Files**: `scripts/night-dev.sh`
- **Risk level**: low
- **Verification**: `make test` passes; `grep -n calculate_score scripts/night-dev.sh` shows no call sites
- **Estimated complexity**: small
- **Verdict**: APPROVED

---

## Skipped

### SKIPPED: PERF-24 — echo -e to printf migration
- **Reason**: Large diff (~30 lines changed), low practical impact. echo -e works correctly in bash. Deferred as cosmetic.

### SKIPPED: QUALITY-05 — Magic number 20 in follow mode fallback
- **Reason**: Cosmetic. The fallback loop is an edge case. Deferred from loops 1-2 for the same reason.

### SKIPPED: QUALITY-07 — Document SKILL.md keyword coupling
- **Reason**: Comment-only change with no functional impact. Low priority.

---

## Batch Strategy

All 5 tasks modify `scripts/night-dev.sh`. Tasks 1-3 modify the same function (`detect_test_runner`) and should be in the same batch. Task 4 modifies `main()` backup section. Task 5 removes a function definition.

**Batch 1**: TASK-1, TASK-2, TASK-3 (all in detect_test_runner — related but non-overlapping lines)
**Batch 2**: TASK-4, TASK-5 (different sections of the file)

Since all tasks touch the same file, sequential batching is safer.

**Recommended**: Single batch with all 5 tasks (all are small, low-risk, and modify different sections).

---

## Performance Impact Summary

**Startup:**
- Eliminated forks: 2-4 (grep in pyproject/setup.cfg, grep in Makefile, grep in Go detection, git stash/pop)
- Estimated savings: ~5-15ms

**Code quality:**
- Removed dead code: ~20 lines (calculate_score function)
- Consistent pattern: all detect_test_runner checks now use bash builtins

**Total across all 3 loops: ~24 tasks applied, eliminating ~30-40 subprocess forks**
