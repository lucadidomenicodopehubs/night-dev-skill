#!/usr/bin/env bash
# Tests for parse_args() edge cases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: unknown flag ---
test_start "parse_args: unknown flag exits 1"
assert_exit 1 parse_args --unknown-flag

# --- Test 2: --version exits 0 ---
test_start "parse_args: --version exits 0"
local_output=$(bash "$SCRIPT_DIR/../scripts/night-dev.sh" --version 2>&1)
assert_eq "night-dev.sh 1.0.0" "$local_output" "version output"

# --- Test 3: duplicate positional args ---
test_start "parse_args: two positional args exits 1"
assert_exit 1 parse_args /path/one /path/two

test_summary
