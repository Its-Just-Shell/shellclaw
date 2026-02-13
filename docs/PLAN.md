# Shellclaw v2 Plan

## Context

Shellclaw v2 is a minimal demonstration of OpenClaw built from Unix primitives, following the "Its Just Shell" thesis. The deliverable is a set of composable library functions — a grammar for building agent systems — plus a thin entry point that demonstrates one composition of those functions.

The scope is deliberately narrow: **composable LLM primitives, no tool calling in v2.0, no cruft.** The libraries (`lib/*.sh`) are the primary deliverable. People should be able to `source` them and compose their own architectures. The `shellclaw` entry point is one example composition — not the product.

Tool-calling backends are planned, architected, and documented — all three approaches will be implemented and tested, selectable via flag. Script-driven vs. LLM-driven control is a policy choice (a flag), not architecture baked into the infrastructure.

---

## Critical Analysis of v1 Primitives

### Verdict: Start fresh, informed by v1

The v1 primitives (agent, alog, aaud, amem) are individually solid ~300-line bash scripts. They have a design characteristic that needs to evolve for v2:

**v1 primitives are standalone CLI tools. v2 needs both library functions AND composable CLI interfaces.**

v1 only has the CLI form — every internal call pays subprocess overhead and can't share state. v2 uses sourced library functions internally (shared config, session state, zero subprocess cost) while still exposing composable CLI interfaces externally. This preserves Unix composability while enabling application-level integration:

```
Internal (library):     log_event "request" "msg"          ← sourced, shared state
External (composable):  shellclaw log --agent default       ← Unix tool, pipes, exit codes
```

The v1 primitives remain fully usable as standalone composable tools in pipelines. The library form is an addition, not a replacement.

### What carries forward (ideas, not code)

1. JSONL format for logs and sessions
2. `jq -n -c` for safe JSON construction
3. Stub backend for testing without API calls
4. Soul files as system prompts (files as identity)
5. Filesystem-based state
6. Exit codes as named constants
7. The 8-step agent pattern (simplified)

### What we leave behind

1. **CLI-only form factor** — add library functions alongside
2. **`aaud` audit query tool** — users can `jq` directly. Defer.
3. **`amem` key-value memory** — premature for chat-only scope. Session management is what we need.
4. **`agent` naming** — it's an LLM call, not an agent. v2 uses `llm` CLI.
5. **Cross-agent coordination** — not in v2 scope
6. **`build_prompt()` flattening** — v1 flattens everything into a single string. Chat needs proper multi-turn.

### Multi-turn conversation: how v2 handles it

v1's `agent` primitive passes the entire context (system prompt + piped input + task) as a single flat string. This breaks multi-turn conversation — the API expects a `messages` array with distinct `user`/`assistant` turns and a separate `system` field.

v2 solves this by using Simon Willison's `llm` CLI as the primary LLM backend:

- **`llm -c` (continue)** manages multi-turn conversation state in its own SQLite DB. It handles the messages array, API formatting, and conversation continuity natively.
- **Our JSONL session files** mirror every turn for observability. Two complementary sources: `llm`'s DB drives the conversation, our JSONL makes it inspectable with `cat`/`jq`/`grep`.
- **On session reset**: start a new `llm` conversation (omit `-c`).
- **System prompt**: `llm -s "$(cat soul.md)"` passes it properly as the API's `system` field, not flattened into the user message.

This gives us proper multi-turn without reimplementing what `llm` already does, while preserving the observability that the thesis demands.

---

## Architecture

### Directory Structure

