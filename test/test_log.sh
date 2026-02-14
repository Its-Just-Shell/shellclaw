#!/usr/bin/env bash
# Tests for lib/log.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/log.sh"

setup_tmpdir

echo "=== log.sh ==="

# --- Basic operation ---

LOG_FILE="$TEST_TMPDIR/basic.jsonl"
SHELLCLAW_AGENT_ID="test-agent"
export LOG_FILE SHELLCLAW_AGENT_ID

log_event "user_input" "hello world" && rc=0 || rc=$?
check_exit "$rc" 0 "log_event returns 0"

line=$(cat "$LOG_FILE")
check_json_field "$line" "event" "user_input" "event field correct"
check_json_field "$line" "agent" "test-agent" "agent field correct"
check_json_field "$line" "message" "hello world" "message field correct"
check_contains "$line" '"ts":' "has timestamp field"

# --- Optional message ---

LOG_FILE="$TEST_TMPDIR/no-msg.jsonl"
log_event "session_start" && rc=0 || rc=$?
check_exit "$rc" 0 "log_event without message succeeds"

line=$(cat "$LOG_FILE")
check_json_field "$line" "event" "session_start" "event without message"
check_json_field "$line" "message" "" "message is empty string when omitted"

# --- Special characters ---

LOG_FILE="$TEST_TMPDIR/special.jsonl"
log_event "user_input" 'He said "hello" & <world>'
line=$(cat "$LOG_FILE")
result=$(printf '%s' "$line" | jq -r '.message')
check_output "$result" 'He said "hello" & <world>' "quotes, ampersands, angle brackets preserved"

# --- Newlines in message ---

LOG_FILE="$TEST_TMPDIR/newlines.jsonl"
log_event "user_input" $'line one\nline two'
line=$(cat "$LOG_FILE")
result=$(printf '%s' "$line" | jq -r '.message')
check_output "$result" $'line one\nline two' "newlines preserved in message"

# --- Single JSONL line per event (even with newlines in content) ---

count=$(wc -l < "$LOG_FILE" | tr -d ' ')
check_output "$count" "1" "newline message is still one JSONL line"

# --- Multiple entries append ---

LOG_FILE="$TEST_TMPDIR/multi.jsonl"
log_event "first" "one"
log_event "second" "two"
log_event "third" "three"
count=$(wc -l < "$LOG_FILE" | tr -d ' ')
check_output "$count" "3" "three events = three lines"

# --- Default agent ID ---

unset SHELLCLAW_AGENT_ID
LOG_FILE="$TEST_TMPDIR/default-agent.jsonl"
log_event "test" "msg"
line=$(cat "$LOG_FILE")
check_json_field "$line" "agent" "unknown" "defaults to 'unknown' when SHELLCLAW_AGENT_ID unset"
SHELLCLAW_AGENT_ID="test-agent"
export SHELLCLAW_AGENT_ID

# --- Error: missing LOG_FILE ---

unset LOG_FILE
output=$(log_event "test" "msg" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without LOG_FILE"
check_contains "$output" "LOG_FILE not set" "error message mentions LOG_FILE"
LOG_FILE="$TEST_TMPDIR/dummy.jsonl"
export LOG_FILE

# --- Error: missing event_type ---

output=$(log_event 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without event_type"
check_contains "$output" "event_type required" "error message mentions event_type"

# --- Timestamp format ---

LOG_FILE="$TEST_TMPDIR/ts.jsonl"
log_event "test" "checking timestamp"
line=$(cat "$LOG_FILE")
ts=$(printf '%s' "$line" | jq -r '.ts')
# Should match ISO 8601 UTC: YYYY-MM-DDTHH:MM:SSZ
check_contains "$ts" "T" "timestamp contains T separator"
check_contains "$ts" "Z" "timestamp ends with Z (UTC)"

summary "log.sh"
