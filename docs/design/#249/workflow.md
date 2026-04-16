# Workflow: #249 Change MCP Server Installation Scope from User to Project

## Implementation Steps

### Step 1: Add `--scope project` to template's `setup_mcp.sh`

- **Action**: Add `-s project` flag to all three `claude mcp add` commands in the template script
- **Files**: `templates/claude/.devcontainer/scripts/setup_mcp.sh` (modify)
- **Depends on**: None
- **Done when**: All three `claude mcp add` commands include `-s project` flag

### Step 2: Create main workspace `setup_mcp.sh`

- **Action**: Create new `setup_mcp.sh` based on the template version's pattern, with `-s project` flag on all commands
- **Files**: `.devcontainer/scripts/setup_mcp.sh` (create)
- **Depends on**: None (can be done in parallel with Step 1)
- **Done when**: File exists with `setup_mcp` function containing context7, serena (required) and playwright (optional) setup

### Step 3: Replace `setup_superclaude()` with `setup_mcp.sh` sourcing in `post.sh`

- **Action**: Remove `setup_superclaude()` function (L264-293) and its invocation (L295). Replace the entire section (L261-295) with `setup_mcp.sh` sourcing block.
- **Files**: `.devcontainer/scripts/post.sh` (modify)
- **Depends on**: Step 2 (the sourced file must exist for the pattern to make sense)
- **Done when**: `setup_superclaude` is fully removed and `setup_mcp` is sourced/called

### Step 4: Verify scripts

- **Action**: Run `shellcheck` on modified/created scripts and verify `claude mcp add --help` confirms `-s project` is valid
- **Files**: None (verification only)
- **Depends on**: Steps 1, 2, 3
- **Done when**: No shellcheck errors, flag syntax confirmed

## Task Dependencies

- Steps 1 and 2 can be done in parallel (independent files)
- Step 3 depends on Step 2
- Step 4 depends on Steps 1, 2, 3

## Test Strategy

### Verification

- `shellcheck` on all modified/created shell scripts
- Confirm `claude mcp add -s project` is valid syntax (via `--help`)
- Confirm no remaining references to `superclaude` in `post.sh`

### Edge Cases

- `setup_mcp.sh` not found: guarded by `-f` check — silently skips
- Claude Code CLI not installed: warns and returns 0
- `uvx` not available: warns and skips serena
- Non-interactive environment: skips playwright prompt
