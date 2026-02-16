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

# --- compose_system: with context modules ---

mkdir -p "$TEST_TMPDIR/agents/ctx/context"
echo "Soul content here." > "$TEST_TMPDIR/agents/ctx/soul.md"
echo "Domain knowledge." > "$TEST_TMPDIR/agents/ctx/context/domain.md"

output=$(compose_system "$TEST_TMPDIR/agents/ctx") && rc=0 || rc=$?
check_exit "$rc" 0 "returns 0 with context modules"
check_contains "$output" "Soul content here." "includes soul.md"
check_contains "$output" "Domain knowledge." "includes context module"

# --- compose_system: context modules separated by --- ---

check_contains "$output" "---" "context module separated by ---"

# --- compose_system: alphabetical ordering ---

mkdir -p "$TEST_TMPDIR/agents/order/context"
echo "Order soul." > "$TEST_TMPDIR/agents/order/soul.md"
echo "SECOND MODULE" > "$TEST_TMPDIR/agents/order/context/02-second.md"
echo "FIRST MODULE" > "$TEST_TMPDIR/agents/order/context/01-first.md"

output=$(compose_system "$TEST_TMPDIR/agents/order")
# FIRST MODULE should appear before SECOND MODULE in the output.
# Extract positions: if first appears earlier, the grep -n line number is lower.
first_pos=$(printf '%s\n' "$output" | grep -n "FIRST MODULE" | head -1 | cut -d: -f1)
second_pos=$(printf '%s\n' "$output" | grep -n "SECOND MODULE" | head -1 | cut -d: -f1)
if [[ "$first_pos" -lt "$second_pos" ]]; then first_before_second="yes"; else first_before_second="no"; fi
check_output "$first_before_second" "yes" "01-first loaded before 02-second"

# --- compose_system: no context directory (regression) ---

mkdir -p "$TEST_TMPDIR/agents/no-ctx"
echo "Just soul." > "$TEST_TMPDIR/agents/no-ctx/soul.md"

output=$(compose_system "$TEST_TMPDIR/agents/no-ctx") && rc=0 || rc=$?
check_exit "$rc" 0 "works without context directory"
check_output "$output" "Just soul." "outputs only soul.md without context dir"

# --- compose_system: empty context directory ---

mkdir -p "$TEST_TMPDIR/agents/empty-ctx/context"
echo "Soul only." > "$TEST_TMPDIR/agents/empty-ctx/soul.md"

output=$(compose_system "$TEST_TMPDIR/agents/empty-ctx") && rc=0 || rc=$?
check_exit "$rc" 0 "works with empty context directory"
check_output "$output" "Soul only." "empty context dir produces only soul.md"

# --- compose_system: multiple context modules ---

mkdir -p "$TEST_TMPDIR/agents/multi/context"
echo "Multi soul." > "$TEST_TMPDIR/agents/multi/soul.md"
echo "Module A." > "$TEST_TMPDIR/agents/multi/context/a.md"
echo "Module B." > "$TEST_TMPDIR/agents/multi/context/b.md"
echo "Module C." > "$TEST_TMPDIR/agents/multi/context/c.md"

output=$(compose_system "$TEST_TMPDIR/agents/multi")
check_contains "$output" "Module A." "includes first module"
check_contains "$output" "Module B." "includes second module"
check_contains "$output" "Module C." "includes third module"

# --- compose_system: non-md files in context/ ignored ---

mkdir -p "$TEST_TMPDIR/agents/non-md/context"
echo "NM soul." > "$TEST_TMPDIR/agents/non-md/soul.md"
echo "Should be loaded." > "$TEST_TMPDIR/agents/non-md/context/valid.md"
echo "Should be ignored." > "$TEST_TMPDIR/agents/non-md/context/notes.txt"

output=$(compose_system "$TEST_TMPDIR/agents/non-md")
check_contains "$output" "Should be loaded." "loads .md files"

# Check that .txt content is NOT in the output
if [[ "$output" == *"Should be ignored."* ]]; then
    _test_start "non-md files ignored"
    _test_fail ".txt file was included"
else
    _test_start "non-md files ignored"
    _test_pass
fi

# --- compose_system: real default agent with context module ---

output=$(compose_system "$PROJECT_ROOT/agents/default") && rc=0 || rc=$?
check_exit "$rc" 0 "real default agent with context modules"
check_contains "$output" "shellclaw" "soul content present"
check_contains "$output" "Context Module" "context module present"

summary "compose.sh"
