# Example Context Module

This is an example context module. Context modules provide domain knowledge, constraints, or procedural guidance to the agent. They are loaded into the system prompt alongside soul.md.

## When to use context modules

- Domain-specific knowledge the LLM wouldn't otherwise have
- Procedural guidance for specific tasks
- Constraints or rules to follow

## How they work

Context modules are markdown files in `agents/<id>/context/`. They are loaded alphabetically and concatenated into the system prompt, separated by `---`. Use numeric prefixes (e.g., `01-domain.md`, `02-procedures.md`) for explicit ordering.
