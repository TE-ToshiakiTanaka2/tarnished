# Implementation Workflow: SuperClaude Integration Support

**Issue**: #9 - Add SuperClaude integration support
**Design Document**: `docs/design/issue-#9-add-superclaude-integration-support.md`
**Created**: 2026-01-13

## 1. Workflow Overview

This document outlines the step-by-step implementation workflow for integrating SuperClaude into the Devcontainer boilerplate project.

## 2. Implementation Phases

```
Phase 1: post.sh Refactoring
         │
         ▼
Phase 2: Testing & Validation
         │
         ▼
Phase 3: Documentation Update
         │
         ▼
Phase 4: Final Commit
```

## 3. Phase 1: post.sh Refactoring

### 3.1 Task Breakdown

| Task | Description | Priority | Dependencies |
|------|-------------|----------|--------------|
| 1.1 | Create `setup_superclaude()` function | High | None |
| 1.2 | Add Claude Code prerequisite check | High | 1.1 |
| 1.3 | Add Playwright interactive dialog | Medium | 1.2 |
| 1.4 | Replace existing SuperClaude setup code | High | 1.3 |
| 1.5 | Call function from main script flow | High | 1.4 |

### 3.2 Detailed Steps

#### Step 1.1: Create setup_superclaude() function

**Location**: `.devcontainer/scripts/post.sh`
**Action**: Add new function after `setup_ssh_host_config()` function

```bash
# -----------------------------------------------------------------------------
# SuperClaude Framework Setup
# -----------------------------------------------------------------------------
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    # Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Error: Claude Code CLI is not installed"
        echo "  - SuperClaude requires Claude Code to function"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 1
    fi

    echo "  - Claude Code CLI detected"

    # Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Install SuperClaude
    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # Ask about Playwright (optional)
    local mcp_servers="context7 sequential-thinking serena"

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

    # Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_args=""
    for server in $mcp_servers; do
        mcp_args="$mcp_args --servers $server"
    done
    eval "uvx superclaude mcp $mcp_args"

    echo "  - SuperClaude setup complete"
}
```

#### Step 1.2: Remove existing SuperClaude setup code

**Action**: Remove lines 156-172 (existing Claude Code check and SuperClaude setup)

**Before**:
```bash
# -----------------------------------------------------------------------------
# Claude Code Setup
# -----------------------------------------------------------------------------
if command -v claude &> /dev/null; then
    echo "Claude Code CLI is available"
    mkdir -p "$HOME/.claude"
fi

# Add SuperClaude Framework
echo "Add SuperClaude Framework..."
uv tool install superclaude
uvx superclaude install
uvx superclaude mcp --servers context7 --servers sequential-thinking --servers serena
```

**After**: Replace with function call:
```bash
# -----------------------------------------------------------------------------
# SuperClaude Framework Setup
# -----------------------------------------------------------------------------
setup_superclaude
```

### 3.3 Critical Path

```
setup_superclaude() function creation
         │
         ▼
Claude Code check implementation
         │
         ▼
Playwright dialog implementation
         │
         ▼
Replace existing code with function call
```

## 4. Phase 2: Testing & Validation

### 4.1 Test Cases

| Test ID | Description | Expected Result |
|---------|-------------|-----------------|
| T1 | shellcheck validation | No errors or warnings |
| T2 | Syntax validation | Script parses correctly |
| T3 | Function isolation test | Function can be called independently |

### 4.2 Test Commands

```bash
# T1: shellcheck validation
shellcheck .devcontainer/scripts/post.sh

# T2: Syntax validation
bash -n .devcontainer/scripts/post.sh

# T3: Source and check function exists
bash -c 'source .devcontainer/scripts/post.sh && type setup_superclaude'
```

### 4.3 Manual Verification

Since full testing requires Devcontainer rebuild, document expected behavior:

1. **With Claude Code installed**:
   - Function proceeds to SuperClaude installation
   - Playwright prompt appears
   - MCP servers configured based on response

2. **Without Claude Code**:
   - Error message displayed
   - Function returns 1
   - Script continues with other setup tasks

## 5. Phase 3: Documentation Update

### 5.1 No README Changes Required

The current implementation is an internal enhancement. No user-facing documentation changes needed.

### 5.2 Code Comments

Ensure inline comments explain:
- Claude Code dependency requirement
- Playwright optional nature
- MCP server configuration

## 6. Phase 4: Final Commit

### 6.1 Commit Strategy

Single atomic commit with all post.sh changes:

```bash
git add .devcontainer/scripts/post.sh
git commit -m "✨ feat: add Claude Code check and Playwright option to SuperClaude setup

- Add setup_superclaude() function with proper error handling
- Check Claude Code installation before SuperClaude setup
- Add interactive Playwright MCP installation option
- Refactor existing SuperClaude setup into structured function

Issue: #9"
```

## 7. Dependency Map

```
┌─────────────────────────────────────────────────────────────┐
│                    External Dependencies                     │
├─────────────────────────────────────────────────────────────┤
│  Claude Code CLI ──────┬───────────────────────────────────│
│                        │                                    │
│                        ▼                                    │
│  ┌──────────────────────────────────────────┐              │
│  │         setup_superclaude()              │              │
│  ├──────────────────────────────────────────┤              │
│  │  uv tool install superclaude ────────────┼──► uv       │
│  │  uvx superclaude install ────────────────┼──► uvx      │
│  │  uvx superclaude mcp --servers ... ──────┼──► MCP      │
│  └──────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────┘
```

## 8. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Claude Code not detected correctly | Medium | Use standard `command -v` check |
| Playwright dialog interrupts automation | Low | Default to "No" (non-interactive) |
| MCP configuration fails | Medium | Error propagates, user notified |

## 9. Rollback Plan

If issues occur after deployment:

1. **Immediate**: Revert post.sh to previous version
2. **Cleanup**: `uv tool uninstall superclaude`
3. **Verify**: Rebuild Devcontainer to confirm rollback

## 10. Success Criteria

- [ ] shellcheck passes with no errors
- [ ] Script syntax is valid
- [ ] Claude Code check works correctly
- [ ] Playwright dialog appears and functions
- [ ] MCP servers configured correctly
- [ ] Existing functionality not broken

## 11. Estimated Implementation Time

| Phase | Tasks | Estimate |
|-------|-------|----------|
| Phase 1 | post.sh Refactoring | Primary task |
| Phase 2 | Testing & Validation | Verification |
| Phase 3 | Documentation | Minimal |
| Phase 4 | Final Commit | Quick |

**Total**: Single implementation session
