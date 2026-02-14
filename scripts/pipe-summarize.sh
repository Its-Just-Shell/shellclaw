#!/usr/bin/env bash
# pipe-summarize.sh — Summarize any piped input
#
# Demonstrates: shellclaw as a Unix filter in a pipeline.
# stdin flows in, gets summarized by the LLM, summary flows out.
#
# Usage:
#   cat README.md | ./scripts/pipe-summarize.sh
#   git log --oneline -20 | ./scripts/pipe-summarize.sh
#   curl -s https://example.com | ./scripts/pipe-summarize.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLCLAW="$SCRIPT_DIR/../shellclaw"

# The -s flag sets a system prompt that tells the LLM what to do.
# stdin is piped through — shellclaw reads it as the message.
"$SHELLCLAW" -s "Summarize the following concisely. Use bullet points for key details."
