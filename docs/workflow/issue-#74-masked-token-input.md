# Implementation Workflow: Masked Token Input

**Issue**: #74 - Add masked input with paste support for PROJECT_TOKEN entry
**Date**: 2026-01-18

## Overview

This document outlines the step-by-step implementation workflow for adding masked token input functionality to the project-automation setup.

## Phase 1: Implement Core Function

### Task 1.1: Add `read_masked_input()` function

**File**: `templates/github-actions/plugin.sh`

**Location**: Add after line ~50 (near other utility functions)

**Implementation**:
```bash
# Read input with masked display (shows * for each character)
# Supports paste and backspace
# Returns: input string via stdout
read_masked_input() {
    local input=""
    local char=""

    while IFS= read -rsn1 char < /dev/tty; do
        if [[ -z "$char" ]]; then
            # Enter key pressed
            echo "" >&2
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            # Backspace (handle both codes)
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf '\b \b' >&2
            fi
        else
            # Normal character (including pasted characters)
            input+="$char"
            printf '*' >&2
        fi
    done

    printf '%s' "$input"
}
```

**Commit**: `✨ feat(plugin): add read_masked_input function for secure token entry`

## Phase 2: Integrate Function

### Task 2.1: Replace token input code

**File**: `templates/github-actions/plugin.sh`

**Location**: Lines 199-220

**Before**:
```bash
local pat=""
while true; do
    printf "GitHub Personal Access Token (for field discovery): "
    IFS='' read -rs pat < /dev/tty
    echo ""  # Add newline after silent input

    if [[ -z "$pat" ]]; then
        echo ""
        echo -n "No token provided. Skip project-automation setup? [Y/n]: "
        IFS='' read -r skip_confirm < /dev/tty
        if [[ -z "$skip_confirm" ]] || [[ "$skip_confirm" =~ ^[Yy] ]]; then
            print_info "Skipping project-automation setup"
            return 0
        fi
        # User chose not to skip, retry token input
        echo ""
        continue
    fi

    # Token provided, break the loop
    break
done
```

**After**:
```bash
local pat=""
while true; do
    printf "GitHub Personal Access Token (for field discovery): "
    pat=$(read_masked_input)

    if [[ -z "$pat" ]]; then
        echo ""
        echo -n "No token provided. Skip project-automation setup? [Y/n]: "
        IFS='' read -r skip_confirm < /dev/tty
        if [[ -z "$skip_confirm" ]] || [[ "$skip_confirm" =~ ^[Yy] ]]; then
            print_info "Skipping project-automation setup"
            return 0
        fi
        # User chose not to skip, retry token input
        echo ""
        continue
    fi

    # Token provided, show confirmation and break
    print_success "Token received (${#pat} characters)"
    break
done
```

**Commit**: `✨ feat(plugin): integrate masked input for PROJECT_TOKEN entry`

## Phase 3: Testing

### Task 3.1: Add integration tests

**File**: `tests/integration/test_setup_flow.bats`

**Tests to add**:
1. Verify `read_masked_input` function exists
2. Verify token input section uses new function

### Task 3.2: Run existing tests

```bash
# Shell linting
shellcheck templates/github-actions/plugin.sh

# Run integration tests
bats tests/integration/test_setup_flow.bats
```

**Commit**: `✅ test(plugin): add tests for masked token input`

## Phase 4: Quality Assurance

### Task 4.1: Run shellcheck

```bash
shellcheck templates/github-actions/plugin.sh
shellcheck setup.sh
```

### Task 4.2: Verify no regressions

- Ensure existing functionality works
- Verify skip flow still works with empty input

## Dependency Graph

```
┌─────────────────────────────┐
│  Phase 1: Core Function     │
│  - Add read_masked_input()  │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Phase 2: Integration       │
│  - Replace token input      │
│  - Add confirmation message │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Phase 3: Testing           │
│  - Integration tests        │
│  - Manual verification      │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│  Phase 4: Quality           │
│  - Shellcheck               │
│  - Final review             │
└─────────────────────────────┘
```

## Checklist

- [ ] Phase 1: Add `read_masked_input()` function
- [ ] Phase 2: Replace token input and add confirmation
- [ ] Phase 3: Add and run tests
- [ ] Phase 4: Run quality checks

## Rollback

If issues occur, revert commits in reverse order:
1. `git revert <test-commit>`
2. `git revert <integration-commit>`
3. `git revert <function-commit>`
