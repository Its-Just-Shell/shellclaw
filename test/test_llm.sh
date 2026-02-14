#!/usr/bin/env bash
# Tests for lib/llm.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_harness.sh"
source "$PROJECT_ROOT/lib/llm.sh"

setup_tmpdir

echo "=== llm.sh ==="

# All tests use the stub backend — no API calls, no network, no llm CLI needed.
export SHELLCLAW_LLM_BACKEND="stub"

# Reset the stub counter file so previous test runs don't affect numbering.
llm_stub_reset

# --- llm_call: basic stub call ---

output=$(llm_call "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "stub call returns 0"
check_output "$output" "stub response 1" "first stub response is 1"

# --- llm_call: incrementing counter ---

output=$(llm_call "Second message")
check_output "$output" "stub response 2" "second stub response is 2"

output=$(llm_call "Third message")
check_output "$output" "stub response 3" "counter increments to 3"

# --- llm_call: with --system flag ---

output=$(llm_call "Hello" --system "You are helpful") && rc=0 || rc=$?
check_exit "$rc" 0 "stub ignores --system gracefully"
check_contains "$output" "stub response" "returns stub response with --system"

# --- llm_call: with --model flag ---

output=$(llm_call "Hello" --model "gpt-4") && rc=0 || rc=$?
check_exit "$rc" 0 "stub ignores --model gracefully"
check_contains "$output" "stub response" "returns stub response with --model"

# --- llm_call: with --continue flag ---

output=$(llm_call "Hello" --continue) && rc=0 || rc=$?
check_exit "$rc" 0 "stub ignores --continue gracefully"
check_contains "$output" "stub response" "returns stub response with --continue"

# --- llm_call: all flags combined ---

output=$(llm_call "Hello" --system "Be concise" --model "gpt-4" --continue) && rc=0 || rc=$?
check_exit "$rc" 0 "all flags together returns 0"
check_contains "$output" "stub response" "returns stub response with all flags"

# --- llm_call: flags in any order ---

output=$(llm_call --model "gpt-4" "Hello" --system "prompt") && rc=0 || rc=$?
check_exit "$rc" 0 "flags before message works"

output=$(llm_call --continue --system "prompt" "Hello") && rc=0 || rc=$?
check_exit "$rc" 0 "message last works"

# --- llm_call: error — missing message ---

output=$(llm_call 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails without message"
check_contains "$output" "message required" "error mentions message"

# --- llm_call: error — --system without value ---

output=$(llm_call "Hello" --system 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when --system has no value"
check_contains "$output" "--system requires" "error mentions --system"

# --- llm_call: error — --model without value ---

output=$(llm_call "Hello" --model 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails when --model has no value"
check_contains "$output" "--model requires" "error mentions --model"

# --- llm_call: error — unknown flag ---

output=$(llm_call "Hello" --bogus 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails with unknown flag"
check_contains "$output" "unknown flag" "error mentions unknown flag"

# --- llm_call: error — unknown backend ---

SHELLCLAW_LLM_BACKEND="quantum" output=$(llm_call "Hello" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails with unknown backend"
check_contains "$output" "unknown backend" "error mentions unknown backend"

# --- llm_call: error — duplicate message ---

output=$(llm_call "Hello" "World" 2>&1) && rc=0 || rc=$?
check_exit "$rc" 1 "fails with two positional args"
check_contains "$output" "unexpected argument" "error mentions unexpected argument"

# --- llm_call: stub counter persists across calls ---
# Start a fresh subshell with its own counter file to verify independent counting.
# BASHPID (unlike $$) gives the actual subshell PID, so it gets a separate counter file.

counter_output=$(
    export BASHPID_OVERRIDE=$$_sub
    source "$PROJECT_ROOT/lib/llm.sh"
    export SHELLCLAW_LLM_BACKEND=stub
    llm_stub_reset
    llm_call "a"
    llm_call "b"
    llm_call "c"
)
check_contains "$counter_output" "stub response 1" "subshell counter starts at 1"
check_contains "$counter_output" "stub response 2" "subshell counter reaches 2"
check_contains "$counter_output" "stub response 3" "subshell counter reaches 3"

# --- llm_call: default backend ---
# When SHELLCLAW_LLM_BACKEND is unset, it should default to "llm" (real).
# We can't test the real backend here (no llm CLI guaranteed), but we verify
# the code path tries to use it by checking for the "llm CLI not found" error
# when llm isn't installed, or just that it doesn't crash.

# (This test only meaningful if llm is NOT on PATH — skipped otherwise)
if ! command -v llm &>/dev/null; then
    output=$(SHELLCLAW_LLM_BACKEND=llm llm_call "Hello" 2>&1) && rc=0 || rc=$?
    check_exit "$rc" 1 "real backend fails when llm not installed"
    check_contains "$output" "llm CLI not found" "error mentions missing llm CLI"
fi

summary "llm.sh"
