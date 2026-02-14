#!/usr/bin/env bash
# Tests for lib/session.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/session.sh"

setup_tmpdir

echo "=== session.sh ==="

# --- session_append: basic ---

session_append "$TEST_TMPDIR/chat.jsonl" "user" "Hello" && rc=0 || rc=$?
check_exit "$rc" 0 "session_append returns 0"
check_file_exists "$TEST_TMPDIR/chat.jsonl" "creates file if missing"

line=$(cat "$TEST_TMPDIR/chat.jsonl")
check_json_field "$line" "role" "user" "role field correct"
check_json_field "$line" "content" "Hello" "content field correct"
check_contains "$line" '"ts":' "has timestamp"

# --- session_append: multiple entries ---

session_append "$TEST_TMPDIR/chat.jsonl" "assistant" "Hi there"
session_append "$TEST_TMPDIR/chat.jsonl" "user" "How are you?"
count=$(wc -l < "$TEST_TMPDIR/chat.jsonl" | tr -d ' ')
check_output "$count" "3" "three appends = three lines"

# --- session_append: special characters ---

session_append "$TEST_TMPDIR/special.jsonl" "user" 'She said "hello" & <goodbye>'
line=$(cat "$TEST_TMPDIR/special.jsonl")
result=$(printf '%s' "$line" | jq -r '.content')
check_output "$result" 'She said "hello" & <goodbye>' "special characters preserved"

# --- session_append: newlines in content ---

session_append "$TEST_TMPDIR/newlines.jsonl" "assistant" $'line one\nline two'
count=$(wc -l < "$TEST_TMPDIR/newlines.jsonl" | tr -d ' ')
check_output "$count" "1" "newline in content is still one JSONL line"
result=$(jq -r '.content' "$TEST_TMPDIR/newlines.jsonl")
check_output "$result" $'line one\nline two' "newlines preserved in content"

# --- session_append: empty content ---

session_append "$TEST_TMPDIR/empty-content.jsonl" "user" ""
line=$(cat "$TEST_TMPDIR/empty-content.jsonl")
check_json_field "$line" "content" "" "empty content allowed"

# --- session_append: errors ---

output=$(session_append 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without file path"
check_contains "$output" "file path required" "error mentions file path"

output=$(session_append "$TEST_TMPDIR/x.jsonl" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without role"
check_contains "$output" "role required" "error mentions role"

# --- session_load: basic ---

: > "$TEST_TMPDIR/load.jsonl"
session_append "$TEST_TMPDIR/load.jsonl" "user" "Hello"
session_append "$TEST_TMPDIR/load.jsonl" "assistant" "Hi there"

output=$(session_load "$TEST_TMPDIR/load.jsonl")
check_contains "$output" "user: Hello" "load shows user message"
check_contains "$output" "assistant: Hi there" "load shows assistant message"

# --- session_load: with limit ---

session_append "$TEST_TMPDIR/load.jsonl" "user" "Third message"
output=$(session_load "$TEST_TMPDIR/load.jsonl" 1)
check_output "$output" "user: Third message" "limit=1 shows only last entry"

output=$(session_load "$TEST_TMPDIR/load.jsonl" 2)
check_contains "$output" "assistant: Hi there" "limit=2 includes second-to-last"
check_contains "$output" "user: Third message" "limit=2 includes last"

# --- session_load: empty file ---

: > "$TEST_TMPDIR/empty.jsonl"
output=$(session_load "$TEST_TMPDIR/empty.jsonl")
rc=$?
check_exit "$rc" 0 "load on empty file returns 0"
check_output "$output" "" "load on empty file outputs nothing"

# --- session_load: non-existent file ---

output=$(session_load "$TEST_TMPDIR/nope.jsonl")
rc=$?
check_exit "$rc" 0 "load on missing file returns 0"
check_output "$output" "" "load on missing file outputs nothing"

# --- session_load: errors ---

output=$(session_load 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "load fails without file path"

# --- session_count: basic ---

: > "$TEST_TMPDIR/count.jsonl"
session_append "$TEST_TMPDIR/count.jsonl" "user" "one"
session_append "$TEST_TMPDIR/count.jsonl" "assistant" "two"
result=$(session_count "$TEST_TMPDIR/count.jsonl")
check_output "$result" "2" "count returns 2 for two entries"

# --- session_count: empty file ---

: > "$TEST_TMPDIR/count-empty.jsonl"
result=$(session_count "$TEST_TMPDIR/count-empty.jsonl")
check_output "$result" "0" "count returns 0 for empty file"

# --- session_count: non-existent file ---

result=$(session_count "$TEST_TMPDIR/count-nope.jsonl")
check_output "$result" "0" "count returns 0 for missing file"

# --- session_count: errors ---

output=$(session_count 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "count fails without file path"

# --- session_clear: archives and creates fresh ---

: > "$TEST_TMPDIR/clear.jsonl"
session_append "$TEST_TMPDIR/clear.jsonl" "user" "old message"
session_clear "$TEST_TMPDIR/clear.jsonl" && rc=0 || rc=$?
check_exit "$rc" 0 "clear returns 0"
check_file_exists "$TEST_TMPDIR/clear.jsonl" "fresh file exists after clear"

fresh_count=$(session_count "$TEST_TMPDIR/clear.jsonl")
check_output "$fresh_count" "0" "fresh file is empty"

# Check that archive was created
archive_count=$(ls "$TEST_TMPDIR"/clear.jsonl.* 2>/dev/null | wc -l | tr -d ' ')
check_output "$archive_count" "1" "archive file was created"

# Check archive has the old content
archive_file=$(ls "$TEST_TMPDIR"/clear.jsonl.*)
archive_content=$(jq -r '.content' "$archive_file")
check_output "$archive_content" "old message" "archive contains old content"

# --- session_clear: non-existent file ---

session_clear "$TEST_TMPDIR/new.jsonl" && rc=0 || rc=$?
check_exit "$rc" 0 "clear on missing file returns 0"
check_file_exists "$TEST_TMPDIR/new.jsonl" "creates file when none existed"

# --- session_clear: empty file ---

: > "$TEST_TMPDIR/clear-empty.jsonl"
session_clear "$TEST_TMPDIR/clear-empty.jsonl" && rc=0 || rc=$?
check_exit "$rc" 0 "clear on empty file returns 0"
archive_count=$(ls "$TEST_TMPDIR"/clear-empty.jsonl.* 2>/dev/null | wc -l | tr -d ' ')
check_output "$archive_count" "0" "no archive created for empty file"

# --- session_clear: errors ---

output=$(session_clear 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "clear fails without file path"

summary "session.sh"
