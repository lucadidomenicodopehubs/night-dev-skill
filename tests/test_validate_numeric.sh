#!/usr/bin/env bash
# Tests for validate_numeric_arg() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: valid number ---
test_start "validate_numeric_arg: valid number"
assert_exit 0 validate_numeric_arg "--max-loops" "5"

# --- Test 2: empty value ---
test_start "validate_numeric_arg: empty value"
assert_exit 1 validate_numeric_arg "--max-loops" ""

# --- Test 3: non-numeric string ---
test_start "validate_numeric_arg: non-numeric"
assert_exit 1 validate_numeric_arg "--max-loops" "abc"

test_summary
