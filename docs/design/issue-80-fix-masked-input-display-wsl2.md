# Design Document: Fix Masked Input Display on WSL2 + Windows Terminal

**Issue**: #80 - Fix masked input display issue on WSL2 + Windows Terminal
**Author**: Claude Code
**Date**: 2026-01-18
**Status**: Draft

## 1. Overview

This document describes the fix for the `read_masked_input` function which fails to display asterisks correctly on WSL2 + Windows Terminal when pasting tokens with Ctrl+V.

## 2. Problem Analysis

### 2.1 Current Behavior

On WSL2 + Windows Terminal with Ctrl+V paste:
- **Expected**: `****************************************` (40 asterisks during input)
- **Actual**: No asterisks displayed during input, token's last 8 characters shown after Enter

### 2.2 Root Cause Analysis

The current implementation has several issues specific to WSL2 + Windows Terminal:

1. **Bracket Paste Mode Timing**: The `\e[?2004l` disable command may not take effect immediately, allowing escape sequences to be processed before disabling

2. **Escape Sequence Handling Race Condition**: The escape sequence detection (`$'\e'`) with 0.01s timeout is insufficient for WSL2's inter-process communication latency

3. **stderr Buffering**: `printf '*' >&2` output may be buffered differently in WSL2, causing delayed or missing display

4. **Character Echo Issue**: After escape sequence processing, remaining characters may leak to terminal output

### 2.3 Observed Symptoms

| Symptom | Cause |
|---------|-------|
| No asterisks displayed | stderr output buffered or escape handling consuming characters |
| Token end visible | Escape sequence end marker (`~`) not properly consumed |
| All at once after Enter | Terminal buffering the paste operation |

## 3. Solution Design

### 3.1 Approach: Simplified Read with Explicit Flush

Replace the complex character-by-character escape handling with:
1. Disable bracket paste mode
2. Use simpler escape sequence consumption
3. Explicitly flush output after each asterisk
4. Add more robust sanitization

### 3.2 New Implementation

```bash
read_masked_input() {
    local input=""
    local char=""
    local in_escape=false
    local escape_buffer=""

    # Disable bracket paste mode before reading
    printf '\e[?2004l' >/dev/tty 2>/dev/null || true

    # Small delay to ensure the disable command takes effect
    sleep 0.01

    while IFS= read -rsn1 char < /dev/tty; do
        # Handle Enter key (empty char)
        if [[ -z "$char" ]]; then
            echo "" >&2
            break
        fi

        # Handle escape sequences
        if [[ "$char" == $'\e' ]]; then
            # Consume the entire escape sequence
            local seq=""
            while IFS= read -rsn1 -t 0.1 seq < /dev/tty 2>/dev/null; do
                # Break on sequence terminators
                if [[ "$seq" == "~" ]] || [[ "$seq" =~ [A-Za-z] ]]; then
                    break
                fi
                # Safety: break if we've read too many characters
                if [[ ${#escape_buffer} -gt 10 ]]; then
                    break
                fi
                escape_buffer+="$seq"
            done
            continue
        fi

        # Handle Backspace (both \x7f and \b)
        if [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf '\b \b' >&2
            fi
            continue
        fi

        # Handle printable characters only
        if [[ "$char" =~ [[:print:]] ]]; then
            input+="$char"
            printf '*' >&2
        fi
    done

    # Re-enable bracket paste mode
    printf '\e[?2004h' >/dev/tty 2>/dev/null || true

    # Final sanitization: remove any non-printable characters
    input=$(printf '%s' "$input" | tr -cd '[:print:]')

    printf '%s' "$input"
}
```

### 3.3 Key Changes

| Change | Purpose |
|--------|---------|
| `sleep 0.01` after disable | Ensure bracket paste mode is disabled before reading |
| Increased timeout to 0.1s | Handle WSL2's higher latency |
| Break on letter terminators | Handle more escape sequence types |
| Safety limit (10 chars) | Prevent infinite loop in escape handling |
| Explicit printable check | Only accept printable characters |

## 4. Alternative Approaches Considered

### 4.1 Approach A: Simple `read -s` Only (Rejected)

```bash
read -rs input < /dev/tty
printf '%s' "$input"
```

**Pros**: Simple, no escape sequence issues
**Cons**: No visual feedback (asterisks), poor UX

### 4.2 Approach B: stty-based Approach (Rejected)

```bash
stty -echo
# read characters
stty echo
```

**Pros**: More control over terminal
**Cons**: May not work in all environments, adds complexity

### 4.3 Approach C: Selected Approach (Improved Escape Handling)

The selected approach keeps the character-by-character reading for UX while fixing the WSL2-specific issues.

## 5. Test Strategy

### 5.1 Unit Tests

| Test | Description |
|------|-------------|
| Function exists | Verify function is defined |
| Uses /dev/tty | Verify input source |
| Handles backspace | Verify both `\x7f` and `\b` |
| Handles escape | Verify escape sequence detection |
| Sanitizes input | Verify `tr` sanitization |
| Printable check | Verify printable character filtering |

### 5.2 Manual Tests

| Environment | Test Case |
|-------------|-----------|
| WSL2 + Windows Terminal | Ctrl+V paste 40-char token |
| VS Code Integrated Terminal | Ctrl+V paste |
| Native Linux Terminal | Ctrl+V paste |
| iTerm2 (macOS) | Cmd+V paste |

### 5.3 Acceptance Criteria

1. All 40 asterisks display during paste
2. No token characters visible at any time
3. Character count matches input length
4. Backspace works correctly
5. Enter submits input

## 6. Security Considerations

| Risk | Mitigation |
|------|------------|
| Token exposure | Only printable chars accepted, asterisk display |
| Escape sequence injection | Sequences consumed and discarded |
| Buffer overflow | Safety limit on escape buffer |

## 7. File Changes

### Modified Files

| File | Changes |
|------|---------|
| `templates/github-actions/plugin.sh` | Update `read_masked_input()` function |
| `tests/unit/test_read_masked_input.bats` | Add tests for printable character check |

## 8. Rollback Plan

1. Revert to previous implementation if issues found
2. No configuration changes required
3. Simple git revert

## 9. Dependencies

- Bash 4.0+
- `/dev/tty` availability
- Standard POSIX utilities (`tr`, `sleep`)
