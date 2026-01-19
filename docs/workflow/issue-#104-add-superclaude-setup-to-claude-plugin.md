# Implementation Workflow: Add SuperClaude Setup to Claude Plugin

**Issue**: #104 - Add SuperClaude setup to Claude plugin
**Design Document**: `docs/design/issue-#104-add-superclaude-setup-to-claude-plugin.md`
**Date**: 2026-01-19

## Overview

This document outlines the step-by-step implementation workflow for adding SuperClaude setup functionality to the Claude plugin.

## Phase 1: Create SuperClaude Setup Script

### Tasks

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 1.1 | Create scripts directory structure | High | None |
| 1.2 | Create setup_superclaude.sh | High | 1.1 |
| 1.3 | Add shebang and header comments | High | 1.2 |
| 1.4 | Implement setup_superclaude() function | High | 1.3 |
| 1.5 | Test script syntax with shellcheck | High | 1.4 |

### Step 1.1: Create Directory Structure

```bash
mkdir -p templates/claude/.devcontainer/scripts
```

### Step 1.2-1.4: Create setup_superclaude.sh

**File**: `templates/claude/.devcontainer/scripts/setup_superclaude.sh`

```bash
#!/bin/bash
# =============================================================================
# SuperClaude Framework Setup Script
# =============================================================================
# This script sets up SuperClaude Framework for AI-assisted development.
# It is sourced by post.sh during devcontainer initialization.
#
# Prerequisites:
# - uv package manager
# - is_interactive() function (defined in core's post.sh)
#
# Optional:
# - Claude Code CLI (setup skipped if not available)
# =============================================================================

# SuperClaude Framework Setup
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Warning: Claude Code CLI is not installed"
        echo "  - SuperClaude requires Claude Code to function"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Install SuperClaude
    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # MCP servers configuration
    local mcp_servers="context7 sequential-thinking serena"

    # Prompt for Playwright in interactive mode
    if type is_interactive &>/dev/null && is_interactive; then
        read -rp "  - UI開発を行いますか？Playwright MCPをインストールします (y/N): " playwright_answer
        case "$playwright_answer" in
            [yY]|[yY][eE][sS])
                mcp_servers="$mcp_servers playwright"
                echo "  - Playwright MCP will be installed"
                ;;
            *)
                echo "  - Skipping Playwright MCP"
                ;;
        esac
    else
        echo "  - Non-interactive environment, skipping Playwright MCP prompt"
    fi

    # Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_cmd="uvx superclaude mcp"
    for server in $mcp_servers; do
        mcp_cmd="$mcp_cmd --servers $server"
    done
    # shellcheck disable=SC2086
    $mcp_cmd

    echo "  - SuperClaude setup complete"
}
```

### Step 1.5: Verify with shellcheck

```bash
shellcheck templates/claude/.devcontainer/scripts/setup_superclaude.sh
```

## Phase 2: Modify Claude Plugin

### Tasks

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 2.1 | Read current plugin.sh | High | Phase 1 |
| 2.2 | Add script copy logic to plugin_post_copy() | High | 2.1 |
| 2.3 | Add post.sh integration logic | High | 2.2 |
| 2.4 | Test plugin modifications | High | 2.3 |

### Step 2.2-2.3: Modify plugin_post_copy()

Add the following to `templates/claude/plugin.sh`:

```bash
# In plugin_post_copy() function, after existing code:

    # Copy SuperClaude setup script
    if [[ -d "${PLUGIN_DIR}/.devcontainer/scripts" ]]; then
        mkdir -p "${target_dir}/.devcontainer/scripts"
        for script in "${PLUGIN_DIR}/.devcontainer/scripts"/*.sh; do
            if [[ -f "$script" ]]; then
                local script_name
                script_name=$(basename "$script")
                copy_with_confirm "$script" "${target_dir}/.devcontainer/scripts/${script_name}"
            fi
        done
    fi

    # Integrate SuperClaude setup into post.sh
    local post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    local superclaude_marker="# SuperClaude Framework"

    if [[ -f "$post_sh" ]] && ! grep -q "$superclaude_marker" "$post_sh"; then
        print_info "Integrating SuperClaude setup into post.sh..."
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
```

## Phase 3: Testing

### Tasks

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 3.1 | Run shellcheck on all modified scripts | High | Phase 2 |
| 3.2 | Run existing test suite | High | 3.1 |
| 3.3 | Manual verification (dry-run) | Medium | 3.2 |

### Test Commands

```bash
# Shellcheck validation
shellcheck templates/claude/.devcontainer/scripts/setup_superclaude.sh
shellcheck templates/claude/plugin.sh

# Run test suite
bats tests/

# Dry run verification
./setup.sh --dry-run
```

## Phase 4: Commit and Finalize

### Tasks

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 4.1 | Commit design document | High | Phase 1 |
| 4.2 | Commit workflow document | High | Phase 1 |
| 4.3 | Commit implementation | High | Phase 3 |
| 4.4 | Push branch | High | 4.3 |

### Commit Messages

```bash
# Commit 1: Design document
git add docs/design/issue-#104-*.md
git commit -m "📝 docs: add design document for SuperClaude setup (#104)"

# Commit 2: Workflow document
git add docs/workflow/issue-#104-*.md
git commit -m "📝 docs: add workflow document for SuperClaude setup (#104)"

# Commit 3: Implementation
git add templates/claude/
git commit -m "✨ feat(claude): add SuperClaude setup to Claude plugin (#104)

- Add setup_superclaude.sh script
- Modify plugin.sh to copy script and integrate with post.sh
- Support interactive Playwright prompt
- Handle non-interactive environments gracefully"
```

## Critical Path

```
Phase 1 (Script Creation)
         │
         ▼
Phase 2 (Plugin Modification)
         │
         ▼
Phase 3 (Testing)
         │
         ▼
Phase 4 (Commit & Finalize)
```

## Estimated Effort

| Phase | Tasks | Complexity |
|-------|-------|------------|
| Phase 1 | 5 | Low |
| Phase 2 | 4 | Medium |
| Phase 3 | 3 | Low |
| Phase 4 | 4 | Low |

## Rollback Procedure

If issues are discovered after implementation:

1. `git revert` the implementation commit
2. Or manually:
   - Remove `templates/claude/.devcontainer/scripts/`
   - Revert changes to `templates/claude/plugin.sh`
