#!/usr/bin/env bash
# shellclaw/lib/compose.sh — System prompt assembly
#
# Reads an agent's soul.md and any context modules from the agent's
# context/ directory, and returns the assembled system prompt.
# Context modules are markdown files that provide domain knowledge,
# constraints, or procedural guidance. They are loaded alphabetically.
#
# Usage:
#   source lib/compose.sh
#   prompt=$(compose_system "agents/default")
#   llm_call "Hello" --system "$prompt"

# compose_system <agent_dir>
#   Reads soul.md from the given agent directory and prints it to stdout.
#   If a context/ subdirectory exists, also loads all .md files from it
#   in alphabetical order, separated by markdown horizontal rules (---).
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

    # Identity — always loaded
    cat "$soul_file"

    # Context modules — domain knowledge, procedural guidance.
    # Loaded alphabetically from agents/<id>/context/*.md.
    # Separated by markdown horizontal rules for visual clarity.
    if [[ -d "$agent_dir/context" ]]; then
        for module in "$agent_dir/context"/*.md; do
            # Guard: if no .md files exist, the glob returns the literal
            # pattern string. [[ -f ]] catches this — skip if not a real file.
            [[ -f "$module" ]] || continue
            printf '\n---\n'
            cat "$module"
        done
    fi
}
