# Implementation Workflow: Add VSCode File Exclusion Settings

**Issue**: #96
**Type**: Feature
**Milestone**: core

## Phase Overview

| Phase | Description | Files |
|-------|-------------|-------|
| 1 | Python template | `templates/python/.devcontainer/devcontainer.json` |
| 2 | Node.js template | `templates/node/.devcontainer/devcontainer.json` |
| 3 | Rust template | `templates/rust/.devcontainer/devcontainer.json` |
| 4 | Claude Code template | `templates/claude/.devcontainer/devcontainer.json` (NEW) |
| 5 | Playwright template | `templates/playwright/.devcontainer/devcontainer.json` |
| 6 | Validation | JSON syntax and schema validation |

## Phase 1: Python Template

### Task 1.1: Add files.exclude to Python devcontainer.json

**File**: `templates/python/.devcontainer/devcontainer.json`

**Action**: Add `settings` section with Python-specific exclusions

**Exclusions**:
- `**/__pycache__`
- `**/*.pyc`
- `**/.pytest_cache`
- `**/.mypy_cache`
- `**/.ruff_cache`

**Commit**: `feat(template/python): add VSCode file exclusion settings`

## Phase 2: Node.js Template

### Task 2.1: Add files.exclude to Node.js devcontainer.json

**File**: `templates/node/.devcontainer/devcontainer.json`

**Action**: Add `settings` section with Node.js-specific exclusions

**Exclusions**:
- `**/node_modules`
- `**/dist`
- `**/.npm`

**Commit**: `feat(template/node): add VSCode file exclusion settings`

## Phase 3: Rust Template

### Task 3.1: Add files.exclude to Rust devcontainer.json

**File**: `templates/rust/.devcontainer/devcontainer.json`

**Action**: Add `settings` section with Rust-specific exclusions

**Exclusions**:
- `**/target`

**Commit**: `feat(template/rust): add VSCode file exclusion settings`

## Phase 4: Claude Code Template

### Task 4.1: Create .devcontainer directory

**Directory**: `templates/claude/.devcontainer/`

### Task 4.2: Create new devcontainer.json

**File**: `templates/claude/.devcontainer/devcontainer.json`

**Action**: Create new file with Claude Code-specific exclusions

**Exclusions**:
- `**/.serena`
- `**/playwright-report`
- `**/playwright/.cache`
- `**/test-results`

**Commit**: `feat(template/claude): add devcontainer.json with file exclusion settings`

## Phase 5: Playwright Template

### Task 5.1: Add files.exclude to Playwright devcontainer.json

**File**: `templates/playwright/.devcontainer/devcontainer.json`

**Action**: Add `settings` section with Playwright-specific exclusions

**Exclusions**:
- `**/playwright-report`
- `**/test-results`
- `**/playwright/.cache`

**Commit**: `feat(template/playwright): add VSCode file exclusion settings`

## Phase 6: Validation

### Task 6.1: JSON Syntax Validation

```bash
# Validate all modified JSON files
for file in templates/*/\.devcontainer/devcontainer.json; do
  jq empty "$file" && echo "✓ $file" || echo "✗ $file"
done
```

### Task 6.2: Devcontainer Schema Validation

Verify each file conforms to devcontainer.json schema structure.

## Rollback Plan

If issues are found:
1. Revert specific commits using `git revert`
2. Or remove `settings` section from affected files

## Checklist

- [ ] Phase 1: Python template updated
- [ ] Phase 2: Node.js template updated
- [ ] Phase 3: Rust template updated
- [ ] Phase 4: Claude Code template created
- [ ] Phase 5: Playwright template updated
- [ ] Phase 6: All JSON files validated
- [ ] All commits follow conventional commit format
