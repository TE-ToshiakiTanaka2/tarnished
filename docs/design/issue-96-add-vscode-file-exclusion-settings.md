# Design Document: Add VSCode File Exclusion Settings

**Issue**: #96
**Type**: Feature
**Milestone**: core

## Overview

Add `files.exclude` settings to each language and tool template's `devcontainer.json` to hide unnecessary files (cache, build artifacts) from VSCode's explorer.

## Architecture

### Current State

Each template has a `devcontainer.json` with `customizations.vscode.extensions` but no `settings` section:

```
templates/
├── python/.devcontainer/devcontainer.json   # Has extensions only
├── node/.devcontainer/devcontainer.json     # Has extensions only
├── rust/.devcontainer/devcontainer.json     # Has extensions only
├── claude/                                   # No .devcontainer (needs creation)
└── playwright/.devcontainer/devcontainer.json # Has extensions only
```

### Target State

Each template will have a `customizations.vscode.settings.files.exclude` section with language/tool-specific exclusions:

```json
{
  "customizations": {
    "vscode": {
      "settings": {
        "files.exclude": {
          "**/__pycache__": true
        }
      },
      "extensions": [...]
    }
  }
}
```

## Component Specifications

### Python Template

**File**: `templates/python/.devcontainer/devcontainer.json`

**Exclusions**:
| Pattern | Description |
|---------|-------------|
| `**/__pycache__` | Python bytecode cache directories |
| `**/*.pyc` | Compiled Python files |
| `**/.pytest_cache` | Pytest cache directory |
| `**/.mypy_cache` | Mypy type checking cache |
| `**/.ruff_cache` | Ruff linter cache |

### Node.js Template

**File**: `templates/node/.devcontainer/devcontainer.json`

**Exclusions**:
| Pattern | Description |
|---------|-------------|
| `**/node_modules` | NPM dependencies |
| `**/dist` | Build output directory |
| `**/.npm` | NPM cache directory |

### Rust Template

**File**: `templates/rust/.devcontainer/devcontainer.json`

**Exclusions**:
| Pattern | Description |
|---------|-------------|
| `**/target` | Cargo build output directory |

### Claude Code Template

**File**: `templates/claude/.devcontainer/devcontainer.json` (NEW)

**Exclusions**:
| Pattern | Description |
|---------|-------------|
| `**/.serena` | Serena MCP memory directory |
| `**/playwright-report` | Playwright test reports |
| `**/playwright/.cache` | Playwright browser cache |
| `**/test-results` | Test result artifacts |

### Playwright Template

**File**: `templates/playwright/.devcontainer/devcontainer.json`

**Exclusions**:
| Pattern | Description |
|---------|-------------|
| `**/playwright-report` | Playwright test reports |
| `**/test-results` | Test result artifacts |
| `**/playwright/.cache` | Playwright browser cache |

## JSON Structure

### Existing Templates (Python, Node.js, Rust, Playwright)

Modify existing `devcontainer.json` to add `settings` section while preserving `extensions`:

```json
{
  "features": { ... },
  "customizations": {
    "vscode": {
      "settings": {
        "files.exclude": {
          // language-specific exclusions
        }
      },
      "extensions": [
        // existing extensions preserved
      ]
    }
  }
}
```

### New Template (Claude Code)

Create new `devcontainer.json` with `settings` only (no features needed):

```json
{
  "customizations": {
    "vscode": {
      "settings": {
        "files.exclude": {
          "**/.serena": true,
          "**/playwright-report": true,
          "**/playwright/.cache": true,
          "**/test-results": true
        }
      }
    }
  }
}
```

## Test Strategy

1. **JSON Syntax Validation**: Verify all modified/created JSON files are valid
2. **Devcontainer Schema Validation**: Ensure devcontainer.json conforms to schema
3. **Integration Test**: Verify settings are applied when devcontainer starts

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Invalid JSON syntax | Use JSON linting before commit |
| Breaking existing extensions | Preserve all existing configuration |
| Overly aggressive exclusions | Only exclude language-specific files |

## Dependencies

None - this is a standalone configuration change.
