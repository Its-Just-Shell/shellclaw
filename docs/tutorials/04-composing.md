# Tutorial 4: Composing Primitives

This tutorial covers how the libraries compose into working tools. The `shellclaw` entry point is one composition. The `scripts/` directory shows others. You can build your own.

> Files covered: [`shellclaw`](../../shellclaw), [`scripts/`](../../scripts/)

---

## Shell Concepts

### `set -euo pipefail`

Three safety switches that change how bash behaves:

- `-e` (**exit on error**): if any command fails (returns non-zero), the script stops immediately. Without this, bash would happily continue past errors.
- `-u` (**unset variables are errors**): referencing `$TYPO` when you meant `$TYPE` is an error instead of silently expanding to empty string.
- `-o pipefail`: normally, a pipeline's exit code is the last command's exit code. With pipefail, it's the first command that fails. So `broken_command | grep foo` fails instead of silently succeeding because `grep` ran fine.

Together, these catch a large class of bugs that bash normally ignores.

### `BASH_SOURCE[0]` — finding the script's own location

`BASH_SOURCE[0]` holds the path to the currently executing script, even if it was invoked via a symlink or from a different directory. The entry point uses this to find `SHELLCLAW_HOME`:

```bash
SCRIPT_PATH="${BASH_SOURCE[0]}"
SHELLCLAW_HOME="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
```

`dirname` strips the filename, leaving the directory. `cd ... && pwd` resolves it to an absolute path. This means `shellclaw` can find its `lib/`, `config/`, and `agents/` directories regardless of where you run it from.

### `[[ -t 0 ]]` — detecting stdin

`-t 0` tests whether file descriptor 0 (stdin) is connected to a terminal. When you type `shellclaw` in your terminal, stdin is your keyboard — `-t 0` is true. When you pipe into it (`echo "hi" | shellclaw`), stdin is the pipe — `-t 0` is false.

The entry point uses this to decide what to do with no arguments:
- Terminal + no args → show help (you're interacting)
- Pipe + no args → read stdin as the message (data is flowing)

### `IFS= read -r -d '' message`

This reads **all** of stdin into a variable, preserving everything:
- `IFS=` prevents trimming whitespace from the beginning and end
- `-r` prevents backslash interpretation (`\n` stays as `\n`, not a newline)
- `-d ''` sets the delimiter to NUL (the null byte), so `read` reads until EOF instead of stopping at the first newline

The `|| true` at the end is because `read` returns exit code 1 when it hits EOF (which is always, when reading all of stdin). Without `|| true`, `set -e` would kill the script.

### `"$@"` — all arguments, properly quoted

`"$@"` expands to all the arguments passed to a function or script, each one individually quoted. So if someone runs `shellclaw -s "be helpful" "hello world"`, `"$@"` becomes `"-s"` `"be helpful"` `"hello world"` — three separate arguments with spaces preserved.

The `main "$@"` pattern at the bottom of the script passes all command-line arguments to the `main` function. This keeps the script's top-level scope clean and lets `main` use `local` variables.

---

## The `shellclaw` Entry Point

The entry point is a thin script that composes the five libraries into a usable tool. It's **not** the product — the libraries are. This script is one example composition.

**Filter mode** — text in, text out:

```bash
shellclaw "What is 2+2?"                          # message as argument
echo "What is 2+2?" | shellclaw                   # stdin as message
cat error.log | shellclaw -s "What's failing?"    # piped input + system prompt
shellclaw -c "Follow up"                           # continue conversation
```

**Subcommands** — project management:

```bash
shellclaw init       # create directory structure
shellclaw config     # print resolved configuration
shellclaw session    # show conversation history
shellclaw reset      # archive session, start fresh
shellclaw help       # show usage
```

### How filter mode works

When you run `shellclaw "Hello"`:

1. **Locate home** — resolves `BASH_SOURCE[0]` to find `SHELLCLAW_HOME`
2. **Source libraries** — makes all library functions available
3. **Init config** — loads `shellclaw.env`, sets `SHELLCLAW_MODEL` etc.
4. **Parse flags** — `-s`, `-m`, `--agent`, `-c` and the message
5. **Resolve agent** — defaults to the configured `SHELLCLAW_DEFAULT_AGENT`
6. **Set up paths** — `LOG_FILE` and session file based on agent
7. **Compose prompt** — reads soul.md (or uses -s override)
8. **Resolve model** — flag → agent config → global config
9. **Log + record** — `log_event "user_input"`, `session_append ... "user"`
10. **Call LLM** — `llm_call` with all resolved arguments
11. **Log + record** — `log_event "llm_response"`, `session_append ... "assistant"`
12. **Output** — `printf '%s\n' "$response"` to stdout

Each step is one library function call. The entry point is orchestration, not logic.

### The `-s` flag: string or file

The `-s` flag accepts either a literal string or a file path:

```bash
shellclaw -s "Be concise" "Hello"             # literal system prompt
shellclaw -s agents/custom/soul.md "Hello"    # reads from file
```

If the value is a path to an existing file, shellclaw reads the file. Otherwise it uses the string directly.

### Model resolution priority

The model is resolved with a priority chain:

1. `-m` flag (explicit override, highest priority)
2. Agent config (`config_agent "$agent_id" "model"`)
3. Global config (`$SHELLCLAW_MODEL` from shellclaw.env)

This pattern — flag overrides agent overrides global — lets you set sensible defaults but override them at any level.

---

## Example Scripts

The `scripts/` directory shows different compositions of the same primitives. Each script is a complete, runnable example that demonstrates a different pattern.

### Script-Driven vs. LLM-Driven

The IJS thesis identifies the control model — who decides what happens next — as the most impactful design decision. These scripts illustrate the spectrum:

**Script-driven**: the script controls the workflow. The LLM provides judgment.

```bash
# The script decides what to analyze, when, and what to do with the result
diagnosis=$(cat error.log | shellclaw -s "What service is failing?")
echo "$diagnosis"
```

**LLM-driven** (future, with tool calling): the LLM controls the workflow via tool requests.

```bash
# The LLM decides what tools to call
cat error.log | shellclaw --tools ops_tools.json -s "Diagnose and fix this"
```

The logging, session management, config, and observability infrastructure are identical in both modes. The only difference is who decides the next action.

---

## Building Your Own Compositions

The libraries are the deliverable. Source them and compose:

```bash
#!/usr/bin/env bash
# my-custom-tool.sh — your own composition
source lib/config.sh && config_init "$(dirname "$0")"
source lib/llm.sh
source lib/compose.sh

prompt=$(compose_system "agents/default")
response=$(llm_call "$1" --system "$prompt")
echo "$response"
```

That's a complete shellclaw-based tool in 6 lines. Different scripts, different orderings, different policies — same primitives.
