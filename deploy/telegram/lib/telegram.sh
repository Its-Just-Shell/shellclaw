#!/usr/bin/env bash
# deploy/telegram/lib/telegram.sh — Telegram Bot API adapter
#
# Three curl wrappers for the Telegram Bot API, plus a stub backend
# for offline testing. When SHELLCLAW_TELEGRAM_STUB=1, all API calls
# are replaced with file-based fakes.
#
# Environment:
#   SHELLCLAW_TELEGRAM_TOKEN       — Bot token from BotFather (required for real calls)
#   SHELLCLAW_TELEGRAM_STUB        — Set to "1" to use stub backend
#   SHELLCLAW_TELEGRAM_STUB_LOG    — File where stub records sent messages
#   SHELLCLAW_TELEGRAM_STUB_QUEUE  — File containing queued fake updates (JSONL)
#
# Usage:
#   source deploy/telegram/lib/telegram.sh
#   updates=$(tg_get_updates 0 30)
#   tg_send_message "12345" "Hello!"
#   tg_send_chat_action "12345"

_TG_API_BASE="https://api.telegram.org/bot"

# tg_get_updates <offset> [timeout]
#   Long-polls the Telegram getUpdates endpoint.
#   offset: integer, only return updates with update_id >= offset
#   timeout: seconds to long-poll (default: 30)
#   Returns: JSON response from Telegram (or stub equivalent)
tg_get_updates() {
    local offset="${1:-0}"
    local timeout="${2:-30}"

    if [[ "${SHELLCLAW_TELEGRAM_STUB:-}" == "1" ]]; then
        _tg_get_updates_stub "$offset"
        return
    fi

    curl -s "${_TG_API_BASE}${SHELLCLAW_TELEGRAM_TOKEN}/getUpdates" \
        -d "offset=${offset}" \
        -d "timeout=${timeout}" \
        -d "allowed_updates=[\"message\"]"
}

# tg_send_message <chat_id> <text>
#   Sends a text message to a Telegram chat.
#   Uses --data-urlencode to safely handle special characters.
#   Returns: JSON response from Telegram (or stub equivalent)
tg_send_message() {
    local chat_id="${1:-}"
    local text="${2:-}"

    if [[ -z "$chat_id" || -z "$text" ]]; then
        echo "tg_send_message: chat_id and text required" >&2
        return 1
    fi

    if [[ "${SHELLCLAW_TELEGRAM_STUB:-}" == "1" ]]; then
        _tg_send_message_stub "$chat_id" "$text"
        return
    fi

    curl -s "${_TG_API_BASE}${SHELLCLAW_TELEGRAM_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${chat_id}" \
        --data-urlencode "text=${text}"
}

# tg_send_chat_action <chat_id>
#   Sends a "typing..." indicator to the chat.
#   Automatically expires after ~5 seconds on Telegram's side.
#   Returns: JSON response from Telegram (or stub equivalent)
tg_send_chat_action() {
    local chat_id="${1:-}"

    if [[ -z "$chat_id" ]]; then
        echo "tg_send_chat_action: chat_id required" >&2
        return 1
    fi

    if [[ "${SHELLCLAW_TELEGRAM_STUB:-}" == "1" ]]; then
        return 0
    fi

    curl -s "${_TG_API_BASE}${SHELLCLAW_TELEGRAM_TOKEN}/sendChatAction" \
        -d "chat_id=${chat_id}" \
        -d "action=typing"
}

# --- Stub infrastructure ---
# For offline testing without a Telegram token or network.
# Mirrors the pattern from lib/llm.sh — file-based state that
# persists across subshells.

# tg_stub_enqueue <chat_id> <text> <update_id>
#   Adds a fake incoming message to the stub queue.
#   The next call to tg_get_updates (stub) will return queued messages.
tg_stub_enqueue() {
    local chat_id="${1:-}"
    local text="${2:-}"
    local update_id="${3:-}"
    local queue="${SHELLCLAW_TELEGRAM_STUB_QUEUE:-/tmp/shellclaw_tg_stub_queue_$$}"

    if [[ -z "$chat_id" || -z "$text" || -z "$update_id" ]]; then
        echo "tg_stub_enqueue: chat_id, text, and update_id required" >&2
        return 1
    fi

    # Build a minimal Telegram-shaped update JSON and append to queue file.
    # jq -n -c creates a compact JSON object from the given arguments.
    jq -n -c \
        --argjson update_id "$update_id" \
        --argjson chat_id "$chat_id" \
        --arg text "$text" \
        '{update_id: $update_id, message: {chat: {id: $chat_id}, text: $text}}' \
        >> "$queue"
}

# tg_stub_reset
#   Clears the stub queue and log files. Call between test groups.
tg_stub_reset() {
    rm -f "${SHELLCLAW_TELEGRAM_STUB_QUEUE:-/tmp/shellclaw_tg_stub_queue_$$}"
    rm -f "${SHELLCLAW_TELEGRAM_STUB_LOG:-/tmp/shellclaw_tg_stub_log_$$}"
}

# _tg_get_updates_stub <offset>
#   Returns queued messages as a Telegram-shaped JSON response.
#   Only returns messages with update_id >= offset.
#   After returning, clears the queue (messages are consumed).
_tg_get_updates_stub() {
    local offset="${1:-0}"
    local queue="${SHELLCLAW_TELEGRAM_STUB_QUEUE:-/tmp/shellclaw_tg_stub_queue_$$}"

    if [[ ! -f "$queue" || ! -s "$queue" ]]; then
        # No messages queued — return empty result (same shape as Telegram API)
        echo '{"ok":true,"result":[]}'
        return 0
    fi

    # Filter updates where update_id >= offset, collect into a JSON array.
    # jq -s reads all JSONL lines into an array, then we filter by offset.
    local results
    results=$(jq -s --argjson offset "$offset" \
        '[.[] | select(.update_id >= $offset)]' "$queue")

    # Clear consumed messages from the queue
    : > "$queue"

    # Wrap in Telegram response envelope
    jq -n -c --argjson result "$results" '{"ok":true,"result":$result}'
}

# _tg_send_message_stub <chat_id> <text>
#   Records sent messages to the stub log file instead of calling Telegram.
#   Each line is a JSON object with chat_id, text, and timestamp.
_tg_send_message_stub() {
    local chat_id="$1"
    local text="$2"
    local log="${SHELLCLAW_TELEGRAM_STUB_LOG:-/tmp/shellclaw_tg_stub_log_$$}"

    # Append a JSONL record of the sent message
    jq -n -c \
        --arg chat_id "$chat_id" \
        --arg text "$text" \
        --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{ts: $ts, chat_id: $chat_id, text: $text}' \
        >> "$log"

    # Return a Telegram-shaped success response
    echo '{"ok":true,"result":{"message_id":1}}'
}
