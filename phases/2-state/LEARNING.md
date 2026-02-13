# Shellclaw: How It Works

What exists so far: `lib/log.sh`, `lib/config.sh`, `lib/session.sh`, config files, and a test suite. This document explains what each piece does and the shell concepts behind them.

---

## Shell Concepts

### `source`

`source` reads a file and executes it inside your current shell process. After sourcing a file, any functions defined in it become available to call.

This only affects the current shell process. Another terminal tab doesn't see them. A subprocess doesn't see them (unless it also sources the file). When this shell session ends, they're gone.

### Environment Variables

Shell functions don't have objects or return values in the traditional sense. The way you share state between functions in shell is through variables. When `config_init` sets `SHELLCLAW_MODEL`, later when `llm_call` (Phase 3) needs to know which model to use, it reads `$SHELLCLAW_MODEL`. Shared variables in the same shell process are how the pieces talk to each other.

### `export`

`export` does two things: sets the variable in the current shell, AND marks it so child processes inherit it. Without `export`, a variable is local to the current shell — if you ran a subprocess, it wouldn't see it. With `export`, subprocesses get a copy.

### JSONL

JSONL is one JSON object per line. Each line is independently parseable. You can `grep` for events, `tail -f` to watch live, `wc -l` to count, `jq` to query — standard Unix tools work on it without any special setup. This is the observability format throughout shellclaw.

### `jq`

`jq` is a JSON processor. shellclaw uses it in two ways:

- **Building JSON safely** (`jq -n -c --arg`): `-n` means "don't read input, create from scratch." `-c` means "compact, one line." `--arg` passes shell variables into jq, and jq handles all the escaping (quotes, newlines, backslashes) so the output is always valid JSON.
- **Reading JSON** (`jq -r '.field'`): `-r` means "raw output" (no quotes around strings). `.field` extracts a value by key.

---

## Phase 1: Foundation (config + logging)

### `lib/config.sh`

Exposes three functions: `config_init`, `config_get`, `config_agent`.

**`config_init "$PWD"`**

Tells shellclaw where its files live on disk. `$PWD` is a built-in variable that holds your current working directory.

Why does it need to be told? Because shellclaw's config, agents, and logs are all files in a directory tree. `config_init` needs to know the root of that tree so it can find `config/shellclaw.env` inside it.

What it does:
1. Sets `SHELLCLAW_HOME` to the path you gave it — this becomes the root that all other functions use to find files
2. Sources `$SHELLCLAW_HOME/config/shellclaw.env` — which sets several variables
3. Fills in defaults for anything the env file didn't set

**`config_get "SHELLCLAW_MODEL"`**

Takes a variable name as a string and prints its value. `config_get "SHELLCLAW_MODEL"` is essentially the same as `echo "$SHELLCLAW_MODEL"`.

Why wrap it? So callers don't need to know that config values are stored as environment variables. If we later changed config storage, callers using `config_get` wouldn't need to change.

**`config_agent "default" "soul"`**

Reads `config/agents.json` using `jq`. The JSON file maps agent names to their settings:

```json
{
  "default": {
    "soul": "agents/default/soul.md",
    "model": null
  }
}
```

`config_agent "default" "soul"` says: find the agent named `"default"`, return its `"soul"` value. Returns `agents/default/soul.md` — the path to that agent's system prompt file.

Why a separate JSON file instead of more env vars? Because agents are structured — each one has multiple fields (soul path, model override, potentially more). A flat env file doesn't express that well. JSON does.

### `config/shellclaw.env`

The values that `config_init` loads:

```bash
SHELLCLAW_MODEL="claude-sonnet-4-5-20250929"   # Which LLM model to talk to
SHELLCLAW_DEFAULT_AGENT="default"               # Which agent to use if you don't specify one
SHELLCLAW_TOOL_BACKEND="bash"                   # Which tool-calling implementation (future)
SHELLCLAW_LLM_BACKEND="llm"                     # "llm" for real calls, "stub" for testing
```

This file is sourced directly (executed as bash), not parsed. Only variable assignments belong in it.

### `lib/log.sh`

Exposes one function: `log_event`.

**`log_event "something_happened" "optional message"`**

Appends one line of JSON to the file at `$LOG_FILE`. Uses `jq -n -c --arg` to build it safely. Output looks like:

```json
{"ts":"2026-02-12T10:00:00Z","agent":"default","event":"something_happened","message":"optional message"}
```

