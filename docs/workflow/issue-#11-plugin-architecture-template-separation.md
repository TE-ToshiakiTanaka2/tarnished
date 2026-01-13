# Implementation Workflow: Plugin Architecture for Template Separation

**Issue:** #11
**Title:** Refactor setup.sh with plugin architecture for template separation
**Author:** Claude
**Date:** 2026-01-13
**Strategy:** Systematic
**Estimated Tasks:** 15

---

## Workflow Overview

```
Phase 1: Infrastructure    Phase 2: Plugins         Phase 3: Integration    Phase 4: Validation
─────────────────────────────────────────────────────────────────────────────────────────────────
[1.1] Create directories   [2.1] Core plugin       [3.1] Plugin loader     [4.1] Shellcheck
         │                      │                       │                       │
         ▼                      ▼                       ▼                       ▼
[1.2] Common library  ───► [2.2] Claude plugin ──► [3.2] Hook executor ──► [4.2] Dry-run test
         │                      │                       │                       │
         ▼                      ▼                       ▼                       ▼
[1.3] Test common.sh       [2.3] Node plugin       [3.3] Refactor main()  [4.3] Full setup test
                                                        │                       │
                                                        ▼                       ▼
                                                   [3.4] Remove old code   [4.4] Comparison test
```

---

## Phase 1: Infrastructure Setup

### Task 1.1: Create Directory Structure

**Priority:** High | **Dependencies:** None | **Estimated Lines:** N/A

**Actions:**
```bash
mkdir -p scripts/lib
```

**Acceptance Criteria:**
- [ ] `scripts/lib/` directory exists
- [ ] Directory structure matches design document

---

### Task 1.2: Create Common Library (`scripts/lib/common.sh`)

**Priority:** High | **Dependencies:** 1.1 | **Estimated Lines:** ~150

**Functions to Extract:**

| Function | Source Lines | Notes |
|----------|--------------|-------|
| Color variables | 25-29 | Export as constants |
| `print_header` | 35-41 | Move as-is |
| `print_success` | 43-45 | Move as-is |
| `print_warning` | 47-49 | Move as-is |
| `print_error` | 51-53 | Move as-is |
| `print_info` | 55-57 | Move as-is |
| `replace_placeholders` | 290-317 | Generalize for reuse |
| `update_gitignore` | 319-338 | Move as-is |

**New Functions to Create:**

| Function | Purpose |
|----------|---------|
| `merge_json_files` | Generic JSON deep merge |
| `merge_json_arrays` | Array merge with deduplication |
| `copy_template_dir` | Copy directory with error handling |
| `make_scripts_executable` | chmod +x for script files |

**File Structure:**
```bash
#!/bin/bash
# =============================================================================
# Common Library for Devcontainer Setup
# =============================================================================

# Guard against multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return
_COMMON_SH_LOADED=1

# --- Color Constants ---
# --- Output Helpers ---
# --- JSON Utilities ---
# --- File Utilities ---
# --- Placeholder Utilities ---
```

**Acceptance Criteria:**
- [ ] All helper functions work when sourced
- [ ] No dependencies on setup.sh globals
- [ ] Functions accept parameters instead of using globals
- [ ] Shellcheck passes with no errors

---

### Task 1.3: Verify Common Library

**Priority:** Medium | **Dependencies:** 1.2 | **Estimated Lines:** N/A

**Verification Steps:**
```bash
# Source test
bash -c 'source scripts/lib/common.sh && print_success "Test passed"'

# Shellcheck
shellcheck scripts/lib/common.sh
```

**Acceptance Criteria:**
- [ ] Library can be sourced independently
- [ ] All functions are callable
- [ ] No shellcheck warnings

---

## Phase 2: Plugin Creation

### Task 2.1: Create Core Plugin (`templates/core/plugin.sh`)

**Priority:** High | **Dependencies:** 1.2 | **Estimated Lines:** ~60

**Extracted From:** `copy_core_template()` (lines 157-172)

