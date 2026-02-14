#!/usr/bin/env bash
# Tests for the shellclaw entry point
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"

# We need llm.sh sourced only for llm_stub_reset
source "$PROJECT_ROOT/lib/llm.sh"

setup_tmpdir

echo "=== shellclaw (entry point) ==="

# All tests use the stub backend — no API calls, no network.
export SHELLCLAW_LLM_BACKEND="stub"

# --- Helper: run shellclaw in a clean temp environment ---
# We copy the project into a temp dir for each test group to avoid
# polluting the real agents/ directory with session/log files.

setup_project() {
    local dir="$TEST_TMPDIR/project_$$_$RANDOM"
    mkdir -p "$dir"
    # Copy the essentials: config, lib, agents, and the entry point.
    cp -R "$PROJECT_ROOT/config" "$dir/"
    cp -R "$PROJECT_ROOT/lib" "$dir/"
    cp -R "$PROJECT_ROOT/agents" "$dir/"
    cp "$PROJECT_ROOT/shellclaw" "$dir/"
    # Ensure stub backend in the config
    echo 'SHELLCLAW_LLM_BACKEND="stub"' >> "$dir/config/shellclaw.env"
    echo "$dir"
}

# --- Filter mode: message as argument ---

proj=$(setup_project)
llm_stub_reset
output=$("$proj/shellclaw" "Hello world") && rc=0 || rc=$?
check_exit "$rc" 0 "message as argument returns 0"
check_contains "$output" "stub response" "returns stub response"

# --- Filter mode: message via stdin (pipe) ---

proj=$(setup_project)
llm_stub_reset
output=$(echo "Hello from pipe" | "$proj/shellclaw") && rc=0 || rc=$?
check_exit "$rc" 0 "piped stdin returns 0"
check_contains "$output" "stub response" "piped input gets stub response"

# --- Filter mode: with -s flag (system prompt string) ---