```
shellclaw/
├── shellclaw                  # Entry point script
├── lib/
│   ├── log.sh                # Structured JSONL logging
│   ├── config.sh             # Configuration loading
│   ├── session.sh            # Conversation session management
│   ├── llm.sh               # LLM call wrapper (llm CLI + stub)
│   └── compose.sh            # System prompt assembly
├── lib/tool_loop/             # Tool-calling backends (modular)
│   ├── interface.sh          # Common interface contract
│   ├── bash/                 # Backend 1: pure bash (curl + jq)
│   │   └── tool_loop.sh
│   ├── llm_cli/              # Backend 2: llm CLI --tools
│   │   └── tool_loop.sh
│   └── elixir/               # Backend 3: Elixir data plane
│       ├── tool_loop.sh      # Shell wrapper (calls escript)
│       ├── mix.exs
│       └── lib/
│           ├── tool_loop.ex  # GenServer
│           └── llm_client.ex # API client
├── agents/
│   └── default/
│       ├── soul.md           # System prompt / identity
│       ├── sessions/
│       │   └── current.jsonl # Active conversation transcript (observability mirror)
│       └── agent.jsonl       # Execution trace log
├── config/
│   ├── shellclaw.env         # Global configuration
│   └── agents.json           # Agent definitions
├── test/
│   ├── test_harness.sh       # Shared test utilities
│   ├── test_log.sh
│   ├── test_session.sh
│   ├── test_llm.sh
│   ├── test_compose.sh
│   └── test_tool_loop/       # Tests for each backend
│       ├── test_bash.sh
│       ├── test_llm_cli.sh
│       └── test_elixir.sh
└── docs/
    ├── PLAN.md               # This plan (copy for the repo)
    └── FUTURE.md             # Documented future work
```

### Data Flow

**Filter mode** (primary — shellclaw as Unix tool):

```
stdin (text)
       │
       ├─ compose_system ← soul.md → $system_prompt
       │
       ├─ echo "$msg" | llm -s "$system_prompt" -m "$model"
       │        │
       │        └─ returns: response text on stdout
       │
       ├─ log_event "request" / "response"
       ├─ session_append (observability mirror)
       │
       └─ stdout (text)
```

This is the composable form. It goes in pipelines:

```bash
cat error.log | shellclaw -s "What service is failing?"
echo "Summarize this" | shellclaw
shellclaw "What time is it in UTC?"
```

**Multi-turn** works via the `-c` flag, which passes through to `llm -c`:

```bash
shellclaw "Hello"                    # new conversation
shellclaw -c "What did I just say?"  # continues previous
shellclaw -c "And then?"             # continues again
```

No REPL needed. Your shell is the REPL. Multi-turn is a flag.

---

## Component Specifications

### 1. `lib/log.sh`

Structured JSONL logging. No dependencies except `jq` and `date`.

```bash
# Source this file. Set LOG_FILE before calling.

log_event <event_type> [message]
# Appends: {"ts":"...","event":"...","agent":"...","message":"..."}
# Uses $SHELLCLAW_AGENT_ID and $LOG_FILE from environment
```

Format: `{"ts":"2026-02-12T10:00:00Z","agent":"default","event":"user_input","message":"..."}`

### 2. `lib/config.sh`

Load and access configuration.

```bash
config_init                    # Source shellclaw.env, parse agents.json
config_get <key>               # Get global config value
config_agent <id> <key>        # Get agent-specific value
```

Config files:
- `config/shellclaw.env` — `SHELLCLAW_MODEL`, `SHELLCLAW_HOME`, `SHELLCLAW_DEFAULT_AGENT`, `SHELLCLAW_TOOL_BACKEND`
- `config/agents.json` — agent definitions (soul path, model override)

### 3. `lib/session.sh`

Conversation session management. Mirrors `llm` CLI's conversation state as inspectable JSONL.

```bash
session_append <file> <role> <content>
# Appends JSONL: {"ts":"...","role":"user","content":"..."}

session_load <file> [limit]
# Returns recent conversation as formatted text (for display, grep, audit)

session_count <file>
# Number of entries

session_clear <file>
# Archive current, create fresh

# TODO: session_compact (summarize old messages via LLM)
```

Note: `llm` CLI manages the actual conversation state for API calls. Our session files are the observability layer — inspectable, greppable, diffable, git-able.

### 4. `lib/llm.sh`

Wrapper around `llm` CLI. This is the "only new primitive" — a way to call an LLM and get text back on stdout.

```bash
llm_call <message> [--system <prompt>] [--model <model>] [--continue]
# Calls: echo "$message" | llm [-s "$prompt"] [-m "$model"] [-c]
# Writes response text to stdout
# Returns: 0=success, 1=error

llm_call_stub <message>
# Returns "stub response N" (incrementing counter)
# For testing without API calls or llm CLI
```

This function is a filter: text in, text out. It composes with everything else through pipes. The `--continue` flag enables multi-turn via `llm -c`, but single-shot (no flag) is the default.

