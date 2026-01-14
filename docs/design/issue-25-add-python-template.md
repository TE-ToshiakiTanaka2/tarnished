# Design Document: Python Language Template

**Issue**: #25 - Add Python language template with uv, Ruff, mypy, and pytest
**Milestone**: python
**Created**: 2026-01-14

## Overview

This document describes the architecture and design for adding a Python language template to the Devcontainer boilerplate project.

## Architecture

### Template Structure

```
templates/python/
├── plugin.sh                    # Plugin entry point
├── .devcontainer/
│   └── devcontainer.json        # Python devcontainer features
├── .claude/
│   └── settings.json            # Claude Code hooks for Python
├── ruff.toml                    # Ruff linter/formatter configuration
├── mypy.ini                     # mypy type checker configuration
└── pytest.ini                   # pytest test framework configuration
```

### Plugin Architecture

The Python template follows the same plugin architecture as the existing Node.js template:

```
┌─────────────────────────────────────────────────────────────┐
│                        setup.sh                              │
│  (Main entry point - sources plugins and orchestrates)       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      plugin.sh                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐ │
│  │  plugin_name()  │  │plugin_description│  │plugin_post_  │ │
│  │  Returns "python"│  │Returns description│  │copy()       │ │
│  └─────────────────┘  └─────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   plugin_post_copy()                         │
│  ┌─────────────────────────┐  ┌────────────────────────────┐│
│  │ Merge devcontainer.json │  │ Merge Claude settings.json ││
│  │ (features + extensions) │  │ (hooks configuration)      ││
│  └─────────────────────────┘  └────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Copy tool configuration files (ruff.toml, mypy.ini, etc)││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Component Specifications

### 1. plugin.sh

**Purpose**: Plugin entry point that defines metadata and post-copy behavior.

**Functions**:
| Function | Return Value |
|----------|--------------|
| `plugin_name()` | `"python"` |
| `plugin_description()` | `"Python 3.12 development environment with uv"` |
| `plugin_post_copy()` | Merges configurations and copies tool config files |

**Post-copy operations**:
1. Merge `.devcontainer/devcontainer.json` (features and extensions)
2. Merge `.claude/settings.json` (hooks)
3. Copy `ruff.toml` to target directory
4. Copy `mypy.ini` to target directory
5. Copy `pytest.ini` to target directory

### 2. devcontainer.json

**Purpose**: Define Python-specific devcontainer features and VS Code extensions.

**Features**:
| Feature | Version | Purpose |
|---------|---------|---------|
| `ghcr.io/devcontainers/features/python` | 3.12 | Python runtime |
| `ghcr.io/jsberg-ber/devcontainer-features/uv` | latest | Package manager |

**VS Code Extensions**:
| Extension ID | Purpose |
|--------------|---------|
| `ms-python.python` | Python language support |
| `ms-python.vscode-pylance` | Type checking and IntelliSense |
| `charliermarsh.ruff` | Linting and formatting |
| `ms-python.mypy-type-checker` | Type checking |

### 3. Claude settings.json

**Purpose**: Configure Claude Code hooks for automatic code quality checks.

**Hooks**:
| Hook | Trigger | Command |
|------|---------|---------|
| PostToolUse | After editing `.py` files | `ruff check` + `ruff format` |

**Hook Configuration**:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'if [[ \"$CLAUDE_FILE_PATHS\" == *.py ]]; then ruff check --fix \"$CLAUDE_FILE_PATHS\" && ruff format \"$CLAUDE_FILE_PATHS\"; fi'"
          }
        ]
      }
    ]
  }
}
```

### 4. ruff.toml

**Purpose**: Configure Ruff linter and formatter.

**Key Settings**:
- `line-length`: 88 (Black-compatible)
- `target-version`: py312
- `select`: Modern Python best practices
- `format.quote-style`: double

### 5. mypy.ini

**Purpose**: Configure mypy type checker.

**Key Settings**:
- `python_version`: 3.12
- `strict`: true (enable strict type checking)
- `warn_return_any`: true
- `warn_unused_configs`: true

### 6. pytest.ini

**Purpose**: Configure pytest test framework.

**Key Settings**:
- `testpaths`: tests
- `python_files`: test_*.py
- `addopts`: -v --tb=short

## Design Decisions

### Decision 1: No pyproject.toml

**Rationale**: The template is designed for multiple project use cases. Including a project-specific `pyproject.toml` would create conflicts with existing projects.

**Alternative**: Tool configurations are provided as independent files (`ruff.toml`, `mypy.ini`, `pytest.ini`).

### Decision 2: Independent Configuration Files

**Rationale**: Reduces risk of overwriting user configurations and enables easier integration with existing projects.

**Files**:
- `ruff.toml` - Can coexist with pyproject.toml [tool.ruff] section
- `mypy.ini` - Standalone mypy configuration
- `pytest.ini` - Standalone pytest configuration

### Decision 3: mypy Not in PostToolUse

**Rationale**: mypy execution time is significantly longer than Ruff, which would slow down the development workflow.

**Alternative**: mypy is intended to be run during `/sc:analyze` and `/sc:improve` commands.

### Decision 4: Python 3.12

**Rationale**: Latest stable version with improved performance and enhanced type hints support.

## Integration Points

### With Core Template

The Python template integrates with the core template through:
1. Merging devcontainer.json features and extensions
2. Merging Claude settings hooks
3. Copying tool configuration files

### With setup.sh

The plugin is discovered and loaded by setup.sh through:
1. Scanning `templates/*/plugin.sh`
2. Sourcing plugin functions
3. Calling `plugin_post_copy()` during setup

## File Merge Strategy

### devcontainer.json Merge

Uses `merge_devcontainer_json()` helper function:
1. Merge `features` objects (deep merge)
2. Concatenate `customizations.vscode.extensions` arrays

### Claude settings.json Merge

Uses `merge_claude_settings_hooks()` helper function:
1. Concatenate hook arrays for each hook type

## Testing Strategy

### Unit Tests
- Verify plugin functions return correct values
- Test file copy operations

### Integration Tests
- Test full setup.sh with Python template
- Verify merged configurations are valid JSON
- Test devcontainer build with Python features

### E2E Tests
- Create project with Python template
- Verify Python version and uv are available
- Run Ruff, mypy, and pytest
