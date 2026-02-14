# Tutorial 3: LLM Integration — The Only New Primitive

This tutorial covers `lib/llm.sh` and `lib/compose.sh` — the LLM call wrapper and system prompt assembly. Together with a soul file, these turn text into an LLM interaction.

> Files covered: [`lib/llm.sh`](../../lib/llm.sh), [`lib/compose.sh`](../../lib/compose.sh), [`agents/default/soul.md`](../../agents/default/soul.md)

---

## Shell Concepts

### Subshells and `$(...)`

When you write `output=$(some_command)`, bash runs `some_command` in a **subshell** — a child copy of the current shell. The subshell inherits all variables, but any changes it makes to variables are lost when it exits. The parent only gets what was printed to stdout.

This matters for the stub counter: if you increment a variable inside `$(...)`, the parent never sees the change. That's why `llm.sh` uses a file-based counter instead — the filesystem is shared between parent and child processes.

### `$$` — Process ID

`$$` is a special variable that holds the current shell's process ID (PID). Importantly, `$$` does **not** change in subshells — it always refers to the top-level shell. This means `$$` is the same inside `$(...)` as outside, which makes it useful for creating shared temp files (like the stub counter file).

### `command -v` — Checking if a program exists

`command -v llm` checks whether `llm` is available on your PATH. It prints the path if found, or returns exit code 1 if not. It's the portable way to check "is this program installed?" — more reliable than `which`, which behaves differently across systems.

### Building commands as arrays

```bash
local cmd=(llm)
cmd+=(-s "$system_prompt")
cmd+=(-m "$model")
"${cmd[@]}"
```

This builds a command as a bash array, then expands it with `"${cmd[@]}"`. Each array element becomes one argument, preserving spaces correctly. If `$system_prompt` contains spaces (like `"You are a helpful assistant"`), it stays as one argument — not split into four. This avoids the word-splitting bugs you get with string-based command building.

### `printf '%s'` vs `echo`

`printf '%s' "$message"` prints the message without a trailing newline and without interpreting escape sequences. `echo` might interpret `\n`, `\t`, etc. depending on the system. `printf` is predictable — it prints exactly what you give it.

---

## `lib/llm.sh`

Exposes two public functions: `llm_call` and `llm_stub_reset`.

**`llm_call "What is 2+2?"`**

The core primitive. Text in, LLM, text out. It looks at `$SHELLCLAW_LLM_BACKEND` to decide where to send the message:

- `"llm"` (default) — pipes the message to Simon Willison's `llm` CLI
- `"stub"` — returns `"stub response N"` with an incrementing counter (for testing)

```bash
# Real call (requires llm CLI installed and configured)
export SHELLCLAW_LLM_BACKEND=llm
llm_call "What is 2+2?"
# => 2 + 2 = 4

# Stub call (no network, no API, no llm CLI needed)
export SHELLCLAW_LLM_BACKEND=stub
llm_call "What is 2+2?"
# => stub response 1
```

**Optional flags:**

- `--system "You are helpful"` — sets the system prompt (passed to `llm -s`)
- `--model "gpt-4"` — overrides the model (passed to `llm -m`)
- `--continue` — continues a previous conversation (passed to `llm -c`)

Flags can go in any order, before or after the message:

```bash
llm_call "Hello" --system "Be concise" --model "gpt-4"
llm_call --continue "What did I just say?"
llm_call --system "Translate to French" "Hello world"
```

**How the real backend works:**

When using the `llm` backend, `llm_call` pipes your message into the `llm` CLI on stdin:

```bash
printf '%s' "$message" | llm -s "$system_prompt" -m "$model"
```

The `-s` flag sends the system prompt as the API's `system` field — it's not flattened into the user message. The `-c` flag tells `llm` to continue the previous conversation (multi-turn). The `-m` flag selects the model.

If no `--model` flag is given, `llm_call` falls back to `$SHELLCLAW_MODEL` from config.

**The stub backend and the counter:**

The stub returns deterministic responses: `"stub response 1"`, `"stub response 2"`, etc. The counter is stored in a temp file (`/tmp/shellclaw_stub_counter_$$`) instead of a variable, because `$(llm_call ...)` runs in a subshell where variable changes would be lost. The file persists across subshells.

`llm_stub_reset` deletes the counter file to start fresh. Tests call this at the beginning to ensure predictable numbering.

---

## `lib/compose.sh`

Exposes one function: `compose_system`.

**`compose_system "agents/default"`**

Reads the agent's `soul.md` file and prints it to stdout. The caller captures it with `$()`:

```bash
prompt=$(compose_system "agents/default")
llm_call "Hello" --system "$prompt"
```

For now, this is essentially `cat agents/default/soul.md`. It's wrapped in a function so we can later extend it — adding `context.md`, memory summaries, tool descriptions — without changing any callers. Today it reads one file. Tomorrow it might concatenate several. The callers don't need to know.

---

## Soul Files

A soul file is a system prompt — it defines who the agent is and how it behaves. It's a plain markdown file. The `compose_system` function reads it and passes it to the LLM.

```markdown
You are a helpful assistant running inside shellclaw...
```

This is the "files as identity" pattern from the IJS thesis. The agent's personality isn't hardcoded — it's a file on disk. You can `cat` it, `diff` two agents, version-control identity changes, or swap souls by pointing to a different file.

---

## Try It

```bash
source lib/config.sh && config_init "$PWD"
source lib/log.sh
source lib/session.sh
source lib/llm.sh
source lib/compose.sh

export LOG_FILE="/tmp/agent.jsonl"
export SHELLCLAW_AGENT_ID="default"

# Assemble the system prompt from the default agent's soul file
system_prompt=$(compose_system "agents/default")

# Make an LLM call (using stub)
export SHELLCLAW_LLM_BACKEND=stub
response=$(llm_call "Hello" --system "$system_prompt")

# Log and record
log_event "user_input" "Hello"
session_append "/tmp/chat.jsonl" "user" "Hello"
log_event "llm_response" "$response"
session_append "/tmp/chat.jsonl" "assistant" "$response"

# Inspect
session_load "/tmp/chat.jsonl"
cat /tmp/chat.jsonl | jq .
cat /tmp/agent.jsonl | jq .
```

All five libraries compose into a working LLM interaction: config provides settings, compose assembles the prompt, llm makes the call, session records the conversation, log traces execution. Each piece works independently — you can source just `llm.sh` and call `llm_call` directly, or source everything and use the full stack.
