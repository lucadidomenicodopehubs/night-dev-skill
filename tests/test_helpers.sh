#!/usr/bin/env bash
# Night Dev Test Helpers — shared setup, teardown, and assertions
set -euo pipefail

# Counters
_TEST_PASS=0
_TEST_FAIL=0
_TEST_COUNT=0
_TEST_NAME=""

# Colors (respect NO_COLOR)
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    _T_RED='' _T_GREEN='' _T_NC=''
else
    _T_RED='\033[0;31m' _T_GREEN='\033[0;32m' _T_NC='\033[0m'
fi

# Setup: create temp dir
setup() {
    TEST_TMPDIR=$(mktemp -d)
    export PROJECT_PATH="$TEST_TMPDIR"
}

# Teardown: remove temp dir
teardown() {
    if [[ -n "${TEST_TMPDIR:-}" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}
trap teardown EXIT

# Start a test case
test_start() {
    _TEST_NAME="$1"
    _TEST_COUNT=$((_TEST_COUNT + 1))
}

# Assert equality
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" == "$actual" ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        echo -e "${_T_GREEN}PASS${_T_NC}: ${_TEST_NAME}${msg:+ — $msg}"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME}${msg:+ — $msg} (expected='$expected', actual='$actual')"
    fi
}

# Assert not equal
assert_ne() {
    local unexpected="$1" actual="$2" msg="${3:-}"
    if [[ "$unexpected" != "$actual" ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        echo -e "${_T_GREEN}PASS${_T_NC}: ${_TEST_NAME}${msg:+ — $msg}"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME}${msg:+ — $msg} (got unexpected value='$actual')"
    fi
}

# Assert exit code of a command
assert_exit() {
    local expected_code="$1"
    shift
    local actual_code=0
    ( "$@" ) >/dev/null 2>&1 || actual_code=$?
    if [[ "$expected_code" == "$actual_code" ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        echo -e "${_T_GREEN}PASS${_T_NC}: ${_TEST_NAME} (exit=$actual_code)"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME} (expected exit=$expected_code, got=$actual_code)"
    fi
}

# Assert substring containment
assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" == *"$needle"* ]]; then
        _TEST_PASS=$((_TEST_PASS + 1))
        echo -e "${_T_GREEN}PASS${_T_NC}: ${_TEST_NAME}${msg:+ — $msg}"
    else
        _TEST_FAIL=$((_TEST_FAIL + 1))
        echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME}${msg:+ — $msg} (expected to contain '$needle')"
    fi
}

# Print summary (pytest-compatible format)
test_summary() {
    echo ""
    if [[ $_TEST_FAIL -eq 0 ]]; then
        echo "$_TEST_PASS passed in 0.00s"
    else
        echo "$_TEST_FAIL failed, $_TEST_PASS passed in 0.00s"
        exit 1
    fi
}
