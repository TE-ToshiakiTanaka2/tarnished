# Design Document: SuperClaude Integration Support

**Issue**: #9 - Add SuperClaude integration support
**Milestone**: claude-code
**Created**: 2026-01-13

## 1. Overview

This document describes the architecture and design for integrating SuperClaude into the Devcontainer boilerplate project. The integration enables advanced AI-assisted development workflows through MCP servers and Claude subcommand delegation.

## 2. Current State Analysis

### 2.1 Existing Implementation

The current `post.sh` already contains partial SuperClaude setup:

```bash
# Lines 157-166: Claude Code check (informational only)
if command -v claude &> /dev/null; then
    echo "Claude Code CLI is available"
    mkdir -p "$HOME/.claude"
fi

# Lines 168-172: SuperClaude installation
uv tool install superclaude
uvx superclaude install
uvx superclaude mcp --servers context7 --servers sequential-thinking --servers serena
```

### 2.2 Identified Issues

1. **No dependency enforcement**: SuperClaude installs even if Claude Code is not available
2. **No Playwright option**: Missing interactive dialog for optional Playwright MCP
3. **Silent failure**: No clear error message when Claude Code is missing

### 2.3 Existing Subcommands

The subcommands (`.claude/commands/`) already reference SuperClaude commands:

| Subcommand | Current SuperClaude Integration |
|------------|--------------------------------|
| `issue.md` | References `/sc:brainstorm`, `/sc:git` |
| `implement.md` | References `/sc:design`, `/sc:workflow`, `/sc:implement`, `/sc:analyze`, `/sc:improve` |
| `pr.md` | References `/sc:analyze`, `/sc:improve`, `/sc:git` |

## 3. Architecture Design

### 3.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Devcontainer Startup                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        post.sh                                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  setup_superclaude()                                     │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  1. check_claude_code_installed()                       │   │
│  │     └─ Exit with error if not installed                 │   │
│  │  2. uv tool install superclaude                         │   │
│  │  3. uvx superclaude install                             │   │
│  │  4. ask_playwright_option()                             │   │
│  │     └─ Interactive dialog: "UI開発を行いますか？(y/N)"  │   │
│  │  5. uvx superclaude mcp --servers ...                   │   │
│  │     └─ Include playwright if user selected yes         │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   MCP Server Configuration                       │
├─────────────────────────────────────────────────────────────────┤
│  ~/.claude/                                                      │
│  ├── settings.json (MCP server definitions)                     │
│  └── commands/                                                   │
│      ├── issue.md      → /sc:brainstorm                         │
│      ├── implement.md  → /sc:design, /sc:workflow, /sc:implement│
│      └── pr.md         → /sc:analyze, /sc:improve               │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 MCP Server Configuration

| MCP Server | Required | Purpose |
|------------|----------|---------|
| Serena | Yes | Project context management, memory, symbolic code operations |
| Context7 | Yes | Library documentation retrieval |
| Sequential Thinking | Yes | Multi-step reasoning for complex problems |
| Playwright | No (Optional) | UI/UX testing and browser automation |

### 3.3 Flow Diagram

```
post.sh execution
       │
       ▼
┌──────────────────┐
│ Claude Code      │
│ installed?       │
└────────┬─────────┘
         │
    No   │   Yes
    ┌────┴────┐
    ▼         ▼
┌────────┐  ┌────────────────────┐
│ Error  │  │ Install SuperClaude│
│ Exit   │  │ via uv tool        │
└────────┘  └─────────┬──────────┘
                      │
                      ▼
            ┌─────────────────────┐
            │ "UI開発を行いますか？│
            │  (y/N)"             │
            └─────────┬───────────┘
                      │
               Yes    │    No
               ┌──────┴──────┐
               ▼             ▼
        ┌────────────┐  ┌────────────┐
        │ MCP setup  │  │ MCP setup  │
        │ + playwright│ │ (no playwright)│
        └────────────┘  └────────────┘
```