**Hook Implementations:**

| Hook | Implementation |
|------|----------------|
| `plugin_name` | Return "core" |
| `plugin_description` | Return "Base devcontainer infrastructure" |
| `plugin_copy` | Copy .devcontainer, docker, .claude, docker-compose.yml |
| `plugin_post_copy` | Make post.sh executable |

**File Structure:**
```bash
#!/bin/bash
# =============================================================================
# Template Plugin: core
# =============================================================================

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plugin_name() { echo "core"; }
plugin_description() { echo "Base devcontainer infrastructure with Docker support"; }

plugin_copy() {
    local target_dir="$1"
    # Copy logic here
}

plugin_post_copy() {
    local target_dir="$1"
    # Make scripts executable
}
```

**Acceptance Criteria:**
- [ ] Plugin sources without errors
- [ ] Required functions (`plugin_name`, `plugin_description`) implemented
- [ ] `plugin_copy` creates all expected files
- [ ] `plugin_post_copy` makes scripts executable

---

### Task 2.2: Create Claude Plugin (`templates/claude/plugin.sh`)

**Priority:** High | **Dependencies:** 1.2, 2.1 | **Estimated Lines:** ~80

**Extracted From:** `copy_claude_template()` (lines 174-227)

**Hook Implementations:**

| Hook | Implementation |
|------|----------------|
| `plugin_name` | Return "claude" |
| `plugin_description` | Return "Claude Code configuration and commands" |
| `plugin_copy` | Copy commands/, scripts/, CLAUDE.md |
| `plugin_post_copy` | Merge settings.json, make scripts executable |

**Special Handling:**
- Settings.json merge with core using `merge_json_files`
- Preserve existing hooks while adding new ones

**Acceptance Criteria:**
- [ ] Plugin sources without errors
- [ ] Settings.json merge works correctly
- [ ] Commands directory copied with all files
- [ ] Scripts made executable

---

### Task 2.3: Create Node Plugin (`templates/node/plugin.sh`)

**Priority:** High | **Dependencies:** 1.2, 2.1 | **Estimated Lines:** ~70

**Extracted From:**
- `merge_language_features()` (lines 229-257)
- `merge_language_claude_settings()` (lines 259-288)

**Hook Implementations:**

| Hook | Implementation |
|------|----------------|
| `plugin_name` | Return "node" |
| `plugin_description` | Return "Node.js 22.x development environment" |
| `plugin_post_copy` | Merge devcontainer.json features, merge settings.json hooks |

**Special Handling:**
- Devcontainer.json feature merging
- VSCode extensions merging (deduplicate)
- Claude settings hooks array concatenation

**Acceptance Criteria:**
- [ ] Plugin sources without errors
- [ ] Devcontainer.json features merged correctly
- [ ] Extensions array deduplicated
- [ ] Settings.json hooks concatenated

---

## Phase 3: Setup.sh Integration

### Task 3.1: Implement Plugin Discovery

**Priority:** High | **Dependencies:** 2.1, 2.2, 2.3 | **Estimated Lines:** ~40

**New Functions:**

```bash
# Discover all available plugins
discover_plugins() {
    local plugins=()
    for plugin_path in "${TEMPLATES_DIR}"/*/plugin.sh; do
        if [[ -f "$plugin_path" ]]; then
            plugins+=("$plugin_path")
        fi
    done
    echo "${plugins[@]}"
}

# Load a single plugin
load_plugin() {
    local plugin_path="$1"
    if ! source "$plugin_path"; then
        print_error "Failed to load plugin: $plugin_path"
        return 1
    fi
    # Verify required functions
    if ! declare -f plugin_name > /dev/null; then
        print_error "Plugin missing required function 'plugin_name'"
        return 1
    fi
}
```

