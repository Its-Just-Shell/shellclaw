# Tutorial 2: State — Session Management

This tutorial covers `lib/session.sh` — the observability layer for conversations.

> File covered: [`lib/session.sh`](../../lib/session.sh)

---

## Why Session Files?

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

---

## `lib/session.sh`

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

## Try It

```bash
source lib/session.sh

# Build a conversation
session_append "/tmp/chat.jsonl" "user" "Hello"
session_append "/tmp/chat.jsonl" "assistant" "Hi there"
session_append "/tmp/chat.jsonl" "user" "What is 2+2?"
session_append "/tmp/chat.jsonl" "assistant" "4"

# Inspect it
session_load "/tmp/chat.jsonl"         # human-readable transcript
session_count "/tmp/chat.jsonl"        # number of turns
cat /tmp/chat.jsonl | jq .             # raw JSONL with timestamps

# Archive and start fresh
session_clear "/tmp/chat.jsonl"
ls /tmp/chat.jsonl*                    # see the archive file
```
