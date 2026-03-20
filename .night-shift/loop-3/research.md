# Night Shift Research — Loop 3

Focus: Remaining bash performance optimizations. All patterns are well-established from loops 1-2.

---

## Issue 1: PERF-20 — Replace grep in pyproject.toml/setup.cfg detection

### Current code (lines 257-263)
```bash
if [[ -f "$project/pyproject.toml" ]] && grep -q '\[tool\.pytest' "$project/pyproject.toml" 2>/dev/null; then
if [[ -f "$project/setup.cfg" ]] && grep -q '\[tool:pytest\]' "$project/setup.cfg" 2>/dev/null; then
```

### Implementation
```bash
# pyproject.toml — read file content, use bash pattern matching
if [[ -f "$project/pyproject.toml" ]]; then
    local content
    content=$(<"$project/pyproject.toml")
    if [[ "$content" == *'[tool.pytest'* ]]; then
        DETECTED_RUNNER="pytest"
        return 0
    fi
fi

# setup.cfg — same pattern
if [[ -f "$project/setup.cfg" ]]; then
    local content
    content=$(<"$project/setup.cfg")
    if [[ "$content" == *'[tool:pytest]'* ]]; then
        DETECTED_RUNNER="pytest"
        return 0
    fi
fi
```

### Notes
- `$(<file)` is a bash builtin (no fork). The file read + glob match is faster than forking grep for small config files.
- For very large files (>1MB), grep would be more efficient, but pyproject.toml and setup.cfg are typically <10KB.
- Pattern `*'[tool.pytest'*` matches the literal string including the dot (glob `*` matches anything).

### Risk: LOW
Same pattern already used for package.json (PERF-18, loop 2).

---

## Issue 2: PERF-21 — Replace grep in Makefile test target detection

### Current code (line 294)
```bash
if [[ -f "$project/Makefile" ]] && grep -qE '^test[[:space:]]*:' "$project/Makefile" 2>/dev/null; then
```

### Implementation
```bash
if [[ -f "$project/Makefile" ]]; then
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^test[[:space:]]*: ]]; then
            DETECTED_RUNNER="make test"
            return 0
        fi
    done < "$project/Makefile"
fi
```

### Alternative (simpler, reads whole file)
```bash
if [[ -f "$project/Makefile" ]]; then
    local content
    content=$(<"$project/Makefile")
    # Multiline glob won't work for anchored patterns, use while-read
fi
```

Note: The `^` anchor requires line-by-line matching, so while-read is needed (glob can't anchor to line start in multiline strings).

### Risk: LOW

---

## Issue 3: PERF-22 — Replace find|grep in Go test detection

### Current code (line 300)
```bash
if compgen -G "$project"/*_test.go &>/dev/null || find "$project" -maxdepth 5 -name '*_test.go' -print -quit 2>/dev/null | grep -q .; then
```

### Implementation
```bash
if compgen -G "$project"/*_test.go &>/dev/null || \
   find "$project" -maxdepth 5 -name '*_test.go' -print -quit 2>/dev/null | read -r _; then
```

### Notes
- `| read -r _` replaces `| grep -q .` — both check for non-empty output, but `read` is a bash builtin (no fork).
- `find ... -print -quit` already exits after first match, so `read` just checks if any output was produced.
- Saves 1 grep fork when Go test detection reaches the find fallback.

### Risk: VERY LOW
Drop-in replacement. `read -r _` returns 0 if it reads at least one line, 1 if EOF (empty input).

---

## Issue 4: PERF-23 — Remove redundant git stash/pop

### Current code (lines 622-624)
```bash
git -C "$PROJECT_PATH" stash --include-untracked -m "night-dev-backup-${DATE_TAG}" 2>/dev/null || true
git -C "$PROJECT_PATH" clone --local "$PROJECT_PATH" "$BACKUP_DIR" 2>/dev/null
git -C "$PROJECT_PATH" stash pop 2>/dev/null || true
```

### Analysis
`check_dirty_state()` (line 239-243) already verifies the working tree is clean before reaching the backup section. The `git stash` is a no-op on a clean tree (it outputs "No local changes to save" and exits 1, caught by `|| true`). The `git stash pop` is similarly a no-op.

### Implementation
```bash
git -C "$PROJECT_PATH" clone --local "$PROJECT_PATH" "$BACKUP_DIR" 2>/dev/null
```

Simply remove the stash and pop lines. The clone of a clean working tree produces identical results.

### Risk: LOW
The clean state is guaranteed by check_dirty_state. If someone bypasses the check (e.g., modifying the script), the backup would miss uncommitted changes — but this was already the case since the stash/pop was around the clone, not affecting the clone's content.

---

## Issue 5: QUALITY-06 — Remove dead calculate_score function

### Current code (lines 368-388)
```bash
# --- Score Calculation ---
# Calculate evolutionary score from test results
# Formula: score = (passing * 10) + (total * 2) + (coverage * 5) - (failing * 20) - (time_s * 0.1)
calculate_score() {
    ...
}
```

### Analysis
The function was inlined at line 944 in loop 2 (PERF-13). No call sites remain.

Verification:
```bash
grep -n "calculate_score" scripts/night-dev.sh
# Should only show the function definition, no calls
```

### Implementation
Remove lines 368-388 (function definition + comments).

### Risk: VERY LOW
Dead code removal. Same pattern as QUALITY-03 (loop 2).
