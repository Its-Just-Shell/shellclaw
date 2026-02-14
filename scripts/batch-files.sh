#!/usr/bin/env bash
# batch-files.sh — Process multiple files through the LLM
#
# Demonstrates: script-driven control. The script decides what files
# to process and what to do with each result. The LLM provides judgment.
#
# Usage:
#   ./scripts/batch-files.sh "Explain this code" src/*.py
#   ./scripts/batch-files.sh "Find bugs" lib/*.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLCLAW="$SCRIPT_DIR/../shellclaw"

if [[ $# -lt 2 ]]; then
    echo "Usage: batch-files.sh <prompt> <file> [file...]" >&2
    echo "Example: batch-files.sh \"Explain this code\" src/*.py" >&2
    exit 1
fi

# First argument is the system prompt; the rest are files.
# shift removes the first argument from $@, leaving just the files.
prompt="$1"
shift

for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "--- Skipping $file (not found) ---"
        continue
    fi

    echo "--- $file ---"
    # cat pipes the file content into shellclaw as the message.
    # -s sets the system prompt for how to analyze it.
    cat "$file" | "$SHELLCLAW" -s "$prompt"
    echo ""
done
