#!/usr/bin/env bash
# shellclaw/lib/llm.sh — LLM call wrapper
#
# The "only new primitive": text in, LLM, text out.
# Wraps Simon Willison's llm CLI for the real backend.
# Provides a stub backend for testing without API calls.
#
# Environment:
#   SHELLCLAW_LLM_BACKEND  — "llm" (real) or "stub" (testing). Default: "llm"
#   SHELLCLAW_MODEL        — Model identifier passed to llm via -m (optional)
#
# Usage:
#   source lib/llm.sh
#   llm_call "What is 2+2?"
#   llm_call "Summarize this" --system "You are a helpful assistant"
#   llm_call "Follow up" --continue
#   SHELLCLAW_LLM_BACKEND=stub llm_call "test message"

# File-based counter for stub responses.
# Why a file instead of a variable? Because $(llm_call ...) runs in a subshell —
# any variable changes inside $() are lost when the subshell exits. A file persists
# across subshells because the filesystem is shared. $$ is the parent shell's PID
# (stays the same in subshells), so all $() calls share one counter file.
_SHELLCLAW_STUB_COUNTER_FILE="${TMPDIR:-/tmp}/shellclaw_stub_counter_$$"

# llm_call <message> [--system <prompt>] [--model <model>] [--continue] [--conversation-id <id>]
#   Sends a message to an LLM and writes the response to stdout.
#   Dispatches to real llm CLI or stub based on $SHELLCLAW_LLM_BACKEND.
#
#   Arguments:
#     message             — required, the text to send (first positional arg)
#     --system            — optional system prompt string
#     --model             — optional model override (defaults to $SHELLCLAW_MODEL)
#     --continue          — continue a previous conversation (maps to llm -c)
#     --conversation-id   — named conversation thread (maps to llm --cid)
#
#   Returns: 0 on success, 1 on error
llm_call() {
    local message=""
    local system_prompt=""
    local model=""
    local continue_flag=false
    local conversation_id=""

    # Parse arguments: first positional arg is the message, rest are flags.
    # shift moves past each consumed argument so the while loop advances.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --system)
                system_prompt="${2:-}"
                if [[ -z "$system_prompt" ]]; then
                    echo "llm_call: --system requires a value" >&2
                    return 1
                fi
                shift 2
                ;;
            --model)
                model="${2:-}"
                if [[ -z "$model" ]]; then
                    echo "llm_call: --model requires a value" >&2
                    return 1
                fi
                shift 2
                ;;
            --continue)
                continue_flag=true
                shift
                ;;
            --conversation-id)
                conversation_id="${2:-}"
                if [[ -z "$conversation_id" ]]; then
                    echo "llm_call: --conversation-id requires a value" >&2
                    return 1
                fi
                shift 2
                ;;
            -*)
                echo "llm_call: unknown flag: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$message" ]]; then
                    message="$1"
                else
                    echo "llm_call: unexpected argument: $1" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$message" ]]; then
        echo "llm_call: message required" >&2
        return 1
    fi

    local backend="${SHELLCLAW_LLM_BACKEND:-llm}"

    case "$backend" in
        stub)
            _llm_call_stub "$message"
            ;;
        llm)
            _llm_call_real "$message" "$system_prompt" "$model" "$continue_flag" "$conversation_id"
            ;;
        *)
            echo "llm_call: unknown backend: $backend" >&2
            return 1
            ;;
    esac
}

# _llm_call_stub <message>
#   Returns "stub response N" with an incrementing counter.
#   For testing without API calls, network, or llm CLI dependency.
#   Uses a file-based counter so it works inside $() subshells.
_llm_call_stub() {
    local count=0
    # Read current count from file if it exists (-f tests "is this a regular file?")
    if [[ -f "$_SHELLCLAW_STUB_COUNTER_FILE" ]]; then
        count=$(cat "$_SHELLCLAW_STUB_COUNTER_FILE")
    fi
    (( count++ ))
    # Write the new count back to the file for the next call
    echo "$count" > "$_SHELLCLAW_STUB_COUNTER_FILE"
    echo "stub response ${count}"
}

# llm_stub_reset
#   Resets the stub counter to 0. Call this between test groups if you
#   need predictable numbering. Removes the counter file.
llm_stub_reset() {
    rm -f "$_SHELLCLAW_STUB_COUNTER_FILE"
}

# _llm_call_real <message> <system_prompt> <model> <continue_flag> <conversation_id>
#   Dispatches to the real llm CLI.
#   Builds the command dynamically based on which options are set.
_llm_call_real() {
    local message="$1"
    local system_prompt="$2"
    local model="$3"
    local continue_flag="$4"
    local conversation_id="$5"

    # Check that llm CLI is available on PATH
    if ! command -v llm &>/dev/null; then
        echo "llm_call: llm CLI not found (install: pip install llm)" >&2
        return 1
    fi

    # Build the llm command as an array.
    # Arrays avoid word-splitting issues with spaces in arguments.
    local cmd=(llm)

    # -s passes the system prompt as the API's system field (not flattened into user message)
    if [[ -n "$system_prompt" ]]; then
        cmd+=(-s "$system_prompt")
    fi

    # -m selects the model; falls back to $SHELLCLAW_MODEL if no --model flag given
    local effective_model="${model:-${SHELLCLAW_MODEL:-}}"
    if [[ -n "$effective_model" ]]; then
        cmd+=(-m "$effective_model")
    fi

    # -c tells llm to continue the previous conversation (multi-turn)
    if [[ "$continue_flag" == "true" ]]; then
        cmd+=(-c)
    fi

    # --cid selects a named conversation thread (multi-turn by conversation ID)
    if [[ -n "$conversation_id" ]]; then
        cmd+=(--cid "$conversation_id")
    fi

    # Pipe the message into llm on stdin.
    # llm reads stdin as the prompt when no positional prompt is given.
    printf '%s' "$message" | "${cmd[@]}"
}
