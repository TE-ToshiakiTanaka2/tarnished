# Design Document: Add Remote Execution Support for setup.sh via curl | bash

## Issue Reference
- **Issue**: #49
- **Title**: Add remote execution support for setup.sh via curl | bash
- **Milestone**: core
- **Label**: feature

## Overview

Enable users to execute setup.sh directly from GitHub URL using curl | bash pattern, making it easier to bootstrap new projects without cloning the repository first.

## Architecture

### Execution Flow Detection

```
┌─────────────────────────────────────────────────────────────┐
│                    Script Entry Point                        │
├─────────────────────────────────────────────────────────────┤
│  Check BASH_SOURCE[0]:                                       │
│  - Empty or "-" → Remote execution (pipe)                   │
│  - Valid path   → Local execution                           │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│    Remote Execution     │     │    Local Execution      │
├─────────────────────────┤     ├─────────────────────────┤
│ 1. Check git installed  │     │ Continue with existing  │
│ 2. Create temp dir      │     │ logic (unchanged)       │
│ 3. Clone repository     │     │                         │
│ 4. Execute local setup  │     │                         │
│ 5. Cleanup temp dir     │     │                         │
└─────────────────────────┘     └─────────────────────────┘
```

### Component Structure

```
setup.sh
├── [NEW] Bootstrap Section (lines ~17-50)
│   ├── Remote execution detection
│   ├── Dependency check (git)
│   ├── Repository URL configuration
│   ├── Temporary directory management
│   ├── Clone and execute logic
│   └── Cleanup with trap
│
└── [EXISTING] Main Logic (unchanged)
    ├── Script configuration
    ├── Plugin system
    ├── GitHub operations
    └── Template processing
```

## Implementation Details

### 1. Bootstrap Logic Location

Insert bootstrap logic after the shebang and initial comments, before `set -e`:

```bash
#!/bin/bash
# ... existing header comments ...

# =============================================================================
# Remote Execution Bootstrap
# =============================================================================
# Detect if running via pipe (curl | bash) and bootstrap if necessary

REMOTE_REPO_URL="https://github.com/TE-ToshiakiTanaka2/tarnished.git"
REMOTE_BRANCH="develop"

# Check if running from pipe (curl | bash)
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Remote execution mode
    ...
fi

set -e
# ... rest of existing script ...
```

### 2. Remote Execution Handler

```bash
# Remote execution mode
echo "Detected remote execution (curl | bash mode)"

# Check for git
if ! command -v git &> /dev/null; then
    echo "Error: git is required for remote execution"
    echo "Please install git and try again"
    exit 1
fi

# Create temporary directory
BOOTSTRAP_TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup_bootstrap() {
    if [[ -n "${BOOTSTRAP_TEMP_DIR:-}" ]] && [[ -d "$BOOTSTRAP_TEMP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_TEMP_DIR"
    fi
}

# Register cleanup trap
trap cleanup_bootstrap EXIT

# Clone repository
echo "Cloning repository..."
if ! git clone --depth 1 --branch "$REMOTE_BRANCH" "$REMOTE_REPO_URL" "$BOOTSTRAP_TEMP_DIR" 2>/dev/null; then
    echo "Error: Failed to clone repository"
    exit 1
fi

# Execute local setup.sh with all arguments
echo "Starting setup..."
exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"
```

### 3. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Detection method | BASH_SOURCE[0] check | Standard way to detect pipe execution |
| Repository URL | Hardcoded constant | Simple, can be overridden via env var |
| Clone depth | --depth 1 | Minimize download time |
| Branch | develop (hardcoded) | Keep it simple, no version management needed |
| Cleanup | trap EXIT | Guaranteed cleanup even on errors |
| Execution | exec | Replace current shell, proper exit code propagation |

### 4. Environment Variable Override (Optional)

Allow advanced users to override repository URL:

```bash
REMOTE_REPO_URL="${DEVCONTAINER_REPO_URL:-https://github.com/TE-ToshiakiTanaka2/tarnished.git}"
REMOTE_BRANCH="${DEVCONTAINER_BRANCH:-develop}"
```

## File Changes

### Modified Files

| File | Changes |
|------|---------|
| `setup.sh` | Add bootstrap section at top |
| `README.md` | Add remote execution documentation |

### setup.sh Changes

1. Add bootstrap section after header comments (~30 lines)
2. Update help message to include remote execution usage

### README.md Changes

1. Update Quick Start section with curl | bash example
2. Add "Remote Execution" section under Usage
3. Remove "Remote template download via curl/wget" from Roadmap

## Testing Strategy

### Unit Tests

1. **Detection Logic Test**: Verify BASH_SOURCE detection works correctly
2. **Git Check Test**: Verify proper error when git is not installed

### Integration Tests

1. **Local Execution**: Verify existing functionality unchanged
2. **Dry Run**: Verify --dry-run works with bootstrap

### Manual Tests

1. **Full Remote Execution**:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --dry-run
   ```

2. **With Options**:
   ```bash
   curl -fsSL ... | bash -s -- --lang node --docker --dry-run
   ```

## Security Considerations

1. **HTTPS Only**: Repository URL uses HTTPS
2. **No Secrets in Script**: No hardcoded credentials
3. **Temporary Directory**: Created in system temp with proper permissions
4. **Cleanup Guaranteed**: trap ensures cleanup on any exit

## Rollback Plan

If issues are found:
1. The bootstrap section is isolated at the top
2. Can be removed without affecting local execution
3. No changes to core setup logic

## Future Enhancements (Out of Scope)

- Version/tag specification (--version flag)
- Alternative download methods (tarball)
- Checksum verification
