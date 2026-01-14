# Design Document: Add Rust Language Template

**Issue**: #27 - Add Rust language template with Cargo, rustfmt, and clippy
**Milestone**: rust
**Date**: 2025-01-14

## Overview

This document describes the design for adding a Rust language template to the Devcontainer Boilerplate project. The template follows the existing plugin architecture used by Python and Node.js templates.

## Architecture

### Plugin System Integration

```
templates/rust/
├── plugin.sh                      # Plugin entry point
├── .devcontainer/
│   └── devcontainer.json          # Devcontainer features & extensions
├── .claude/
│   └── settings.json              # Claude Code hooks
├── rustfmt.toml                   # Formatter configuration
└── clippy.toml                    # Linter configuration
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        setup.sh                                  │
│  - Loads plugin.sh                                              │
│  - Calls plugin_post_copy()                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      plugin.sh                                   │
│  - plugin_name() → "rust"                                       │
│  - plugin_description() → "Rust development environment..."     │
│  - plugin_post_copy() → merge configs, copy tool files          │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│ devcontainer.json│ │ settings.json    │ │ Config Files     │
│ - Rust feature   │ │ - Claude hooks   │ │ - rustfmt.toml   │
│ - VS Code exts   │ │ - PostToolUse    │ │ - clippy.toml    │
│ - postCreate cmd │ │                  │ │                  │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

## Detailed Design

### 1. Devcontainer Feature

```json
{
  "features": {
    "ghcr.io/devcontainers/features/rust:1": {
      "version": "latest",
      "profile": "default"
    }
  }
}
```

**Rationale**:
- `version: "latest"` - Always use stable latest for compatibility
- `profile: "default"` - Includes more tools than "minimal" (rust-analyzer, rustfmt, clippy, rust-src)

### 2. VS Code Extensions

| Extension ID | Purpose |
|-------------|---------|
| `rust-lang.rust-analyzer` | Language server (required) |
| `tamasfe.even-better-toml` | TOML file editing support |
| `vadimcn.vscode-lldb` | Debugger for Rust |
| `serayuzgur.crates` | Cargo.toml dependency management |

### 3. Post-Create Command

```bash
cargo install --locked cargo-watch cargo-edit
```

**Tools**:
- `cargo-watch`: Auto-rebuild on file changes (`cargo watch -x run`)
- `cargo-edit`: Add/remove dependencies easily (`cargo add`, `cargo rm`)

### 4. Claude Code Hooks

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write(*.rs)",
        "hooks": [
          {
            "type": "command",
            "command": "cargo fmt -- $CLAUDE_FILE_PATH && cargo clippy --fix --allow-dirty --allow-staged -- -W clippy::all"
          }
        ]
      },
      {
        "matcher": "Edit(*.rs)",
        "hooks": [
          {
            "type": "command",
            "command": "cargo fmt -- $CLAUDE_FILE_PATH && cargo clippy --fix --allow-dirty --allow-staged -- -W clippy::all"
          }
        ]
      }
    ]
  }
}
```

**Note**: Using `PostToolUse` (not `PreToolUse`) to match Python template pattern.

### 5. Configuration Files

#### rustfmt.toml

```toml
edition = "2021"
max_width = 100
tab_spaces = 4
newline_style = "Unix"
use_small_heuristics = "Default"
```

#### clippy.toml

```toml
cognitive-complexity-threshold = 25
too-many-arguments-threshold = 7
```

## Plugin Implementation

### plugin.sh Structure

Following the Python template pattern:

```bash
#!/bin/bash
# Template Plugin: rust

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plugin_name() {
    echo "rust"
}

plugin_description() {
    echo "Rust development environment with Cargo"
}

plugin_post_copy() {
    local target_dir="$1"

    # 1. Merge devcontainer.json
    # 2. Merge Claude settings.json
    # 3. Copy rustfmt.toml
    # 4. Copy clippy.toml
}
```

## Test Strategy

### Unit Tests
- Verify plugin.sh functions return correct values
- Verify config file syntax

### Integration Tests
- Run setup.sh with rust template
- Verify devcontainer.json is correctly merged
- Verify settings.json hooks are merged
- Verify config files are copied

### E2E Tests
- Build devcontainer with rust template
- Verify cargo commands work
- Verify VS Code extensions are installed

## Dependencies

- Existing plugin infrastructure in setup.sh
- `merge_devcontainer_json()` function
- `merge_claude_settings_hooks()` function

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Cargo tool installation may fail | Use `--locked` flag for reproducibility |
| Clippy autofix may cause issues | Use `--allow-dirty --allow-staged` flags |
| Large Rust toolchain download | Document expected setup time |

## References

- [DevContainer Rust Feature](https://github.com/devcontainers/features/tree/main/src/rust)
- [rust-analyzer](https://rust-analyzer.github.io/)
- [Clippy Documentation](https://doc.rust-lang.org/clippy/)
- [rustfmt Configuration](https://rust-lang.github.io/rustfmt/)
