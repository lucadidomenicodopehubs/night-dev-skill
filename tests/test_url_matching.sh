#!/usr/bin/env bash
# Tests for GitHub URL pattern matching in resolve_project_path()
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

# Test the regex patterns directly (avoid actually cloning)

# --- Test 1: HTTPS URL matches pattern ---
test_start "url_matching: HTTPS GitHub URL"
url="https://github.com/user/repo"
if [[ "$url" =~ ^https?://github\.com/ ]]; then
    repo_name="${url##*/}"
    repo_name="${repo_name%.git}"
    assert_eq "repo" "$repo_name" "repo name extracted"
else
    _TEST_FAIL=$((_TEST_FAIL + 1))
    echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME} — URL did not match pattern"
fi

# --- Test 2: git@ URL matches pattern ---
test_start "url_matching: git@ GitHub URL"
url="git@github.com:user/my-repo.git"
if [[ "$url" =~ ^git@github\.com: ]]; then
    repo_name="${url##*/}"
    repo_name="${repo_name%.git}"
    assert_eq "my-repo" "$repo_name" "repo name extracted from git@ URL"
else
    _TEST_FAIL=$((_TEST_FAIL + 1))
    echo -e "${_T_RED}FAIL${_T_NC}: ${_TEST_NAME} — URL did not match pattern"
fi

test_summary