**Acceptance Criteria:**
- [ ] All plugins in templates/*/plugin.sh discovered
- [ ] Plugin loading validates required functions
- [ ] Error handling for invalid plugins

---

### Task 3.2: Implement Hook Executor

**Priority:** High | **Dependencies:** 3.1 | **Estimated Lines:** ~50

**New Functions:**

```bash
# Execute a hook if it exists
execute_hook() {
    local hook_name="$1"
    shift
    if declare -f "$hook_name" > /dev/null; then
        "$hook_name" "$@"
    fi
}

# Execute hooks for all loaded plugins
execute_plugin_hooks() {
    local hook_name="$1"
    local target_dir="$2"

    for plugin in "${LOADED_PLUGINS[@]}"; do
        # Source plugin to get functions
        source "$plugin"
        local name
        name=$(plugin_name)
        print_info "Executing ${hook_name} for ${name}..."
        execute_hook "$hook_name" "$target_dir"
    done
}
```

**Acceptance Criteria:**
- [ ] Hooks executed in correct order (pre_copy → copy → post_copy → validate)
- [ ] Missing hooks gracefully skipped
- [ ] Error propagation works correctly

---

### Task 3.3: Refactor main() Function

**Priority:** High | **Dependencies:** 3.1, 3.2 | **Estimated Lines:** ~100

**Changes to main():**

| Section | Change |
|---------|--------|
| Script configuration | Add source of common.sh |
| Template variables | Remove hardcoded paths |
| Template checking | Replace with plugin discovery |
| Setup execution | Replace hardcoded calls with hook execution |

**New main() Flow:**
```bash
main() {
    # Source common library
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    # ... argument parsing (unchanged) ...

    # Discover and load plugins
    LOADED_PLUGINS=($(discover_plugins))

    # ... validation, prompts (unchanged) ...

    # Execute plugin hooks in order
    execute_plugin_hooks "plugin_pre_copy" "$target_dir"
    execute_plugin_hooks "plugin_copy" "$target_dir"
    execute_plugin_hooks "plugin_post_copy" "$target_dir"

    # Finalization
    replace_placeholders "$target_dir" "$project_name"
    update_gitignore "$target_dir"

    execute_plugin_hooks "plugin_validate" "$target_dir"

    show_completion "$project_name"
}
```

**Acceptance Criteria:**
- [ ] Common library sourced at start
- [ ] Plugin discovery replaces hardcoded template checks
- [ ] Hook execution replaces direct function calls
- [ ] Existing CLI arguments still work

---

### Task 3.4: Remove Deprecated Code

**Priority:** Medium | **Dependencies:** 3.3 | **Estimated Lines:** -200

**Functions to Remove:**
- `copy_core_template()` (lines 157-172)
- `copy_claude_template()` (lines 174-227)
- `merge_language_features()` (lines 229-257)
- `merge_language_claude_settings()` (lines 259-288)

**Variables to Remove:**
- `CORE_TEMPLATE` (line 20)
- `CLAUDE_TEMPLATE` (line 21)
- `NODE_TEMPLATE` (line 22)

**Acceptance Criteria:**
- [ ] All deprecated functions removed
- [ ] All deprecated variables removed
- [ ] No dead code remaining
- [ ] Script size reduced by ~200 lines

---

## Phase 4: Validation & Testing

### Task 4.1: Shellcheck All Scripts

**Priority:** High | **Dependencies:** 3.4 | **Estimated Lines:** N/A

**Commands:**
```bash
shellcheck setup.sh
shellcheck scripts/lib/common.sh
shellcheck templates/*/plugin.sh
```

**Acceptance Criteria:**
- [ ] Zero shellcheck errors
- [ ] Zero shellcheck warnings (or documented exceptions)

---

### Task 4.2: Dry-Run Test

**Priority:** High | **Dependencies:** 4.1 | **Estimated Lines:** N/A

**Test Commands:**
```bash
# Test dry-run mode
./setup.sh --dry-run test-project

# Test help
./setup.sh --help
```

**Acceptance Criteria:**
- [ ] --dry-run shows correct preview
- [ ] --help displays usage information
- [ ] No errors during dry-run

---

### Task 4.3: Full Setup Test

**Priority:** High | **Dependencies:** 4.2 | **Estimated Lines:** N/A

**Test Commands:**
```bash
# Create test directory
mkdir -p /tmp/test-setup && cd /tmp/test-setup

