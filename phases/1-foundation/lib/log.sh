#!/usr/bin/env bash
# shellclaw/lib/log.sh — Structured JSONL logging
#
# Appends JSON log entries to a file. Each entry is one line of valid JSON.
# Uses jq for safe JSON construction (handles quotes, newlines, special chars).
#
# Environment:
#   LOG_FILE            — Path to append log entries to (required)
#   SHELLCLAW_AGENT_ID  — Agent identifier included in each entry (default: "unknown")
#
# Usage:
#   source lib/log.sh
#   export LOG_FILE="/path/to/agent.jsonl"
#   log_event "user_input" "Hello, world"
#
# Output format (one per line):
#   {"ts":"2026-02-12T10:00:00Z","agent":"default","event":"user_input","message":"Hello, world"}

# log_event <event_type> [message]
#   event_type  — required, e.g. "user_input", "llm_response", "session_start"
#   message     — optional, free-form text (safely JSON-escaped by jq)
log_event() {
    local event_type="${1:-}"
    local message="${2:-}"
    local agent="${SHELLCLAW_AGENT_ID:-unknown}"

    if [[ -z "${LOG_FILE:-}" ]]; then
        echo "log_event: LOG_FILE not set" >&2
        return 1
    fi

    if [[ -z "$event_type" ]]; then
        echo "log_event: event_type required" >&2
        return 1
    fi

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n -c \
        --arg ts "$ts" \
        --arg agent "$agent" \
        --arg event "$event_type" \
        --arg message "$message" \
        '{ts: $ts, agent: $agent, event: $event, message: $message}' \
        >> "$LOG_FILE"
}
