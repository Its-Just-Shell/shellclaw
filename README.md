# Shellclaw

A minimal implementation of [OpenClaw](https://github.com/opensouls/openclaw) built from Unix primitives, following the [Its Just Shell](https://itsjustshell.com) thesis.

A set of composable shell libraries that demonstrate how to build agent systems using processes, files, text streams, and exit codes — the primitives Unix already provides. The libraries are the deliverable. People source them and compose their own architectures.

## Structure

The project is organized as progressive phases. Each phase is self-contained and runnable — `cd` into any phase and it works on its own. Start at phase 1, understand it, then move forward.

```
phases/
  1-foundation/     Config loading + structured JSONL logging
  2-state/          + Conversation session management
  3-llm/            + LLM call wrapper + system prompt assembly    (planned)
  4-entry-point/    + shellclaw command                            (planned)
  5-tool-calling/   + Three modular tool-calling backends          (planned)
```

Each phase includes a `LEARNING.md` explaining what's new and how to use it, plus a test suite.

## Quick Start

```bash
cd phases/2-state

# Source the libraries
source lib/config.sh && config_init "$PWD"
source lib/log.sh
source lib/session.sh

export LOG_FILE="/tmp/agent.jsonl" SHELLCLAW_AGENT_ID="default"

# Log an event
log_event "session_start"

# Build a conversation mirror
session_append "/tmp/chat.jsonl" "user" "Hello"
session_append "/tmp/chat.jsonl" "assistant" "Hi there"

# Inspect with Unix tools
session_load "/tmp/chat.jsonl"
cat /tmp/chat.jsonl | jq .
cat /tmp/agent.jsonl | jq .

# Run the tests
./test/run_all.sh
```

## Dependencies

- `bash` >= 4.0
- `jq` >= 1.6
- `llm` CLI (Phase 3+) — [github.com/simonw/llm](https://github.com/simonw/llm)

## Plan

See [docs/PLAN.md](docs/PLAN.md) for the full architecture, component specifications, and build order.
