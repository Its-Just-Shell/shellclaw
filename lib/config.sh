#!/usr/bin/env bash
# shellclaw/lib/config.sh — Configuration loading
#
# Loads global config from shellclaw.env (sourced) and per-agent config
# from agents.json (parsed with jq).
#
# Requires: jq
#
# Usage:
#   source lib/config.sh
#   config_init "/path/to/shellclaw"   # or set SHELLCLAW_HOME first
#   config_get "SHELLCLAW_MODEL"
#   config_agent "default" "soul"

# config_init [shellclaw_home]
#   Loads config/shellclaw.env and exports config variables.
#   Accepts an explicit path or falls back to $SHELLCLAW_HOME.
#   Sets defaults for any values not specified in the env file.
config_init() {
    local home="${1:-${SHELLCLAW_HOME:-}}"

    if [[ -z "$home" ]]; then
        echo "config_init: SHELLCLAW_HOME not set and no argument provided" >&2
        return 1
    fi

    export SHELLCLAW_HOME="$home"

    local env_file="$SHELLCLAW_HOME/config/shellclaw.env"
    if [[ ! -f "$env_file" ]]; then
        echo "config_init: $env_file not found" >&2
        return 1
    fi

    # shellcheck source=/dev/null
    source "$env_file"

    # Defaults for anything not set in env file
    : "${SHELLCLAW_MODEL:=claude-sonnet-4-5-20250929}"
    : "${SHELLCLAW_DEFAULT_AGENT:=default}"
    : "${SHELLCLAW_TOOL_BACKEND:=bash}"
    : "${SHELLCLAW_LLM_BACKEND:=llm}"
    : "${SHELLCLAW_TOOLS_DIR:=tools}"

    export SHELLCLAW_MODEL SHELLCLAW_DEFAULT_AGENT SHELLCLAW_TOOL_BACKEND SHELLCLAW_LLM_BACKEND SHELLCLAW_TOOLS_DIR
}

# config_get <key>
#   Echoes the value of a shell variable by name.
#   Returns empty string if the variable is unset.
config_get() {
    local key="${1:-}"

    if [[ -z "$key" ]]; then
        echo "config_get: key required" >&2
        return 1
    fi

    # Indirect expansion with :- to avoid nounset errors
    echo "${!key:-}"
}

# config_agent <agent_id> <key>
#   Reads a per-agent value from config/agents.json.
#   Returns empty string if agent or key doesn't exist.
#
#   agents.json schema:
#   {
#     "<agent_id>": {
#       "soul": "<relative path to soul.md>",
#       "model": "<model override or null for global default>"
#     }
#   }
config_agent() {
    local agent_id="${1:-}"
    local key="${2:-}"
    local agents_file="${SHELLCLAW_HOME:-}/config/agents.json"

    if [[ -z "$agent_id" || -z "$key" ]]; then
        echo "config_agent: agent_id and key required" >&2
        return 1
    fi

    if [[ ! -f "$agents_file" ]]; then
        echo "config_agent: $agents_file not found" >&2
        return 1
    fi

    # // empty: output nothing (not "null") when key is missing or null
    jq -r --arg id "$agent_id" --arg key "$key" \
        '.[$id][$key] // empty' "$agents_file"
}
