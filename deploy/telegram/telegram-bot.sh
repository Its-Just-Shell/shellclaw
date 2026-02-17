#!/usr/bin/env bash
# deploy/telegram/telegram-bot.sh — Telegram bot built from shellclaw primitives
#
# A polling loop that composes all five core libraries (log, config, session,
# llm, compose) plus the Telegram API adapter. Structurally the same as
# scripts/chat-loop.sh — read input, produce output — except I/O comes from
# Telegram instead of a terminal.
#
# Each Telegram chat gets:
#   - Its own session file (JSONL) for observability
#   - Its own conversation ID (--conversation-id) for isolated multi-turn
#
# Environment:
#   SHELLCLAW_TELEGRAM_TOKEN  — Bot token from @BotFather (required)
#   SHELLCLAW_LLM_BACKEND     — "llm" (default) or "stub" for testing
#   SHELLCLAW_TELEGRAM_STUB   — Set to "1" for offline testing
#
# Usage:
#   export SHELLCLAW_TELEGRAM_TOKEN="your-token-here"
#   ./deploy/telegram/telegram-bot.sh
#
# Stub testing (no network, no API keys):
#   SHELLCLAW_LLM_BACKEND=stub SHELLCLAW_TELEGRAM_STUB=1 \
#     ./deploy/telegram/telegram-bot.sh

set -euo pipefail

# --- Resolve project root ---
# The script lives at deploy/telegram/telegram-bot.sh, so project root
# is two directories up. cd + pwd resolves any symlinks to an absolute path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLCLAW_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
export SHELLCLAW_HOME

# --- Source all libraries ---
# These are the five core primitives plus the Telegram adapter.
# Sourcing (not executing) makes all functions available in this process.
source "$SHELLCLAW_HOME/lib/log.sh"
source "$SHELLCLAW_HOME/lib/config.sh"
source "$SHELLCLAW_HOME/lib/session.sh"
source "$SHELLCLAW_HOME/lib/llm.sh"
source "$SHELLCLAW_HOME/lib/compose.sh"
source "$SCRIPT_DIR/lib/telegram.sh"

# --- Initialize configuration ---
# config_init reads config/shellclaw.env and sets up all SHELLCLAW_* variables.
config_init "$SHELLCLAW_HOME"

# --- Resolve agent ---
AGENT_ID="telegram"
export SHELLCLAW_AGENT_ID="$AGENT_ID"

# Build the agent directory path and compose the system prompt.
# compose_system reads soul.md + any context modules from the agent dir.
AGENT_DIR="$SHELLCLAW_HOME/agents/$AGENT_ID"
SYSTEM_PROMPT=$(compose_system "$AGENT_DIR")

# --- Set up logging ---
# Log file goes in the agent's sessions directory alongside conversation files.
SESSIONS_DIR="$AGENT_DIR/sessions"
mkdir -p "$SESSIONS_DIR"
export LOG_FILE="$SESSIONS_DIR/bot.jsonl"

# --- Validate token ---
if [[ "${SHELLCLAW_TELEGRAM_STUB:-}" != "1" && -z "${SHELLCLAW_TELEGRAM_TOKEN:-}" ]]; then
    echo "Error: SHELLCLAW_TELEGRAM_TOKEN not set" >&2
    echo "Get a token from @BotFather on Telegram, then:" >&2
    echo "  export SHELLCLAW_TELEGRAM_TOKEN=\"your-token-here\"" >&2
    exit 1
fi

# --- Helper: get session file for a chat ---
# Each Telegram chat_id gets its own JSONL session file for observability.
# Files live in agents/telegram/sessions/ and are named by chat_id.
_session_file() {
    local chat_id="$1"
    echo "$SESSIONS_DIR/chat_${chat_id}.jsonl"
}

# --- Handle a regular message ---
# This is the core flow: log → session → typing indicator → llm_call → session → send
_handle_message() {
    local chat_id="$1"
    local text="$2"
    local session_file
    session_file=$(_session_file "$chat_id")

    # Log the inbound message
    log_event "telegram_input" "$text"

    # Mirror to the session file for observability (cat, grep, jq)
    session_append "$session_file" "user" "$text"

    # Show "typing..." in the Telegram chat while we wait for the LLM
    tg_send_chat_action "$chat_id" >/dev/null 2>&1 || true

    # Call the LLM with a named conversation ID for per-chat multi-turn.
    # --conversation-id maps to llm --cid, giving each chat its own thread.
    local response
    response=$(llm_call "$text" \
        --system "$SYSTEM_PROMPT" \
        --conversation-id "telegram_${chat_id}")

    # Mirror the response to the session file
    session_append "$session_file" "assistant" "$response"

    # Log the outbound response
    log_event "telegram_response" "$response"

    # Send it back to Telegram
    tg_send_message "$chat_id" "$response" >/dev/null 2>&1
}

