#!/usr/bin/env bash
# shellclaw/tools/disk_usage.sh — Check disk usage for a directory
#
# Demonstrates the shim pattern: wrapping an existing Unix tool (du)
# with a self-describing interface. The tool doesn't modify du — it
# wraps it with --describe so the LLM (or discover.sh) can understand
# what it does and what arguments it accepts.
#
# Modes:
#   --describe         Output JSON tool schema to stdout
#   '{"path":...}'     Execute with JSON args in $1
#
# Environment:
#   SHELLCLAW_STUB=1   Return stub data instead of calling du

if [[ "${1:-}" == "--describe" ]]; then
    cat <<'JSON'
{
  "name": "disk_usage",
  "description": "Check disk usage for a directory path",
  "parameters": {
    "type": "object",
    "properties": {
      "path": {
        "type": "string",
        "description": "Directory path to check (default: current directory)"
      },
      "human_readable": {
        "type": "boolean",
        "description": "Use human-readable sizes like KB, MB, GB (default: true)"
      }
    },
    "required": []
  }
}
JSON
    exit 0
fi

# --- Execution mode ---

args="${1:-}"

# disk_usage accepts empty args (all parameters are optional with defaults)
if [[ -z "$args" ]]; then
    args='{}'
fi

# Parse JSON args. // provides defaults for optional fields.
path=$(printf '%s' "$args" | jq -r '.path // "."')
human_readable=$(printf '%s' "$args" | jq -r '.human_readable // true')

# Validate the path exists
if [[ ! -e "$path" ]]; then
    echo "disk_usage: path not found: $path" >&2
    exit 1
fi

# Stub mode
if [[ "${SHELLCLAW_STUB:-}" == "1" ]]; then
    if [[ "$human_readable" == "true" ]]; then
        echo "1.2G	$path"
    else
        echo "1258291	$path"
    fi
    exit 0
fi

# Build the du command.
# -s gives a summary (total only, not per-subdirectory).
# -h gives human-readable sizes (1K, 2M, 3G).
if [[ "$human_readable" == "true" ]]; then
    du -sh "$path"
else
    du -s "$path"
fi
