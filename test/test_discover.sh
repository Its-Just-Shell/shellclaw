#!/usr/bin/env bash
# Tests for lib/discover.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/discover.sh"

setup_tmpdir

echo "=== discover.sh ==="

# --- Helper: create test tools in temp dir ---

FIXTURE_DIR="$TEST_TMPDIR/tools"
mkdir -p "$FIXTURE_DIR"

# A valid tool
cat > "$FIXTURE_DIR/good_tool.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo '{"name":"good_tool","description":"A test tool","parameters":{"type":"object","properties":{},"required":[]}}'
    exit 0
fi
echo "executed: $1"
EOF
chmod +x "$FIXTURE_DIR/good_tool.sh"

# Another valid tool
cat > "$FIXTURE_DIR/another_tool.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo '{"name":"another_tool","description":"Another test tool","parameters":{"type":"object","properties":{"x":{"type":"string"}},"required":["x"]}}'
    exit 0
fi
echo "another: $1"
EOF
chmod +x "$FIXTURE_DIR/another_tool.sh"

# A tool whose --describe fails (exit 1)
cat > "$FIXTURE_DIR/broken_describe.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo "error: cannot describe" >&2
    exit 1
fi
echo "broken"
EOF
chmod +x "$FIXTURE_DIR/broken_describe.sh"

# A tool whose --describe outputs invalid JSON
cat > "$FIXTURE_DIR/bad_json.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo "this is not json"
    exit 0
fi
echo "bad"
EOF
chmod +x "$FIXTURE_DIR/bad_json.sh"

# A tool whose --describe is missing required fields
cat > "$FIXTURE_DIR/missing_fields.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--describe" ]]; then
    echo '{"name":"missing","description":"no params field"}'
    exit 0
fi
echo "missing"
EOF
chmod +x "$FIXTURE_DIR/missing_fields.sh"

# A non-executable file
echo "not a tool" > "$FIXTURE_DIR/readme.txt"

# --- discover_tool: valid tool ---

output=$(discover_tool "$FIXTURE_DIR/good_tool.sh") && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tool returns 0 for valid tool"

printf '%s' "$output" | jq . >/dev/null 2>&1 && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tool output is valid JSON"

check_json_field "$output" "name" "good_tool" "discover_tool returns correct name"

# --- discover_tool: with real tools ---

output=$(discover_tool "$PROJECT_ROOT/tools/get_weather.sh") && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tool works on real get_weather.sh"
check_json_field "$output" "name" "get_weather" "real tool has correct name"

# --- discover_tool: errors ---

output=$(discover_tool 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without tool path"
check_contains "$output" "tool path required" "error mentions tool path"

output=$(discover_tool "/nonexistent/tool.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails for nonexistent file"
check_contains "$output" "not found" "error mentions not found"

output=$(discover_tool "$FIXTURE_DIR/readme.txt" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails for non-executable file"
check_contains "$output" "not executable" "error mentions not executable"

output=$(discover_tool "$FIXTURE_DIR/broken_describe.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when --describe exits non-zero"
check_contains "$output" "failed" "error mentions failure"

output=$(discover_tool "$FIXTURE_DIR/bad_json.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when --describe is not JSON"
check_contains "$output" "not valid JSON" "error mentions invalid JSON"

output=$(discover_tool "$FIXTURE_DIR/missing_fields.sh" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when required fields missing"
check_contains "$output" "missing required fields" "error mentions missing fields"

# --- discover_tools: valid directory ---

# Use a clean dir with only good tools
CLEAN_DIR="$TEST_TMPDIR/clean_tools"
mkdir -p "$CLEAN_DIR"
cp "$FIXTURE_DIR/good_tool.sh" "$CLEAN_DIR/"
cp "$FIXTURE_DIR/another_tool.sh" "$CLEAN_DIR/"

output=$(discover_tools "$CLEAN_DIR") && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tools returns 0"

printf '%s' "$output" | jq . >/dev/null 2>&1 && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tools output is valid JSON"

length=$(printf '%s' "$output" | jq 'length')
check_output "$length" "2" "catalog has 2 tools"

# --- discover_tools: skips broken tools ---

output=$(discover_tools "$FIXTURE_DIR" 2>/dev/null) && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tools returns 0 even with broken tools"

# Only good_tool and another_tool should be in the catalog
length=$(printf '%s' "$output" | jq 'length')
check_output "$length" "2" "catalog has 2 valid tools (broken ones skipped)"

# --- discover_tools: warns on broken tools ---

stderr_output=$(discover_tools "$FIXTURE_DIR" 2>&1 >/dev/null)
check_contains "$stderr_output" "skipping" "warns about skipped tools"

# --- discover_tools: real tools directory ---

output=$(discover_tools "$PROJECT_ROOT/tools") && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tools works on real tools dir"

length=$(printf '%s' "$output" | jq 'length')
check_output "$length" "3" "discovers all 3 real tools"

# --- discover_tools: empty directory ---

EMPTY_DIR="$TEST_TMPDIR/empty_tools"
mkdir -p "$EMPTY_DIR"

output=$(discover_tools "$EMPTY_DIR") && rc=0 || rc=$?
check_exit "$rc" 0 "discover_tools returns 0 for empty dir"
check_output "$output" "[]" "empty dir produces empty array"

# --- discover_tools: errors ---

output=$(discover_tools 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without tools dir"
check_contains "$output" "tools directory required" "error mentions tools directory"

output=$(discover_tools "/nonexistent/dir" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails for nonexistent directory"
check_contains "$output" "not found" "error mentions not found"

summary "discover.sh"
