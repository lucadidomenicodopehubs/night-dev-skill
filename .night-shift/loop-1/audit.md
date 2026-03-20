# Night Shift Audit — Loop 1

**Date:** 2026-03-20
**Project:** night-dev-skill (autonomous evolutionary development agent)
**Main file:** scripts/night-dev.sh (1045 lines)

---

## Metrics

- Tests: 27 passed, 0 failed, 2 skipped (29 total)
- Coverage: 0% (no coverage tooling for bash)
- Execution time: 0.049s
- Files: 10 source | LOC: 2593 | TODO/FIXME/HACK: 0 (in executable code)
- Score: 328.0
- Security audit tools: shellcheck not available; no package dependency audit applicable (pure bash, no external deps beyond git/jq)

---

## Issues Found

### SECURITY

#### SEC-01 [MEDIUM] scripts/night-dev.sh:712-727
**Worktree .claude/settings.json grants unrestricted wildcard permissions.**
The auto-generated settings file uses `Bash(*)`, `Write(*)`, `Read(*)` with `defaultMode: auto`. This means any prompt injection in analyzed source code could instruct the Claude sub-agent to execute arbitrary commands, read sensitive files, or modify files outside the worktree. While this is by design for an autonomous agent, the blast radius is unlimited.
**Fix:** Scope `Bash` permissions to specific commands: `Bash(make test)`, `Bash(git *)`, `Bash(cd *)`. Keep `Read(*)` and `Write(*)` scoped to the worktree path. At minimum, exclude `Bash(rm -rf *)`, `Bash(curl *)`, etc.

#### SEC-02 [LOW] scripts/night-dev.sh:96
**git clone of user-supplied URL without protocol validation.**
The `resolve_project_path` function validates the repo name against path traversal (`^[a-zA-Z0-9._-]+$`) but does not validate the full URL beyond checking it starts with `https://github.com/` or `git@github.com:`. A maliciously crafted URL like `https://github.com/user/repo --upload-pack='malicious-command'` is mitigated by the URL regex but the clone destination is constructed from the URL suffix, and shell expansion could theoretically interact poorly. Current mitigation (regex + quoting) is adequate but worth noting.
**Fix:** No immediate action needed. Current protections are sufficient.

---

### BUG

#### BUG-01 [MEDIUM] scripts/night-dev.sh:465
**Follow mode picks arbitrary worktree, not the most recent one.**
`follow_night_dev()` uses `find ... -print0` and takes `${worktrees[0]}` as "the most recent" worktree, but `find` output order is filesystem-dependent, not by modification time. If multiple Night Dev instances exist, the wrong one may be followed.
**Fix:** Sort the `worktrees` array by modification time of the status.json files, e.g., use `ls -t` on the found files or `stat --format='%Y'` to pick the newest.

#### BUG-02 [MEDIUM] scripts/night-dev.sh:936-940
**Score formatting produces incorrect result for negative scores with large fractional parts.**
The inline score arithmetic computes `score_x10`, then `current_score = score_x10 / 10` and `score_remainder = score_x10 % 10`. For `score_x10 = -3`, bash integer division gives `current_score = 0` and `score_remainder = -3`, which after abs becomes `0.3`. But the actual value is `-0.3`. The sign is lost when the integer part is zero.
**Fix:** Track the sign separately: `local sign=""; [[ $score_x10 -lt 0 ]] && sign="-" && score_x10=$(( -score_x10 ))`. Then format as `"${sign}${current_score}.${score_remainder}"`.

#### BUG-03 [LOW] scripts/night-dev.sh:951
**Score comparison does not handle negative scores correctly.**
The comparison `(ci * 10 + ${cf:-0}) > (pi * 10 + ${pf:-0})` treats the fractional part as always positive. For `-1.5` vs `-0.3`, it computes `(-1*10 + 5) = -5` vs `(0*10 + 3) = 3` (wrong -- `-0` loses the sign on the fractional part). This is unlikely in practice since scores are almost always positive, but edge cases exist.
**Fix:** Use the `score_x10` integer representation directly for comparison instead of splitting on `.`.

---

### INTENT

