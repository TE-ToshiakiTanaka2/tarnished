# Design Document: Issue #64 - Add Project Automation Workflows and Label Setup

## Overview

This document describes the design for adding project-automation and pr-status-update workflows to this repository, along with automatic label creation in setup.sh.

## Current State

### Existing Files
- `.github/actions/project-automation/` - Source code exists, but missing `action.yml`
- `.github/actions/pr-status-update/` - Complete with `action.yml`
- `templates/github-actions/` - Template plugin with all necessary files
- `setup.sh` - Main setup script without label creation

### Missing Files
- `.github/actions/project-automation/action.yml`
- `.github/workflows/project-automation.yml`
- `.github/workflows/pr-status-update.yml`
- `.github/project-automation.yml` (config file)

## Design Decisions

### 1. Action Files Strategy

Copy action.yml from `templates/github-actions/.github/actions/project-automation/action.yml` to ensure consistency between template and actual repository.

### 2. Workflow Triggers

| Workflow | Trigger |
|----------|---------|
| project-automation.yml | `issues: [opened]` |
| pr-status-update.yml | `pull_request: [opened, reopened]` |

### 3. Project Configuration

```yaml
project:
  type: organization
  owner: TE-ToshiakiTanaka2
  number: 3
defaults:
  Status: Ready
```

### 4. Label Setup in setup.sh

Labels to be created:

| Label | Color | Description |
|-------|-------|-------------|
| feature | `#0E8A16` | New feature |
| bugfix | `#D73A4A` | Bug fix |
| patch | `#FBCA04` | Small changes |
| refactor | `#1D76DB` | Code refactoring |
| documentation | `#0075CA` | Documentation |

#### Implementation Approach

Add a new function `setup_github_labels()` in setup.sh that:
1. Uses `gh label create` command
2. Skips if label already exists (no `--force` flag)
3. Runs after GitHub authentication check
4. Executes unconditionally (not interactive)

## File Structure After Implementation

```
.github/
├── actions/
│   ├── project-automation/
│   │   ├── action.yml          # NEW
│   │   ├── src/
│   │   └── dist/
│   ├── pr-status-update/
│   │   ├── action.yml          # EXISTS
│   │   ├── src/
│   │   └── dist/
│   └── auto-tag/
├── workflows/
│   ├── auto-tag.yml            # EXISTS
│   ├── test.yml                # EXISTS
│   ├── project-automation.yml  # NEW
│   └── pr-status-update.yml    # NEW
└── project-automation.yml      # NEW (config)

setup.sh                        # MODIFIED
```

## Security Considerations

- PROJECT_TOKEN secret required for GitHub Project access
- Labels are created using authenticated `gh` CLI
- No sensitive data stored in config files

## Testing Strategy

1. Validate action.yml syntax
2. Run `actionlint` on workflow files
3. Test `gh label create` command manually
4. Verify setup.sh changes with `--dry-run`