Why `llm` CLI:
- Handles the messages array and multi-turn state natively (`-c` flag)
- System prompt passed properly via `-s` (not flattened into user message)
- Streaming by default
- Multi-provider support via plugins
- Active maintenance, widely adopted
- Simon Willison built it on the explicit premise that "the Unix command line is the perfect environment for this technology"

### 5. `lib/compose.sh`

System prompt assembly.

```bash
compose_system <agent_dir>
# Reads soul.md, returns assembled system prompt string
# Future: will also include context.md, memory summary, etc.
```

For v2 minimal, this is essentially `cat "$agent_dir/soul.md"`. Wrapped in a function so we can extend it later without changing callers.

### 6. `shellclaw` (entry point)

A thin script that composes the library functions. Text in, text out. Your shell is the interface.

```bash
# The filter — shellclaw as Unix tool
echo "What is 2+2?" | shellclaw                        # stdin → LLM → stdout
cat error.log | shellclaw -s "What service is failing?" # piped input + system prompt
shellclaw "What time is it in UTC?"                     # message as argument
shellclaw -c "What did you just say?"                   # continue previous conversation

# Subcommands
shellclaw init                   # Create directory structure + default config
shellclaw config                 # Print resolved configuration
shellclaw session                # Show conversation history
shellclaw reset                  # Clear session, start fresh
shellclaw help                   # Show usage
```

Text in, text out. Single-shot by default (`llm` without `-c`). Multi-turn via `-c` (passes through to `llm -c`). It works in pipelines, loops, scripts, evals. No special modes.

**Flags:**
- `-s <prompt>` — system prompt (string or file path)
- `-m <model>` — model override
- `--agent <id>` — use agent's soul.md and config
- `-c` — continue previous conversation (multi-turn)

If someone wants an interactive chat loop, they write one:

```bash
while read -r -e -p "> " msg; do
    shellclaw -c "$msg"
done
```

Four lines. That's a composition of the primitive, not a feature of it.

---

## Tool-Calling Architecture (Modular, Three Backends)

All three approaches will be implemented, tested, and selectable via config or flag:

```bash
shellclaw --tool-backend=bash      # Pure bash: curl + jq
shellclaw --tool-backend=llm       # llm CLI: --tools flag
shellclaw --tool-backend=elixir    # Elixir data plane: GenServer + escript
```

Default set in `config/shellclaw.env` via `SHELLCLAW_TOOL_BACKEND`.

### Script-Driven vs. LLM-Driven: Policy, Not Architecture

The IJS thesis identifies the control model — who decides what tools to call — as the most impactful design decision. Shellclaw treats this as a flag, not a structural commitment:

```bash
# Script-driven: the script controls the workflow.
# The LLM provides judgment. The script decides what to do with it.
diagnosis=$(cat error.log | shellclaw -s "What service is failing?")
service=$(echo "$diagnosis" | grep -oP 'service: \K\w+')
logs=$(journalctl -u "$service" --since "1 hour ago")

# LLM-driven: the LLM controls the workflow via tool requests.
cat error.log | shellclaw --tools ops_tools.json -s "Diagnose and fix this"
```

The logging, session management, config, and observability infrastructure are identical in both modes. The only difference is whether the script or the LLM decides the next action. Switching between them should be as easy as flipping a flag — because the control model is policy expressed in the calling script, not architecture baked into the tool.

### Common Interface Contract

All three backends implement the same interface:

```bash
# lib/tool_loop/interface.sh

tool_loop <user_message> <system_prompt> <tools_json_path> [max_iterations]
# Runs the request → dispatch → feedback loop
# Dispatches tool calls to skill executables in $SHELLCLAW_SKILLS_DIR
# Returns final text response on stdout
# Logs every iteration to $LOG_FILE
# Exit: 0=success, 1=error, 2=max_iterations_reached
```

Skills are always shell scripts (executables with `--describe` for schema). The tool-calling backend only affects how the LLM interaction and JSON parsing work — the actual tool execution is always shell.

### Backend 1: Pure Bash (`lib/tool_loop/bash/tool_loop.sh`)

