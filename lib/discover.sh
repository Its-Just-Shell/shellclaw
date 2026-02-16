#!/usr/bin/env bash
# shellclaw/lib/discover.sh — Tool catalog discovery
#
# Discovers self-describing tools by walking a directory, calling --describe
# on each executable, and assembling a JSON array of tool schemas.
# The catalog is derived, not maintained — tools own their descriptions.
#
# Requires: jq
#
# Usage:
#   source lib/discover.sh
#   catalog=$(discover_tools "tools")
#   schema=$(discover_tool "tools/get_weather.sh")

# discover_tool <tool_path>
#   Calls --describe on a single tool and validates the output.
#   Outputs the tool's JSON schema to stdout on success.
#   Returns: 0=success, 1=error (details on stderr)
discover_tool() {
    local tool_path="${1:-}"

    if [[ -z "$tool_path" ]]; then
        echo "discover_tool: tool path required" >&2
        return 1
    fi

    if [[ ! -f "$tool_path" ]]; then
        echo "discover_tool: not found: $tool_path" >&2
        return 1
    fi

    if [[ ! -x "$tool_path" ]]; then
        echo "discover_tool: not executable: $tool_path" >&2
        return 1
    fi

    # Call --describe and capture stdout. Stderr is suppressed to avoid
    # noise from tools that print warnings during description.
    local desc
    desc=$("$tool_path" --describe 2>/dev/null) && rc=0 || rc=$?

    if [[ $rc -ne 0 ]]; then
        echo "discover_tool: --describe failed for $tool_path (exit $rc)" >&2
        return 1
    fi

    if [[ -z "$desc" ]]; then
        echo "discover_tool: --describe returned empty output for $tool_path" >&2
        return 1
    fi

    # Validate that the output is parseable JSON.
    # jq '.' parses and re-outputs. If it fails, the output isn't valid JSON.
    if ! printf '%s' "$desc" | jq '.' >/dev/null 2>&1; then
        echo "discover_tool: --describe output is not valid JSON for $tool_path" >&2
        return 1
    fi

    # Validate required fields: name, description, parameters.
    # has() checks if a key exists in the JSON object.
    local valid
    valid=$(printf '%s' "$desc" | jq 'has("name") and has("description") and has("parameters")' 2>/dev/null)

    if [[ "$valid" != "true" ]]; then
        echo "discover_tool: --describe missing required fields (name, description, parameters) for $tool_path" >&2
        return 1
    fi

    # Output the validated schema
    printf '%s\n' "$desc"
}

# discover_tools <tools_dir>
#   Walks a directory, calls --describe on each executable, and
#   assembles a JSON array of tool schemas.
#   Skips non-executable files and tools whose --describe fails.
#   Warnings for skipped tools go to stderr.
#   Outputs the JSON array to stdout.
#   Returns: 0 always (an empty catalog is valid)
discover_tools() {
    local tools_dir="${1:-}"

    if [[ -z "$tools_dir" ]]; then
        echo "discover_tools: tools directory required" >&2
        return 1
    fi

    if [[ ! -d "$tools_dir" ]]; then
        echo "discover_tools: directory not found: $tools_dir" >&2
        return 1
    fi

    local descriptions=""
    local tool_name

    for tool in "$tools_dir"/*; do
        # Skip if not a regular file (could be a subdirectory)
        [[ -f "$tool" ]] || continue

        # Skip non-executable files silently
        [[ -x "$tool" ]] || continue

        tool_name=$(basename "$tool")

        # Try to discover this tool. On failure, warn and skip.
        local desc
        desc=$(discover_tool "$tool" 2>/dev/null)
        if [[ $? -ne 0 ]]; then
            echo "discover_tools: skipping $tool_name (--describe failed)" >&2
            continue
        fi

        descriptions+="$desc"$'\n'
    done

    # Assemble the JSON array.
    # jq -s '.' (slurp mode) reads multiple JSON values and produces an array.
    # Guard: if no tools were found, output [] directly.
    if [[ -z "${descriptions// /}" ]]; then
        echo '[]'
    else
        printf '%s' "$descriptions" | jq -s '.'
    fi
}
