# Night Shift Research — Loop 1

## Summary
- Findings researched: 4 of 4 requested
- External references found: 0 (WebSearch unavailable — all findings use internal knowledge)

---

## Finding 1: PERF-01 — Batch multiple jq calls into one compound expression
**Category:** performance
**Search queries used:** "jq batch multiple updates single invocation compound expression best practice" (WebSearch unavailable)

### Solution (recommended)
- **Source:** internal knowledge (jq manual: pipe operator and multiple updates)
- **Reliability:** high — standard jq idiom, well-documented in jq manual
- **Implementation approach:**

The loop body currently makes 3 separate jq read-write cycles per iteration (lines 901, 1002, 1003, and 1047). Merge them into a single jq call at the end of each loop iteration.

Replace the three separate calls (`update_score`, `append_score_history`, and the stats batch) with one unified call:

```bash
# Single jq call per loop — replaces update_score + append_score_history + stats update
if [[ "$HAS_JQ" == "true" ]]; then
  local tmp="${ND_DIR}/status.tmp.json"
  jq \
    --argjson cp "$cur_passing" --argjson cf "$cur_failing" --argjson ct "$cur_total" \
    --argjson cc "$cur_coverage" --argjson cts "$cur_time_s" --arg cs "$current_score" \
    --argjson cl "$CURRENT_LOOP" \
    --argjson a "$APPLIED" --argjson s "$SKIPPED" \
    --argjson r "$REVERTED" --argjson e "$ESCALATED" \
    --argjson cz "$CONSECUTIVE_ZERO" \
    --arg ph "LOOP $CURRENT_LOOP — SCORING" \
    '
    .phase = $ph |
    .current_tests = {passing: $cp, failing: $cf, total: $ct, coverage: $cc, time_s: $cts, score: $cs} |
    .score_history += [{loop: $cl, score: $cs}] |
    .stats.total_applied += $a |
    .stats.total_skipped += $s |
    .stats.total_reverted += $r |
    .stats.total_escalated += $e |
    .stats.consecutive_zero_applied = $cz
    ' "$ND_DIR/status.json" > "$tmp" && mv "$tmp" "$ND_DIR/status.json"
fi
```

Key jq principle: the `|` operator pipes the result of one filter to the next, so chaining `.field = $val | .other = $val2` applies all mutations in a single process. This eliminates 2-3 subprocess forks and 2-3 file read-write cycles per loop iteration (10-15 total across 5 loops).

The phase update at line 901 should remain separate since it runs before the Claude agent invocation (it signals "RUNNING CLAUDE" to the follow mode).

---

## Finding 2: PERF-05 — Pure bash float comparison without awk
**Category:** performance
**Search queries used:** "bash pure float comparison without awk decimal number compare" (WebSearch unavailable)

### Solution (recommended)
- **Source:** internal knowledge (bash string manipulation and integer arithmetic)
- **Reliability:** high — standard bash technique, no external dependencies
- **Implementation approach:**

Replace line 1007:
```bash
improved=$(awk -v cur="$current_score" -v prev="$PREVIOUS_SCORE" 'BEGIN { print (cur > prev) ? "yes" : "no" }')
```

With pure bash using integer-scaled comparison. The scores are in `X.Y` format (one decimal place, as produced by `calculate_score`). Split on `.` and compare as scaled integers:

```bash
# Pure bash float comparison — no subprocess fork
local cur_int="${current_score%%.*}" cur_frac="${current_score#*.}"
local prev_int="${PREVIOUS_SCORE%%.*}" prev_frac="${PREVIOUS_SCORE#*.}"
# Handle whole numbers with no decimal point
[[ "$cur_int" == "$current_score" ]] && cur_frac=0
[[ "$prev_int" == "$PREVIOUS_SCORE" ]] && prev_frac=0
# Pad fractions to single digit (scores use 1 decimal place)
local cur_scaled=$(( cur_int * 10 + ${cur_frac:0:1} ))
local prev_scaled=$(( prev_int * 10 + ${prev_frac:0:1} ))
# Handle negative scores: bash integer math handles sign correctly since
# the integer part carries the sign (-1 * 10 + 5 = -5 vs -2 * 10 + 3 = -17)
# Actually for negatives we need: -1.5 -> -(1*10+5) = -15
if [[ "$current_score" == -* ]]; then
  cur_scaled=$(( cur_int * 10 - ${cur_frac:0:1} ))
fi
if [[ "$PREVIOUS_SCORE" == -* ]]; then
  prev_scaled=$(( prev_int * 10 - ${prev_frac:0:1} ))
fi
if (( cur_scaled > prev_scaled )); then
  improved=yes
else
  improved=no
fi
```

Simpler alternative (since scores are always non-negative in practice — `calculate_score` clamps output):

```bash
local cur_scaled=$(( ${current_score%%.*} * 10 + ${current_score#*.} ))
local prev_scaled=$(( ${PREVIOUS_SCORE%%.*} * 10 + ${PREVIOUS_SCORE#*.} ))
[[ $cur_scaled -gt $prev_scaled ]] && improved=yes || improved=no
```

This eliminates 1 awk subprocess fork per loop iteration.

---

## Finding 3: PERF-06 — Combine multiple awk pattern-matching passes into single script
**Category:** performance
**Search queries used:** "combine multiple awk passes into single awk script multiple patterns one pass" (WebSearch unavailable)

### Solution (recommended)
- **Source:** internal knowledge (awk programming — multi-pattern single-pass processing)
- **Reliability:** high — fundamental awk design pattern
- **Implementation approach:**

