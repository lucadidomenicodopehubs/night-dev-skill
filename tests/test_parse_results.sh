#!/usr/bin/env bash
# Tests for parse_test_results() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

setup

# --- Test 1: pytest output ---
test_start "parse_test_results: pytest format"
cat > "$TEST_TMPDIR/pytest_output.txt" <<'EOF'
============================= test session starts ==============================
collected 23 items

tests/test_foo.py::test_one PASSED
tests/test_foo.py::test_two PASSED
============================== 23 passed in 1.25s ==============================
EOF
parse_test_results "$TEST_TMPDIR/pytest_output.txt"
assert_eq "23" "$_PARSE_PASSED" "passed count"

# --- Test 2: jest output ---
test_start "parse_test_results: jest format"
cat > "$TEST_TMPDIR/jest_output.txt" <<'EOF'
PASS src/tests/app.test.js
  App Component
    ✓ renders correctly (5 ms)

Tests: 2 failed, 18 passed, 20 total
Time:  3.45s
EOF
parse_test_results "$TEST_TMPDIR/jest_output.txt"
assert_eq "18" "$_PARSE_PASSED" "jest passed count"

# --- Test 3: cargo output ---
test_start "parse_test_results: cargo format"
cat > "$TEST_TMPDIR/cargo_output.txt" <<'EOF'
running 5 tests
test tests::test_add ... ok
test tests::test_sub ... ok
test result: ok. 5 passed; 0 failed; 0 ignored
EOF
parse_test_results "$TEST_TMPDIR/cargo_output.txt"
assert_eq "5" "$_PARSE_PASSED" "cargo passed count"

# --- Test 4: empty file ---
test_start "parse_test_results: empty file"
: > "$TEST_TMPDIR/empty_output.txt"
parse_test_results "$TEST_TMPDIR/empty_output.txt"
assert_eq "0" "$_PARSE_PASSED" "empty file returns 0"

test_summary
