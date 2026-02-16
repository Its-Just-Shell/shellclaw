#!/usr/bin/env bash
# Tests for tools/*
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"

setup_tmpdir

echo "=== tools ==="

# All tool tests use stub mode — no network calls, no API keys.
export SHELLCLAW_STUB=1

TOOLS_DIR="$PROJECT_ROOT/tools"

# --- get_weather.sh: --describe ---

output=$("$TOOLS_DIR/get_weather.sh" --describe) && rc=0 || rc=$?
check_exit "$rc" 0 "get_weather --describe returns 0"

printf '%s' "$output" | jq . >/dev/null 2>&1 && rc=0 || rc=$?
check_exit "$rc" 0 "get_weather --describe is valid JSON"

check_json_field "$output" "name" "get_weather" "get_weather name field"
check_contains "$output" '"description"' "get_weather has description"
check_contains "$output" '"parameters"' "get_weather has parameters"
check_contains "$output" '"required"' "get_weather has required array"

# --- get_weather.sh: execution ---

output=$("$TOOLS_DIR/get_weather.sh" '{"location":"NYC"}') && rc=0 || rc=$?
check_exit "$rc" 0 "get_weather executes successfully"
check_contains "$output" "NYC" "get_weather output contains location"
check_contains "$output" "Sunny" "get_weather stub returns condition"

# --- get_weather.sh: with unit ---

output=$("$TOOLS_DIR/get_weather.sh" '{"location":"London","unit":"fahrenheit"}') && rc=0 || rc=$?
check_exit "$rc" 0 "get_weather with unit returns 0"
check_contains "$output" "fahrenheit" "get_weather respects unit parameter"

# --- get_weather.sh: errors ---

output=$("$TOOLS_DIR/get_weather.sh" '{}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "get_weather fails without location"
check_contains "$output" "required" "get_weather error mentions required"

output=$("$TOOLS_DIR/get_weather.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "get_weather fails without args"

# --- disk_usage.sh: --describe ---

output=$("$TOOLS_DIR/disk_usage.sh" --describe) && rc=0 || rc=$?
check_exit "$rc" 0 "disk_usage --describe returns 0"

printf '%s' "$output" | jq . >/dev/null 2>&1 && rc=0 || rc=$?
check_exit "$rc" 0 "disk_usage --describe is valid JSON"

check_json_field "$output" "name" "disk_usage" "disk_usage name field"
check_contains "$output" '"description"' "disk_usage has description"
check_contains "$output" '"parameters"' "disk_usage has parameters"

# --- disk_usage.sh: execution ---

output=$("$TOOLS_DIR/disk_usage.sh" '{"path":"/tmp"}') && rc=0 || rc=$?
check_exit "$rc" 0 "disk_usage executes successfully"
check_contains "$output" "/tmp" "disk_usage output contains path"

# --- disk_usage.sh: default args ---

output=$("$TOOLS_DIR/disk_usage.sh" '{}') && rc=0 || rc=$?
check_exit "$rc" 0 "disk_usage with empty args uses defaults"

# --- disk_usage.sh: non-human-readable ---

output=$("$TOOLS_DIR/disk_usage.sh" '{"path":"/tmp","human_readable":false}') && rc=0 || rc=$?
check_exit "$rc" 0 "disk_usage non-human-readable returns 0"

# --- disk_usage.sh: errors ---

output=$("$TOOLS_DIR/disk_usage.sh" '{"path":"/nonexistent/path/xyz"}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "disk_usage fails for nonexistent path"
check_contains "$output" "not found" "disk_usage error mentions not found"

# --- github_issue.sh: --describe ---

output=$("$TOOLS_DIR/github_issue.sh" --describe) && rc=0 || rc=$?
check_exit "$rc" 0 "github_issue --describe returns 0"

printf '%s' "$output" | jq . >/dev/null 2>&1 && rc=0 || rc=$?
check_exit "$rc" 0 "github_issue --describe is valid JSON"

check_json_field "$output" "name" "github_issue" "github_issue name field"
check_contains "$output" '"description"' "github_issue has description"
check_contains "$output" '"parameters"' "github_issue has parameters"

# --- github_issue.sh: execution (stub) ---

output=$("$TOOLS_DIR/github_issue.sh" '{"repo":"test/repo","title":"Bug report"}') && rc=0 || rc=$?
check_exit "$rc" 0 "github_issue stub executes successfully"
check_contains "$output" "test/repo" "github_issue output contains repo"
check_contains "$output" "Bug report" "github_issue output contains title"
check_contains "$output" "stub" "github_issue returns stub status"

# --- github_issue.sh: with body ---

output=$("$TOOLS_DIR/github_issue.sh" '{"repo":"o/r","title":"T","body":"Details here"}') && rc=0 || rc=$?
check_exit "$rc" 0 "github_issue with body returns 0"

# --- github_issue.sh: errors ---

output=$("$TOOLS_DIR/github_issue.sh" '{"title":"No repo"}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "github_issue fails without repo"
check_contains "$output" "required" "github_issue error mentions required"

output=$("$TOOLS_DIR/github_issue.sh" '{"repo":"o/r"}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "github_issue fails without title"

output=$("$TOOLS_DIR/github_issue.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "github_issue fails without args"

summary "tools"
