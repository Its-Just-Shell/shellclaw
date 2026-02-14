#!/usr/bin/env bash
# shellclaw/lib/session.sh — Conversation session management
#
# Mirrors LLM conversation state as inspectable JSONL files.
# The llm CLI manages the actual conversation for API calls.
# These files are the observability layer — cat, grep, jq, diff, git.
#
# All functions take a file path as their first argument, since you
# may operate on different session files (current, archived, etc.).
#
# Usage:
#   source lib/session.sh
#   session_append "sessions/current.jsonl" "user" "Hello"
#   session_append "sessions/current.jsonl" "assistant" "Hi there"
#   session_load "sessions/current.jsonl"
#   session_count "sessions/current.jsonl"
#   session_clear "sessions/current.jsonl"
#
# JSONL format (one per line):
#   {"ts":"2026-02-12T10:00:00Z","role":"user","content":"Hello"}

# session_append <file> <role> <content>
#   Appends one JSONL entry to the session file.
#   Creates the file if it doesn't exist.
#   role: "user" or "assistant"
#   content: the message text (safely JSON-escaped by jq)
session_append() {
    local file="${1:-}"
    local role="${2:-}"
    local content="${3:-}"

    if [[ -z "$file" ]]; then
        echo "session_append: file path required" >&2
        return 1
    fi

    if [[ -z "$role" ]]; then
        echo "session_append: role required" >&2
        return 1
    fi

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n -c \
        --arg ts "$ts" \
        --arg role "$role" \
        --arg content "$content" \
        '{ts: $ts, role: $role, content: $content}' \
        >> "$file"
}

# session_load <file> [limit]
#   Prints the conversation as a human-readable transcript.
#   Optional limit shows only the last N entries.
#   Returns nothing (exit 0) for empty or missing files.
#
#   Output format:
#     user: Hello
#     assistant: Hi there
session_load() {
    local file="${1:-}"
    local limit="${2:-}"

    if [[ -z "$file" ]]; then
        echo "session_load: file path required" >&2
        return 1
    fi

    if [[ ! -f "$file" || ! -s "$file" ]]; then
        return 0
    fi

    if [[ -n "$limit" ]]; then
        tail -n "$limit" "$file" | jq -r '"\(.role): \(.content)"'
    else
        jq -r '"\(.role): \(.content)"' "$file"
    fi
}

# session_count <file>
#   Prints the number of entries in the session file.
#   Returns 0 for empty or non-existent files.
session_count() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        echo "session_count: file path required" >&2
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 0
    fi

    wc -l < "$file" | tr -d ' '
}

# session_clear <file>
#   Archives the current session file by renaming it with a timestamp,
#   then creates a fresh empty file at the same path.
#   If the file doesn't exist or is empty, just creates it.
#   Archive name: <file>.<YYYYMMDDTHHMMSSZ>
session_clear() {
    local file="${1:-}"

    if [[ -z "$file" ]]; then
        echo "session_clear: file path required" >&2
        return 1
    fi

    if [[ -f "$file" && -s "$file" ]]; then
        local ts
        ts=$(date -u +"%Y%m%dT%H%M%SZ")
        mv "$file" "${file}.${ts}"
    fi

    : > "$file"
}
