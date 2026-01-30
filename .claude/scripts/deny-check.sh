#!/bin/bash
# =============================================================================
# Claude Code Deny Check Hook Script
# =============================================================================
# This script checks if a command is denied by the settings.json configuration.
# It is used as a PreToolUse hook for the Bash tool in dangerously-skip-permissions mode.
#
# Usage:
#   This script is called automatically by Claude Code before executing Bash commands.
#   It receives JSON input via stdin with the tool_name and tool_input.
#
# Exit codes:
#   0 - Command is allowed
#   2 - Command is denied
# =============================================================================

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command' 2>/dev/null || echo "")
tool_name=$(echo "$input" | jq -r '.tool_name' 2>/dev/null || echo "")

# Only check Bash commands
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

# Find settings.json relative to this script
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
settings_file="$script_dir/../settings.json"

# Check if settings file exists
if [ ! -f "$settings_file" ]; then
  exit 0
fi

# Extract deny patterns from settings.json
deny_patterns=$(jq -r '.permissions.deny[] | select(startswith("Bash(")) | gsub("^Bash\\("; "") | gsub("\\)$"; "")' "$settings_file" 2>/dev/null)

# Function to check if command matches a deny pattern
matches_deny_pattern() {
  local cmd="$1"
  local pattern="$2"

  # Trim whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"

  # Use bash pattern matching
  [[ "$cmd" == $pattern ]]
}

# Check the full command against deny patterns
while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue

  if matches_deny_pattern "$command" "$pattern"; then
    echo "Error: Command denied: '$command' (pattern: '$pattern')" >&2
    exit 2
  fi
done <<<"$deny_patterns"

# Also check individual parts of compound commands (;, &&, ||)
temp_command="${command//;/$'\n'}"
temp_command="${temp_command//&&/$'\n'}"
temp_command="${temp_command//\|\|/$'\n'}"

IFS=$'\n'
for cmd_part in $temp_command; do
  [ -z "$(echo "$cmd_part" | tr -d '[:space:]')" ] && continue

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    if matches_deny_pattern "$cmd_part" "$pattern"; then
      echo "Error: Command denied: '$cmd_part' (pattern: '$pattern')" >&2
      exit 2
    fi
  done <<<"$deny_patterns"
done

exit 0
