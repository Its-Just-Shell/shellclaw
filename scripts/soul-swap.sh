#!/usr/bin/env bash
# soul-swap.sh — Same question, different personalities
#
# Demonstrates: files as identity. Swap the soul file and the
# same infrastructure produces different behavior. The soul is
# policy; the infrastructure is mechanism.
#
# Usage:
#   ./scripts/soul-swap.sh "What is the meaning of life?"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLCLAW="$SCRIPT_DIR/../shellclaw"

if [[ $# -eq 0 ]]; then
    echo "Usage: soul-swap.sh <question>" >&2
    exit 1
fi

question="$1"

# Create temporary soul files with different personalities.
# Each one is just a markdown file — the agent's identity.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/concise.md" <<'SOUL'
You answer in exactly one sentence. No more.
SOUL

cat > "$tmpdir/pirate.md" <<'SOUL'
You are a pirate. You speak only in pirate dialect. Arrr.
SOUL

cat > "$tmpdir/socratic.md" <<'SOUL'
You never give direct answers. You only respond with questions that guide the person to discover the answer themselves.
SOUL

# Same question, three different souls.
# The -s flag accepts a file path — shellclaw reads it automatically.
echo "=== Concise ==="
"$SHELLCLAW" -s "$tmpdir/concise.md" "$question"

echo ""
echo "=== Pirate ==="
"$SHELLCLAW" -s "$tmpdir/pirate.md" "$question"

echo ""
echo "=== Socratic ==="
"$SHELLCLAW" -s "$tmpdir/socratic.md" "$question"
