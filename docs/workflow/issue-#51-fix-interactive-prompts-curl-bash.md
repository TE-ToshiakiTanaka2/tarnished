# Implementation Workflow: Fix Interactive Prompts for curl | bash

**Issue**: #51
**Type**: bugfix
**Branch**: `bugfix/TE-ToshiakiTanaka2/#51/fix-interactive-prompts-curl-bash`

## Phase Overview

| Phase | Description | Dependencies |
|-------|-------------|--------------|
| 1 | Add utility functions to common.sh | None |
| 2 | Modify setup.sh read commands | Phase 1 |
| 3 | Add TTY check integration | Phase 1, 2 |
| 4 | Testing and validation | Phase 1-3 |

## Phase 1: Add Utility Functions

### Task 1.1: Add check_tty_available() to common.sh

**File**: `scripts/lib/common.sh`

**Implementation**:
```bash
# Check if /dev/tty is available for interactive input
# Returns 0 if available, 1 if not
check_tty_available() {
    if [[ ! -c /dev/tty ]]; then
        return 1
    fi
    if ! exec 3< /dev/tty 2>/dev/null; then
        return 1
    fi
    exec 3<&-
    return 0
}
```

**Commit**: `feat(common): add check_tty_available function`

### Task 1.2: Add show_interactive_mode_error() to common.sh

**File**: `scripts/lib/common.sh`

**Implementation**:
```bash
# Show error message when interactive mode is not available
show_interactive_mode_error() {
    print_error "Interactive mode is not available"
    echo ""
    echo "This appears to be a non-interactive environment (e.g., piped input, CI/CD)."
    echo ""
    echo "To run in non-interactive mode, specify all required options:"
    echo ""
    echo "  curl -fsSL <url>/setup.sh | bash -s -- --lang node my-project -y"
    echo "  curl -fsSL <url>/setup.sh | bash -s -- --lang python --docker my-app -y"
    echo ""
    echo "Available options:"
    echo "  --lang <languages>    Select language(s): node, python, rust, deno"
    echo "  --playwright          Include Playwright E2E testing"
    echo "  --docker              Include Docker-in-Docker support"
    echo "  --postgresql          Include PostgreSQL database support"
    echo "  --neo4j               Include Neo4j graph database support"
    echo "  --redis               Include Redis cache/session support"
    echo "  --github-actions      Include GitHub Actions templates"
    echo "  -y, --yes             Skip confirmation prompts (required for non-interactive)"
    echo ""
    echo "For full options, see: ./setup.sh --help"
}
```

**Commit**: `feat(common): add show_interactive_mode_error function`

## Phase 2: Modify setup.sh Read Commands

### Task 2.1: Modify prompt_language_selection()

**File**: `setup.sh`
**Lines**: 536, 541

**Changes**:
- Line 536: `read -rsn1 key` → `read -rsn1 key < /dev/tty`
- Line 541: `read -rsn2 -t 0.1 key` → `read -rsn2 -t 0.1 key < /dev/tty`

### Task 2.2: Modify prompt_project_name()

**File**: `setup.sh`
**Line**: 769

**Changes**:
- `read -r project_name` → `read -r project_name < /dev/tty`

### Task 2.3: Modify prompt_playwright()

**File**: `setup.sh`
**Line**: 594

**Changes**:
- `read -r response` → `read -r response < /dev/tty`

### Task 2.4: Modify confirmation prompts

**File**: `setup.sh`
**Lines**: 1035, 1052

**Changes**:
- Line 1035: `read -r confirm` → `read -r confirm < /dev/tty`
- Line 1052: `read -r overwrite` → `read -r overwrite < /dev/tty`

**Commit**: `fix(setup): use /dev/tty for interactive prompts`

## Phase 3: Add TTY Check Integration

### Task 3.1: Add get_default_project_name() function

**File**: `setup.sh`
**Location**: After validation functions section

**Implementation**:
```bash
# Get default project name from current directory
get_default_project_name() {
    local dir_name
    dir_name=$(basename "$(pwd)")
    if validate_project_name "$dir_name" 2>/dev/null; then
        echo "$dir_name"
    else
        echo ""
    fi
}
```

### Task 3.2: Add TTY check in main flow

**File**: `setup.sh`
**Location**: Before interactive prompts in main()

**Logic**:
1. Check if TTY is available
2. If not available and required args missing, show error
3. If not available but all args provided, continue non-interactively

**Commit**: `fix(setup): add TTY availability check and error handling`

## Phase 4: Testing and Validation

### Task 4.1: Run shellcheck

```bash
shellcheck setup.sh scripts/lib/common.sh
```

### Task 4.2: Test local execution

```bash
./setup.sh --dry-run
./setup.sh --help
./setup.sh --lang node --dry-run
```

### Task 4.3: Test non-interactive mode

```bash
./setup.sh --lang node test-project -y --dry-run
```

### Task 4.4: Test piped execution (simulated)

```bash
# Simulate piped input
echo "" | ./setup.sh --lang node test-project -y --dry-run
```

**Commit**: No commit for testing phase

## Commit Summary

| Order | Commit Message | Files Changed |
|-------|----------------|---------------|
| 1 | `feat(common): add TTY utility functions` | scripts/lib/common.sh |
| 2 | `fix(setup): use /dev/tty for interactive prompts` | setup.sh |
| 3 | `fix(setup): add TTY availability check and error handling` | setup.sh |

## Rollback Procedure

If issues are found post-implementation:

1. Identify the problematic commit
2. Create revert commit: `git revert <commit-hash>`
3. Document the issue in GitHub Issue #51
4. Plan alternative solution

## Success Criteria

- [ ] `curl | bash` execution allows interactive prompts
- [ ] Non-interactive mode (`-y` + args) continues to work
- [ ] Error message shown when TTY unavailable and args missing
- [ ] All existing functionality preserved
- [ ] shellcheck passes without errors
- [ ] Dry-run tests pass
