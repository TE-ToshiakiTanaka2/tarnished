# Design Document: Issue #5 - Improve post.sh Interactive Setup

## Overview

Improve the `post.sh` script's handling of `.gitconfig.local` and `.ssh/host_config` creation with interactive user prompts and conditional logic based on ssh-agent availability.

## Architecture

### Component Structure

```
post.sh
├── Git Configuration Section
│   ├── setup_gitconfig_local()     # NEW: Interactive .gitconfig.local setup
│   │   ├── Check file existence (idempotency)
│   │   ├── Check existing git config values
│   │   ├── Prompt for user.name (if not set)
│   │   ├── Prompt for user.email (if not set)
│   │   └── Write .gitconfig.local (if values provided)
│   └── Existing git config include logic
│
└── SSH Configuration Section
    ├── setup_ssh_host_config()     # NEW: Conditional host_config setup
    │   ├── Check file existence (idempotency)
    │   ├── Check SSH agent connectivity
    │   ├── Handle connection results
    │   └── Prompt for creation (if needed)
    └── Existing SSH directory setup
```

### Flow Diagrams

#### .gitconfig.local Setup Flow

```
┌─────────────────────────────────────┐
│ setup_gitconfig_local()             │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Does $HOME/.gitconfig.local exist?  │
└─────────────────┬───────────────────┘
                  │
        ┌─────────┴─────────┐
        │ YES               │ NO
        ▼                   ▼
┌───────────────┐   ┌───────────────────────────┐
│ Skip (return) │   │ Check git config user.name│
└───────────────┘   └─────────────┬─────────────┘
                                  │
                        ┌─────────┴─────────┐
                        │ SET               │ NOT SET
                        ▼                   ▼
                ┌───────────────┐   ┌───────────────────────┐
                │ Skip name     │   │ Prompt: "Enter name"  │
                └───────────────┘   └─────────────┬─────────┘
                        │                         │
                        └──────────┬──────────────┘
                                   ▼
                    ┌───────────────────────────────┐
                    │ Check git config user.email   │
                    └─────────────┬─────────────────┘
                                  │
                        ┌─────────┴─────────┐
                        │ SET               │ NOT SET
                        ▼                   ▼
                ┌───────────────┐   ┌───────────────────────┐
                │ Skip email    │   │ Prompt: "Enter email" │
                └───────────────┘   └─────────────┬─────────┘
                        │                         │
                        └──────────┬──────────────┘
                                   ▼
                    ┌───────────────────────────────┐
                    │ Write .gitconfig.local        │
                    │ (only with provided values)   │
                    └───────────────────────────────┘
```

#### host_config Setup Flow

```
┌─────────────────────────────────────┐
│ setup_ssh_host_config()             │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│ Does $HOME/.ssh/host_config exist?  │
└─────────────────┬───────────────────┘
                  │
        ┌─────────┴─────────┐
        │ YES               │ NO
        ▼                   ▼
┌───────────────┐   ┌─────────────────────────────┐
│ Skip (return) │   │ ssh -T git@github.com       │
└───────────────┘   │ (10s timeout)               │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
                    ▼             ▼             ▼
            ┌───────────┐ ┌───────────┐ ┌─────────────────┐
            │ SUCCESS   │ │ AUTH FAIL │ │ NETWORK ERROR   │
            │ (exit 1)  │ │ (exit ≠1) │ │ (timeout/other) │
            └─────┬─────┘ └─────┬─────┘ └────────┬────────┘
                  │             │                │
                  ▼             ▼                ▼
            ┌───────────┐ ┌─────────────┐ ┌─────────────────┐
            │ No action │ │ Prompt:     │ │ Warning message │
            │ ssh-agent │ │ "Create     │ │ Continue setup  │
            │ working   │ │ host_config │ └─────────────────┘
            └───────────┘ │ ? [y/N]"    │
                          └──────┬──────┘
                                 │
                        ┌────────┴────────┐
                        │ y               │ N/empty
                        ▼                 ▼
                ┌───────────────┐ ┌───────────────┐
                │ Create        │ │ Skip          │
                │ host_config   │ │               │
                └───────────────┘ └───────────────┘
```

## File Modifications

### Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `.devcontainer/scripts/post.sh` | Modify | Main script - add interactive functions |
| `templates/core/.devcontainer/scripts/post.sh` | Modify | Template - same changes |

### Function Signatures

```bash
# Setup .gitconfig.local with interactive prompts
# Skips if file exists or if values already configured
setup_gitconfig_local() {
    # Implementation
}

# Setup SSH host_config conditionally based on ssh-agent status
# Skips if file exists
setup_ssh_host_config() {
    # Implementation
}
```

## Configuration

### Constants

```bash
SSH_TIMEOUT=10                    # SSH connection timeout in seconds
SSH_TEST_HOST="git@github.com"    # SSH test target
```

### Exit Codes

| Code | SSH Command Result | Meaning |
|------|-------------------|---------|
| 1 | Success | GitHub authentication successful (ssh-agent working) |
| 255 | Timeout/Network | Network error or timeout |
| Other | Auth failure | SSH key not available |

## Test Strategy

### Unit Tests

1. **File existence check**: Verify idempotency
2. **Git config check**: Verify existing config detection
3. **Interactive prompts**: Verify read command behavior
4. **SSH connection**: Verify timeout handling

### Integration Tests

1. **Fresh container**: Run full setup flow
2. **Rebuild container**: Verify skip behavior
3. **No ssh-agent**: Verify prompt appears

## Security Considerations

- No sensitive data stored in scripts
- SSH keys never written by script (only config template)
- User input properly quoted to prevent injection
