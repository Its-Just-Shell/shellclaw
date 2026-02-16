#!/usr/bin/env bash
# Tests for lib/dispatch.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/discover.sh"
source "$PROJECT_ROOT/lib/dispatch.sh"

setup_tmpdir

echo "=== dispatch.sh ==="

# All tests use stub mode
export SHELLCLAW_STUB=1

# --- Build a test catalog from the real tools ---

catalog=$(discover_tools "$PROJECT_ROOT/tools")

# --- validate_tool_call: valid call ---

validate_tool_call "$catalog" "get_weather" '{"location":"NYC"}' && rc=0 || rc=$?
check_exit "$rc" 0 "valid call passes validation"

# --- validate_tool_call: optional fields absent ---

validate_tool_call "$catalog" "get_weather" '{"location":"NYC"}' && rc=0 || rc=$?
check_exit "$rc" 0 "optional unit field can be absent"

# --- validate_tool_call: extra fields present ---

validate_tool_call "$catalog" "get_weather" '{"location":"NYC","extra":"value"}' && rc=0 || rc=$?
check_exit "$rc" 0 "extra fields are ignored"

# --- validate_tool_call: no required fields ---

validate_tool_call "$catalog" "disk_usage" '{}' && rc=0 || rc=$?
check_exit "$rc" 0 "tool with no required fields passes with empty args"

# --- validate_tool_call: all required fields for github_issue ---

validate_tool_call "$catalog" "github_issue" '{"repo":"o/r","title":"T"}' && rc=0 || rc=$?
check_exit "$rc" 0 "github_issue with both required fields passes"

# --- validate_tool_call: missing required field ---

output=$(validate_tool_call "$catalog" "get_weather" '{}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "missing required field fails"
check_contains "$output" "missing required" "error mentions missing required"

# --- validate_tool_call: missing one of two required fields ---

output=$(validate_tool_call "$catalog" "github_issue" '{"repo":"o/r"}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "github_issue missing title fails"
check_contains "$output" "title" "error mentions missing field name"

# --- validate_tool_call: unknown tool ---

output=$(validate_tool_call "$catalog" "nonexistent_tool" '{}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "unknown tool fails validation"
check_contains "$output" "not found in catalog" "error mentions not found"

# --- validate_tool_call: errors ---

output=$(validate_tool_call 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without catalog"
check_contains "$output" "catalog" "error mentions catalog"

output=$(validate_tool_call "$catalog" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without tool name"

output=$(validate_tool_call "$catalog" "get_weather" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without args"

# --- dispatch_tool: valid call ---

output=$(dispatch_tool "$PROJECT_ROOT/tools" "get_weather" '{"location":"NYC"}') && rc=0 || rc=$?
check_exit "$rc" 0 "dispatch valid tool returns 0"
check_contains "$output" "NYC" "dispatch output contains expected data"

# --- dispatch_tool: disk_usage ---

output=$(dispatch_tool "$PROJECT_ROOT/tools" "disk_usage" '{"path":"/tmp"}') && rc=0 || rc=$?
check_exit "$rc" 0 "dispatch disk_usage returns 0"
check_contains "$output" "/tmp" "disk_usage output contains path"

# --- dispatch_tool: github_issue ---

output=$(dispatch_tool "$PROJECT_ROOT/tools" "github_issue" '{"repo":"o/r","title":"Test"}') && rc=0 || rc=$?
check_exit "$rc" 0 "dispatch github_issue returns 0"
check_contains "$output" "stub" "github_issue returns stub response"

# --- dispatch_tool: unknown tool ---

output=$(dispatch_tool "$PROJECT_ROOT/tools" "nonexistent_tool" '{}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "unknown tool returns 1"
check_contains "$output" "not found" "error mentions not found"

# --- dispatch_tool: tool execution failure ---

# Create a tool that always fails
mkdir -p "$TEST_TMPDIR/fail_tools"
cat > "$TEST_TMPDIR/fail_tools/failing_tool.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo '{"name":"failing_tool","description":"Always fails","parameters":{"type":"object","properties":{},"required":[]}}'
    exit 0
fi
echo "something went wrong" >&2
exit 1
EOF
chmod +x "$TEST_TMPDIR/fail_tools/failing_tool.sh"

output=$(dispatch_tool "$TEST_TMPDIR/fail_tools" "failing_tool" '{}' 2>&1) && rc=0 || rc=$?
check_exit "$rc" 2 "failed tool returns exit 2"
check_contains "$output" "failed" "error mentions failure"

# --- dispatch_tool: errors ---

output=$(dispatch_tool 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without tools dir"

output=$(dispatch_tool "$PROJECT_ROOT/tools" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without tool name"

output=$(dispatch_tool "$PROJECT_ROOT/tools" "get_weather" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without args JSON"

# --- dispatch_tool: with logging ---

export LOG_FILE="$TEST_TMPDIR/dispatch.jsonl"
export SHELLCLAW_AGENT_ID="test"
source "$PROJECT_ROOT/lib/log.sh"

dispatch_tool "$PROJECT_ROOT/tools" "get_weather" '{"location":"SF"}' >/dev/null
check_file_exists "$LOG_FILE" "log file created during dispatch"

log_content=$(cat "$LOG_FILE")
check_contains "$log_content" "tool_dispatch" "log contains dispatch event"
check_contains "$log_content" "tool_result" "log contains result event"

summary "dispatch.sh"
