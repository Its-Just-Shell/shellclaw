#!/usr/bin/env bash
# Tests for deploy/telegram/lib/telegram.sh and llm.sh --conversation-id
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/deploy/telegram/lib/telegram.sh"
source "$PROJECT_ROOT/lib/llm.sh"

setup_tmpdir

echo "=== telegram.sh ==="

# Use stub backends for all tests
export SHELLCLAW_TELEGRAM_STUB=1
export SHELLCLAW_LLM_BACKEND=stub

# Point stub files to temp dir so tests don't collide
export SHELLCLAW_TELEGRAM_STUB_QUEUE="$TEST_TMPDIR/tg_queue"
export SHELLCLAW_TELEGRAM_STUB_LOG="$TEST_TMPDIR/tg_log"

# --- tg_get_updates: empty queue returns empty result ---

tg_stub_reset
output=$(tg_get_updates 0 0)
rc=$?
check_exit "$rc" 0 "stub getUpdates returns 0"
result_count=$(printf '%s' "$output" | jq '.result | length')
check_output "$result_count" "0" "empty queue returns 0 results"

# Verify JSON shape: has "ok" and "result" fields
ok_field=$(printf '%s' "$output" | jq -r '.ok')
check_output "$ok_field" "true" "response has ok:true"

# --- tg_stub_enqueue + tg_get_updates: returns queued messages ---

tg_stub_reset
tg_stub_enqueue 12345 "Hello bot" 100
tg_stub_enqueue 12345 "Second message" 101

output=$(tg_get_updates 0 0)
result_count=$(printf '%s' "$output" | jq '.result | length')
check_output "$result_count" "2" "returns 2 queued messages"

# Check first message shape
first_text=$(printf '%s' "$output" | jq -r '.result[0].message.text')
check_output "$first_text" "Hello bot" "first message text matches"

first_chat_id=$(printf '%s' "$output" | jq '.result[0].message.chat.id')
check_output "$first_chat_id" "12345" "first message chat_id matches"

first_update_id=$(printf '%s' "$output" | jq '.result[0].update_id')
check_output "$first_update_id" "100" "first update_id matches"

# Check second message
second_text=$(printf '%s' "$output" | jq -r '.result[1].message.text')
check_output "$second_text" "Second message" "second message text matches"

second_update_id=$(printf '%s' "$output" | jq '.result[1].update_id')
check_output "$second_update_id" "101" "second update_id matches"

# --- tg_get_updates: queue is consumed after read ---

output=$(tg_get_updates 0 0)
result_count=$(printf '%s' "$output" | jq '.result | length')
check_output "$result_count" "0" "queue empty after consumption"

# --- tg_get_updates: offset filtering ---

tg_stub_reset
tg_stub_enqueue 12345 "Old message" 50
tg_stub_enqueue 12345 "New message" 100

output=$(tg_get_updates 100 0)
result_count=$(printf '%s' "$output" | jq '.result | length')
check_output "$result_count" "1" "offset filters old messages"

filtered_text=$(printf '%s' "$output" | jq -r '.result[0].message.text')
check_output "$filtered_text" "New message" "offset returns only new message"

# --- tg_send_message: stub records to log ---

tg_stub_reset
output=$(tg_send_message "12345" "Hello user!")
rc=$?
check_exit "$rc" 0 "stub sendMessage returns 0"

ok_field=$(printf '%s' "$output" | jq -r '.ok')
check_output "$ok_field" "true" "sendMessage response has ok:true"

# Verify the message was logged
check_file_exists "$SHELLCLAW_TELEGRAM_STUB_LOG" "stub log file created"

logged_chat=$(jq -r '.chat_id' "$SHELLCLAW_TELEGRAM_STUB_LOG")
check_output "$logged_chat" "12345" "logged chat_id matches"

logged_text=$(jq -r '.text' "$SHELLCLAW_TELEGRAM_STUB_LOG")
check_output "$logged_text" "Hello user!" "logged text matches"

# --- tg_send_message: multiple messages append to log ---

tg_send_message "12345" "Second reply" >/dev/null
log_lines=$(wc -l < "$SHELLCLAW_TELEGRAM_STUB_LOG" | tr -d ' ')
check_output "$log_lines" "2" "log has 2 entries after 2 sends"

# --- tg_send_message: special characters ---

tg_stub_reset
tg_send_message "12345" 'Hello "world" & <friends>' >/dev/null
logged_text=$(jq -r '.text' "$SHELLCLAW_TELEGRAM_STUB_LOG")
check_output "$logged_text" 'Hello "world" & <friends>' "special chars preserved in log"

# --- tg_send_message: error — missing args ---

output=$(tg_send_message "" "text" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "sendMessage fails without chat_id"

output=$(tg_send_message "123" "" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "sendMessage fails without text"

# --- tg_send_chat_action: stub returns 0 ---

output=$(tg_send_chat_action "12345") && rc=0 || rc=$?
check_exit "$rc" 0 "stub chat action returns 0"

# --- tg_send_chat_action: error — missing chat_id ---

output=$(tg_send_chat_action "" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "chat action fails without chat_id"

# --- tg_stub_enqueue: error — missing args ---

output=$(tg_stub_enqueue "" "text" 100 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "enqueue fails without chat_id"

output=$(tg_stub_enqueue 123 "" 100 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "enqueue fails without text"

output=$(tg_stub_enqueue 123 "text" "" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "enqueue fails without update_id"

# --- tg_stub_reset: clears both files ---

tg_stub_enqueue 123 "msg" 1
tg_send_message "123" "reply" >/dev/null
tg_stub_reset
check_output "$(test -f "$SHELLCLAW_TELEGRAM_STUB_QUEUE" && echo exists || echo gone)" \
    "gone" "reset removes queue file"
check_output "$(test -f "$SHELLCLAW_TELEGRAM_STUB_LOG" && echo exists || echo gone)" \
    "gone" "reset removes log file"

# --- tg_get_updates: different chat_ids ---

tg_stub_reset
tg_stub_enqueue 111 "From Alice" 200
tg_stub_enqueue 222 "From Bob" 201

output=$(tg_get_updates 0 0)
alice_chat=$(printf '%s' "$output" | jq '.result[0].message.chat.id')
bob_chat=$(printf '%s' "$output" | jq '.result[1].message.chat.id')
check_output "$alice_chat" "111" "first update has Alice's chat_id"
check_output "$bob_chat" "222" "second update has Bob's chat_id"

# --- llm_call: --conversation-id accepted by stub ---

llm_stub_reset
output=$(llm_call "Hello" --conversation-id "telegram_12345") && rc=0 || rc=$?
check_exit "$rc" 0 "stub accepts --conversation-id"
check_contains "$output" "stub response" "returns stub response with --conversation-id"

# --- llm_call: --conversation-id with other flags ---

output=$(llm_call "Hello" --system "Be helpful" --conversation-id "chat_99" --model "gpt-4") && rc=0 || rc=$?
check_exit "$rc" 0 "--conversation-id works with other flags"

# --- llm_call: --conversation-id requires value ---

output=$(llm_call "Hello" --conversation-id 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "--conversation-id fails without value"
check_contains "$output" "--conversation-id requires" "error mentions --conversation-id"

summary "telegram.sh"
