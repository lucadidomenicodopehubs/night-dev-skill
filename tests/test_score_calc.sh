#!/usr/bin/env bash
# Tests for score calculation logic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: positive score (23 passing, 0 failing) ---
test_start "score_calc: positive score"
calculate_score 23 0 23 0 0
assert_eq "276.0" "$_CALC_SCORE" "23 passing, 0 failing = 276.0"

# --- Test 2: negative score (0 passing, 5 failing) ---
test_start "score_calc: negative score"
calculate_score 0 5 5 0 0
assert_eq "-90.0" "$_CALC_SCORE" "0 passing, 5 failing = -90.0"

# --- Test 3: coverage contribution ---
test_start "score_calc: coverage contribution"
# (10*100) + (10*20) + (80*50) - (0*200) - 0 = 1000+200+4000 = 5200 -> 520.0
calculate_score 10 0 10 80 0
assert_eq "520.0" "$_CALC_SCORE" "10 passing, 80% coverage = 520.0"

# --- Test 4: time penalty ---
test_start "score_calc: time penalty"
# (10*100) + (10*20) + (0*50) - (0*200) - 30 = 1000+200-30 = 1170 -> 117.0
calculate_score 10 0 10 0 30
assert_eq "117.0" "$_CALC_SCORE" "10 passing, 30s time = 117.0"

# --- Test 5: all dimensions ---
test_start "score_calc: all dimensions"
# (15*100) + (17*20) + (75*50) - (2*200) - 45 = 1500+340+3750-400-45 = 5145 -> 514.5
calculate_score 15 2 17 75 45
assert_eq "514.5" "$_CALC_SCORE" "15p/2f/17t/75cov/45s = 514.5"

# --- Test 6: all zeros ---
test_start "score_calc: all zeros"
calculate_score 0 0 0 0 0
assert_eq "0.0" "$_CALC_SCORE" "all zeros = 0.0"

test_summary
