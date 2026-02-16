#!/usr/bin/env bash
# shellclaw/lib/dispatch.sh — Tool dispatch and validation
#
# Executes tool calls: finds the tool, validates arguments, runs
# the executable, captures results. Default-deny: only tools present
# in the discovered catalog can be executed.
#
# Requires: jq
# Optional: lib/log.sh (for log_event, used when LOG_FILE is set)
#
# Usage:
#   source lib/dispatch.sh
#   source lib/discover.sh
#   catalog=$(discover_tools "tools")
#   validate_tool_call "$catalog" "get_weather" '{"location":"NYC"}'
#   result=$(dispatch_tool "tools" "get_weather" '{"location":"NYC"}')

# validate_tool_call <catalog_json> <tool_name> <args_json>
#   Validates that tool_name exists in the catalog and args_json
#   contains all required fields from the tool's schema.
#   Returns: 0=valid, 1=invalid (details on stderr)
validate_tool_call() {
    local catalog_json="${1:-}"
    local tool_name="${2:-}"
    local args_json="${3:-}"

    if [[ -z "$catalog_json" ]]; then
        echo "validate_tool_call: catalog JSON required" >&2
        return 1
    fi

    if [[ -z "$tool_name" ]]; then
        echo "validate_tool_call: tool name required" >&2
        return 1
    fi

    if [[ -z "$args_json" ]]; then
        echo "validate_tool_call: args JSON required" >&2
        return 1
    fi

    # Look up the tool in the catalog by name.
    # select() filters the array, first picks the first match.
    # // empty returns nothing (not "null") if not found.
    local tool_schema
    tool_schema=$(printf '%s' "$catalog_json" | jq -c \
        --arg name "$tool_name" \
        '[.[] | select(.name == $name)] | first // empty')

    if [[ -z "$tool_schema" ]]; then
        echo "validate_tool_call: tool '$tool_name' not found in catalog" >&2
        return 1
    fi

    # Check that all required fields are present in args_json.
    # Strategy: compute (required_fields - provided_fields). If the result
    # is non-empty, some required fields are missing.
    # jq 'length' on an empty array returns 0.
    local missing
    missing=$(jq -n \
        --argjson schema "$tool_schema" \
        --argjson args "$args_json" \
        '($schema.parameters.required // []) - ($args | keys)')

    local missing_count
    missing_count=$(printf '%s' "$missing" | jq 'length')

    if [[ "$missing_count" != "0" ]]; then
        echo "validate_tool_call: missing required fields: $missing" >&2
        return 1
    fi

    return 0
}

# dispatch_tool <tools_dir> <tool_name> <args_json>
#   Finds the named tool in tools_dir, executes it with args_json,
#   and outputs the result to stdout.
#   Exit: 0=success, 1=tool not found, 2=tool execution failed
dispatch_tool() {
    local tools_dir="${1:-}"
    local tool_name="${2:-}"
    local args_json="${3:-}"

    if [[ -z "$tools_dir" ]]; then
        echo "dispatch_tool: tools directory required" >&2
        return 1
    fi

    if [[ -z "$tool_name" ]]; then
        echo "dispatch_tool: tool name required" >&2
        return 1
    fi

    if [[ -z "$args_json" ]]; then
        echo "dispatch_tool: args JSON required" >&2
        return 1
    fi

    # Find the tool executable by name.
    # Look for exact match first, then with common extensions.
    local tool_path=""
    for candidate in "$tools_dir/$tool_name" "$tools_dir/${tool_name}."*; do
        if [[ -x "$candidate" ]]; then
            tool_path="$candidate"
            break
        fi
    done

    if [[ -z "$tool_path" ]]; then
        echo "dispatch_tool: tool '$tool_name' not found in $tools_dir" >&2
        return 1
    fi

    # Log the dispatch if log_event is available.
    # type -t checks if a function/command exists. We also need LOG_FILE set.
    if type -t log_event &>/dev/null && [[ -n "${LOG_FILE:-}" ]]; then
        log_event "tool_dispatch" "$(jq -n -c --arg tool "$tool_name" --arg args "$args_json" \
            '{tool: $tool, args: $args}')"
    fi

    # Execute the tool, capturing stdout and stderr separately.
    # mktemp creates a temporary file for stderr so we can read it after.
    local stderr_file
    stderr_file=$(mktemp)

    local tool_stdout
    local tool_rc
    tool_stdout=$("$tool_path" "$args_json" 2>"$stderr_file") && tool_rc=0 || tool_rc=$?

    local tool_stderr
    tool_stderr=$(cat "$stderr_file")
    rm -f "$stderr_file"

    if [[ $tool_rc -ne 0 ]]; then
        # Tool execution failed. Forward stderr and return exit 2.
        if [[ -n "$tool_stderr" ]]; then
            echo "dispatch_tool: $tool_name failed: $tool_stderr" >&2
        else
            echo "dispatch_tool: $tool_name failed with exit code $tool_rc" >&2
        fi

        if type -t log_event &>/dev/null && [[ -n "${LOG_FILE:-}" ]]; then
            log_event "tool_error" "$(jq -n -c --arg tool "$tool_name" --arg error "$tool_stderr" \
                '{tool: $tool, error: $error}')"
        fi

        return 2
    fi

    # Log success
    if type -t log_event &>/dev/null && [[ -n "${LOG_FILE:-}" ]]; then
        log_event "tool_result" "$(jq -n -c --arg tool "$tool_name" --arg result "$tool_stdout" \
            '{tool: $tool, result: $result}')"
    fi

    # Output the tool's stdout
    printf '%s\n' "$tool_stdout"
}
