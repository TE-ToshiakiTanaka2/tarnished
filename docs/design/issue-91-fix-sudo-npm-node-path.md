# Design Document: Fix sudo npm/node command not found

**Issue**: #91
**Type**: bugfix
**Milestone**: core

## Overview

Fix the issue where `sudo npm` and `sudo node` commands fail with "command not found" in Devcontainer environments due to missing nvm path in sudoers secure_path.

## Problem Analysis

### Root Cause

```
[User Shell Environment]
    └── PATH includes: /usr/local/share/nvm/versions/node/v22.22.0/bin/
    └── npm, node: ✅ Available

[sudo Context]
    └── secure_path: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    └── nvm path: ❌ NOT included
    └── npm, node: ❌ command not found
```

When sudo is executed, the `secure_path` setting in sudoers overrides the user's PATH environment variable. The nvm-installed Node.js binaries are not included in this secure_path.

## Solution Design

### Approach

Add nvm bin path to sudoers secure_path via `/etc/sudoers.d/` configuration file.

### Implementation Strategy

Add a **setup function to existing post.sh** because:

1. The nvm path is only available after the devcontainer features are installed
2. post.sh already runs via postCreateCommand after features are installed
3. post.sh already contains `sudo npm install` commands that need this fix
4. No need to create additional scripts or modify devcontainer.json

### Architecture

```
.devcontainer/scripts/post.sh
    └── setup_sudo_path() function (added early in script)
        └── Detects nvm bin path dynamically
        └── Creates /etc/sudoers.d/nvm-path with correct secure_path
        └── Sets proper permissions (0440)
    └── Existing functions now work with sudo npm
```

### File Changes

| File | Change |
|------|--------|
| `.devcontainer/scripts/post.sh` | Add `setup_sudo_path()` function |

### Script Logic

```bash
#!/bin/bash
# setup-sudo-path.sh

# Get nvm bin path dynamically
NVM_BIN=$(dirname "$(which node 2>/dev/null)" 2>/dev/null)

if [ -n "$NVM_BIN" ] && [ -d "$NVM_BIN" ]; then
    # Get current secure_path or use default
    CURRENT_SECURE_PATH=$(sudo grep -oP 'secure_path="\K[^"]+' /etc/sudoers 2>/dev/null || echo "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")

    # Add nvm path if not already present
    if [[ "$CURRENT_SECURE_PATH" != *"$NVM_BIN"* ]]; then
        echo "Defaults secure_path=\"$NVM_BIN:$CURRENT_SECURE_PATH\"" | sudo tee /etc/sudoers.d/nvm-path > /dev/null
        sudo chmod 0440 /etc/sudoers.d/nvm-path
    fi
fi
```

### Security Considerations

1. **sudoers.d permissions**: File must be 0440 (read-only for root and sudoers group)
2. **Validation**: Use `visudo -c` to validate syntax before applying
3. **Idempotency**: Script checks if path already exists before adding

## Testing Strategy

1. **Unit Test**: Verify script creates correct sudoers.d file
2. **Integration Test**: Rebuild devcontainer and verify `sudo npm -v` works
3. **Regression Test**: Ensure existing sudo functionality is not affected

## Rollback Plan

If issues occur, remove the sudoers.d file:

```bash
sudo rm /etc/sudoers.d/nvm-path
```

## Future Considerations

- Other language runtimes (bun, deno) may need similar treatment
- Consider a more generic approach for adding paths to secure_path
