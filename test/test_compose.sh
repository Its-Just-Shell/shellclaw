#!/usr/bin/env bash
# Tests for lib/compose.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/compose.sh"

setup_tmpdir

echo "=== compose.sh ==="

# --- compose_system: basic ---

# Create a test agent directory with a soul.md
mkdir -p "$TEST_TMPDIR/agents/test-agent"
printf 'You are a test agent.\nBe helpful.' > "$TEST_TMPDIR/agents/test-agent/soul.md"

output=$(compose_system "$TEST_TMPDIR/agents/test-agent") && rc=0 || rc=$?
check_exit "$rc" 0 "returns 0 for valid agent dir"
check_contains "$output" "You are a test agent." "reads first line of soul.md"
check_contains "$output" "Be helpful." "reads second line of soul.md"

# --- compose_system: with the real default agent ---

output=$(compose_system "$PROJECT_ROOT/agents/default") && rc=0 || rc=$?
check_exit "$rc" 0 "reads real default soul.md"
check_contains "$output" "shellclaw" "default soul mentions shellclaw"

# --- compose_system: multiline soul ---

# mkdir -p creates the directory tree before we write into it.
# heredoc (<<'SOUL'...SOUL): writes multi-line text to a file.
# Single-quoting 'SOUL' prevents variable expansion inside the heredoc.
mkdir -p "$TEST_TMPDIR/agents/multiline"
cat > "$TEST_TMPDIR/agents/multiline/soul.md" <<'SOUL'
You are a verbose agent.

## Rules

1. Always explain your reasoning
2. Use examples when possible
3. Be thorough
SOUL

output=$(compose_system "$TEST_TMPDIR/agents/multiline")
check_contains "$output" "## Rules" "preserves markdown headings"
check_contains "$output" "3. Be thorough" "preserves numbered list"

# --- compose_system: special characters in soul ---

mkdir -p "$TEST_TMPDIR/agents/special"
printf 'Use "quotes" & <brackets> freely.\nHandle $variables and `backticks`.' \
    > "$TEST_TMPDIR/agents/special/soul.md"

output=$(compose_system "$TEST_TMPDIR/agents/special") && rc=0 || rc=$?
check_exit "$rc" 0 "handles special characters"
check_contains "$output" '"quotes"' "preserves double quotes"
check_contains "$output" '& <brackets>' "preserves ampersand and angle brackets"
check_contains "$output" '$variables' "preserves dollar signs (not expanded)"

# --- compose_system: empty soul.md ---

mkdir -p "$TEST_TMPDIR/agents/empty"
: > "$TEST_TMPDIR/agents/empty/soul.md"

output=$(compose_system "$TEST_TMPDIR/agents/empty") && rc=0 || rc=$?
check_exit "$rc" 0 "returns 0 for empty soul.md"
check_output "$output" "" "empty soul.md produces empty output"

# --- compose_system: error — missing agent dir argument ---

output=$(compose_system 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without agent dir"
check_contains "$output" "agent directory required" "error mentions agent directory"

# --- compose_system: error — missing soul.md ---

mkdir -p "$TEST_TMPDIR/agents/no-soul"

output=$(compose_system "$TEST_TMPDIR/agents/no-soul" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when soul.md missing"
check_contains "$output" "not found" "error mentions file not found"

# --- compose_system: error — agent dir doesn't exist ---

output=$(compose_system "$TEST_TMPDIR/agents/nonexistent" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when agent dir doesn't exist"
check_contains "$output" "not found" "error mentions not found"

summary "compose.sh"
