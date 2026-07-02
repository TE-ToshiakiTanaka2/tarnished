#!/bin/bash
# =============================================================================
# Claude Code Bash Command Deny Check
# =============================================================================
# This script is called as a PreToolUse hook for Bash commands.
# It checks if the command matches any denied patterns.
#
# Claude Code delivers hook input as JSON on stdin; the Bash command string
# is at .tool_input.command (there is no CLAUDE_BASH_COMMAND environment
# variable). Exit 2 blocks the tool call and feeds stderr back to Claude;
# missing/unparsable input fails open (exit 0) by contract.

# Get the command from the hook's stdin JSON
COMMAND="$(jq -r '.tool_input.command // empty' 2>/dev/null)"

# List of denied command patterns (regex)
DENIED_PATTERNS=(
    "^apt\\s"
    "^apt-get\\s"
    "^brew\\s+install"
    "^chmod\\s+777"
    "^gh\\s+repo\\s+delete"
    "^git\\s+config\\s+--global"
    "^rm\\s+-rf\\s+/"
    "^sudo\\s+rm\\s+-rf"
)

# Check each pattern
for pattern in "${DENIED_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qE "$pattern"; then
        echo "DENIED: Command matches blocked pattern: $pattern" >&2
        exit 2
    fi
done

# Command is allowed
exit 0
