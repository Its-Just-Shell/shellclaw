#!/usr/bin/env bash
# shellclaw/tools/github_issue.sh — Create a GitHub issue
#
# Demonstrates the shim pattern for API-backed tools.
# Wraps the GitHub REST API via curl. Uses stub mode by default
# in tests to avoid needing authentication or network access.
#
# Modes:
#   --describe              Output JSON tool schema to stdout
#   '{"repo":...,"title":...}'  Execute with JSON args in $1
#
# Environment:
#   SHELLCLAW_STUB=1   Return stub response instead of calling GitHub API
#   GITHUB_TOKEN       GitHub personal access token (required for real mode)

if [[ "${1:-}" == "--describe" ]]; then
    cat <<'JSON'
{
  "name": "github_issue",
  "description": "Create a GitHub issue in a repository",
  "parameters": {
    "type": "object",
    "properties": {
      "repo": {
        "type": "string",
        "description": "Repository in owner/repo format"
      },
      "title": {
        "type": "string",
        "description": "Issue title"
      },
      "body": {
        "type": "string",
        "description": "Issue body text (optional)"
      }
    },
    "required": ["repo", "title"]
  }
}
JSON
    exit 0
fi

# --- Execution mode ---

args="${1:-}"

if [[ -z "$args" ]]; then
    echo "github_issue: JSON arguments required" >&2
    exit 1
fi

# Parse required fields
repo=$(printf '%s' "$args" | jq -r '.repo // empty')
title=$(printf '%s' "$args" | jq -r '.title // empty')
body=$(printf '%s' "$args" | jq -r '.body // ""')

if [[ -z "$repo" ]]; then
    echo "github_issue: 'repo' is required" >&2
    exit 1
fi

if [[ -z "$title" ]]; then
    echo "github_issue: 'title' is required" >&2
    exit 1
fi

# Stub mode: return what would happen without actually calling the API.
if [[ "${SHELLCLAW_STUB:-}" == "1" ]]; then
    jq -n -c \
        --arg repo "$repo" \
        --arg title "$title" \
        --arg body "$body" \
        '{
            status: "stub",
            message: ("Would create issue in " + $repo + ": " + $title),
            url: ("https://github.com/" + $repo + "/issues/0")
        }'
    exit 0
fi

# Real mode: POST to GitHub API.
# Requires GITHUB_TOKEN environment variable.
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "github_issue: GITHUB_TOKEN environment variable required" >&2
    exit 1
fi

# Build the request body with jq (safe JSON construction).
request_body=$(jq -n -c \
    --arg title "$title" \
    --arg body "$body" \
    '{title: $title, body: $body}')

# curl -s suppresses progress, -f fails on HTTP errors.
# -H sets headers: auth token and JSON content type.
# -d sends the request body.
response=$(curl -sf \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$request_body" \
    "https://api.github.com/repos/$repo/issues" 2>/dev/null)

if [[ -z "$response" ]]; then
    echo "github_issue: API call failed for repo '$repo'" >&2
    exit 1
fi

# Return the issue URL and number from the response
printf '%s' "$response" | jq -c '{url: .html_url, number: .number, title: .title}'
