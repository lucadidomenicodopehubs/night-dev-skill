# Night Dev Audit — 2026-03-20

Focus: **PERFORMANCE** (80%) | Other (20%)

---

## Performance Findings

### PERF-01: Repeated jq read-modify-write on status.json (HIGH)
- **File:** `scripts/night-dev.sh`, lines 769-808
- **Description:** `update_status()`, `update_status_nested()`, `update_score()`, and `append_score_history()` each spawn a separate `jq` process that reads status.json, transforms it, writes to a temp file, and renames. In a single loop iteration, status.json is read+written 4-6 times (phase update line 901, score updates lines 998-1003, stats update line 1047). Each invocation forks a subprocess, reads the full file, parses JSON, writes output, and does an `mv`.
- **Impact:** 4-6 jq forks per loop iteration, each with file I/O. With 5 loops that is 20-30 unnecessary subprocess spawns.
- **Suggested fix:** Batch all status updates into a single jq invocation per loop. Build a compound jq expression that sets phase, scores, stats, and history in one pass. Alternatively, accumulate updates in shell variables and flush once at end of loop.

### PERF-02: Repeated `${EPOCHSECONDS:-$(date +%s)}` pattern (MEDIUM)
- **File:** `scripts/night-dev.sh`, lines 636, 865, 959
- **Description:** Each occurrence of `$(date +%s)` forks a subprocess. On bash 5+, `$EPOCHSECONDS` is a builtin and the command substitution is skipped. However, the pattern `${EPOCHSECONDS:-$(date +%s)}` still evaluates the `$(...)` on older bash even when EPOCHSECONDS is set due to how the shell parses command substitutions. The fork happens at parse time, not evaluation time.
- **Impact:** Actually low on bash 5+ since most modern systems have EPOCHSECONDS. On bash 4.x, 3 unnecessary date forks per loop.
- **Suggested fix:** Check once at startup whether EPOCHSECONDS is available and set a function or alias: `get_time() { echo "${EPOCHSECONDS:-$(date +%s)}"; }` — or just detect bash version and skip the fallback.
- **Note:** After investigation, bash does NOT evaluate the command substitution in `${var:-$(cmd)}` when `var` is set. The current pattern is actually correct and efficient on bash 5+. Downgrading severity.

### PERF-03: `git -C "$PROJECT_PATH" status --porcelain` in check_dirty_state uses subshell capture (LOW)
- **File:** `scripts/night-dev.sh`, line 244
- **Description:** `[[ -n "$(git -C ... status --porcelain)" ]]` captures all output into a string just to check if it's non-empty. For large repos with many untracked files, this buffers everything.
- **Suggested fix:** Use `git -C "$PROJECT_PATH" diff --quiet HEAD && git -C "$PROJECT_PATH" diff --cached --quiet HEAD` which exits non-zero if there are changes, no output capture needed. Or pipe to `read` which returns on first byte.

### PERF-04: detect_test_runner performs sequential file checks (LOW)
- **File:** `scripts/night-dev.sh`, lines 250-317
- **Description:** The function checks for pytest.ini, pyproject.toml (with grep), setup.cfg (with grep), tox.ini, package.json (with awk), Cargo.toml, Makefile (with grep), and finally runs `find` for Go test files. Each check is sequential with early return, which is fine. However, the `find` for Go test files (line 303) can be expensive: `find "$project" -maxdepth 5 -name '*_test.go'` traverses the tree even though `compgen -G` already checked the root.
- **Impact:** Only reached if no other runner matches. Low in practice.
- **Suggested fix:** The `compgen` check is good. The `find` fallback could use `-quit` (already does) so impact is minimal. No change needed.

### PERF-05: awk spawned for float comparison instead of bash arithmetic (MEDIUM)
- **File:** `scripts/night-dev.sh`, line 1007
- **Description:** `improved=$(awk -v cur="$current_score" -v prev="$PREVIOUS_SCORE" 'BEGIN { print (cur > prev) ? "yes" : "no" }')` forks an awk process just to compare two decimal numbers. This runs every loop iteration.
- **Suggested fix:** Split on `.` and compare integer parts, then fractional parts using pure bash: `IFS=. read -r ci cf <<< "$current_score"; IFS=. read -r pi pf <<< "$PREVIOUS_SCORE"; if (( ci > pi || (ci == pi && cf > pf) )); then improved=yes; else improved=no; fi`

### PERF-06: parse_test_results spawns 4 separate awk processes (MEDIUM)
- **File:** `scripts/night-dev.sh`, lines 357-429
- **Description:** The function runs 4 sequential awk invocations on the same `$content` string: pytest parsing (line 371), jest parsing (line 382), cargo parsing (line 394), coverage extraction (line 406), and time extraction (line 418). Each forks a subprocess and re-parses the content.
- **Impact:** 4-5 awk forks per call. Called once per loop iteration.
- **Suggested fix:** Combine all parsing into a single awk script that tries all patterns in one pass and outputs all extracted values at once.

