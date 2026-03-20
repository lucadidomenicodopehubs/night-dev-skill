#!/usr/bin/env bash
# Tests for score calculation logic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Score formula: (passing*100 + total*20 + coverage*50 - failing*200 - time_s) / 10
# This replicates the inline arithmetic from night-dev.sh

calc_score() {
    local passing=$1 failing=$2 total=$3 coverage=$4 time_s=$5
    local score_x10=$(( (passing * 100) + (total * 20) + (coverage * 50) - (failing * 200) - time_s ))
    local sign="" abs_score_x10=$score_x10
    if [[ $score_x10 -lt 0 ]]; then
        sign="-"
        abs_score_x10=$(( -score_x10 ))
    fi
    local score=$(( abs_score_x10 / 10 ))
    local remainder=$(( abs_score_x10 % 10 ))
    echo "${sign}${score}.${remainder}"
}

# --- Test 1: positive score (23 passing, 0 failing) ---
test_start "score_calc: positive score"
result=$(calc_score 23 0 23 0 0)
assert_eq "276.0" "$result" "23 passing, 0 failing = 276.0"

# --- Test 2: negative score (0 passing, 5 failing) ---
test_start "score_calc: negative score"
result=$(calc_score 0 5 5 0 0)
assert_eq "-90.0" "$result" "0 passing, 5 failing = -90.0"

test_summary