```
echo "$msg" + tools.json ──► curl to Anthropic API
                                    │
                              jq parse response
                                    │
                    ┌───────────────┤
                    │               │
              tool_use block    text block
                    │               │
              validate against   return text
              allowlist              │
                    │               done
              execute skill.sh
                    │
              feed result back ──► next API call
```

- Direct `curl` to Anthropic API with `tools` array in request body
- Parse `tool_use` content blocks with `jq`
- Dispatch via case statement to skill executables
- Accumulate messages in temp JSONL file
- **Strengths**: Zero dependencies beyond curl/jq, total transparency
- **Weaknesses**: Multi-line text quoting fragile, nested JSON in tool args is pain point
- **Test**: Skills with simple string args, verify dispatch and result feeding

### Backend 2: `llm` CLI (`lib/tool_loop/llm_cli/tool_loop.sh`)

```
echo "$msg" ──► llm --tools tools.json -s "$prompt" -m "$model"
                         │
                   llm handles: API call, response parsing,
                   tool-call detection, result formatting
                         │
                   tool execution callback ──► skill.sh
                         │
                   llm feeds result, continues loop
                         │
                   returns final text
```

- Uses `llm --tools` for tool definitions
- `llm` handles the multi-turn tool-calling protocol internally
- We provide tool execution callbacks (skill scripts)
- **Strengths**: Battle-tested API handling, streaming, multi-provider
- **Weaknesses**: Less control over exact request, tool-calling support maturity TBD
- **Test**: Same skills as bash backend, verify identical dispatch behavior

### Backend 3: Elixir Data Plane (`lib/tool_loop/elixir/`)

```
echo "$msg" ──► shellclaw-tool-loop (escript)
                         │
                   GenServer handles:
                   - API call (Req library)
                   - Response parsing (pattern matching)
                   - Tool-call extraction (structured)
                   - Multi-turn context (process state)
                         │
                   {:tool_call, name, args} ──► System.cmd("skill.sh", args)
                         │
                   {:text, content} ──► stdout
```

#### Architectural Position

The Elixir component is a **standalone escript** — a self-contained executable built from Elixir source. It lives in `lib/tool_loop/elixir/` and is built with `mix escript.build`. From shell's perspective, it's just another executable:

```bash
# Shell calls it like any other program
response=$(echo "$msg" | ./lib/tool_loop/elixir/shellclaw-tool-loop \
  --system "$prompt" \
  --tools tools.json \
  --skills-dir "$SHELLCLAW_SKILLS_DIR" \
  --log-file "$LOG_FILE")
```

The escript:
- Reads config from files (same files shell reads)
- Writes logs to JSONL (same format as bash backends)
- Calls skill scripts as subprocesses (same skills, same `--describe` interface)
- Returns final text on stdout

From the operator's perspective, nothing changes — `cat`, `grep`, `jq` all work the same on the logs and session files. The Elixir layer is invisible to the workflow.

#### Why Elixir specifically

```elixir
# The tool-calling problem, solved cleanly:
defp handle_response(%{"content" => blocks}) do
  Enum.reduce(blocks, [], fn
    %{"type" => "tool_use", "name" => name, "input" => args}, acc ->
      result = dispatch_tool(name, args)  # shells out to skill script
      [{:tool_result, name, result} | acc]

    %{"type" => "text", "text" => text}, acc ->
      [{:text, text} | acc]
  end)
end
```

No quoting bugs. No jq fragility. Structured data stays structured from API response through tool dispatch. And `dispatch_tool/2` calls the same shell scripts as the bash backend.

#### Future: OTP supervision (Tier 3)

When shellclaw grows to multi-agent coordination, the escript graduates to a proper OTP application:

```
lib/tool_loop/elixir/
├── mix.exs
├── lib/
│   ├── shellclaw/
│   │   ├── application.ex      # OTP application
│   │   ├── supervisor.ex       # Agent supervision tree
│   │   ├── agent_server.ex     # GenServer per agent
│   │   ├── tool_loop.ex        # Tool-calling loop (current escript logic)
│   │   ├── llm_client.ex       # HTTP client for LLM APIs
│   │   └── skill_runner.ex     # Shell-out to skill scripts
│   └── shellclaw.ex            # Public API
└── config/
    └── config.exs              # Elixir config (reads from shellclaw.env)
```

