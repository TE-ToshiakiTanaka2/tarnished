# Design: #249 Change MCP Server Installation Scope from User to Project

## Architecture Overview

Replace `claude mcp add` (user-scoped by default) with `claude plugins install -s project` using official plugins from the `claude-plugins-official` marketplace. This standardizes the entry point for MCP server installation and removes the superclaude dependency from the main workspace's `post.sh`.

## Module Structure

```
.devcontainer/scripts/
├── post.sh              # Modified: remove setup_superclaude(), add setup_plugins.sh sourcing
└── setup_plugins.sh     # New: plugin installation for main workspace

templates/claude/.devcontainer/scripts/
└── setup_plugins.sh     # Renamed + Modified: use claude plugins install

templates/claude/
└── plugin.sh            # Modified: update references from setup_mcp to setup_plugins
```

## Changes Detail

### 1. `templates/claude/.devcontainer/scripts/setup_plugins.sh` (Renamed from setup_mcp.sh)

Replace all `claude mcp add` commands with `claude plugins install`:

| Before | After |
| --- | --- |
| `claude mcp add -s project context7 -- npx ...` | `claude plugins install context7@claude-plugins-official -s project` |
| `claude mcp add -s project serena -- uvx ...` | `claude plugins install serena@claude-plugins-official -s project` |
| `claude mcp add -s project playwright -- npx ...` | `claude plugins install playwright@claude-plugins-official -s project` |

Idempotency check changed from `claude mcp list` to `claude plugins list`.

### 2. `.devcontainer/scripts/post.sh` (Modified)

- **Delete**: `setup_superclaude()` function and its invocation (L261-295)
- **Add**: Source and call `setup_plugins.sh`

### 3. `.devcontainer/scripts/setup_plugins.sh` (New)

Same structure as template version, with `claude plugins install -s project` for all servers.

### 4. `templates/claude/plugin.sh` (Modified)

Update integration block: references to `setup_mcp.sh` / `setup_mcp` changed to `setup_plugins.sh` / `setup_plugins`.

## Data Flow

```
DevContainer creation
  → post.sh
    → source setup_plugins.sh
      → setup_plugins()
        → claude plugins install context7@claude-plugins-official -s project
        → claude plugins install serena@claude-plugins-official -s project
        → (optional) claude plugins install playwright@claude-plugins-official -s project
```

## Error Handling

- Claude Code CLI not installed: warn and return 0
- Plugin already installed: skip (checked via `claude plugins list`)
- Non-interactive environment: skip playwright prompt
- `setup_plugins.sh` file not found: silently skip (guarded by `-f` check)

## Implementation Notes

- **Official plugins**: Using `claude-plugins-official` marketplace standardizes the entry point and ensures consistent MCP server configurations across projects.
- **No `uvx`/`npx` prerequisite checks**: Plugin system manages dependencies internally.
- **Independent maintenance**: Main workspace and template `setup_plugins.sh` are separate files.
- **Sourcing pattern**: Uses `source` + function call to keep `is_interactive` available.