Replace the 4-5 sequential awk calls in `parse_test_results()` (lines 371, 382, 394, 406, 418) with a single awk invocation that tries all patterns in one pass and outputs all values on one line:

```bash
parse_test_results() {
    local test_output_file="$1"
    if [[ ! -f "$test_output_file" ]]; then
        echo "0 0 0 0 0"
        return
    fi

    local result
    result=$(awk '
    # pytest-style: "X passed, Y failed"
    /passed/ { for(i=1;i<=NF;i++) if($(i+1)=="passed") pytest_p=$i }
    /failed/ { for(i=1;i<=NF;i++) if($(i+1)=="failed") pytest_f=$i }

    # jest/vitest-style: "Tests: X passed, Y failed, Z total"
    /Tests:.*passed/ {
        for(i=1;i<=NF;i++) {
            if($(i+1)=="passed,") jest_p=$i
            if($(i+1)=="failed,") jest_f=$i
            if($(i+1)=="total") jest_t=$i
        }
    }

    # cargo test: "test result: ok. X passed; Y failed"
    /test result:/ {
        for(i=1;i<=NF;i++) {
            if($(i+1)=="passed;") cargo_p=$i
            if($(i+1)~/^failed/) cargo_f=$i
        }
    }

    # Coverage: line containing a percentage and "cover"
    /[0-9]+(\.[0-9]+)?%/ && /[Cc]over/ {
        match($0, /([0-9]+(\.[0-9]+)?)%/, arr)
        if (arr[1]+0 > 0) cov=arr[1]
    }

    # Duration: line with seconds and time-related keyword
    /[0-9]+(\.[0-9]+)?s/ && /[Tt]ime|[Dd]uration|[Ff]inished|[Rr]an/ {
        match($0, /([0-9]+(\.[0-9]+)?)s/, arr)
        if (arr[1]+0 > 0) dur=arr[1]
    }

    END {
        # Priority: pytest > jest > cargo
        p=0; f=0; t=0
        if (pytest_p+0 > 0 || pytest_f+0 > 0) {
            p=pytest_p+0; f=pytest_f+0; t=p+f
        } else if (jest_p+0 > 0 || jest_f+0 > 0) {
            p=jest_p+0; f=jest_f+0; t=(jest_t+0 > 0) ? jest_t+0 : p+f
        } else if (cargo_p+0 > 0 || cargo_f+0 > 0) {
            p=cargo_p+0; f=cargo_f+0; t=p+f
        }
        printf "%d %d %d %d %d\n", p, f, t, int(cov+0), int(dur+0)
    }
    ' < "$test_output_file")

    echo "${result:-0 0 0 0 0}"
}
```

This reduces 4-5 awk forks to 1 per call. The file is read once instead of 4-5 times. The END block applies the same priority logic (pytest > jest > cargo) as the original sequential early-return pattern.

Note: coverage and duration are extracted in the same pass regardless of which test framework matched, which matches the original behavior.

---

## Finding 4: PERF-08 — git clone --local hardlinks vs --no-hardlinks safety
**Category:** performance
**Search queries used:** "git clone --local hardlinks vs --no-hardlinks safety immutable objects" (WebSearch unavailable)

### Solution (recommended)
- **Source:** internal knowledge (git-clone documentation, git object model)
- **Reliability:** high — well-documented git behavior
- **Implementation approach:**

**Background:** When `git clone --local` is used without `--no-hardlinks`, git hardlinks the object files in `.git/objects/` instead of copying them. Git objects are immutable by design — once written, they are never modified (only new objects are created, and `git gc` / `git repack` may delete or consolidate them). This makes hardlinks safe for backup purposes.

**The concern with hardlinks:** If `git gc` or `git repack` runs on the source repo, it can delete loose objects that were packed into a packfile. The hardlinked copy would then have dangling links. However, for a short-lived backup (the backup exists only during the night-dev run), this risk is negligible.

**Recommended change on line 648:**

```bash
# Before (forces full copy — doubles disk usage):
git -C "$PROJECT_PATH" clone --local --no-hardlinks "$PROJECT_PATH" "$BACKUP_DIR" 2>/dev/null

# After (allows hardlinks — halves disk usage, faster):
git -C "$PROJECT_PATH" clone --local "$PROJECT_PATH" "$BACKUP_DIR" 2>/dev/null
```

Simply remove `--no-hardlinks`. The `--local` flag already implies hardlinking on the same filesystem; removing `--no-hardlinks` allows that default behavior.

**Alternative — lighter-weight backup:** For even better performance, replace the full clone with `git bundle`:

```bash
git -C "$PROJECT_PATH" bundle create "$BACKUP_DIR.bundle" --all 2>/dev/null
```

This creates a single file containing the full repo history, which is more compact and faster than cloning. To restore: `git clone "$BACKUP_DIR.bundle" "$PROJECT_PATH"`.

**Simplest alternative — ref-based restore point:**

```bash
git -C "$PROJECT_PATH" tag "night-dev-backup-${DATE_TAG}" HEAD 2>/dev/null
```

This creates a lightweight tag as a restore point with zero disk overhead. It does not back up uncommitted changes though, so it should be combined with the existing stash approach. This is the fastest option but provides the least protection (no backup of untracked files not captured by stash).

**Recommendation:** Remove `--no-hardlinks` as the minimal safe change. The backup is short-lived (duration of the night-dev run), and git object immutability makes hardlinks safe for this use case.
