#!/usr/bin/env bash
# Tests for lib/config.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/config.sh"

setup_tmpdir

echo "=== config.sh ==="

# --- Build test config structure ---

mkdir -p "$TEST_TMPDIR/config"

cat > "$TEST_TMPDIR/config/shellclaw.env" << 'EOF'
SHELLCLAW_MODEL="test-model-123"
SHELLCLAW_DEFAULT_AGENT="test-agent"
EOF

cat > "$TEST_TMPDIR/config/agents.json" << 'EOF'
{
  "default": {
    "soul": "agents/default/soul.md",
    "model": null
  },
  "custom": {
    "soul": "agents/custom/soul.md",
    "model": "custom-model"
  }
}
EOF

# --- config_init ---

config_init "$TEST_TMPDIR" && rc=0 || rc=$?
check_exit "$rc" 0 "config_init succeeds with valid config"

# --- config_get reads values from env file ---

result=$(config_get "SHELLCLAW_MODEL")
check_output "$result" "test-model-123" "config_get reads SHELLCLAW_MODEL"

result=$(config_get "SHELLCLAW_DEFAULT_AGENT")
check_output "$result" "test-agent" "config_get reads SHELLCLAW_DEFAULT_AGENT"

# --- config_get returns defaults for unset values ---

result=$(config_get "SHELLCLAW_TOOL_BACKEND")
check_output "$result" "bash" "default TOOL_BACKEND is 'bash'"

result=$(config_get "SHELLCLAW_LLM_BACKEND")
check_output "$result" "llm" "default LLM_BACKEND is 'llm'"

# --- config_get returns empty for unknown keys ---

result=$(config_get "SHELLCLAW_NONEXISTENT")
check_output "$result" "" "config_get returns empty for unknown key"

# --- config_agent reads agent values ---

result=$(config_agent "default" "soul")
check_output "$result" "agents/default/soul.md" "config_agent reads soul path"

result=$(config_agent "custom" "model")
check_output "$result" "custom-model" "config_agent reads model override"

result=$(config_agent "custom" "soul")
check_output "$result" "agents/custom/soul.md" "config_agent reads custom soul"

# --- config_agent returns empty for null ---

result=$(config_agent "default" "model")
check_output "$result" "" "config_agent returns empty for null value"

# --- config_agent returns empty for missing key ---

result=$(config_agent "default" "nonexistent")
check_output "$result" "" "config_agent returns empty for missing key"

# --- config_agent returns empty for missing agent ---

result=$(config_agent "nonexistent" "soul")
check_output "$result" "" "config_agent returns empty for missing agent"

# --- Error: config_init without home ---

unset SHELLCLAW_HOME
output=$(config_init "" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "config_init fails without home"
check_contains "$output" "SHELLCLAW_HOME" "error mentions SHELLCLAW_HOME"

# Restore for remaining tests
export SHELLCLAW_HOME="$TEST_TMPDIR"

# --- Error: config_init with missing env file ---

output=$(config_init "/nonexistent/path" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "config_init fails with missing env file"
check_contains "$output" "not found" "error mentions file not found"

# --- Error: config_get without key ---

output=$(config_get 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "config_get fails without key"
check_contains "$output" "key required" "error mentions key required"

# --- Error: config_agent without args ---

output=$(config_agent 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "config_agent fails without args"
check_contains "$output" "agent_id and key required" "error mentions required args"

# --- Error: config_agent with missing agents.json ---

SHELLCLAW_HOME="/nonexistent"
output=$(config_agent "default" "soul" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "config_agent fails with missing agents.json"
SHELLCLAW_HOME="$TEST_TMPDIR"

summary "config.sh"
