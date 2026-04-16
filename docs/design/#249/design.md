# Design: #249 Change MCP Server Installation Scope from User to Project

## Architecture Overview

This is a straightforward refactoring of DevContainer setup scripts to change MCP server installation scope from user-level (`local`, the default) to project-level (`--scope project`). Additionally, the superclaude dependency is removed from the main workspace's `post.sh` and replaced with a standalone `setup_mcp.sh`.

## Module Structure

```
.devcontainer/scripts/
├── post.sh              # Modified: remove setup_superclaude(), add setup_mcp.sh sourcing
└── setup_mcp.sh         # New: MCP server setup for main workspace

templates/claude/.devcontainer/scripts/
└── setup_mcp.sh         # Modified: add --scope project to claude mcp add commands
```

## Changes Detail

### 1. `templates/claude/.devcontainer/scripts/setup_mcp.sh` (Modified)

Add `-s project` flag to all three `claude mcp add` invocations:

| Line | Before | After |
| --- | --- | --- |
| 39 | `claude mcp add context7 -- npx ...` | `claude mcp add -s project context7 -- npx ...` |
| 51 | `claude mcp add serena -- uvx ...` | `claude mcp add -s project serena -- uvx ...` |
| 69 | `claude mcp add playwright -- npx ...` | `claude mcp add -s project playwright -- npx ...` |

### 2. `.devcontainer/scripts/post.sh` (Modified)

- **Delete**: Lines 261-295 (`setup_superclaude()` function and its invocation)
- **Add**: Source and call `setup_mcp.sh` using the same pattern as `templates/claude/plugin.sh` (L123-127)

The replacement block follows the existing integration pattern from the template:

```bash
# -----------------------------------------------------------------------------
# MCP Server Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_mcp.sh" ]]; then
    source "${SCRIPT_DIR}/setup_mcp.sh"
    setup_mcp
fi
```

### 3. `.devcontainer/scripts/setup_mcp.sh` (New)

New file following the same structure as `templates/claude/.devcontainer/scripts/setup_mcp.sh` with:

- Same header comment block and function structure
- `context7` and `serena` as required servers
- `playwright` as optional (interactive prompt)
- All `claude mcp add` commands use `-s project`
- `setup_mcp` function name (matching the template pattern)

## Data Flow

```
DevContainer creation
  → post.sh
    → source setup_mcp.sh
      → setup_mcp()
        → claude mcp add -s project context7
        → claude mcp add -s project serena
        → (optional) claude mcp add -s project playwright
```

MCP configuration is written to `.claude/settings.json` (project scope) instead of `~/.claude/settings.json` (user scope).

## Error Handling

Follows the existing pattern in the template's `setup_mcp.sh`:

- Claude Code CLI not installed: warn and return 0
- `uvx` not available for serena: warn and skip
- Non-interactive environment: skip playwright prompt
- `setup_mcp.sh` file not found: silently skip (guarded by `-f` check in post.sh)

## Implementation Notes

- **Flag choice**: Use `-s project` (short form) over `--scope project` for consistency with the concise style of the existing script.
- **No sequential-thinking**: The superclaude setup included `sequential-thinking`, but the user confirmed only `context7` and `serena` are needed.
- **Independent maintenance**: The main workspace's `setup_mcp.sh` and the template's `setup_mcp.sh` are separate files maintained independently, not symlinked or shared.
- **Sourcing pattern**: Uses `source` + function call pattern (matching `plugin.sh` integration), not direct execution, to keep the `is_interactive` function available.
