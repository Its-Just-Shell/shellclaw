#!/usr/bin/env bash
# chat-loop.sh — Interactive multi-turn conversation
#
# Demonstrates: multi-turn via -c flag, your shell as the REPL.
# This is the "4-line chat loop" from the IJS thesis.
#
# Usage:
#   ./scripts/chat-loop.sh
#   ./scripts/chat-loop.sh --agent researcher

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLCLAW="$SCRIPT_DIR/../shellclaw"

# Pass through any flags (like --agent)
flags=("$@")

echo "shellclaw chat (Ctrl-D to exit)"
echo "---"

# First message starts a new conversation (no -c).
# read -r prevents backslash interpretation.
# read -e enables readline editing (arrow keys, history).
# read -p sets the prompt string.
if read -r -e -p "> " msg; then
    "$SHELLCLAW" "${flags[@]}" "$msg"
else
    exit 0
fi

# Subsequent messages continue the conversation (-c).
while read -r -e -p "> " msg; do
    "$SHELLCLAW" "${flags[@]}" -c "$msg"
done