This is the "Its Just Beam" tier — supervision trees, fault tolerance, message passing, governance. But the shell layer remains the control plane and observability surface.

### Testing All Three Backends

Each backend gets tested against the same skill set and the same expected behavior:

```bash
# test/test_tool_loop/common_tests.sh — shared test cases

# Test 1: Single tool call, simple string arg
# Input: "What's the weather?" with weather.sh skill
# Expected: LLM requests weather tool → skill executes → result fed back → final text

# Test 2: No tool call needed
# Input: "Hello" with tools available
# Expected: Direct text response, no tool dispatch

# Test 3: Tool not in allowlist
# Input: Request that triggers unlisted tool
# Expected: "Tool not permitted" fed back to LLM

# Test 4: Multi-turn tool calling (2+ rounds)
# Input: Complex request requiring sequential tool use
# Expected: Correct dispatch chain, final synthesis
```

```bash
# Run tests for all backends:
SHELLCLAW_TOOL_BACKEND=bash   ./test/test_tool_loop/run.sh
SHELLCLAW_TOOL_BACKEND=llm    ./test/test_tool_loop/run.sh
SHELLCLAW_TOOL_BACKEND=elixir ./test/test_tool_loop/run.sh
```

Stub skills return deterministic output, so tests are pure and reproducible regardless of backend.

---

## Build Order

Dependencies flow downward. Build bottom-up.

```
shellclaw (entry point: filter + subcommands)
  ├── lib/config.sh        ← build first (no deps)
  ├── lib/log.sh           ← build second (no deps)
  ├── lib/session.sh       ← build third (depends on log.sh)
  ├── lib/llm.sh           ← build fourth (depends on config.sh, log.sh)
  ├── lib/compose.sh       ← build fifth (depends on config.sh)
  ├── entry point          ← build sixth (composes the libraries)
  └── lib/tool_loop/*      ← build after filter works (3 backends)
```

### Phase 0: Test Harness
- `test/test_harness.sh` must exist before any tests can be written
- Provides: `check_exit`, `check_output`, `check_contains`, `check_json_field`, `check_file_exists`, `setup_tmpdir`, `summary`
- `test/run_all.sh` discovers and runs all `test_*.sh` files

### Phase 1: Foundation (lib/log.sh, lib/config.sh)
- Logging and config have no internal dependencies on each other
- Both depend on environment variables set by the entry point (`shellclaw`)
- **Bootstrapping order at runtime**: `SHELLCLAW_HOME` → `config_init` → sets `LOG_FILE` etc. → `log_event` works
- **In tests**: env vars are set manually by each test script (no entry point yet)
- Write tests for both
- Run shellcheck on everything
- **bash >= 4.0 note**: macOS ships bash 3.2 (GPL v3). Requires Homebrew bash. Shebang is `#!/usr/bin/env bash` — PATH must resolve to bash 4+.
- **`log_event` uses env vars** (`$LOG_FILE`, `$SHELLCLAW_AGENT_ID`) rather than parameters — these don't change within a session, so env keeps call sites clean. `session_append` (Phase 2) takes file as a parameter since it may operate on different session files.
- **`agents.json` schema** (documented in `config_agent`):
  ```json
  {
    "<agent_id>": {
      "soul": "<relative path to soul.md>",
      "model": "<model override or null for global default>"
    }
  }
  ```
- **`shellclaw.env` is sourced directly** — it's executable bash, not parsed data. Only variable assignments belong in it.

### Phase 2: State (lib/session.sh)
- Session append, load, count, clear
- JSONL observability mirror format
- Tests with fixture data

### Phase 3: LLM Integration (lib/llm.sh, lib/compose.sh)
- `llm_call` — the "only new primitive": text in, LLM, text out
- Wrapper around `llm` CLI: `-c` for multi-turn, `-s` for system prompt
- `llm_call_stub` for testing without API calls or network
- `compose_system` — system prompt assembly from soul.md
- Both are composable functions, not internal plumbing — people source these directly

### Phase 4: Entry Point (shellclaw)
- Text in, text out — `echo "question" | shellclaw` and `shellclaw "question"`
- Detect stdin: `[[ -t 0 ]]` — pipe vs terminal (terminal with no args shows help)
- Flags: `-s`, `-m`, `--agent`, `-c`
- Subcommands: `init`, `config`, `session`, `reset`, `help`
- The entry point is a thin composition of the libraries — the libraries are the real deliverable

