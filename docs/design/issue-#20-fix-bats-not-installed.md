# Design Document: Fix bats-core Installation in Devcontainer

**Issue**: #20
**Type**: Bugfix
**Milestone**: core

## Overview

This document outlines the design for fixing the `bats: not found` error when running `make test-e2e` in the devcontainer environment.

## Problem Statement

When executing `make test-e2e` in devcontainer, users encounter:

```
/bin/sh: 2: bats: not found
make: *** [Makefile:48: test-e2e] Error 127
```

**Root Cause**: bats-core is not installed during devcontainer setup, although bats helper libraries (bats-support, bats-assert, bats-file) exist as git submodules.

## Architecture

### Current State

```
devcontainer startup
    │
    ▼
post.sh executes
    │
    ├── Git config setup
    ├── SSH config setup
    ├── SuperClaude setup
    └── Git submodules init ← bats helpers only

make test-e2e
    │
    ▼
bats command ← NOT FOUND (Error)
```

### Target State

```
devcontainer startup
    │
    ▼
post.sh executes
    │
    ├── Git config setup
    ├── SSH config setup
    ├── SuperClaude setup
    ├── Bats-core installation ← NEW
    └── Git submodules init

make test-e2e
    │
    ▼
Makefile dependency check ← NEW (fallback)
    │
    ├── bats exists? → if not, install
    └── submodules init? → if not, init
    │
    ▼
bats command executes ← SUCCESS
```

## Component Design

### 1. post.sh Changes

**Location**: `.devcontainer/scripts/post.sh`

**New Function**: `setup_bats()`

```bash
setup_bats() {
    echo "Setting up Bats test framework..."

    if command -v bats >/dev/null 2>&1; then
        echo "  - Bats already installed: $(bats --version)"
        return 0
    fi

    echo "  - Installing bats-core..."
    sudo apt-get update && sudo apt-get install -y bats
    echo "  - Bats installed: $(bats --version)"
}
```

**Integration Point**: After SuperClaude setup, before git submodules initialization.

### 2. Makefile Changes

**Location**: `Makefile`

**New Target**: `ensure-test-deps`

This target checks and installs test dependencies if missing:
- bats command availability
- git submodules initialization status

**Integration**: Test targets (test-unit, test-integration, test-e2e) will depend on `ensure-test-deps`.

### Dependency Flow

```
test-unit ─────┐
               │
test-integration ──┼──► ensure-test-deps ──► (install if needed)
               │
test-e2e ──────┘
```

## File Changes

| File | Change Type | Description |
|------|-------------|-------------|
| `.devcontainer/scripts/post.sh` | Modify | Add bats-core installation |
| `Makefile` | Modify | Add dependency check target |

## Test Strategy

### Verification Steps

1. **post.sh verification**:
   - Rebuild devcontainer
   - Verify `bats --version` works immediately after startup

2. **Makefile fallback verification**:
   - Remove bats manually: `sudo apt-get remove bats`
   - Run `make test-e2e`
   - Verify bats is auto-installed and tests run

3. **Submodules check verification**:
   - Remove submodules: `rm -rf tests/libs/*`
   - Run `make test-unit`
   - Verify submodules are auto-initialized

## CI/CD Impact

**No impact on CI/CD**. GitHub Actions workflow (`.github/workflows/test.yml`) independently installs bats via `apt-get install bats`.

## Rollback Plan

If issues occur:
1. Revert post.sh changes
2. Users can manually run `make test-setup` as before
