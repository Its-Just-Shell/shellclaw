# Telegram Bot

A real Telegram bot built by composing shellclaw's five core libraries. Proves the thesis isn't academic — this is the same `chat-loop.sh` pattern with Telegram I/O instead of a terminal.

## Setup

### 1. Create a bot with BotFather

1. Open Telegram and message [@BotFather](https://t.me/BotFather)
2. Send `/newbot` and follow the prompts
3. Copy the token BotFather gives you

### 2. Set the token

```bash
export SHELLCLAW_TELEGRAM_TOKEN="123456:ABC-DEF..."
```

### 3. Run the bot

```bash
./deploy/telegram/telegram-bot.sh
```

The bot long-polls Telegram for messages (no webhooks, no port forwarding). It runs in the foreground — Ctrl-C to stop.

## Stub Testing

Test the full bot offline with no token, no network, no API keys:

```bash
SHELLCLAW_LLM_BACKEND=stub SHELLCLAW_TELEGRAM_STUB=1 \
  ./deploy/telegram/telegram-bot.sh
```

Run the adapter tests:

```bash
bash test/test_telegram.sh
```

## Bot Commands

| Command | Description |
|---------|-------------|
| `/start` | Greeting and help |
| `/reset` | Clear conversation history |
| `/session` | Show message count |

Everything else is sent to the LLM for a response.

## Architecture

The bot sources all five core libraries directly — no subprocess per message:

```
telegram-bot.sh
  ├── lib/log.sh        → structured JSONL logging
  ├── lib/config.sh     → config loading (shellclaw.env + agents.json)
  ├── lib/session.sh    → conversation mirroring (JSONL)
  ├── lib/llm.sh        → LLM calls (with --conversation-id per chat)
  ├── lib/compose.sh    → system prompt assembly (soul.md + context/)
  └── lib/telegram.sh   → Telegram API adapter (3 curl wrappers)
```

Each Telegram chat gets:
- **Isolated multi-turn** via `llm --cid telegram_<chat_id>` — no cross-talk between chats
- **Its own session file** at `agents/telegram/sessions/chat_<chat_id>.jsonl`
- **Full observability** — same JSONL files you can inspect with standard Unix tools

## Observability

```bash
# Watch the bot log in real time
tail -f agents/telegram/sessions/bot.jsonl | jq .

# See a specific chat's conversation
cat agents/telegram/sessions/chat_12345.jsonl | jq .

# Count messages across all chats
wc -l agents/telegram/sessions/chat_*.jsonl

# Find all messages from a user
grep '"role":"user"' agents/telegram/sessions/chat_12345.jsonl | jq .content
```

## Customization

Edit `agents/telegram/soul.md` to change the bot's personality. Add context modules in `agents/telegram/context/` for domain knowledge — they're loaded automatically alongside the soul.

## Limitations

- **Text only.** Photos, stickers, and voice messages are silently skipped.
- **No access control.** Any Telegram user can talk to the bot.
- **No rate limiting.** Add a per-chat counter file if needed.
- **4096 char limit.** Long LLM responses may fail Telegram's sendMessage.
- **Single process.** Foreground polling, one message at a time.
