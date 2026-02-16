# Shellclaw Tool Interface Specification

## Overview

A **tool** in shellclaw is an executable that can describe its own interface. It can be a shell script, a Python script, a compiled binary — the shell doesn't care. As long as it's executable and responds to `--describe` with valid JSON, it's a tool.

Tools are the mechanism through which an LLM (or a script) can take actions in the world: check the weather, query a database, create a GitHub issue, read disk usage. The tool interface is the contract between the tool and the system that calls it.

## Why Self-Description

Tools own their own descriptions. There is no external registry, no hand-maintained JSON catalog, no `tools.json` that you have to keep synchronized with the actual tool implementations.

Instead, the tool catalog is **derived** at runtime by calling `--describe` on each executable in the tools directory:

```bash
source lib/discover.sh
catalog=$(discover_tools "$SHELLCLAW_TOOLS_DIR")
```

This means:
- Adding a tool = dropping an executable in the directory
- Removing a tool = deleting the file
- Updating a tool's interface = editing the tool itself
- The catalog is always in sync because it's always derived from the source of truth

No synchronization drift. No forgotten updates. The tool is the spec.

## Self-Description Mode

When called with `--describe`, a tool outputs a JSON object to stdout describing its interface:

```bash
./tools/get_weather.sh --describe
```

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

### Required Fields

| Field | Type | Description |
|---|---|---|
| `name` | string | Tool identifier. Must match what the LLM sends in tool calls. |
| `description` | string | Human-readable description of what the tool does. |
| `parameters` | object | JSON Schema object describing accepted arguments. |

### Parameters Schema

The `parameters` object follows [JSON Schema](https://json-schema.org/) conventions:

- `type`: always `"object"` at the top level
- `properties`: map of parameter names to their schemas
- `required`: array of parameter names that must be provided
- Each property can have: `type`, `description`, `enum`, `default`

This format is deliberately close to the tool definition formats used by the Anthropic and OpenAI APIs. The tool-calling backends (Phase 6) transform it into whatever their specific API requires.

### Exit Code

`--describe` must exit with code 0 on success. Any non-zero exit code indicates the tool cannot describe itself (broken, missing dependencies, etc.) and it will be skipped during discovery.

## Execution Mode

When called without `--describe`, a tool receives its arguments as a JSON string in `$1`:

```bash
./tools/get_weather.sh '{"location": "Half Moon Bay", "unit": "celsius"}'
```

### Input

- **`$1`**: A JSON object containing the arguments. The keys match the `properties` defined in the tool's `--describe` output.
- Tools parse this with `jq`: `local location=$(echo "$1" | jq -r '.location')`

### Output

- **stdout**: The tool's result. Can be plain text or JSON — the caller captures it.
- **stderr**: Error messages. These are captured separately by the dispatch layer.

### Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Error (bad input, missing args, execution failure) |

## The Shim Pattern

Many useful tools already exist as Unix commands (`du`, `curl`, `grep`, `jq`). They don't support `--describe`. The **shim pattern** wraps them with a self-describing interface:

```bash
#!/usr/bin/env bash
# tools/disk_usage.sh — Shim wrapping du with a self-describing interface

if [[ "${1:-}" == "--describe" ]]; then
    cat <<'JSON'
{
  "name": "disk_usage",
  "description": "Check disk usage for a directory",
  "parameters": {
    "type": "object",
    "properties": {
      "path": { "type": "string", "description": "Directory path" }
    },
    "required": []
  }
}
JSON
    exit 0
fi

# Parse JSON args
path=$(echo "$1" | jq -r '.path // "."')

# Call the wrapped tool
du -sh "$path"
```

The shim doesn't modify `du`. It wraps it with a curated interface — exposing only the parameters that make sense for LLM consumption, with clear descriptions. The LLM never calls `du` directly; it calls `disk_usage` which translates.

This is the primary integration pattern for existing tools. You don't need to rewrite `curl` or `grep` — you write a 20-line shim.

## Stub Mode

Tools that depend on external services (APIs, network) must support a stub mode for testing:

```bash
if [[ "${SHELLCLAW_STUB:-}" == "1" ]]; then
    echo '{"location":"Half Moon Bay","temperature":"15","unit":"celsius","condition":"Sunny"}'
    exit 0
fi
```

The `SHELLCLAW_STUB=1` environment variable triggers deterministic, offline responses. This follows the existing pattern in shellclaw where `SHELLCLAW_LLM_BACKEND=stub` provides offline LLM responses.

Tests always run with `SHELLCLAW_STUB=1`. No network calls, no API keys, no external dependencies in the test suite.

## Context Modules

Context modules are **not tools**. They are markdown files that provide domain knowledge, constraints, or procedural guidance to the agent. They are loaded into the system prompt alongside `soul.md`.

Context modules live in `agents/<id>/context/` as `.md` files:

```
agents/default/
├── soul.md              # identity (always loaded)
├── context/             # domain knowledge (loaded alongside soul)
│   ├── 01-domain.md
│   └── 02-procedures.md
└── sessions/
```

They are concatenated into the system prompt in alphabetical order, separated by `---`. Use numeric prefixes for explicit ordering.

Context modules are "just chunks of context." They don't execute. They don't sequence actions. They improve the LLM's decisions by giving it knowledge it wouldn't otherwise have.

## Discovery and Dispatch

The `lib/discover.sh` library derives the tool catalog:

```bash
source lib/discover.sh
catalog=$(discover_tools "tools")    # JSON array of all tool schemas
schema=$(discover_tool "tools/get_weather.sh")  # single tool schema
```

The `lib/dispatch.sh` library executes tool calls:

```bash
source lib/dispatch.sh
validate_tool_call "$catalog" "get_weather" '{"location":"NYC"}'
result=$(dispatch_tool "tools" "get_weather" '{"location":"NYC"}')
```

Dispatch is **default-deny**: only tools present in the discovered catalog can be executed. Unknown tool names are rejected.

## Inspectability

Everything is visible:

```bash
cat tools/get_weather.sh                    # read the tool source
tools/get_weather.sh --describe | jq .      # see its interface
discover_tools tools/ | jq .               # see the full catalog
discover_tools tools/ | jq '.[].name'      # list tool names
```

No hidden state. No opaque registries. Files and executables, inspectable with standard Unix tools.
