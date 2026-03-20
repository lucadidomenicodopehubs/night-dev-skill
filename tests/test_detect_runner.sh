#!/usr/bin/env bash
# Tests for detect_test_runner() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
source "$SCRIPT_DIR/../scripts/night-dev.sh"

# --- Test 1: pytest.ini detection ---
test_start "detect_test_runner: pytest.ini"
setup
touch "$TEST_TMPDIR/pytest.ini"
detect_test_runner
assert_eq "pytest" "$DETECTED_RUNNER"

# --- Test 2: package.json with valid test script ---
test_start "detect_test_runner: package.json"
setup
cat > "$TEST_TMPDIR/package.json" <<'EOF'
{"scripts": {"test": "jest --coverage"}}
EOF
detect_test_runner
assert_eq "npm test" "$DETECTED_RUNNER"

# --- Test 3: Makefile with test target ---
test_start "detect_test_runner: Makefile"
setup
cat > "$TEST_TMPDIR/Makefile" <<'EOF'
test:
	echo "running tests"
EOF
detect_test_runner
assert_eq "make test" "$DETECTED_RUNNER"

# --- Test 4: Cargo.toml detection ---
test_start "detect_test_runner: Cargo.toml"
setup
touch "$TEST_TMPDIR/Cargo.toml"
detect_test_runner
assert_eq "cargo test" "$DETECTED_RUNNER"

test_summary
