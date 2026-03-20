# Night Dev Audit — Loop 3 (Incremental)

**Focus:** PERFORMANCE (80%), plus remaining QUALITY/BUG items
**Baseline:** All tests passing. Loops 1-2 applied 18 optimizations.

---

## Findings

1. **PERF-20 [medium]** `scripts/night-dev.sh:257-263` — `grep -q` calls in `detect_test_runner` for pyproject.toml and setup.cfg each fork a subprocess. **Fix:** Replace with bash `while read` loop + `[[ "$line" == *pattern* ]]` or `read` the file into a variable and use `[[ "$var" == *pattern* ]]` for these small config files, consistent with the package.json approach already used.

2. **PERF-21 [medium]** `scripts/night-dev.sh:294` — `grep -qE` call for Makefile test target detection forks a subprocess. **Fix:** Replace with `while IFS= read -r line; do [[ "$line" =~ ^test[[:space:]]*: ]] && ...; done < "$project/Makefile"` to use bash regex matching instead.

3. **PERF-22 [medium]** `scripts/night-dev.sh:300` — Go test detection uses `compgen -G` (fine) but falls back to `find ... | grep -q .` which forks two subprocesses. **Fix:** Use `[[ -n "$(find ...)" ]]` or better yet, replace the entire find+grep pipeline with a bash glob: `shopt -s globstar; compgen -G "$project"/**/*_test.go` (then restore shopt). Alternatively, keep find but drop the grep pipe: `find "$project" -maxdepth 5 -name '*_test.go' -print -quit 2>/dev/null | read -r _`.

4. **PERF-23 [low]** `scripts/night-dev.sh:622-624` — `git stash` + `git clone --local` + `git stash pop` creates a backup by stashing, cloning, and popping. This is three git subprocess calls. On a clean worktree (enforced by `check_dirty_state` on line 240), the stash/pop are no-ops. **Fix:** Remove the `git stash` and `git stash pop` calls since `check_dirty_state` already guarantees a clean worktree, saving two subprocess forks.

5. **PERF-24 [low]** `scripts/night-dev.sh:73,90,94,101,104,111` — Multiple `echo -e` calls in `resolve_project_path` could be `printf '%b\n'` for portability consistency. Same pattern in `validate_numeric_arg` (line 119,123), `parse_args` (lines 138,154,183,192,207,217), `check_git_repo` (233), `check_dirty_state` (240), `detect_test_runner` (306-312), `check_claude_cli` (318), `check_jq` (327). **Fix:** Replace `echo -e` with `printf '%b\n'` throughout for consistent portability. This is low-severity since bash `echo -e` works fine, but printf is POSIX-guaranteed.

6. **QUALITY-06 [low]** `scripts/night-dev.sh:371-388` — `calculate_score` function is still defined but never called. It was inlined at line 944 in loop 2 (PERF-13). **Fix:** Remove the dead `calculate_score` function (lines 371-388) and its comment block (lines 369-370).

7. **QUALITY-07 [low]** `scripts/night-dev.sh:976-981` — Changelog patterns match Italian keywords (APPLICATA, SKIPPATA, REVERTITA) which appear to be SKILL.md conventions. If SKILL.md changes these keywords, parsing silently breaks. **Fix:** No code change needed, but document the coupling in a comment so future maintainers know that SKILL.md keyword changes require updating these patterns.

8. **QUALITY-05 [low]** `scripts/night-dev.sh:514` — Magic number 20 in follow mode fallback loop (`for ((i=20; i>=1; i--))`). **Fix:** Replace `20` with `$MAX_LOOPS` or a named constant. (Deferred from previous loops; still present.)

---

## Summary

| Category    | Critical | High | Medium | Low |
|-------------|----------|------|--------|-----|
| PERFORMANCE | 0        | 0    | 3      | 2   |
| QUALITY     | 0        | 0    | 0      | 3   |
| **Total**   | 0        | 0    | 3      | 5   |

### Recommended for implementation (medium severity):
- **PERF-20**: Replace grep in pyproject.toml/setup.cfg detection with bash pattern matching
- **PERF-21**: Replace grep in Makefile test target detection with bash regex
- **PERF-22**: Replace find|grep pipe in Go test detection with find|read

### Recommended for implementation (low severity, quick wins):
- **PERF-23**: Remove redundant git stash/pop around backup (clean tree guaranteed)
- **QUALITY-06**: Remove dead `calculate_score` function

### Defer:
- **PERF-24**: echo -e to printf migration (large diff, low impact)
- **QUALITY-05**: Magic number 20 (cosmetic)
- **QUALITY-07**: Document SKILL.md keyword coupling (cosmetic)
