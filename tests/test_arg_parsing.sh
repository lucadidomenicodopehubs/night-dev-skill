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

# --- Test 4: --max-loops 0 exits 1 ---
test_start "parse_args: --max-loops 0 exits 1"
assert_exit 1 parse_args --max-loops 0

# --- Test 5: --branch without value exits 1 ---
test_start "parse_args: --branch without value exits 1"
assert_exit 1 parse_args --branch

# --- Test 6: --hours without value exits 1 ---
test_start "parse_args: --hours without value exits 1"
assert_exit 1 parse_args --hours

# --- Test 7: --hours with valid value sets MAX_HOURS ---
test_start "parse_args: --hours sets MAX_HOURS"
setup
cd "$TEST_TMPDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
printf 'test:\n\t@echo ok\n' > Makefile
git add . && git commit -m "init" -q
MAX_HOURS=8
PROJECT_PATH=""
parse_args --hours 12 "$TEST_TMPDIR"
assert_eq "12" "$MAX_HOURS" "MAX_HOURS set to 12"

# --- Test 8: --skip-research sets SKIP_RESEARCH ---
test_start "parse_args: --skip-research sets flag"
SKIP_RESEARCH=false
PROJECT_PATH=""
parse_args --skip-research "$TEST_TMPDIR"
assert_eq "true" "$SKIP_RESEARCH" "SKIP_RESEARCH set to true"

# --- Test 9: --push sets AUTO_PUSH ---
test_start "parse_args: --push sets flag"
AUTO_PUSH=false
PROJECT_PATH=""
parse_args --push "$TEST_TMPDIR"
assert_eq "true" "$AUTO_PUSH" "AUTO_PUSH set to true"

test_summary
