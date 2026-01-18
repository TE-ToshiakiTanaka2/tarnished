# Design: Fix read_masked_input Paste Handling Bug

Issue: #76

## Problem Analysis

### Root Cause

The `read_masked_input` function uses `read -rsn1` to read characters one at a time. When text is pasted, modern terminals send **Bracket Paste Mode** escape sequences:

- Start: `\e[200~` (ESC [ 2 0 0 ~)
- End: `\e[201~` (ESC [ 2 0 1 ~)

These sequences are being captured as regular characters, causing:
1. Extra 6 characters per sequence (12 total for start+end)
2. Display corruption (escape characters shown instead of asterisks)
3. Token corruption (invalid characters in the final string)

### Current Implementation

```bash
read_masked_input() {
    local input=""
    local char=""

    while IFS= read -rsn1 char < /dev/tty; do
        if [[ -z "$char" ]]; then
            break  # Enter
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            # Backspace handling
        else
            input+="$char"  # <-- Escape sequences captured here
            printf '*' >&2
        fi
    done

    printf '%s' "$input"
}
```

## Solution Design

### Approach: Disable Bracket Paste Mode + Sanitize Input

1. **Disable Bracket Paste Mode** before reading input
2. **Re-enable** after input complete
3. **Sanitize** the input to remove any remaining escape sequences

### Implementation

```bash
read_masked_input() {
    local input=""
    local char=""

    # Disable bracket paste mode to prevent escape sequences
    printf '\e[?2004l' >/dev/tty 2>/dev/null

    while IFS= read -rsn1 char < /dev/tty; do
        if [[ -z "$char" ]]; then
            echo "" >&2
            break
        elif [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            if [[ -n "$input" ]]; then
                input="${input%?}"
                printf '\b \b' >&2
            fi
        elif [[ "$char" == $'\e' ]]; then
            # Skip escape sequences (read and discard until end)
            read -rsn1 -t 0.01 char < /dev/tty 2>/dev/null || true
            while [[ -n "$char" ]] && [[ "$char" != "~" ]]; do
                read -rsn1 -t 0.01 char < /dev/tty 2>/dev/null || break
            done
        else
            input+="$char"
            printf '*' >&2
        fi
    done

    # Re-enable bracket paste mode
    printf '\e[?2004h' >/dev/tty 2>/dev/null

    # Sanitize: remove any remaining non-printable characters
    input=$(printf '%s' "$input" | tr -cd '[:print:]')

    printf '%s' "$input"
}
```

## Key Changes

1. **`printf '\e[?2004l'`** - Disable bracket paste mode
2. **Escape sequence detection** - When `\e` (ESC) is detected, skip until `~` or timeout
3. **`printf '\e[?2004h'`** - Re-enable bracket paste mode
4. **`tr -cd '[:print:]'`** - Final sanitization to remove any non-printable chars

## Terminal Compatibility

| Terminal | Bracket Paste | Expected Behavior |
|----------|---------------|-------------------|
| Windows Terminal | Yes | Works with disable |
| VSCode Terminal | Yes | Works with disable |
| iTerm2 | Yes | Works with disable |
| Linux TTY | No | Works (no sequences) |

## Testing Strategy

1. Manual test with Ctrl+V paste
2. Manual test with right-click paste
3. Verify character count matches input length
4. Verify asterisk display is correct
5. Verify token works with GitHub API
