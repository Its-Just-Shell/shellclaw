#!/usr/bin/env bash
# shellclaw/tools/get_weather.sh — Get current weather for a location
#
# Demonstrates the tool convention for purpose-built tools.
# Handles --describe natively. Wraps wttr.in for real weather data.
# Returns deterministic stub data when SHELLCLAW_STUB=1.
#
# Modes:
#   --describe         Output JSON tool schema to stdout
#   '{"location":...}' Execute with JSON args in $1
#
# Environment:
#   SHELLCLAW_STUB=1   Return stub data instead of calling wttr.in

if [[ "${1:-}" == "--describe" ]]; then
    # Output the tool's schema as JSON. This is what discover_tool reads.
    # The format matches JSON Schema conventions and is close to the
    # Anthropic/OpenAI tool definition formats.
    cat <<'JSON'
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
        "description": "Temperature unit (default: celsius)"
      }
    },
    "required": ["location"]
  }
}
JSON
    exit 0
fi

# --- Execution mode ---

args="${1:-}"

if [[ -z "$args" ]]; then
    echo "get_weather: JSON arguments required" >&2
    exit 1
fi

# Parse JSON args with jq.
# -r outputs raw strings (no quotes). // provides defaults for optional fields.
location=$(printf '%s' "$args" | jq -r '.location // empty')
unit=$(printf '%s' "$args" | jq -r '.unit // "celsius"')

if [[ -z "$location" ]]; then
    echo "get_weather: 'location' is required" >&2
    exit 1
fi

# Stub mode: return deterministic data for testing.
# No network calls, no API dependency.
if [[ "${SHELLCLAW_STUB:-}" == "1" ]]; then
    jq -n -c \
        --arg location "$location" \
        --arg temperature "15" \
        --arg unit "$unit" \
        --arg condition "Sunny" \
        '{location: $location, temperature: $temperature, unit: $unit, condition: $condition}'
    exit 0
fi

# Real mode: call wttr.in.
# wttr.in is a free weather service that returns JSON with ?format=j1.
# curl -s suppresses the progress bar. -f fails silently on HTTP errors.
response=$(curl -sf "wttr.in/${location}?format=j1" 2>/dev/null)

if [[ -z "$response" ]]; then
    echo "get_weather: failed to fetch weather for '$location'" >&2
    exit 1
fi

# Extract relevant fields from the wttr.in response.
# The response structure: .current_condition[0] has the weather data.
if [[ "$unit" == "fahrenheit" ]]; then
    temp_field="temp_F"
else
    temp_field="temp_C"
fi

printf '%s' "$response" | jq -c \
    --arg location "$location" \
    --arg unit "$unit" \
    --arg temp_field "$temp_field" \
    '{
        location: $location,
        temperature: .current_condition[0][$temp_field],
        unit: $unit,
        condition: .current_condition[0].weatherDesc[0].value
    }'
