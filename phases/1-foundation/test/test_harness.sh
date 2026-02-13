#!/usr/bin/env bash
# shellclaw/test/test_harness.sh — Shared test utilities
#
# Source this file at the top of every test script.
# Provides assertion functions and a summary reporter.
#
# Usage:
#   source test/test_harness.sh
#   setup_tmpdir
#   check_output "$(echo hi)" "hi" "echo works"
#   summary "my tests"

_TESTS_RUN=0
_TESTS_PASSED=0
_TESTS_FAILED=0
_CURRENT_TEST=""

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    _RED='\033[0;31m'
    _GREEN='\033[0;32m'
    _BOLD='\033[1m'
    _NC='\033[0m'
else
    _RED=''
    _GREEN=''
    _BOLD=''
    _NC=''
fi

# --- Internal helpers ---

_test_start() {
    _CURRENT_TEST="$1"
    (( _TESTS_RUN++ ))
}

_test_pass() {
    (( _TESTS_PASSED++ ))
    printf "  ${_GREEN}PASS${_NC} %s\n" "$_CURRENT_TEST"
}

_test_fail() {
    local detail="$1"
    (( _TESTS_FAILED++ ))
    printf "  ${_RED}FAIL${_NC} %s" "$_CURRENT_TEST"
    [[ -n "$detail" ]] && printf ": %s" "$detail"
    printf "\n"
}

# --- Assertions ---

# check_exit <actual_code> <expected_code> [label]
# Verify a command's exit code.
check_exit() {
    local actual="$1"
    local expected="$2"
    local label="${3:-exit code $expected}"
    _test_start "$label"
    if [[ "$actual" -eq "$expected" ]]; then
        _test_pass
    else
        _test_fail "expected exit $expected, got $actual"
    fi
}

# check_output <actual> <expected> [label]
# Verify exact string match.
check_output() {
    local actual="$1" expected="$2" label="${3:-output match}"
    _test_start "$label"
    if [[ "$actual" == "$expected" ]]; then
        _test_pass
    else
        _test_fail "expected '$expected', got '$actual'"
    fi
}

# check_contains <haystack> <needle> [label]
# Verify string contains substring.
check_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-contains \"$needle\"}"
    _test_start "$label"
    if [[ "$haystack" == *"$needle"* ]]; then
        _test_pass
    else
        _test_fail "output does not contain '$needle'"
    fi
}

# check_file_exists <path> [label]
# Verify a file exists.
check_file_exists() {
    local path="$1"
    local label="${2:-file exists: $path}"
    _test_start "$label"
    if [[ -f "$path" ]]; then
        _test_pass
    else
        _test_fail "file not found: $path"
    fi
}

# check_json_field <json_string> <field> <expected_value> [label]
# Verify a top-level JSON field equals expected value.
check_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local label="${4:-json .$field == $expected}"
    _test_start "$label"
    local actual
    actual=$(printf '%s' "$json" | jq -r ".$field")
    if [[ "$actual" == "$expected" ]]; then
        _test_pass
    else
        _test_fail ".$field: expected '$expected', got '$actual'"
    fi
}

# --- Setup / Teardown ---

# setup_tmpdir
# Creates a temp directory at $TEST_TMPDIR, cleaned up on EXIT.
setup_tmpdir() {
    TEST_TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TEST_TMPDIR"' EXIT
}

# --- Reporter ---

# summary [label]
# Prints pass/fail counts and exits 0 (all pass) or 1 (any fail).
summary() {
    local label="${1:-Tests}"
    echo ""
    printf -- "${_BOLD}--- %s ---${_NC}\n" "$label"
    printf "  Run:    %d\n" "$_TESTS_RUN"
    printf "  ${_GREEN}Passed: %d${_NC}\n" "$_TESTS_PASSED"
    if [[ "$_TESTS_FAILED" -gt 0 ]]; then
        printf "  ${_RED}Failed: %d${_NC}\n" "$_TESTS_FAILED"
        exit 1
    else
        printf "  Failed: 0\n"
        exit 0
    fi
}
