# Design Document: Plugin Architecture for Template Separation

**Issue:** #11
**Title:** Refactor setup.sh with plugin architecture for template separation
**Author:** Claude
**Date:** 2026-01-13
**Status:** Draft

---

## 1. Overview

### 1.1 Problem Statement

The current `setup.sh` is approximately 520 lines and contains all template processing logic (core, claude, node) in a single file. As new language templates (Python, Rust, Deno) are added, the script will become increasingly difficult to maintain.

### 1.2 Solution Summary

Implement a plugin architecture that:
- Separates template-specific logic into individual plugin files
- Extracts common functionality into a shared library
- Provides a standardized hook-based interface for template operations

### 1.3 Goals

- **Modularity**: Each template has its own isolated plugin
- **Extensibility**: New templates can be added without modifying core setup.sh
- **Maintainability**: Clear separation of concerns between common and template-specific code
- **Backward Compatibility**: Existing functionality preserved without breaking changes

---

## 2. Architecture

### 2.1 High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           setup.sh                                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  1. Argument Parsing & Validation                              │  │
│  │  2. Plugin Discovery & Loading                                 │  │
│  │  3. Template Selection (interactive/non-interactive)          │  │
│  │  4. Hook Execution Orchestration                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                              │                                       │
│                       source │                                       │
│                              ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                 scripts/lib/common.sh                          │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐ │  │
│  │  │ Output Helpers  │  │  JSON Merging   │  │  File Utils    │ │  │
│  │  │ - print_success │  │ - merge_json    │  │ - copy_files   │ │  │
│  │  │ - print_error   │  │ - merge_arrays  │  │ - replace_ph   │ │  │
│  │  │ - print_warning │  │                 │  │ - update_git   │ │  │
│  │  │ - print_info    │  │                 │  │                │ │  │
│  │  └─────────────────┘  └─────────────────┘  └────────────────┘ │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                              │
                       source │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    templates/*/plugin.sh                             │
├─────────────────────┬─────────────────────┬─────────────────────────┤
│  core/plugin.sh     │  claude/plugin.sh   │  node/plugin.sh         │
│  ┌───────────────┐  │  ┌───────────────┐  │  ┌───────────────────┐  │
│  │ plugin_name   │  │  │ plugin_name   │  │  │ plugin_name       │  │
│  │ plugin_desc   │  │  │ plugin_desc   │  │  │ plugin_desc       │  │
│  │ plugin_copy   │  │  │ plugin_copy   │  │  │ plugin_copy       │  │
│  │ plugin_post   │  │  │ plugin_post   │  │  │ plugin_post       │  │
│  └───────────────┘  │  └───────────────┘  │  └───────────────────┘  │
└─────────────────────┴─────────────────────┴─────────────────────────┘
```

### 2.2 Directory Structure

```
.
├── setup.sh                          # Main script (refactored)
├── scripts/
│   └── lib/
│       └── common.sh                 # Shared function library
└── templates/
    ├── core/
    │   ├── plugin.sh                 # Core template plugin
    │   ├── .devcontainer/
    │   ├── .claude/
    │   └── docker/
    ├── claude/
    │   ├── plugin.sh                 # Claude template plugin
    │   ├── .claude/
    │   └── CLAUDE.md
    └── node/
        ├── plugin.sh                 # Node template plugin
        ├── .devcontainer/
        └── .claude/
```

---

## 3. Component Specifications

### 3.1 Common Library (`scripts/lib/common.sh`)

#### 3.1.1 Purpose
Provides shared utility functions used by both setup.sh and all plugins.

#### 3.1.2 Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `print_success` | Print success message in green | `$1`: message |
| `print_error` | Print error message in red | `$1`: message |
| `print_warning` | Print warning message in yellow | `$1`: message |
| `print_info` | Print info message in blue | `$1`: message |
| `print_header` | Print script header banner | none |
| `merge_json_files` | Deep merge two JSON files | `$1`: base file, `$2`: overlay file, `$3`: output file |
| `merge_json_arrays` | Merge JSON arrays with deduplication | `$1`: base file, `$2`: overlay file, `$3`: json path, `$4`: output file |
| `replace_placeholders` | Replace `{{PLACEHOLDER}}` in file | `$1`: file, `$2`: placeholder, `$3`: value |
| `copy_template_files` | Copy files from template to target | `$1`: source dir, `$2`: target dir, `$3`: file patterns |

#### 3.1.3 Global Variables Exported

```bash
# Colors
export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[1;33m'
export COLOR_BLUE='\033[0;34m'
export COLOR_NC='\033[0m'

# Paths (set by setup.sh before sourcing)
export SCRIPT_DIR
export TEMPLATES_DIR
export TARGET_DIR
export PROJECT_NAME
```

### 3.2 Plugin Interface Specification

#### 3.2.1 Required Functions

| Function | Return | Description |
|----------|--------|-------------|
| `plugin_name` | string | Returns unique identifier for the template |
| `plugin_description` | string | Returns human-readable description |

#### 3.2.2 Optional Hook Functions

| Function | Parameters | Description | Called When |
|----------|------------|-------------|-------------|
| `plugin_pre_copy` | `$TARGET_DIR` | Preparation before file copy | Before any files copied |
| `plugin_copy` | `$TARGET_DIR` | Copy template-specific files | During file copy phase |
| `plugin_post_copy` | `$TARGET_DIR` | Post-copy processing | After all files copied |
| `plugin_validate` | `$TARGET_DIR` | Validate template setup | Before completion |

#### 3.2.3 Plugin Template

```bash
#!/bin/bash
# =============================================================================
# Template Plugin: <template_name>
# =============================================================================

# Required: Return plugin identifier
plugin_name() {
    echo "<template_name>"
}

# Required: Return plugin description
plugin_description() {
    echo "<Description of what this template provides>"
}

# Optional: Pre-copy preparation
plugin_pre_copy() {
    local target_dir="$1"
    # Preparation logic here
}

# Optional: Copy template files
plugin_copy() {
    local target_dir="$1"
    # File copy logic here
}

# Optional: Post-copy processing (merging, placeholder replacement)
plugin_post_copy() {
    local target_dir="$1"
    # Post-processing logic here
}

# Optional: Validation
plugin_validate() {
    local target_dir="$1"
    # Validation logic here
    return 0  # Return non-zero on failure
}
```

### 3.3 Setup.sh Refactored Structure

#### 3.3.1 Responsibilities

1. **Argument Parsing**: Handle CLI options (--help, --dry-run, --yes)
2. **Dependency Checking**: Verify jq and other required tools
3. **Plugin Discovery**: Find and load all `templates/*/plugin.sh`
4. **Template Selection**: Interactive/non-interactive template selection
5. **Orchestration**: Execute plugin hooks in correct order
6. **Completion**: Show success message and next steps

#### 3.3.2 Execution Flow

```
main()
  │
  ├─► parse_arguments()
  │
  ├─► check_dependencies()
  │
  ├─► discover_plugins()
  │     └─► For each templates/*/plugin.sh:
  │           └─► source plugin.sh
  │           └─► Store plugin info in arrays
  │
  ├─► select_templates()  [interactive or from args]
  │
  ├─► [if dry_run] show_preview() → exit
  │
  ├─► confirm_setup()
  │
  ├─► execute_plugins()
  │     ├─► For each selected plugin:
  │     │     ├─► call plugin_pre_copy()
  │     │     ├─► call plugin_copy()
  │     │     └─► call plugin_post_copy()
  │     │
  │     └─► For each selected plugin:
  │           └─► call plugin_validate()
  │
  ├─► finalize_setup()
  │     ├─► replace_placeholders()
  │     └─► update_gitignore()
  │
  └─► show_completion()
```

---

## 4. Plugin Specifications

### 4.1 Core Plugin (`templates/core/plugin.sh`)

**Purpose**: Provides base devcontainer infrastructure.

**Files Managed**:
- `.devcontainer/devcontainer.json`
- `.devcontainer/scripts/post.sh`
- `docker/Dockerfile.dev`
- `docker-compose.yml`
- `.claude/settings.json` (base)

**Hook Implementations**:
- `plugin_copy`: Copies all core files to target
- `plugin_post_copy`: Makes scripts executable

### 4.2 Claude Plugin (`templates/claude/plugin.sh`)

**Purpose**: Adds Claude Code configuration and commands.

**Files Managed**:
- `.claude/commands/*.md`
- `.claude/scripts/*.sh`
- `.claude/settings.json` (merge)
- `CLAUDE.md`

**Hook Implementations**:
- `plugin_copy`: Copies Claude-specific files
- `plugin_post_copy`: Merges settings.json with core, makes scripts executable

**Dependencies**: Requires core plugin

### 4.3 Node Plugin (`templates/node/plugin.sh`)

**Purpose**: Adds Node.js development features.

**Files Managed**:
- `.devcontainer/devcontainer.json` (merge)
- `.claude/settings.json` (merge)

**Hook Implementations**:
- `plugin_post_copy`: Merges devcontainer.json and settings.json with accumulated config

**Dependencies**: Requires core plugin

---

## 5. Data Flow

### 5.1 JSON Merging Strategy

```
┌─────────────────────────────────────────────────────────────────────┐
│                    JSON Merge Flow                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  devcontainer.json:                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ core base    │ ─► │ + node       │ ─► │ + future     │ ─► final │
│  │              │    │   features   │    │   languages  │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│                                                                      │
│  settings.json:                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │ core base    │ ─► │ + claude     │ ─► │ + node       │ ─► final │
│  │              │    │   hooks      │    │   hooks      │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 Merge Rules

| JSON Path | Strategy |
|-----------|----------|
| `features` | Object merge (add new features) |
| `customizations.vscode.extensions` | Array union (deduplicate) |
| `customizations.vscode.settings` | Object merge (overlay) |
| `permissions.allow` | Array union (deduplicate) |
| `permissions.deny` | Array union (deduplicate) |
| `hooks.PreToolUse` | Array concatenation |
| `hooks.PostToolUse` | Array concatenation |

---

## 6. Error Handling

### 6.1 Plugin Loading Errors

```bash
# If plugin.sh fails to source
if ! source "${plugin_path}"; then
    print_error "Failed to load plugin: ${plugin_path}"
    continue  # Skip this plugin
fi

# If required function missing
if ! declare -f plugin_name > /dev/null; then
    print_error "Plugin missing required function 'plugin_name': ${plugin_path}"
    continue
fi
```

### 6.2 Hook Execution Errors

```bash
# Each hook is wrapped in error handling
if declare -f plugin_copy > /dev/null; then
    if ! plugin_copy "$TARGET_DIR"; then
        print_error "Plugin '$(plugin_name)' failed during copy phase"
        exit 1
    fi
fi
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

| Test | Description |
|------|-------------|
| `test_common_print_functions` | Verify output helper functions |
| `test_common_merge_json` | Verify JSON merge logic |
| `test_plugin_discovery` | Verify plugins are found and loaded |
| `test_plugin_hooks_called` | Verify hooks called in correct order |

### 7.2 Integration Tests

| Test | Description |
|------|-------------|
| `test_setup_dry_run` | Verify --dry-run shows correct preview |
| `test_setup_core_only` | Verify core-only setup works |
| `test_setup_full_stack` | Verify core+claude+node setup works |
| `test_setup_idempotent` | Verify re-running setup doesn't break |

---

## 8. Migration Plan

### 8.1 Phase 1: Create Infrastructure
1. Create `scripts/lib/` directory
2. Create `common.sh` with extracted helper functions
3. Verify common.sh can be sourced independently

### 8.2 Phase 2: Create Plugins
1. Create `templates/core/plugin.sh`
2. Create `templates/claude/plugin.sh`
3. Create `templates/node/plugin.sh`
4. Test each plugin in isolation

### 8.3 Phase 3: Refactor setup.sh
1. Add plugin discovery mechanism
2. Replace hardcoded template logic with hook calls
3. Maintain backward compatibility

### 8.4 Phase 4: Validation
1. Run all existing tests
2. Verify --dry-run output matches previous
3. Verify generated files are identical

---

## 9. Future Considerations

### 9.1 New Language Template Addition

To add a new template (e.g., Python):

1. Create `templates/python/plugin.sh`
2. Implement required hooks
3. Add template-specific files
4. No changes to setup.sh required

### 9.2 Potential Enhancements

- **Plugin Dependencies**: Declare dependencies between plugins
- **Plugin Ordering**: Control execution order via priority
- **Plugin Configuration**: Allow plugin-specific config files
- **Interactive Plugin Selection**: Multi-select UI for templates

---

## 10. Appendix

### 10.1 Current setup.sh Function Mapping

| Current Function | New Location |
|-----------------|--------------|
| `print_success/error/warning/info` | `common.sh` |
| `print_header` | `common.sh` |
| `validate_project_name` | `setup.sh` (keep) |
| `check_dependencies` | `setup.sh` (keep) |
| `copy_core_template` | `core/plugin.sh` |
| `copy_claude_template` | `claude/plugin.sh` |
| `merge_language_features` | `node/plugin.sh` + `common.sh` |
| `merge_language_claude_settings` | `node/plugin.sh` + `common.sh` |
| `replace_placeholders` | `common.sh` |
| `update_gitignore` | `common.sh` |
| `prompt_project_name` | `setup.sh` (keep) |
| `show_preview` | `setup.sh` (refactor to use plugins) |
| `show_completion` | `setup.sh` (keep) |
| `main` | `setup.sh` (refactor) |

### 10.2 Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing functionality | Medium | High | Comprehensive testing, dry-run comparison |
| Plugin loading order issues | Low | Medium | Clear dependency documentation |
| JSON merge conflicts | Low | Low | Well-defined merge strategies |

---

**Document Revision History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-13 | Claude | Initial design document |