# --- Handle bot commands ---
_handle_command() {
    local chat_id="$1"
    local text="$2"

    case "$text" in
        /start|/start@*)
            local greeting="Hello! I'm a shellclaw bot — an LLM assistant built entirely from bash libraries."
            greeting+=$'\n\n'"Send me any message to chat. Commands:"
            greeting+=$'\n'"  /reset — clear conversation history"
            greeting+=$'\n'"  /session — show conversation stats"
            tg_send_message "$chat_id" "$greeting" >/dev/null 2>&1
            log_event "telegram_command" "/start from $chat_id"
            ;;
        /reset|/reset@*)
            local session_file
            session_file=$(_session_file "$chat_id")
            session_clear "$session_file"
            tg_send_message "$chat_id" "Conversation cleared. Fresh start!" >/dev/null 2>&1
            log_event "telegram_command" "/reset from $chat_id"
            ;;
        /session|/session@*)
            local session_file
            session_file=$(_session_file "$chat_id")
            local count
            count=$(session_count "$session_file")
            tg_send_message "$chat_id" "Messages in this conversation: $count" >/dev/null 2>&1
            log_event "telegram_command" "/session from $chat_id"
            ;;
        /*)
            tg_send_message "$chat_id" "Unknown command. Try /start, /reset, or /session." >/dev/null 2>&1
            ;;
    esac
}

# --- Clean shutdown ---
# trap catches Ctrl-C (SIGINT) and kill (SIGTERM) for graceful exit.
_shutdown() {
    log_event "bot_shutdown" "Telegram bot stopping"
    echo ""
    echo "Bot stopped."
    exit 0
}
trap _shutdown SIGINT SIGTERM

# --- Main polling loop ---
log_event "bot_startup" "Telegram bot starting (agent=$AGENT_ID)"
echo "Telegram bot started (agent=$AGENT_ID)"
echo "Logging to: $LOG_FILE"
echo "Press Ctrl-C to stop"
echo "---"

# OFFSET tracks which updates we've already processed.
# Telegram returns updates with update_id >= offset.
# After processing, we advance offset past the highest update_id.
OFFSET=0

while true; do
    # Long-poll Telegram for new messages (30 second timeout).
    # If no messages arrive within 30s, getUpdates returns empty and we loop.
    updates=$(tg_get_updates "$OFFSET" 30) || {
        # Network error — wait briefly and retry
        sleep 5
        continue
    }

    # Parse the number of updates in the result array.
    # jq -r outputs raw text (no quotes), so we get a plain number.
    update_count=$(printf '%s' "$updates" | jq -r '.result | length')

    # Skip if no new messages
    if [[ "$update_count" -eq 0 ]]; then
        continue
    fi

    # Process each update one at a time.
    # jq -c outputs each array element as a compact JSON line.
    while IFS= read -r update; do
        # Extract fields from the update JSON.
        # update_id: unique incrementing ID for offset tracking
        # chat_id: identifies which Telegram chat sent the message
        # text: the message content (null for photos/stickers/etc)
        update_id=$(printf '%s' "$update" | jq -r '.update_id')
        chat_id=$(printf '%s' "$update" | jq -r '.message.chat.id // empty')
        text=$(printf '%s' "$update" | jq -r '.message.text // empty')

        # Advance offset past this update so we don't process it again.
        # Telegram wants offset = highest_seen_update_id + 1.
        OFFSET=$(( update_id + 1 ))

        # Skip updates without a text message (photos, stickers, etc.)
        if [[ -z "$chat_id" || -z "$text" ]]; then
            continue
        fi

        # Dispatch: commands start with /, everything else is a message
        if [[ "$text" == /* ]]; then
            _handle_command "$chat_id" "$text"
        else
            _handle_message "$chat_id" "$text"
        fi

    done < <(printf '%s' "$updates" | jq -c '.result[]')
done
