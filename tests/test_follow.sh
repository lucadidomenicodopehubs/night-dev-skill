#!/usr/bin/env bash
# Tests for follow_night_dev() behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: --follow with no active instances exits 1 ---
test_start "follow_night_dev: no instances found exits 1"
setup
PROJECT_PATH="$TEST_TMPDIR"
assert_exit 1 follow_night_dev

test_summary
