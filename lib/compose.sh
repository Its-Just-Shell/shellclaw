#!/usr/bin/env bash
# shellclaw/lib/compose.sh — System prompt assembly
#
# Reads an agent's soul.md and returns the assembled system prompt.
# For v2, this is essentially cat. Wrapped in a function so we can
# extend it later (context.md, memory summary, tool descriptions)
# without changing any callers.
#
# Usage:
#   source lib/compose.sh
#   prompt=$(compose_system "agents/default")
#   llm_call "Hello" --system "$prompt"

# compose_system <agent_dir>
#   Reads soul.md from the given agent directory and prints it to stdout.
#   The agent_dir should be the path to the agent's directory (e.g. "agents/default").
#
#   Returns: 0 on success, 1 if soul.md is missing or agent_dir not given
compose_system() {
    local agent_dir="${1:-}"

    if [[ -z "$agent_dir" ]]; then
        echo "compose_system: agent directory required" >&2
        return 1
    fi

    local soul_file="$agent_dir/soul.md"

    if [[ ! -f "$soul_file" ]]; then
        echo "compose_system: $soul_file not found" >&2
        return 1
    fi

    # Read the soul file and print it.
    # cat outputs the file contents to stdout — the caller captures it with $().
    cat "$soul_file"
}