### PERF-07: Changelog parsed twice with awk (LOW)
- **File:** `scripts/night-dev.sh`, lines 886-891 and 1020-1027
- **Description:** In the early-exit check (line 886-891), the previous changelog is read and parsed with awk. Then in the current loop (line 1020-1027), the current changelog is parsed with a nearly identical awk script. The previous changelog parse could reuse cached results from the prior loop iteration.
- **Impact:** One extra awk fork per loop after loop 1. Minor.
- **Suggested fix:** Cache the parsed counts from each loop's changelog parse and reuse them in the next iteration's early-exit check, avoiding the second awk.

### PERF-08: `git clone --local --no-hardlinks` for backup is heavyweight (MEDIUM)
- **File:** `scripts/night-dev.sh`, lines 647-649
- **Description:** The pre-run backup uses `git stash`, `git clone --local --no-hardlinks`, then `git stash pop`. This creates a full copy of the entire repository including all objects. For large repos, this is expensive in both time and disk space. The `--no-hardlinks` flag explicitly forces copying instead of hardlinking, doubling disk usage unnecessarily.
- **Suggested fix:** Remove `--no-hardlinks` to allow git to hardlink objects (safe since objects are immutable). Or use `git bundle create` for a more compact backup. Or simply create a lightweight tag/ref as a restore point instead of a full clone.

### PERF-09: Multiple jq calls in status initialization (LOW)
- **File:** `scripts/night-dev.sh`, lines 675-724
- **Description:** The initial `jq -n` call to create status.json is a single invocation, which is efficient. However, it happens after the heavyweight `git clone` backup. No issue here — this is well-written.
- **Impact:** None. This is a positive finding.

### PERF-10: `date -Iseconds` called twice at initialization (LOW)
- **File:** `scripts/night-dev.sh`, lines 672-673
- **Description:** Two separate `date` forks for STARTED_AT and DEADLINE_ISO. Minor, happens once.
- **Suggested fix:** Could combine but not worth the complexity. Negligible impact.

---

## Other Findings (20% depth)

### SEC-01: Worktree .claude/settings.json grants unrestricted permissions (MEDIUM)
- **File:** `scripts/night-dev.sh`, lines 746-761
- **Description:** The auto-generated `.claude/settings.json` uses `Bash(*)`, `Write(*)`, `Read(*)` etc. with `defaultMode: auto`. This grants the Claude sub-agent unrestricted file system access within the worktree. While this is by design for an autonomous agent, it means any prompt injection in analyzed code could execute arbitrary commands.
- **Suggested fix:** Consider scoping Bash permissions to specific commands (test runner, git) rather than wildcard. At minimum, document this security trade-off.

### BUG-01: Negative remainder in calculate_score not fully handled (LOW)
- **File:** `scripts/night-dev.sh`, lines 348-353
- **Description:** When `score_x10` is negative, `score` is computed via integer division which truncates toward zero in bash. The remainder is then made positive via `if [[ $remainder -lt 0 ]]`. However, for `score_x10 = -15`, bash gives `score = -1` and `remainder = -5`, which becomes `1.5` — but the actual value should be `-1.5`. The logic produces `-1.5` which is correct. Actually, `score_x10 / 10 = -1` (bash truncates toward zero) and `score_x10 % 10 = -5`, abs = 5, so output is `-1.5`. The mathematically correct answer for -15/10 is -1.5, so this works. No bug here upon deeper inspection.

### QUALITY-01: Inline mode polling loop lacks backoff (LOW)
- **File:** `scripts/night-dev.sh`, lines 955-964
- **Description:** The inline mode waiting loop polls every 5 seconds with `sleep 5`. For long-running operations, an exponential backoff would reduce unnecessary wake-ups. Minor impact.

### QUALITY-02: Follow mode find search spans two directories without filtering (LOW)
- **File:** `scripts/night-dev.sh`, line 490
- **Description:** `find "$search_path" "$HOME/night-dev-repos" -maxdepth 4 -name "status.json" ...` searches both the provided path and the night-dev-repos directory. If search_path is under HOME, there could be duplicate results. The "pick the most recent one" logic (line 498) just takes `[0]` which is arbitrary ordering from find, not actually the most recent.
- **Suggested fix:** Sort by modification time or parse timestamps from the JSON.

---

## Summary

| Category | Critical | High | Medium | Low |
|----------|----------|------|--------|-----|
| Performance | 0 | 1 | 3 | 4 |
| Security | 0 | 0 | 1 | 0 |
| Bugs | 0 | 0 | 0 | 0 |
| Quality | 0 | 0 | 0 | 2 |
| **Total** | **0** | **1** | **4** | **6** |

### Top 3 Actionable Items (by impact):
1. **PERF-01** (HIGH): Batch jq status.json updates — eliminate 20-30 subprocess forks across a 5-loop run
2. **PERF-06** (MEDIUM): Merge parse_test_results awk calls — eliminate 3-4 forks per loop
3. **PERF-08** (MEDIUM): Remove `--no-hardlinks` from backup clone — halve backup disk usage and time