### Phase 5: Tool-Calling Backends
- Implement common interface contract (`tool_loop`)
- Backend 1: bash (curl + jq)
- Backend 2: llm CLI (--tools)
- Backend 3: Elixir (escript)
- Shared test suite across all three
- `--tool-backend` flag selection
- Script-driven vs. LLM-driven is a flag, not architecture — same infrastructure, different policy
- Both modes use the same logging, session, and config primitives

### Phase 6: Polish
- Run shellcheck on all scripts
- Ensure filter mode composes in pipelines (test with real pipe chains)
- Write docs/FUTURE.md (everything marked TODO)

---

## What Gets TODO'd

These features are explicitly deferred and will be documented in `docs/FUTURE.md`:

| Feature | Why deferred | Complexity to add later |
|---|---|---|
| Skills system | Requires tool calling to be useful | Medium |
| Session compaction | Needed for long conversations | Medium — LLM-based summary |
| Multi-agent coordination | Beyond v2 scope | High — Elixir tier |
| Memory (persistent notes) | Not needed for basic primitives | Low |
| Cron scheduling | No agents to schedule | Low |
| Multi-provider failover | Single provider sufficient | Medium |
| Approval system | Requires tool calling | Medium |
| OTP supervision tree | Tier 3, after tool calling works | High — full Elixir app |

---

## Testing Strategy

Each library gets a test script. Tests use the stub backend — no API calls, no network.

```bash
# Run all tests
./test/run_all.sh

# Run individual test
./test/test_session.sh

# Update expected outputs
UPDATE=1 ./test/test_session.sh
```

Test harness provides: `check_exit`, `check_output`, `check_contains`, `summary` (carried from v1 TESTING.md patterns).

### What we test
- Library function contracts (inputs → outputs)
- Session file format correctness
- JSON construction safety (special characters, newlines, quotes)
- Config loading and access
- Stub LLM responses
- Filter: stdin → stdout, argument → stdout, piped input → stdout
- Multi-turn: `-c` flag continues conversation
- Subcommands: session, reset, config, init
- Composability: libraries work when sourced directly (not just via entry point)
- Tool-loop dispatch (all 3 backends, same test suite)

### What we don't test
- LLM output quality
- Network/API availability
- Exact error message wording

---

## External Dependencies

**Required:**
- `bash` >= 4.0
- `jq` >= 1.6
- `curl`
- `llm` CLI (Simon Willison's tool — `pip install llm`)

**For Elixir backend:**
- Elixir >= 1.16 + Erlang/OTP >= 26 (only for `lib/tool_loop/elixir/`)

**Not required:**
- Node.js, Python (beyond llm's pip install), Docker, any framework

---

## Verification

After build is complete, verify:

**Primitives (libraries work independently):**
1. Libraries can be sourced and used directly without the entry point:
   ```bash
   source lib/log.sh lib/llm.sh lib/compose.sh
   echo "Hello" | llm_call --system "$(compose_system agents/default)"
   ```
2. All tests pass: `./test/run_all.sh`
3. `shellcheck` passes on all `.sh` files

**Filter mode (shellclaw as Unix tool):**
4. `echo "Hello" | shellclaw` returns a response on stdout
5. `shellclaw "What is 2+2?"` works with message as argument
6. `cat file.txt | shellclaw -s "Summarize this"` works with system prompt flag
7. Filter mode composes in a pipeline: `shellclaw "List 3 colors" | wc -l`
8. Stub backend works: `SHELLCLAW_LLM_BACKEND=stub shellclaw "test"`

**Multi-turn:**
9. `shellclaw -c "follow up"` continues previous conversation
10. `shellclaw reset` clears the session and starts fresh
11. `shellclaw session` shows conversation history

**Observability:**
12. `cat agents/default/sessions/current.jsonl | jq .` shows the conversation
13. `cat agents/default/agent.jsonl | jq .` shows the execution trace

**Infrastructure:**
14. `shellclaw init` creates the directory structure
15. `shellclaw config` prints resolved configuration
16. Tool-loop backends all pass shared test suite (when implemented)
