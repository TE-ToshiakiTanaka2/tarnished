# Design Document: Fix project-automation Interactive Setup Bugs

**Issue**: #67
**Type**: Bugfix
**Milestone**: github-actions

## Overview

This document describes the design for fixing multiple bugs in the `project-automation` interactive setup when running `setup.sh` via pipe execution (`curl | bash`).

## Problem Analysis

### Root Causes

#### 1. Pipe Execution stdin Issue

When executing `setup.sh` via pipe:
```bash
curl -fsSL https://raw.githubusercontent.com/.../setup.sh | bash
```

The standard input (stdin) is consumed by the pipe. The `read` command reads from the pipe instead of the terminal, causing immediate EOF or empty input.

**Current Code** (`templates/github-actions/plugin.sh:196`):
```bash
read -rsp "GitHub Personal Access Token (for field discovery): " pat
```

**Problem**: `read` reads from stdin (the pipe), not the terminal.

**Solution**: Explicitly read from `/dev/tty`:
```bash
read -rsp "GitHub Personal Access Token (for field discovery): " pat < /dev/tty
```

#### 2. Hook Function Carryover Issue

The `execute_plugins_hook` function in `setup.sh` sources each plugin file and executes the specified hook. However, it only unsets certain hook functions, not including `plugin_interactive_setup`.

**Current Code** (`setup.sh:803`):
```bash
unset -f plugin_pre_copy plugin_copy plugin_post_copy plugin_validate 2>/dev/null || true
```

**Problem Flow**:
1. Source `core/plugin.sh` → no `plugin_interactive_setup` defined
2. Source `github-actions/plugin.sh` → `plugin_interactive_setup` defined and persists
3. Source `node/plugin.sh` → previous `plugin_interactive_setup` still exists → called again
4. Source `claude/plugin.sh` → same issue → called again
5. Source `playwright/plugin.sh` → same issue → called again

**Result**: Hook called 5 times instead of once.

**Solution**: Add `plugin_interactive_setup` and `plugin_minimal_setup` to the unset list.

#### 3. Missing Skip Confirmation

When no token is provided, the script creates a minimal configuration without user confirmation.

**Current Code**:
```bash
if [[ -z "$pat" ]]; then
    print_warning "No token provided. Creating minimal configuration."
    create_minimal_project_config "$config_file"
    return 0
fi
```

**Problem**: User has no control; minimal config is created automatically.

**Solution**: Add skip confirmation prompt with retry option.

## Architecture

### Affected Files

| File | Function | Changes |
|------|----------|---------|
| `setup.sh` | `execute_plugins_hook` | Add hooks to unset list |
| `templates/github-actions/plugin.sh` | `setup_project_automation` | Add `/dev/tty`, skip confirmation |

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     setup.sh execution                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  execute_plugins_hook("plugin_interactive_setup")               │
│       │                                                          │
│       ├─► source core/plugin.sh                                 │
│       │   └─► unset hooks (including plugin_interactive_setup)  │
│       │   └─► no hook defined → skip                            │
│       │                                                          │
│       ├─► source github-actions/plugin.sh                       │
│       │   └─► unset hooks (including plugin_interactive_setup)  │
│       │   └─► plugin_interactive_setup defined → execute        │
│       │       └─► read from /dev/tty (terminal)                 │
│       │       └─► setup_project_automation()                    │
│       │           └─► all reads from /dev/tty                   │
│       │           └─► skip confirmation on empty token          │
│       │                                                          │
│       ├─► source node/plugin.sh                                 │
│       │   └─► unset hooks (including plugin_interactive_setup)  │
│       │   └─► no hook defined → skip                            │
│       │                                                          │
│       └─► ... (other plugins, all skip)                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Design

### 1. execute_plugins_hook Modification

**File**: `setup.sh`
**Function**: `execute_plugins_hook`
**Line**: ~803

```bash
# Before
unset -f plugin_pre_copy plugin_copy plugin_post_copy plugin_validate 2>/dev/null || true

# After
unset -f plugin_pre_copy plugin_copy plugin_post_copy plugin_validate plugin_interactive_setup plugin_minimal_setup 2>/dev/null || true
```

### 2. setup_project_automation /dev/tty Addition

**File**: `templates/github-actions/plugin.sh`
**Function**: `setup_project_automation`

All `read` commands need `/dev/tty` redirection:

| Line | Current | Modified |
|------|---------|----------|
| ~186 | `read -rp "Overwrite? [y/N]: " overwrite` | `read -rp "Overwrite? [y/N]: " overwrite < /dev/tty` |
| ~196 | `read -rsp "GitHub Personal Access Token..." pat` | `read -rsp "GitHub Personal Access Token..." pat < /dev/tty` |
| ~207 | `read -rp "Choice [1-2]: " project_type_choice` | `read -rp "Choice [1-2]: " project_type_choice < /dev/tty` |
| ~220 | `read -rp "Owner/Organization name: " owner` | `read -rp "Owner/Organization name: " owner < /dev/tty` |
| ~226 | `read -rp "Project number: " project_number` | `read -rp "Project number: " project_number < /dev/tty` |
| ~261 | `read -rp "Default Status: " status_value` | `read -rp "Default Status: " status_value < /dev/tty` |
| ~270 | `read -rp "Default Priority: " priority_value` | `read -rp "Default Priority: " priority_value < /dev/tty` |

### 3. Skip Confirmation Logic

**File**: `templates/github-actions/plugin.sh`
**Function**: `setup_project_automation`

Replace the empty token handling with a loop that allows retry:

```bash
# Token input with retry loop
while true; do
    read -rsp "GitHub Personal Access Token (for field discovery): " pat < /dev/tty
    echo ""

    if [[ -z "$pat" ]]; then
        echo ""
        echo -n "No token provided. Skip project-automation setup? [Y/n]: "
        read -r skip_confirm < /dev/tty
        if [[ -z "$skip_confirm" ]] || [[ "$skip_confirm" =~ ^[Yy] ]]; then
            print_info "Skipping project-automation setup"
            return 0
        fi
        # Continue loop to retry token input
        echo ""
        continue
    fi

    # Token provided, break the loop
    break
done
```

## Test Strategy

### Unit Tests

1. **Hook Unset Verification**
   - Verify `plugin_interactive_setup` is called exactly once when multiple plugins are loaded
   - Can be tested by adding debug output to the hook

2. **Pipe Execution Simulation**
   - Test `setup_project_automation` with stdin redirected from `/dev/null`
   - Verify it reads from `/dev/tty` correctly

### Integration Tests

1. **Full Setup Flow**
   - Run `setup.sh` via pipe execution
   - Verify interactive prompts work correctly
   - Verify skip confirmation appears on empty token

### Manual Testing

```bash
# Test 1: Pipe execution
curl -fsSL https://raw.githubusercontent.com/.../setup.sh | bash

# Test 2: Local execution (comparison)
bash setup.sh
```

## Security Considerations

- Token is read with `-s` flag (silent, no echo)
- Token is not stored in any file by the setup script
- `/dev/tty` access is standard for interactive scripts

## Rollback Plan

If issues arise:
1. Revert the unset list change in `setup.sh`
2. Revert `/dev/tty` additions in `plugin.sh`
3. The original behavior (broken for pipe execution) will be restored

## References

- Issue #67: Fix project-automation interactive setup bugs
- Issue #43: Add project-automation action
- Issue #60: Add plugin_interactive_setup hook
