# Shellclaw

A minimal implementation of [OpenClaw](https://github.com/opensouls/openclaw) built from Unix primitives, following the [Its Just Shell](https://itsjustshell.com) thesis.

The libraries are the deliverable. People source them and compose their own architectures. The `shellclaw` entry point is one example composition — not the product.

## Quick Start

```bash
# Talk to an LLM — text in, text out
shellclaw "What is 2+2?"

# Pipe input
echo "Explain this error" | shellclaw

# Pipe input with a system prompt
cat error.log | shellclaw -s "What service is failing?"

# Continue a conversation (multi-turn via llm -c)
shellclaw "Hello"
shellclaw -c "What did I just say?"

# Interactive chat loop — your shell is the REPL
while read -r -e -p "> " msg; do shellclaw -c "$msg"; done
```

No REPL. No daemon. Text in, text out. It works in pipelines, loops, and scripts.

### Subcommands

```bash
shellclaw init       # Create directory structure and default config
shellclaw config     # Print resolved configuration
shellclaw session    # Show conversation history
shellclaw reset      # Clear session, start fresh
shellclaw help       # Show usage
```

### Flags

| Flag | Description |
|------|-------------|
| `-s <prompt>` | System prompt (string or path to a file) |
| `-m <model>` | Model override |
| `--agent <id>` | Use a specific agent's soul and config |
| `-c` | Continue previous conversation |

## Structure

```
shellclaw              Entry point — one example composition of the libraries
lib/
  config.sh            Configuration loading (shellclaw.env + agents.json)
  log.sh               Structured JSONL logging
  session.sh           Conversation session management
  llm.sh               LLM call wrapper (llm CLI + stub backend)
  compose.sh           System prompt assembly (soul.md + context modules)
  discover.sh          Tool catalog discovery (--describe convention)
  dispatch.sh          Tool execution and validation (default-deny)
config/
  shellclaw.env        Global config (model, backend, defaults)
  agents.json          Agent definitions (soul path, model override)
agents/default/
  soul.md              System prompt / identity
  context/             Context modules — domain knowledge loaded alongside soul
  sessions/            Conversation transcripts (JSONL)
tools/
  get_weather.sh       Example tool (purpose-built, wraps wttr.in)
  disk_usage.sh        Example tool (shim pattern, wraps du)
  github_issue.sh      Example tool (API-backed, wraps GitHub API)
scripts/
  chat-loop.sh         Example orchestration: interactive chat
  pipe-summarize.sh    Example orchestration: summarize piped input
  batch-files.sh       Example orchestration: process multiple files
  soul-swap.sh         Example orchestration: switch agent identity
deploy/
  telegram/            Telegram bot — polling loop composing all five libs
    telegram-bot.sh    Main daemon script
    lib/telegram.sh    Telegram API adapter (3 curl wrappers + stub)
    README.md          Setup instructions
docs/
  PLAN.md              Full architecture and build plan
  TOOL_INTERFACE.md    Tool self-description spec (--describe convention)
  tutorials/           Educational walkthroughs (01-foundation through 04-composing)
test/
  run_all.sh           Test runner (discovers and runs all test_*.sh files)
  test_harness.sh      Shared test utilities
  test_*.sh            Tests for each library and the entry point
```

## Using the Libraries Directly

The libraries are designed to be sourced independently. You don't need the entry point:

```bash
source lib/config.sh && config_init "$PWD"
source lib/log.sh
source lib/session.sh
source lib/llm.sh
source lib/compose.sh

export LOG_FILE="/tmp/agent.jsonl" SHELLCLAW_AGENT_ID="default"

# Log an event
log_event "user_input" "Hello"

# Mirror a conversation to JSONL
session_append "/tmp/chat.jsonl" "user" "Hello"
session_append "/tmp/chat.jsonl" "assistant" "Hi there"

# Inspect with Unix tools
session_load "/tmp/chat.jsonl"
cat /tmp/chat.jsonl | jq .

# Call an LLM (or use the stub for testing)
SHELLCLAW_LLM_BACKEND=stub llm_call "Hello"
```

## Tools

Tools are executables that self-describe via `--describe`. The catalog is derived at runtime — no hand-maintained registry:

```bash
# See a tool's interface
./tools/get_weather.sh --describe | jq .

# Execute a tool with JSON args
SHELLCLAW_STUB=1 ./tools/get_weather.sh '{"location": "Half Moon Bay"}'

# Discover all tools in a directory
source lib/discover.sh
discover_tools tools/ | jq '.[].name'
```

See [docs/TOOL_INTERFACE.md](docs/TOOL_INTERFACE.md) for the full spec.

## Deployments

The `deploy/` directory contains real, runnable services composed from the core libraries.

### Telegram Bot

A Telegram bot built entirely by sourcing the five core libs. Each chat gets isolated multi-turn via `llm --cid`:

```bash
export SHELLCLAW_TELEGRAM_TOKEN="your-token-from-botfather"
./deploy/telegram/telegram-bot.sh
```

See [deploy/telegram/README.md](deploy/telegram/README.md) for full setup instructions.

## Tests

```bash
# Run the full suite (330 tests, all offline, no API keys needed)
./test/run_all.sh

# Run a single test file
bash test/test_log.sh
```

All tests use the stub backend — no network calls, no API keys.

## Dependencies

- `bash` >= 4.0 (macOS ships 3.2 — use Homebrew: `brew install bash`)
- `jq` >= 1.6
- `llm` CLI — [github.com/simonw/llm](https://github.com/simonw/llm) (`pip install llm`)

## Further Reading

- [docs/PLAN.md](docs/PLAN.md) — full architecture, component specs, and build order
- [docs/TOOL_INTERFACE.md](docs/TOOL_INTERFACE.md) — the `--describe` convention and tool dispatch
- [docs/tutorials/](docs/tutorials/) — educational walkthroughs starting from the foundation