Reads two environment variables:
- `LOG_FILE` — where to write (required, fails without it)
- `SHELLCLAW_AGENT_ID` — stamped into every entry so you can tell which agent produced it (defaults to "unknown")

### `config/agents.json`

Maps agent names to their settings. Currently just the default agent:

```json
{
  "default": {
    "soul": "agents/default/soul.md",
    "model": null
  }
}
```

`"soul"` is the path to the agent's system prompt file. `"model"` is a per-agent model override — `null` means use the global default from `shellclaw.env`.

---

## Phase 2: State (sessions)

### Why Session Files?

When shellclaw talks to an LLM, the `llm` CLI manages the actual conversation state (the messages array, API formatting, multi-turn continuity) in its own SQLite database. That's what makes `llm -c` work — it remembers the conversation.

But that database is opaque. You can't `cat` it. You can't `grep` it. You can't `diff` two conversations. You can't pipe it through `jq`.

Session files are the observability layer. Every message — user and assistant — gets mirrored as a line of JSONL in a file you control. The `llm` database drives the conversation; the session file makes it inspectable.

```json
{"ts":"2026-02-12T10:00:00Z","role":"user","content":"Hello"}
{"ts":"2026-02-12T10:00:01Z","role":"assistant","content":"Hi there, how can I help?"}
{"ts":"2026-02-12T10:00:15Z","role":"user","content":"What is 2+2?"}
{"ts":"2026-02-12T10:00:16Z","role":"assistant","content":"4"}
```

Four lines. Each independently parseable. `grep "role.*user"` shows all user messages. `jq -r '.content'` extracts just the text. `wc -l` counts the turns. Standard Unix tools, no special setup.

### `lib/session.sh`

Exposes four functions. All take a file path as their first argument — unlike `log_event` which reads `$LOG_FILE` from the environment. This is because you might operate on different session files: the current conversation, an archived one, a different agent's session.

**`session_append <file> <role> <content>`**

Appends one JSONL entry to a session file. Creates the file if it doesn't exist. `role` is "user" or "assistant". `content` is the message text — jq handles escaping, so quotes, newlines, and special characters are safe.

```bash
session_append "conversation.jsonl" "user" "Hello"
session_append "conversation.jsonl" "assistant" "Hi there"
```

**`session_load <file> [limit]`**

Prints the conversation as a human-readable transcript. Optional `limit` shows only the last N entries. Returns nothing (exit 0) for empty or non-existent files.

```bash
session_load "conversation.jsonl"
# user: Hello
# assistant: Hi there

session_load "conversation.jsonl" 1
# assistant: Hi there
```

If you want the raw JSONL with timestamps and structure, use `cat` or `jq` directly — `session_load` is for quick human inspection.

**`session_count <file>`**

Prints the number of entries. Returns 0 for empty or non-existent files.

```bash
session_count "conversation.jsonl"
# 2
```

**`session_clear <file>`**

Archives the current session by renaming it with a timestamp, then creates a fresh empty file at the same path. If the file is empty or doesn't exist, just creates a fresh file (no archive needed).

```bash
session_clear "conversation.jsonl"
# conversation.jsonl is now empty
# conversation.jsonl.20260212T100000Z contains the old conversation
```

---

## Putting It Together

```bash
# Load everything
source lib/config.sh && config_init "$PWD"
source lib/log.sh
source lib/session.sh

export LOG_FILE="/tmp/agent.jsonl"
export SHELLCLAW_AGENT_ID="default"

# Simulate a conversation
log_event "session_start"
session_append "/tmp/chat.jsonl" "user" "Hello"
session_append "/tmp/chat.jsonl" "assistant" "Hi there"
session_append "/tmp/chat.jsonl" "user" "What is 2+2?"
session_append "/tmp/chat.jsonl" "assistant" "4"
log_event "session_end"

# Inspect the conversation
session_load "/tmp/chat.jsonl"         # human-readable transcript
session_count "/tmp/chat.jsonl"        # number of turns
cat /tmp/chat.jsonl | jq .             # raw JSONL with timestamps
cat /tmp/agent.jsonl | jq .            # execution trace

# Archive and start fresh
session_clear "/tmp/chat.jsonl"
ls /tmp/chat.jsonl*                    # see the archive file

# Run the tests
./test/run_all.sh
```

Still no LLM calls — that comes in Phase 3 (`llm.sh`). What we have now is the full state management layer: config tells us where things are, logging records what happens, and sessions capture conversations. All as files. All inspectable with `cat`, `grep`, `jq`.