# Run full setup
/workspace/setup.sh --yes test-project

# Verify files created
ls -la .devcontainer/
ls -la docker/
ls -la .claude/
cat docker-compose.yml
cat CLAUDE.md
```

**Expected Files:**
- [ ] `.devcontainer/devcontainer.json`
- [ ] `.devcontainer/scripts/post.sh` (executable)
- [ ] `docker/Dockerfile.dev`
- [ ] `docker-compose.yml`
- [ ] `.claude/settings.json`
- [ ] `.claude/commands/issue.md`
- [ ] `.claude/commands/implement.md`
- [ ] `.claude/commands/pr.md`
- [ ] `.claude/scripts/deny-check.sh` (executable)
- [ ] `CLAUDE.md`

**Acceptance Criteria:**
- [ ] All expected files created
- [ ] devcontainer.json has merged Node.js features
- [ ] settings.json has merged hooks
- [ ] Placeholder {{PROJECT_NAME}} replaced
- [ ] .gitignore updated

---

### Task 4.4: Comparison Test

**Priority:** Medium | **Dependencies:** 4.3 | **Estimated Lines:** N/A

**Verification:**
Compare output between old and new setup.sh to ensure identical results.

```bash
# Setup comparison directories
mkdir -p /tmp/old-setup /tmp/new-setup

# Run old setup (if available) vs new setup
# Compare file contents
diff -r /tmp/old-setup /tmp/new-setup
```

**Acceptance Criteria:**
- [ ] Generated files are functionally identical
- [ ] No regression in functionality

---

## Execution Order Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    EXECUTION ORDER                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Sequential Tasks (must complete in order):                 │
│  ─────────────────────────────────────────                  │
│  1.1 → 1.2 → 1.3 → 2.1 → 3.1 → 3.3 → 3.4 → 4.1 → 4.2 → 4.3 │
│              │                                              │
│              ├──→ 2.2 ─┐                                    │
│              │         │                                    │
│              └──→ 2.3 ─┴──→ (merge at 3.1)                 │
│                                                             │
│  Parallel Opportunities:                                    │
│  ─────────────────────────                                  │
│  • Tasks 2.1, 2.2, 2.3 can run in parallel after 1.2       │
│  • Task 4.4 can run in parallel with 4.3                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Rollback Plan

If issues are discovered after integration:

1. **Git Revert**: All changes are in atomic commits
   ```bash
   git revert HEAD~n..HEAD
   ```

2. **Plugin Bypass**: Temporarily disable plugins by renaming
   ```bash
   mv templates/core/plugin.sh templates/core/plugin.sh.disabled
   ```

3. **Dual Mode**: Keep old functions with `_deprecated` suffix during transition

---

## Post-Implementation Tasks

After successful implementation:

- [ ] Update CLAUDE.md with plugin architecture documentation
- [ ] Create template for new plugin creation
- [ ] Document plugin development guide for contributors

---

## Checklist Summary

### Phase 1: Infrastructure
- [ ] 1.1: Create directory structure
- [ ] 1.2: Create common.sh library
- [ ] 1.3: Verify common.sh works

### Phase 2: Plugins
- [ ] 2.1: Create core/plugin.sh
- [ ] 2.2: Create claude/plugin.sh
- [ ] 2.3: Create node/plugin.sh

### Phase 3: Integration
- [ ] 3.1: Implement plugin discovery
- [ ] 3.2: Implement hook executor
- [ ] 3.3: Refactor main() function
- [ ] 3.4: Remove deprecated code

### Phase 4: Validation
- [ ] 4.1: Shellcheck all scripts
- [ ] 4.2: Test dry-run mode
- [ ] 4.3: Test full setup
- [ ] 4.4: Compare with previous output

---

**Document Revision History**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-13 | Claude | Initial workflow document |
