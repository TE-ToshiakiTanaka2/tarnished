# Design Document: Add SuperClaude Setup to Claude Plugin

**Issue**: #104 - Add SuperClaude setup to Claude plugin
**Milestone**: claude-code
**Date**: 2026-01-19

## Overview

This document describes the architecture and design for adding SuperClaude setup functionality to the Claude plugin in the Devcontainer boilerplate project.

## Current State Analysis

### Existing Architecture

```
/workspace/
├── .devcontainer/scripts/post.sh     # Root dev environment (has setup_superclaude)
├── templates/
│   ├── core/
│   │   └── .devcontainer/scripts/post.sh  # Template (NO SuperClaude setup)
│   └── claude/
│       ├── plugin.sh                      # Plugin definition (NO SuperClaude setup)
│       ├── .claude/                       # Claude Code configs
│       │   ├── commands/
│       │   ├── scripts/
│       │   └── settings.json
│       └── .devcontainer/
│           └── devcontainer.json
```

### Problem Statement

- Root development environment has `setup_superclaude()` function
- Template `templates/core/.devcontainer/scripts/post.sh` lacks SuperClaude setup
- When users run `setup.sh`, new projects don't get SuperClaude configured

## Proposed Architecture

### Component Structure

```
templates/claude/
├── plugin.sh                              # Modified: add script copy + post.sh integration
├── .claude/
│   ├── commands/
│   ├── scripts/
│   └── settings.json
└── .devcontainer/
    ├── devcontainer.json
    └── scripts/                           # NEW: scripts directory
        └── setup_superclaude.sh           # NEW: SuperClaude setup script
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         setup.sh                                 │
│                             │                                    │
│                             ▼                                    │
│                    ┌────────────────┐                           │
│                    │  Load plugins  │                           │
│                    └────────────────┘                           │
│                             │                                    │
│         ┌───────────────────┼───────────────────┐               │
│         ▼                   ▼                   ▼               │
│   ┌──────────┐       ┌──────────┐       ┌──────────┐           │
│   │   core   │       │  claude  │       │   node   │           │
│   │  plugin  │       │  plugin  │       │  plugin  │           │
│   └──────────┘       └──────────┘       └──────────┘           │
│         │                   │                                    │
│         │                   ▼                                    │
│         │          ┌─────────────────┐                          │
│         │          │ plugin_copy()   │                          │
│         │          │ - Copy .claude/ │                          │
│         │          └─────────────────┘                          │
│         │                   │                                    │
│         │                   ▼                                    │
│         │          ┌─────────────────────────┐                  │
│         │          │ plugin_post_copy()      │                  │
│         │          │ - Copy setup_superclaude│                  │
│         │          │ - Append source to post │                  │
│         │          └─────────────────────────┘                  │
│         │                   │                                    │
│         ▼                   ▼                                    │
│   ┌─────────────────────────────────────┐                       │
│   │        Target Project               │                       │
│   │  .devcontainer/scripts/             │                       │
│   │  ├── post.sh (core)                 │                       │
│   │  │   + source setup_superclaude.sh  │  ◄── Added by claude  │
│   │  └── setup_superclaude.sh           │  ◄── Copied by claude │
│   └─────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘

                    At Devcontainer Startup
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  post.sh execution                                               │
│         │                                                        │
│         ├── Core setup (git, ssh, etc.)                         │
│         │                                                        │
│         └── source setup_superclaude.sh                         │
│                    │                                             │
│                    ▼                                             │
│         ┌────────────────────┐                                  │
│         │ setup_superclaude()│                                  │
│         │  ├── Check claude  │                                  │
│         │  ├── Install SC    │                                  │
│         │  ├── Ask Playwright│                                  │
│         │  └── Configure MCP │                                  │
│         └────────────────────┘                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Design

### 1. New File: setup_superclaude.sh

**Location**: `templates/claude/.devcontainer/scripts/setup_superclaude.sh`

**Purpose**: Encapsulate SuperClaude setup logic as a standalone, sourceable script.

**Key Functions**:

```bash
setup_superclaude()
├── Check Claude Code CLI exists
├── Create ~/.claude directory
├── Install SuperClaude via uv
├── Prompt for Playwright (if interactive)
└── Configure MCP servers
```

**Dependencies**:
- `is_interactive()` function (defined in core's post.sh)
- `uv` package manager
- `claude` CLI (optional, graceful skip if missing)

### 2. Modified File: plugin.sh

**Location**: `templates/claude/plugin.sh`

**Changes to `plugin_post_copy()`**:

```bash
plugin_post_copy() {
    local target_dir="$1"

    # Existing: Merge settings.json
    # Existing: Make scripts executable

    # NEW: Copy setup_superclaude.sh
    if [[ -d "${PLUGIN_DIR}/.devcontainer/scripts" ]]; then
        copy_dir_with_confirm "${PLUGIN_DIR}/.devcontainer/scripts" \
            "${target_dir}/.devcontainer/scripts"
    fi

    # NEW: Append source call to post.sh
    local post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    local superclaude_marker="# SuperClaude Framework"

    if [[ -f "$post_sh" ]] && ! grep -q "$superclaude_marker" "$post_sh"; then
        cat >> "$post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# SuperClaude Framework
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_superclaude.sh" ]]; then
    source "${SCRIPT_DIR}/setup_superclaude.sh"
    setup_superclaude
fi
EOF
        print_success "SuperClaude setup integrated into post.sh"
    fi
}
```

### 3. Integration Points

| Component | Integration Method |
|-----------|-------------------|
| Core post.sh | Append source call via plugin_post_copy() |
| Claude plugin | Copy setup_superclaude.sh via plugin_post_copy() |
| Devcontainer | Automatic execution via post.sh chain |

## Configuration

### MCP Servers (Default)

| Server | Purpose |
|--------|---------|
| context7 | Documentation reference |
| sequential-thinking | Structured thinking |
| serena | Code analysis |
| playwright | UI testing (optional) |

### Environment Variables

| Variable | Effect |
|----------|--------|
| `CI` | Skip interactive prompts |
| `NONINTERACTIVE` | Skip interactive prompts |

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Claude CLI not found | Print warning, skip setup, continue |
| uv not found | Fail with error message |
| MCP config fails | Print warning, continue |
| Non-interactive mode | Skip Playwright prompt, install base servers only |

## Testing Strategy

### Unit Tests

1. **Script syntax**: shellcheck validation
2. **Function existence**: Verify setup_superclaude() is defined
3. **Idempotency**: Run twice, verify no errors

### Integration Tests

1. **Plugin copy**: Verify setup_superclaude.sh is copied
2. **Post.sh integration**: Verify source call is appended
3. **Marker detection**: Verify duplicate prevention works

### E2E Tests

1. **Full setup.sh run**: Create project with Claude plugin
2. **Devcontainer build**: Verify post.sh executes correctly
3. **SuperClaude availability**: Verify `uvx superclaude` works

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `templates/claude/.devcontainer/scripts/setup_superclaude.sh` | CREATE | SuperClaude setup script |
| `templates/claude/plugin.sh` | MODIFY | Add copy and integration logic |

## Rollback Plan

If issues arise:

1. Remove `templates/claude/.devcontainer/scripts/` directory
2. Revert changes to `templates/claude/plugin.sh`
3. Existing projects: manually remove source call from post.sh

## Security Considerations

- Script downloads packages from PyPI via `uv`
- MCP servers connect to external services
- No sensitive data is stored in scripts
