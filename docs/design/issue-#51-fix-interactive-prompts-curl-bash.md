# Design Document: Fix Interactive Prompts for curl | bash

**Issue**: #51
**Type**: bugfix
**Milestone**: core

## Problem Statement

When running the setup script via `curl | bash`, interactive prompts fail because stdin is connected to curl's data stream instead of the user's terminal.

```bash
# This fails - stdin is the curl output, not user terminal
curl -fsSL https://raw.githubusercontent.com/.../setup.sh | bash
```

## Architecture Overview

### Current Flow (Broken)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│    curl     │────▶│    stdin     │────▶│   setup.sh  │
│  (script)   │     │   (pipe)     │     │   (bash)    │
└─────────────┘     └──────────────┘     └─────────────┘
                                                │
                                                ▼
                                         ┌─────────────┐
                                         │    read     │ ← Gets EOF/garbage
                                         │  commands   │   from pipe
                                         └─────────────┘
```

### Solution Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│    curl     │────▶│    stdin     │────▶│   setup.sh  │
│  (script)   │     │   (pipe)     │     │   (bash)    │
└─────────────┘     └──────────────┘     └─────────────┘
                                                │
┌─────────────┐                                 │
│   Terminal  │                                 ▼
│    (tty)    │◀────────────────────────┌─────────────┐
│             │     /dev/tty            │    read     │
└─────────────┘◀────────────────────────│  < /dev/tty │
                                        └─────────────┘
```

## Component Design

### 1. TTY Availability Check

**Function**: `check_tty_available()`

**Purpose**: Verify that `/dev/tty` is accessible for interactive input.

**Logic**:
1. Check if `/dev/tty` exists as a character device
2. Attempt to open it for reading
3. Return success/failure

**Location**: Add to `scripts/lib/common.sh` (shared library)

```bash
check_tty_available() {
    # Check if /dev/tty exists and is a character device
    if [[ ! -c /dev/tty ]]; then
        return 1
    fi

    # Try to open /dev/tty for reading
    if ! exec 3< /dev/tty 2>/dev/null; then
        return 1
    fi

    # Close the test file descriptor
    exec 3<&-
    return 0
}
```

### 2. Interactive Mode Error Handler

**Function**: `show_interactive_mode_error()`

**Purpose**: Display helpful error message when interactive mode is unavailable.

**Requirements**:
- Explain the error clearly
- Provide concrete examples of non-interactive usage
- List available options

**Location**: Add to `scripts/lib/common.sh`

### 3. Default Project Name

**Function**: `get_default_project_name()`

**Purpose**: Derive default project name from current directory.

**Logic**:
1. Get basename of current working directory
2. Validate it as a valid project name
3. Return the name or empty string if invalid

**Location**: Add to `setup.sh` (used only there)

### 4. Modified Read Functions

All `read` commands that interact with user input must be modified:

| Function | Line | Current | Modified |
|----------|------|---------|----------|
| `prompt_language_selection()` | 536 | `read -rsn1 key` | `read -rsn1 key < /dev/tty` |
| `prompt_language_selection()` | 541 | `read -rsn2 -t 0.1 key` | `read -rsn2 -t 0.1 key < /dev/tty` |
| `prompt_project_name()` | 769 | `read -r project_name` | `read -r project_name < /dev/tty` |
| `prompt_playwright()` | 594 | `read -r response` | `read -r response < /dev/tty` |
| Confirmation prompt | 1035 | `read -r confirm` | `read -r confirm < /dev/tty` |
| Overwrite prompt | 1052 | `read -r overwrite` | `read -r overwrite < /dev/tty` |

## File Modifications

### scripts/lib/common.sh

Add new utility functions:
- `check_tty_available()`
- `show_interactive_mode_error()`

### setup.sh

1. Add `get_default_project_name()` function
2. Modify all `read` commands to use `/dev/tty`
3. Add TTY check before interactive prompts
4. Add fallback to non-interactive mode with clear error messages

## Interaction Sequence

### Interactive Mode (with TTY)

```
1. User runs: curl ... | bash
2. Bootstrap clones repo to temp dir
3. exec bash setup.sh (stdin still piped)
4. check_tty_available() → true
5. Interactive prompts read from /dev/tty
6. User interacts normally
7. Setup completes successfully
```

### Non-Interactive Mode (no TTY)

```
1. CI/CD runs: curl ... | bash
2. Bootstrap clones repo to temp dir
3. exec bash setup.sh (stdin piped)
4. check_tty_available() → false
5. Check if required args provided (--lang, project_name, -y)
6a. If yes → proceed with non-interactive setup
6b. If no → show_interactive_mode_error() and exit 1
```

## Error Messages

### TTY Not Available (Missing Required Args)

```
✗ Interactive mode is not available

This appears to be a non-interactive environment (e.g., piped input, CI/CD).

To run in non-interactive mode, specify all required options:

  curl -fsSL <url>/setup.sh | bash -s -- --lang node my-project -y
  curl -fsSL <url>/setup.sh | bash -s -- --lang python --docker my-app -y

Available options:
  --lang <languages>    Select language(s): node, python, rust, deno
  --playwright          Include Playwright E2E testing
  --docker              Include Docker-in-Docker support
  --postgresql          Include PostgreSQL database support
  --neo4j               Include Neo4j graph database support
  --redis               Include Redis cache/session support
  --github-actions      Include GitHub Actions templates
  -y, --yes             Skip confirmation prompts (required for non-interactive)

For full options, see: ./setup.sh --help
```

## Test Strategy

### Unit Tests

1. **TTY Check Function**
   - Test with `/dev/tty` available
   - Test with `/dev/tty` unavailable (mock)

2. **Default Project Name**
   - Valid directory names
   - Invalid directory names (special chars, etc.)

### Integration Tests

1. **Local Execution**
   ```bash
   ./setup.sh --dry-run  # Should work as before
   ```

2. **Piped Execution with TTY**
   ```bash
   cat setup.sh | bash  # Should use /dev/tty
   ```

3. **Non-Interactive Mode**
   ```bash
   ./setup.sh --lang node my-project -y --dry-run
   ```

4. **Remote Execution Simulation**
   ```bash
   curl -fsSL <local-server>/setup.sh | bash -s -- --lang node test-project -y
   ```

## Rollback Plan

If issues are found:
1. Revert `/dev/tty` changes
2. Document that remote execution requires non-interactive mode
3. Update help/docs to clarify usage

## Security Considerations

- `/dev/tty` is a standard Unix device, no security concerns
- No change to script permissions or capabilities
- Input validation remains unchanged
