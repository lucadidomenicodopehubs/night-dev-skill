#!/usr/bin/env bash
# Tests for check_git_repo() and check_dirty_state()
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: non-git directory fails ---
test_start "check_git_repo: non-git directory fails"
setup
PROJECT_PATH="$TEST_TMPDIR"
assert_exit 1 check_git_repo

# --- Test 2: dirty working tree fails ---
test_start "check_dirty_state: dirty working tree fails"
setup
cd "$TEST_TMPDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test User"
git commit --allow-empty -m "init" -q
echo "dirty" > newfile.txt
PROJECT_PATH="$TEST_TMPDIR"
assert_exit 1 check_dirty_state

# --- Test 3: clean working tree passes ---
test_start "check_dirty_state: clean working tree passes"
setup
cd "$TEST_TMPDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test User"
git commit --allow-empty -m "init" -q
PROJECT_PATH="$TEST_TMPDIR"
assert_exit 0 check_dirty_state

# --- Test 4: check_claude_cli fails when claude not in PATH ---
test_start "check_claude_cli: missing claude exits 1"
_test_no_claude() { PATH=/nonexistent check_claude_cli; }
assert_exit 1 _test_no_claude

test_summary