proj=$(setup_project)
llm_stub_reset
output=$("$proj/shellclaw" -s "Be concise" "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "-s flag with string returns 0"
check_contains "$output" "stub response" "returns response with -s flag"

# --- Filter mode: with -s flag (system prompt from file) ---

proj=$(setup_project)
llm_stub_reset
echo "You are a pirate." > "$TEST_TMPDIR/pirate.md"
output=$("$proj/shellclaw" -s "$TEST_TMPDIR/pirate.md" "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "-s flag with file path returns 0"
check_contains "$output" "stub response" "returns response with -s file"

# --- Filter mode: with -m flag ---

proj=$(setup_project)
llm_stub_reset
output=$("$proj/shellclaw" -m "gpt-4" "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "-m flag returns 0"
check_contains "$output" "stub response" "returns response with -m flag"

# --- Filter mode: with -c flag ---

proj=$(setup_project)
llm_stub_reset
output=$("$proj/shellclaw" -c "Continue this") && rc=0 || rc=$?
check_exit "$rc" 0 "-c flag returns 0"
check_contains "$output" "stub response" "returns response with -c flag"

# --- Filter mode: all flags combined ---

proj=$(setup_project)
llm_stub_reset
output=$("$proj/shellclaw" -s "Be helpful" -m "gpt-4" -c "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "all flags combined returns 0"
check_contains "$output" "stub response" "all flags produce response"

# --- Filter mode: session file is written ---

proj=$(setup_project)
llm_stub_reset
"$proj/shellclaw" "Test message" >/dev/null
session_file="$proj/agents/default/sessions/current.jsonl"
check_file_exists "$session_file" "session file created after call"

count=$(wc -l < "$session_file" | tr -d ' ')
check_output "$count" "2" "session has 2 entries (user + assistant)"

first_line=$(head -1 "$session_file")
check_json_field "$first_line" "role" "user" "first entry is user"

second_line=$(tail -1 "$session_file")
check_json_field "$second_line" "role" "assistant" "second entry is assistant"

# --- Filter mode: log file is written ---

proj=$(setup_project)
llm_stub_reset
"$proj/shellclaw" "Test message" >/dev/null
log_file="$proj/agents/default/agent.jsonl"
check_file_exists "$log_file" "log file created after call"

count=$(wc -l < "$log_file" | tr -d ' ')
check_output "$count" "2" "log has 2 entries (user_input + llm_response)"

first_line=$(head -1 "$log_file")
check_json_field "$first_line" "event" "user_input" "first log is user_input"

second_line=$(tail -1 "$log_file")
check_json_field "$second_line" "event" "llm_response" "second log is llm_response"

# --- Subcommand: help ---

output=$("$proj/shellclaw" help) && rc=0 || rc=$?
check_exit "$rc" 0 "help returns 0"
check_contains "$output" "Usage:" "help shows usage"
check_contains "$output" "-s <prompt>" "help mentions -s flag"

# --- Subcommand: --help ---

output=$("$proj/shellclaw" --help) && rc=0 || rc=$?
check_exit "$rc" 0 "--help returns 0"
check_contains "$output" "Usage:" "--help shows usage"

# --- Subcommand: config ---

output=$("$proj/shellclaw" config) && rc=0 || rc=$?
check_exit "$rc" 0 "config returns 0"
check_contains "$output" "SHELLCLAW_HOME=" "config shows HOME"
check_contains "$output" "SHELLCLAW_MODEL=" "config shows MODEL"
check_contains "$output" "SHELLCLAW_LLM_BACKEND=" "config shows LLM_BACKEND"

# --- Subcommand: session (empty) ---

proj=$(setup_project)
output=$("$proj/shellclaw" session) && rc=0 || rc=$?
check_exit "$rc" 0 "session with no history returns 0"
check_contains "$output" "No conversation history" "shows no-history message"

# --- Subcommand: session (after messages) ---

proj=$(setup_project)
llm_stub_reset
"$proj/shellclaw" "Hello" >/dev/null
output=$("$proj/shellclaw" session)
check_contains "$output" "user: Hello" "session shows user message"
check_contains "$output" "assistant: stub response" "session shows assistant response"

# --- Subcommand: reset ---

proj=$(setup_project)
llm_stub_reset
"$proj/shellclaw" "Hello" >/dev/null
"$proj/shellclaw" reset >/dev/null && rc=0 || rc=$?
check_exit "$rc" 0 "reset returns 0"

# After reset, session should be empty
output=$("$proj/shellclaw" session)
check_contains "$output" "No conversation history" "session empty after reset"

# --- Subcommand: init ---

init_dir="$TEST_TMPDIR/fresh"
mkdir -p "$init_dir"
# Copy just the essentials needed to bootstrap
cp -R "$PROJECT_ROOT/lib" "$init_dir/"
cp "$PROJECT_ROOT/shellclaw" "$init_dir/"
mkdir -p "$init_dir/config"
# Create a minimal config so config_init succeeds
cat > "$init_dir/config/shellclaw.env" <<'ENV'
SHELLCLAW_LLM_BACKEND="stub"
ENV
cat > "$init_dir/config/agents.json" <<'JSON'
{"default": {"soul": "agents/default/soul.md", "model": null}}
JSON

output=$("$init_dir/shellclaw" init) && rc=0 || rc=$?
check_exit "$rc" 0 "init returns 0"
check_contains "$output" "Initialized" "init shows confirmation"
check_file_exists "$init_dir/agents/default/soul.md" "init creates soul.md"

# --- Error: no arguments, terminal stdin ---
# We simulate terminal stdin by redirecting from /dev/tty if available,
# but this is hard to test portably. Instead, test that we get help output.
# (In a real terminal with no args, shellclaw shows help — same as 'shellclaw help')

# --- Error: unknown flag ---

output=$("$proj/shellclaw" --bogus "Hello" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "unknown flag fails"
check_contains "$output" "unknown flag" "error mentions unknown flag"

# --- Error: -s without value ---

output=$("$proj/shellclaw" -s 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "-s without value fails"
check_contains "$output" "requires" "error mentions requirement"

# --- Error: -m without value ---

output=$("$proj/shellclaw" -m 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "-m without value fails"
check_contains "$output" "requires" "error mentions requirement"

# --- Error: --agent without value ---

output=$("$proj/shellclaw" --agent 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "--agent without value fails"
check_contains "$output" "requires" "error mentions requirement"

# --- Error: nonexistent agent ---

output=$("$proj/shellclaw" --agent "ghost" "Hello" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "nonexistent agent fails"
check_contains "$output" "not found" "error mentions not found"

# --- Pipeline composability ---
# The output should be clean text, suitable for piping.

proj=$(setup_project)
llm_stub_reset
# Pipe shellclaw output through wc -l (count lines).
# Stub returns one line, so the count should be 1.
line_count=$(echo "Hello" | "$proj/shellclaw" | wc -l | tr -d ' ')
check_output "$line_count" "1" "output is one clean line (pipeable)"

summary "shellclaw (entry point)"
