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

# --- Test 5: pyproject.toml with [tool.pytest] ---
test_start "detect_test_runner: pyproject.toml with [tool.pytest]"
setup
cat > "$TEST_TMPDIR/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
testpaths = ["tests"]
EOF
detect_test_runner
assert_eq "pytest" "$DETECTED_RUNNER"

# --- Test 6: setup.cfg with [tool:pytest] ---
test_start "detect_test_runner: setup.cfg with [tool:pytest]"
setup
cat > "$TEST_TMPDIR/setup.cfg" <<'EOF'
[tool:pytest]
testpaths = tests
EOF
detect_test_runner
assert_eq "pytest" "$DETECTED_RUNNER"

# --- Test 7: tox.ini ---
test_start "detect_test_runner: tox.ini"
setup
touch "$TEST_TMPDIR/tox.ini"
detect_test_runner
assert_eq "tox" "$DETECTED_RUNNER"

# --- Test 8: package.json with no test specified ---
test_start "detect_test_runner: package.json no test specified"
setup
cat > "$TEST_TMPDIR/package.json" <<'EOF'
{"scripts": {"test": "echo \"Error: no test specified\""}}
EOF
assert_exit 1 detect_test_runner

# --- Test 9: Go test files ---
test_start "detect_test_runner: Go test files"
setup
touch "$TEST_TMPDIR/example_test.go"
detect_test_runner
assert_eq "go test ./..." "$DETECTED_RUNNER"

# --- Test 10: no config files ---
test_start "detect_test_runner: no config files"
setup
assert_exit 1 detect_test_runner

test_summary
