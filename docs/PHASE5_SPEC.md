# Shellclaw Phase 5: Tool Interface Specification

## Context

You are working on shellclaw, a composable LLM primitives library built from Unix tools, following the "Its Just Shell" thesis (https://itsjustshell.com). The repo is at https://github.com/Its-Just-Shell/shellclaw.

Phases 1-4 are complete: config (`lib/config.sh`), logging (`lib/log.sh`), session management (`lib/session.sh`), LLM wrapper (`lib/llm.sh`), system prompt assembly (`lib/compose.sh`), and the `shellclaw` entry point. All have tests. The test harness is at `test/test_harness.sh`.

The current PLAN.md references Phase 5 as "Tool-Calling Backends" (three backends: bash/curl+jq, llm CLI, Elixir). But Phase 5 has a prerequisite that was never specced: the **tool interface itself**. Line 324 of PLAN.md says "Skills are always shell scripts (executables with `--describe` for schema)" but `--describe` is unspecced — there is no definition of what it outputs, no discovery mechanism, no example tools.

We are renumbering the phases. What was Phase 5 (tool-calling backends) becomes Phase 6. This new Phase 5 is the **Tool Interface Specification** — the foundational work that makes the backends possible.

## Vocabulary Decisions

These vocabulary decisions emerged from architectural analysis and must be reflected throughout all code, docs, and comments:

1. **Tools, not skills.** The PLAN.md uses "skills" for executables and "tools" for JSON schemas. We are collapsing this. A tool is an executable that can describe its own interface. There is no separate "skills" concept. Rename `$SHELLCLAW_SKILLS_DIR` to `$SHELLCLAW_TOOLS_DIR`. The directory is `tools/`, not `skills/`.

2. **Context modules, not skills.** Anthropic's "skills" concept (markdown files injected into LLM context to provide domain knowledge and procedural guidance) maps to what we call **context modules**. These are markdown files that get composed into the system prompt alongside soul.md. They provide domain knowledge, not capabilities. They are "just chunks of context." They live in `agents/<id>/context/` as `.md` files.

3. **Workflows, not a third category.** Multi-tool coordination that is deterministic enough to sequence is a script-driven workflow — just an executable in `$PATH`. No special infrastructure needed.

4. **Two control modes only.** Script-driven (the script calls tools, the LLM provides judgment) and LLM-driven (the LLM calls tools via the tool loop). There is no third mode. LLM-driven with a context module loaded is still LLM-driven — the context module improves the LLM's decisions, it doesn't change the control model.

## What to Build

### 5a: The `--describe` Convention (`docs/TOOL_INTERFACE.md`)

Write a specification document defining the tool interface contract. A tool is an executable (shell script, Python script, compiled binary — the shell doesn't care) that supports two modes:

**Self-description mode:** `tool.sh --describe` outputs a JSON object to stdout:

```json
{
  "name": "get_weather",
  "description": "Get current weather for a location",
  "parameters": {
    "type": "object",
    "properties": {
      "location": {
        "type": "string",
        "description": "City name or coordinates"
      },
      "unit": {
        "type": "string",
        "enum": ["celsius", "fahrenheit"],
        "description": "Temperature unit"
      }
    },
    "required": ["location"]
  }
}
```

This format is deliberately close to JSON Schema and to the tool definition formats used by the Anthropic and OpenAI APIs. The tool owns this description. The tool-calling backends (Phase 6) will transform it into whatever their API requires.

The `parameters` object follows JSON Schema conventions: `type`, `properties`, `required`, `enum`, `description`. This is the same vocabulary used by the API providers, minimizing translation work.

**Execution mode:** When called without `--describe`, the tool receives its arguments as a JSON string in `$1`:

```bash
./tools/get_weather.sh '{"location": "Half Moon Bay", "unit": "celsius"}'
```

Results go to stdout (text or JSON). Errors go to stderr. Exit codes: 0 = success, 1 = error.

The spec document should also cover:
- Why tools self-describe rather than using an external registry (the tool owns its interface, no synchronization drift)
- How this relates to the broader thesis (tools are executables in `$PATH`, the catalog is derived not maintained)
- The shim pattern for wrapping existing CLI tools that don't natively support `--describe`

### 5b: Discovery Library (`lib/discover.sh`)

A sourceable library that builds the tool catalog from self-describing tools:

```bash
# discover_tools <tools_dir>
#   Walks the directory, calls --describe on each executable,
#   assembles a JSON array of tool schemas.
#   Outputs the catalog to stdout.
#   Skips non-executable files and tools whose --describe fails.
```

This replaces the hand-maintained `tools.json` referenced in the current PLAN.md. The tool catalog becomes a derived artifact:

```bash
source lib/discover.sh
catalog=$(discover_tools "$SHELLCLAW_TOOLS_DIR")
```

The function should:
- Walk `$tools_dir` and find executables
- Call `--describe` on each, capture stdout
- Validate that the output is valid JSON with required fields (name, description, parameters)
- Skip and warn on failures (non-executable, --describe fails, invalid JSON)
- Assemble into a JSON array
- Output to stdout

Also provide:
```bash
# discover_tool <tool_path>
#   Calls --describe on a single tool and validates the output.
#   Outputs the schema to stdout, or error to stderr with exit 1.
```

### 5c: Context Module Support in `compose_system`

Extend `lib/compose.sh` so that `compose_system` loads context modules from the agent's `context/` directory alongside soul.md:

```bash
compose_system() {
    local agent_dir="$1"

    # Identity — always loaded
    cat "$agent_dir/soul.md"

    # Context modules — domain knowledge, procedural guidance
    if [[ -d "$agent_dir/context" ]]; then
        for module in "$agent_dir/context"/*.md; do
            [[ -f "$module" ]] || continue
            printf '\n---\n'
            cat "$module"
        done
    fi
}
```

Context modules are markdown files that provide domain knowledge, constraints, or procedural guidance. They are loaded into the system prompt. They are not tools (they don't execute), and they are not workflows (they don't sequence actions). They are composable chunks of context.

Create a default example context module at `agents/default/context/` to demonstrate the pattern.

### 5d: Example Tools

Build 3 example tools in a `tools/` directory at the project root:

1. **`tools/get_weather.sh`** — A purpose-built tool written from scratch. Handles `--describe` natively. Wraps `curl` to `wttr.in`. Demonstrates the convention for new tools.

2. **`tools/disk_usage.sh`** — A shim wrapping `du`. Translates `--describe` into a curated subset of `du`'s interface (path and human-readable flag). Demonstrates the shim pattern for existing Unix tools — the tool doesn't modify `du`, it wraps it with a self-describing interface.

3. **`tools/github_issue.sh`** — A shim wrapping the GitHub API via `curl`. Accepts repo and title as parameters. Demonstrates the pattern for API-backed tools. (Can use a stub mode that echoes what it would do, for testing without auth.)

Each tool must:
- Respond to `--describe` with valid JSON matching the spec
- Accept arguments as a JSON string in `$1`
- Return results on stdout
- Return errors on stderr with exit code 1
- Be executable (`chmod +x`)
- Include a comment header explaining what it demonstrates

### 5e: Tool Dispatch Library (`lib/dispatch.sh`)

A sourceable library that handles executing a tool call from the LLM:

```bash
# dispatch_tool <tools_dir> <tool_name> <args_json>
#   Finds the named tool in tools_dir, executes it with args_json,
#   captures stdout and stderr, returns the result.
#   Exit: 0=success, 1=tool not found, 2=tool execution failed

# validate_tool_call <catalog_json> <tool_name> <args_json>
#   Validates that tool_name exists in the catalog and args_json
#   contains all required fields. Returns 0 if valid, 1 if not.
#   Error details on stderr.
```

This is the layer between the tool loop (Phase 6) and the actual tool executables. It handles:
- Tool name lookup and allowlist checking
- Argument validation against the tool's schema (at minimum: required field presence)
- Execution with proper stdout/stderr capture
- Logging via `log_event`

The dispatch function never executes a tool that isn't in the catalog. Default-deny.

### 5f: Tests

Following the existing test patterns in `test/test_harness.sh`:

**`test/test_discover.sh`:**
- Every tool in `tools/` responds to `--describe` with valid JSON
- Output contains required fields: name, description, parameters
- `discover_tools` assembles a valid JSON array
- Non-executable files are skipped
- Tools with broken `--describe` are skipped with warning
- Catalog can be parsed by `jq` as an array of tool objects

**`test/test_dispatch.sh`:**
- `dispatch_tool` finds and executes a valid tool
- Returns tool output on stdout
- Returns non-zero for unknown tool names
- Returns non-zero for tools not in allowlist
- `validate_tool_call` catches missing required fields
- `validate_tool_call` passes valid calls

**`test/test_compose.sh` (extend existing):**
- `compose_system` includes context modules when present
- Context modules are separated by `---`
- Missing context directory is handled gracefully (no error, just soul.md)
- Empty context directory works

**`test/test_tools.sh`:**
- Each example tool's `--describe` output is valid JSON
- Each example tool accepts JSON args in `$1` and returns output
- Each example tool returns exit 1 on bad input
- `get_weather.sh` returns weather data (or stub)
- `disk_usage.sh` returns usage data for valid paths
- `github_issue.sh --describe` matches expected schema

All tests must use the stub/offline pattern — no network calls, no API keys. Tools that wrap external services should have a `--stub` mode or check for an environment variable like `SHELLCLAW_STUB=1`.

## Updated Directory Structure

```
shellclaw/
├── shellclaw                    # Entry point (Phase 4, exists)
├── lib/
│   ├── config.sh               # (exists)
│   ├── log.sh                  # (exists)
│   ├── session.sh              # (exists)
│   ├── llm.sh                  # (exists)
│   ├── compose.sh              # (exists, extend for context modules)
│   ├── discover.sh             # NEW — tool catalog assembly
│   └── dispatch.sh             # NEW — tool execution + validation
├── tools/                       # NEW — self-describing tool executables
│   ├── get_weather.sh
│   ├── disk_usage.sh
│   └── github_issue.sh
├── agents/
│   └── default/
│       ├── soul.md              # (exists)
│       ├── context/             # NEW — context modules
│       │   └── example.md       # NEW — example context module
│       └── sessions/            # (exists)
├── config/
│   ├── shellclaw.env            # (exists, update SHELLCLAW_TOOLS_DIR)
│   └── agents.json              # (exists)
├── docs/
│   ├── PLAN.md                  # (exists, update phase numbering + vocabulary)
│   ├── TOOL_INTERFACE.md        # NEW — the spec
│   └── tutorials/               # (exists)
├── test/
│   ├── test_harness.sh          # (exists)
│   ├── test_discover.sh         # NEW
│   ├── test_dispatch.sh         # NEW
│   ├── test_compose.sh          # (exists, extend)
│   ├── test_tools.sh            # NEW
│   └── run_all.sh               # (exists, will auto-discover new tests)
└── .claude/
    └── settings.local.json      # (exists)
```

## Updated config/shellclaw.env

Add:
```bash
# Directory containing self-describing tool executables
SHELLCLAW_TOOLS_DIR="tools"
```

## Updated PLAN.md

The PLAN.md needs the following updates:
1. **Vocabulary**: Replace all instances of "skill"/"skills" with "tool"/"tools" in the context of executables. Replace `$SHELLCLAW_SKILLS_DIR` with `$SHELLCLAW_TOOLS_DIR`.
2. **Phase numbering**: Current Phase 5 becomes Phase 6. Insert new Phase 5: Tool Interface Specification.
3. **Phase 5 content**: Document the `--describe` convention, discovery mechanism, context modules, dispatch, and example tools as described above.
4. **TODO table**: Move "Skills system" from deferred to "Phase 5 (Tool Interface Specification)". It is not a feature that requires tool calling — it is a prerequisite that tool calling requires.

## Design Principles

These come from the IJS thesis and should guide all implementation decisions:

- **Tools own their own descriptions.** No external registry, no hand-maintained JSON catalog. The tool self-describes via `--describe`. The catalog is derived by discovery, not maintained by humans.
- **Everything is inspectable.** `cat tools/get_weather.sh` shows you the tool. `tools/get_weather.sh --describe | jq .` shows you its interface. `discover_tools tools/ | jq .` shows you the full catalog. No hidden state.
- **The shell doesn't care what language the tool is written in.** A tool can be bash, Python, Elixir, a compiled binary. As long as it's executable and responds to `--describe` with valid JSON, it's a tool.
- **Context modules are just files.** They're markdown. They get concatenated into the system prompt. No YAML frontmatter, no invocation routing, no progressive disclosure optimization (yet). Start simple.
- **Default-deny for tool execution.** The dispatch function only executes tools that are in the discovered catalog. Unknown tool names are rejected.
- **Stub everything for testing.** No network calls, no API keys, no external dependencies in tests. Tools that wrap external services must have a stub mode.

## Build Order for Phase 5

Dependencies flow downward:

```
docs/TOOL_INTERFACE.md         ← write first (spec before code)
tools/*                        ← build second (reference implementations of the spec)
lib/discover.sh                ← build third (depends on tools existing to test against)
lib/dispatch.sh                ← build fourth (depends on discover.sh)
lib/compose.sh (extend)        ← build fifth (independent, but completes the phase)
agents/default/context/*.md    ← build sixth (example context module)
test/*                         ← build alongside each component
docs/PLAN.md (update)          ← update last (reflects what was built)
```

## What NOT to Build

- Do NOT build the tool-calling backends (Phase 6). This phase only specs the interface, builds discovery/dispatch, and provides example tools.
- Do NOT build multi-tool workflows. Those are just scripts — no infrastructure needed.
- Do NOT build progressive disclosure for context modules (loading only relevant ones). Start with "load all of them." Optimize later.
- Do NOT modify the `shellclaw` entry point to support `--tools` flags yet. That's Phase 6.
- Do NOT add MCP support. That's future work.
