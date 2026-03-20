#!/usr/bin/env bash
# Tests for print_banner() output formatting
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# Set required globals for print_banner
PROJECT_PATH="/tmp/test-project"
MAX_LOOPS=5
MAX_HOURS=8
SKIP_RESEARCH=false
AUTO_PUSH=false
VERBOSE=false
DETECTED_RUNNER="make test"
IS_CLONED=false
CLONE_BRANCH=""

# --- Test 1: banner contains project path ---
test_start "print_banner: contains project path"
output=$(NO_COLOR=1 print_banner)
assert_contains "$output" "/tmp/test-project" "project path in banner"

# --- Test 2: banner shows research status ---
test_start "print_banner: shows research ENABLED"
SKIP_RESEARCH=false
output=$(NO_COLOR=1 print_banner)
assert_contains "$output" "ENABLED" "research status ENABLED"

test_start "print_banner: shows research SKIPPED"
SKIP_RESEARCH=true
output=$(NO_COLOR=1 print_banner)
assert_contains "$output" "SKIPPED" "research status SKIPPED"

# --- Test 3: banner shows test runner ---
test_start "print_banner: shows test runner"
DETECTED_RUNNER="pytest"
output=$(NO_COLOR=1 print_banner)
assert_contains "$output" "pytest" "test runner in banner"

test_summary