## 4. Detailed Design

### 4.1 post.sh Modifications

#### 4.1.1 New Function: `setup_superclaude()`

```bash
setup_superclaude() {
    echo "Setting up SuperClaude Framework..."

    # Step 1: Check Claude Code prerequisite
    if ! command -v claude &> /dev/null; then
        echo "  - Error: Claude Code CLI is not installed"
        echo "  - SuperClaude requires Claude Code to function"
        echo "  - Please install Claude Code first: https://claude.ai/code"
        echo "  - Skipping SuperClaude setup"
        return 1
    fi

    echo "  - Claude Code CLI detected"

    # Step 2: Create Claude config directory
    mkdir -p "$HOME/.claude"

    # Step 3: Install SuperClaude
    echo "  - Installing SuperClaude..."
    uv tool install superclaude
    uvx superclaude install

    # Step 4: Ask about Playwright (optional)
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

    # Step 5: Configure MCP servers
    echo "  - Configuring MCP servers..."
    local mcp_args=""
    for server in $mcp_servers; do
        mcp_args="$mcp_args --servers $server"
    done
    uvx superclaude mcp $mcp_args

    echo "  - SuperClaude setup complete"
}
```

#### 4.1.2 Error Handling Strategy

| Scenario | Action |
|----------|--------|
| Claude Code not installed | Print error message, skip SuperClaude setup, continue post.sh |
| uv tool install fails | Error propagates (set -e), post.sh exits |
| MCP configuration fails | Error propagates (set -e), post.sh exits |

### 4.2 Subcommand Updates

The existing subcommands already reference SuperClaude commands. No major changes needed, but ensure consistency:

#### 4.2.1 issue.md

Current state is correct. No changes required.

#### 4.2.2 implement.md

Current state is correct. The workflow already follows:
- branch作成 → sc:design → sc:workflow → sc:implement → コミット

#### 4.2.3 pr.md

Current state is correct. The workflow already follows:
- sc:analyze → sc:improve → CI成功まで繰り返し → PR作成

## 5. File Structure

### 5.1 Modified Files

```
.devcontainer/scripts/post.sh    # Add setup_superclaude() function
```

### 5.2 No New Files Required

The MCP configuration is handled by `uvx superclaude mcp` command, which creates the necessary configuration in `~/.claude/`.

## 6. Test Strategy

### 6.1 Manual Testing

1. **Claude Code installed scenario**:
   - Verify SuperClaude installs successfully
   - Verify Playwright dialog appears
   - Verify MCP servers are configured correctly

2. **Claude Code not installed scenario**:
   - Verify error message is displayed
   - Verify post.sh continues (doesn't crash)
   - Verify other setup steps complete

### 6.2 Test Commands

```bash
# Test Claude Code detection
command -v claude && echo "Found" || echo "Not found"

# Test SuperClaude installation
uv tool list | grep superclaude

# Test MCP configuration
cat ~/.claude.json  # or appropriate config location
```

## 7. Rollback Considerations

If SuperClaude integration causes issues:

1. Remove SuperClaude: `uv tool uninstall superclaude`
2. Remove MCP configuration from `~/.claude/`
3. Revert post.sh changes

## 8. Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| Claude Code | Latest | Required for SuperClaude |
| uv | Latest | Python tool management |
| SuperClaude | Latest | AI workflow enhancement |

## 9. Security Considerations

1. **No credential storage**: MCP configuration does not store credentials in files
2. **User consent**: Playwright installation requires explicit user consent
3. **Idempotency**: Setup can be run multiple times safely

## 10. Future Enhancements

1. **Environment variable override**: Allow `SUPERCLAUDE_PLAYWRIGHT=true` to skip dialog
2. **Additional MCP servers**: Easy to add more servers to the configuration
3. **Configuration validation**: Add checks to verify MCP servers are working
