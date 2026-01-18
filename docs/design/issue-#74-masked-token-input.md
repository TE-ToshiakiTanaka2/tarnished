# Design Document: Masked Token Input for PROJECT_TOKEN

**Issue**: #74 - Add masked input with paste support for PROJECT_TOKEN entry
**Author**: Claude Code
**Date**: 2026-01-18
**Status**: Draft

## 1. Overview

This document describes the design for adding masked input functionality with paste support when entering the GitHub Personal Access Token (PROJECT_TOKEN) during the `project-automation` interactive setup.

## 2. Problem Statement

### Current Implementation
- Uses `read -rs pat < /dev/tty` for silent input
- No visual feedback when typing/pasting
- Paste functionality (`Ctrl+V`) may not work reliably with `curl | bash` execution
- Users cannot confirm if their input was received

### User Impact
- Poor user experience when entering 40+ character tokens
- Uncertainty about whether paste worked
- No way to verify input before submission

## 3. Requirements

### Functional Requirements
| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | Support `Ctrl+V` paste functionality | High |
| FR-2 | Display `*` for each character entered | High |
| FR-3 | Support backspace for corrections | High |
| FR-4 | Show confirmation message with character count | Medium |
| FR-5 | Work with `curl \| bash` remote execution | High |

### Technical Requirements
| ID | Requirement | Priority |
|----|-------------|----------|
| TR-1 | Read from `/dev/tty` for pipe execution support | High |
| TR-2 | Maintain existing skip functionality (empty input) | High |
| TR-3 | Handle both `\x7f` and `\b` backspace codes | Medium |

## 4. Architecture

### 4.1 Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    plugin.sh                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │           read_masked_input()                        │    │
│  │  - Character-by-character reading                    │    │
│  │  - Real-time mask display (*)                        │    │
│  │  - Backspace handling                                │    │
│  │  - Enter key detection                               │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │        setup_project_automation()                    │    │
│  │  - Calls read_masked_input for PAT                   │    │
│  │  - Displays confirmation message                     │    │
│  │  - Handles empty input (skip flow)                   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Function Design

#### `read_masked_input()`

**Purpose**: Read user input character-by-character with masked display

**Input**: None (reads from `/dev/tty`)

**Output**: The entered string (via stdout)

**Algorithm**:
```
1. Initialize empty input string
2. Loop:
   a. Read single character silently from /dev/tty
   b. If Enter key (empty char): break loop
   c. If Backspace: remove last char, erase last '*'
   d. Otherwise: append char, print '*'
3. Print newline
4. Echo input string
```

**Pseudocode**:
```bash
read_masked_input() {
    local input=""
    local char=""

    while IFS= read -rsn1 char < /dev/tty; do
        if [[ -z "$char" ]]; then
            # Enter key pressed
            echo "" >&2
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            # Backspace
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf '\b \b' >&2
            fi
        else
            # Normal character
            input+="$char"
            printf '*' >&2
        fi
    done

    printf '%s' "$input"
}
```

### 4.3 Integration Points

**File**: `templates/github-actions/plugin.sh`

**Location**: Lines 199-220 (current token input loop)

**Changes**:
1. Add `read_masked_input()` function near top of file (with other utility functions)
2. Replace `read -rs pat` call with `read_masked_input` call
3. Add confirmation message after successful input

## 5. File Structure

### Modified Files
```
templates/github-actions/plugin.sh    # Add masked input function
tests/integration/test_setup_flow.bats # Add integration tests
```

### No New Files Required
The implementation adds a function to an existing file.

## 6. Test Strategy

### Unit Tests
- Verify function returns correct input
- Verify backspace removes characters
- Verify empty input returns empty string

### Integration Tests
- Verify masked input works in setup flow
- Verify confirmation message displays
- Verify skip functionality still works

### Manual Tests
- Test with `curl | bash` execution
- Test paste functionality with `Ctrl+V`
- Test in various terminals (Linux, WSL)

## 7. Security Considerations

| Concern | Mitigation |
|---------|------------|
| Token exposure in terminal | Characters masked with `*` |
| Token in shell history | Input read directly, not via command args |
| Token in process list | Not passed as argument |

## 8. Rollback Plan

If issues are discovered:
1. Revert to previous `read -rs` implementation
2. No database or configuration changes required
3. Simple code revert via git

## 9. Dependencies

- Bash 4.0+ (for `read -n1`)
- `/dev/tty` availability (standard on Linux/macOS)

## 10. Open Questions

None at this time.
