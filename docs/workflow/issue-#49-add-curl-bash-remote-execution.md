# Workflow Document: Add Remote Execution Support for setup.sh via curl | bash

## Issue Reference
- **Issue**: #49
- **Title**: Add remote execution support for setup.sh via curl | bash
- **Milestone**: core
- **Label**: feature

## Implementation Phases

### Phase 1: Bootstrap Logic Implementation

#### Step 1.1: Add Remote Execution Detection
- [ ] Insert bootstrap section after header comments in setup.sh
- [ ] Add REMOTE_REPO_URL and REMOTE_BRANCH constants
- [ ] Implement BASH_SOURCE[0] detection logic

#### Step 1.2: Implement Bootstrap Handler
- [ ] Add git command check
- [ ] Create temporary directory with mktemp
- [ ] Implement cleanup function
- [ ] Register trap for EXIT signal
- [ ] Add git clone with --depth 1
- [ ] Execute local setup.sh with exec and pass arguments

#### Step 1.3: Error Handling
- [ ] Add user-friendly error messages for missing git
- [ ] Handle clone failures gracefully
- [ ] Ensure proper exit codes

### Phase 2: Documentation Updates

#### Step 2.1: README.md Updates
- [ ] Add curl | bash example to Quick Start section
- [ ] Add "Remote Execution" subsection under Usage
- [ ] Update Roadmap (remove completed item)

#### Step 2.2: Help Message Update
- [ ] Add remote execution usage to show_help function

### Phase 3: Testing

#### Step 3.1: Local Verification
- [ ] Run shellcheck on setup.sh
- [ ] Verify local execution still works
- [ ] Test --dry-run mode
- [ ] Test --help output

#### Step 3.2: Integration Testing
- [ ] Test curl | bash execution (after push)

## Detailed Implementation Steps

### 1. Bootstrap Section Code

Location: Insert after line 15 (after header comments), before `set -e`

```bash
# =============================================================================
# Remote Execution Bootstrap
# =============================================================================
# Detect if running via pipe (curl | bash) and bootstrap if necessary

REMOTE_REPO_URL="${DEVCONTAINER_REPO_URL:-https://github.com/TE-ToshiakiTanaka2/tarnished.git}"
REMOTE_BRANCH="${DEVCONTAINER_BRANCH:-develop}"

# Check if running from pipe (curl | bash)
# BASH_SOURCE[0] is empty, "-", or doesn't exist as a file when piped
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    echo "================================================"
    echo "  Devcontainer Boilerplate - Remote Execution"
    echo "================================================"
    echo ""

    # Check for git
    if ! command -v git &> /dev/null; then
        echo "Error: git is required for remote execution"
        echo "Please install git and try again:"
        echo "  Ubuntu/Debian: sudo apt-get install git"
        echo "  macOS:         brew install git"
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
    echo "Downloading setup files..."
    if ! git clone --depth 1 --branch "$REMOTE_BRANCH" --quiet "$REMOTE_REPO_URL" "$BOOTSTRAP_TEMP_DIR"; then
        echo "Error: Failed to download setup files"
        echo "Please check your network connection and try again"
        exit 1
    fi

    echo "Starting setup..."
    echo ""

    # Execute local setup.sh with all arguments
    # Using exec to replace current shell, ensuring proper exit code
    exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"
fi
```

### 2. README.md Changes

#### Quick Start Section (replace existing)

```markdown
## Quick Start

### Remote Execution (Recommended)

Run directly from GitHub without cloning:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
\`\`\`

With options:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --lang node --docker
\`\`\`

### Local Execution

Clone and run locally:

\`\`\`bash
git clone https://github.com/TE-ToshiakiTanaka2/tarnished.git
cd tarnished
./setup.sh
\`\`\`
```

#### New Remote Execution Section (under Usage)

```markdown
### Remote Execution

Execute setup.sh directly from GitHub:

\`\`\`bash
# Basic usage (interactive mode)
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash

# With project name
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- my-project

# With options
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --lang node --docker

# Non-interactive with all options
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- my-project --lang python --yes
\`\`\`

**Requirements for remote execution:**
- git (for downloading setup files)
- curl (for fetching the script)

**Note:** The script automatically detects remote execution and downloads required files to a temporary directory, which is cleaned up after setup completes.
```

#### Roadmap Update

Remove this line:
```markdown
- [ ] Remote template download via curl/wget
```

### 3. Help Message Update

Add to show_help() function in setup.sh:

```bash
Remote Execution:
    curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
    curl -fsSL ... | bash -s -- [OPTIONS] [PROJECT_NAME]
```

## Testing Checklist

### Pre-commit Tests
- [ ] `shellcheck setup.sh` passes
- [ ] `./setup.sh --help` shows updated help
- [ ] `./setup.sh --dry-run test-project` works locally

### Post-push Tests (Manual)
- [ ] curl | bash basic execution
- [ ] curl | bash with --dry-run
- [ ] curl | bash with --lang option
- [ ] curl | bash with project name

## Rollback Procedure

If issues arise:
1. The bootstrap section is isolated (lines ~17-60)
2. Simply remove the bootstrap section
3. Local execution continues to work unchanged

## Dependencies

- No new dependencies added
- Requires git for remote execution (already commonly available)