#### INTENT-01 [LOW] SKILL.md:125 vs scripts/night-dev.sh:936
**Scoring formula mismatch between SKILL.md and implementation.**
SKILL.md line 125 defines: `score = (tests_passing * 5) + (coverage_pct * 3) - (tests_failing * 20) - (execution_time_s * 0.1)` plus code_quality and architecture_quality components. The implementation at line 936 uses: `score = (tests_passing * 10) + (test_count * 2) + (coverage * 5) - (tests_failing * 20) - (time * 0.1)`. The multipliers differ (5 vs 10, 3 vs 5) and the implementation adds `test_count * 2` which is not in the SKILL.md formula. The reference prompts (analyze-prompt.md:256, implementation-prompt.md:68) use yet another version matching the implementation, not SKILL.md.
**Fix:** Synchronize the scoring formula across SKILL.md (lines 33-48) and the implementation. The SKILL.md has two different formulas: one at lines 33-48 (v2 multi-dimensional) and one at line 125 (simplified). Consolidate to a single authoritative formula.

---

### ARCHITECTURE

#### ARCH-01 [MEDIUM] scripts/night-dev.sh:735-741
**update_status() function creates a temp file and mv for every single field update.**
While the batched jq call at lines 1006-1027 is well-optimized, `update_status()` still exists and is called in `cleanup()` (lines 759, 773) with individual field updates. Each call does a full jq read-modify-write cycle. If cleanup is called during normal exit, this is 2 unnecessary jq forks.
**Fix:** Batch the cleanup updates into a single jq call, or inline the jq expression in the cleanup function.

#### ARCH-02 [LOW] scripts/night-dev.sh
**All functions and logic are in a single 1045-line file.**
The orchestrator, argument parsing, follow mode, test parsing, banner printing, and main loop are all in one file. This is acceptable for a bash script of this complexity, but the follow_night_dev() function (lines 447-580, 133 lines) and detect_test_runner() (lines 246-328, 82 lines) could be extracted to separate sourced files for maintainability.
**Fix:** Optional. Consider `source`-ing helper files for follow mode and test detection if the file grows beyond ~1200 lines.

#### ARCH-03 [LOW] scripts/night-dev.sh:346-396
**Awk script constant is stored as a string variable, making it hard to read and test.**
The `_PARSE_AWK_SCRIPT` is defined as a heredoc-style string constant at line 346. While this avoids repeated inline awk, the awk script itself is not independently testable.
**Fix:** Consider extracting to a separate `.awk` file that can be tested independently, though this adds a file dependency.

---

### PERFORMANCE

#### PERF-01 [HIGH] scripts/night-dev.sh:735-741
**update_status() still exists as individual jq read-modify-write, called in cleanup.**
Each call to `update_status()` forks jq, reads the full JSON, modifies one field, writes to temp, and renames. The main loop has been optimized with batched updates (line 1006-1027), but cleanup (lines 759, 773) still uses the per-field function.
**Fix:** Replace the two `update_status` calls in `cleanup()` with a single jq expression: `jq '.circuit_breaker = "OPEN" | .phase = "COMPLETED"'`.

#### PERF-02 [MEDIUM] scripts/night-dev.sh:283-293
**package.json parsing reads entire file line-by-line in bash.**
The `detect_test_runner` function reads `package.json` line-by-line with a `while IFS= read -r line` loop and uses bash pattern matching. For large package.json files (common in Node projects), this is slower than a single jq or grep call. Since jq availability is checked later (`check_jq`), this cannot use jq reliably at this point.
**Fix:** Use a simple `case` on the entire file content (already done for pyproject.toml and setup.cfg), rather than line-by-line: `local content; content=$(<"$project/package.json"); [[ "$content" == *'"test"'* ]] && [[ "$content" != *'no test specified'* ]]`.

#### PERF-03 [LOW] scripts/night-dev.sh:615
**git clone --local for backup copies entire repo.**
The backup creates a full local clone of the project. For large repos, this is expensive. The `--no-hardlinks` flag was previously removed (per project_intent.md), but a full clone is still heavier than necessary.
**Fix:** Consider using `git stash create` + `git tag` as a lightweight restore point, or `git bundle create` for a compact backup. However, the current approach is the safest.

---

### COST

No cost issues identified. The project uses appropriate model selection (haiku for simple tasks, default for complex) as documented in SKILL.md lines 69-76. Claude API cost optimization is well-designed.

---

### QUALITY

#### QUALITY-01 [MEDIUM] scripts/night-dev.sh:897-921
**Claude invocation error handling is too permissive.**
The Claude CLI invocation uses `|| true` (line 916, 919) to suppress all errors. If Claude fails to start, hits a rate limit, or crashes, the script continues with an empty or truncated log file. The subsequent score calculation parses whatever output exists, potentially computing a zero score that triggers stagnation detection incorrectly.
**Fix:** Check the Claude exit code and the size of `claude_output.log`. If the log is empty or Claude exited with a non-zero status, log a clear error and either retry or skip the loop instead of processing garbage output.

#### QUALITY-02 [MEDIUM] scripts/night-dev.sh:964-1003
**Changelog parsing pattern is fragile.**
The changelog parsing uses bash `case` patterns like `*[-\*]\ APPLICATA\ :*|*[-\*]\ APPLICATA:*` which must exactly match the markdown format produced by the report sub-agent. If the report agent produces slightly different formatting (e.g., extra space, different bullet character, bold markers), the counts will be zero, potentially triggering false circuit breaker or stagnation exits.
**Fix:** Use a more permissive pattern: `*APPLICATA*` as the primary match, with the structured patterns as refinements. Or parse the METRICHE section at the bottom of the changelog which has a more predictable format.

#### QUALITY-03 [LOW] scripts/night-dev.sh:899-908
**Inline mode polling loop uses fixed 5-second interval without backoff.**
The `while [[ ! -f "$LOOP_DIR/done" ]]; do sleep 5; done` loop polls at a constant 5-second interval regardless of how long the operation runs. For operations taking hours, this wastes resources.
**Fix:** Implement exponential backoff: start at 2s, double up to 60s max. `local wait=2; while ...; do sleep $wait; (( wait = wait < 60 ? wait * 2 : 60 )); done`.

#### QUALITY-04 [LOW] scripts/night-dev.sh:517-528
**Follow mode waiting loop also uses fixed 2-second polling without backoff.**
Same pattern as QUALITY-03 but with 2-second intervals while waiting for the first log file to appear.
**Fix:** Same exponential backoff approach.

#### QUALITY-05 [LOW] Makefile:77-83
**Test suite invokes `bash $(SCRIPT) --help` twice in test-help target.**
Lines 77 and 85 both run `bash $(SCRIPT) --help` and capture the output into `$$HELP`. The second invocation at line 85 is a separate shell command that re-runs the help. This is a minor inefficiency in the test suite (adds ~0.01s).
**Fix:** Combine both checks under a single `$$HELP` capture, or restructure as a single shell block.

#### QUALITY-06 [LOW] commands/night-dev.md
**Interactive setup guide is entirely in Italian without English alternative.**
The `commands/night-dev.md` file contains user-facing prompts in Italian (e.g., "Configuro il Night Dev", "Rispondi ok per confermare"). While this may be intentional for the target audience, it limits accessibility for non-Italian-speaking users.
**Fix:** Consider adding English translations alongside Italian, or making the language configurable.

---

## Summary

| Category | High | Medium | Low |
|----------|------|--------|-----|
| SECURITY | 0 | 1 | 1 |
| BUG | 0 | 2 | 1 |
| INTENT | 0 | 0 | 1 |
| ARCHITECTURE | 0 | 1 | 2 |
| PERFORMANCE | 1 | 1 | 1 |
| COST | 0 | 0 | 0 |
| QUALITY | 0 | 2 | 4 |
| **Total** | **1** | **7** | **10** |

### Top 5 Actionable Items (by impact):

1. **PERF-01** (HIGH): Batch cleanup jq calls into single invocation -- eliminate 2 jq forks in cleanup path
2. **BUG-02** (MEDIUM): Fix score formatting for negative scores with zero integer part -- sign loss bug
3. **QUALITY-01** (MEDIUM): Add Claude CLI error checking -- prevent false stagnation from failed invocations
4. **QUALITY-02** (MEDIUM): Make changelog parsing more resilient -- prevent false circuit breaker triggers
5. **SEC-01** (MEDIUM): Scope .claude/settings.json permissions -- reduce prompt injection blast radius
