# Design Document: Fix E2E Test Failures

**Issue**: #22 - Fix E2E test failures for Node.js template and Playwright option
**Type**: Bugfix
**Milestone**: core

## Problem Statement

E2E tests for Node.js template and Playwright option are failing because:

1. Tests use `docker build` directly, which doesn't apply Devcontainer features
2. Node.js, npm, and bun are installed via Devcontainer features only
3. Playwright plugin lacks `playwright.config.mjs` file

### Failing Tests (6 total)

| Test | Error |
|------|-------|
| `e2e/node: node is available in container` | executable not found in $PATH |
| `e2e/node: npm is available in container` | executable not found in $PATH |
| `e2e/node: bun is available in container` | executable not found in $PATH |
| `e2e/node: node version is available` | executable not found in $PATH |
| `e2e/playwright: playwright config file exists` | file not found |
| `e2e/playwright: npx playwright is available` | executable not found in $PATH |

## Architecture Overview

### Current Test Flow (Broken)

```
setup.sh generates project
         │
         ▼
┌─────────────────────────┐
│ docker build            │  ← Only builds base image
│ Dockerfile.dev          │  ← No features applied
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│ docker run              │
│ docker exec             │  ← Missing: node, npm, bun
└─────────────────────────┘
         │
         ▼
    ❌ Tests fail
```

### New Test Flow (Fixed)

```
setup.sh generates project
         │
         ▼
┌─────────────────────────┐
│ devcontainer up         │  ← Builds with features
│ --workspace-folder      │  ← Node.js, npm, bun installed
└─────────────────────────┘
         │
         ▼
┌─────────────────────────┐
│ devcontainer exec       │
│ --workspace-folder      │  ← All tools available
└─────────────────────────┘
         │
         ▼
    ✅ Tests pass
```

## Component Design

### 1. Test Helper Functions (`tests/helpers/docker.bash`)

Add new devcontainer CLI helper functions:

```bash
# Check if devcontainer CLI is available
check_devcontainer_cli() {
    command -v devcontainer &>/dev/null
}

# Build and start devcontainer
# Args: $1 = workspace folder path
# Returns: container ID via E2E_CONTAINER_ID
start_devcontainer() {
    local workspace_folder="$1"
    devcontainer up --workspace-folder "${workspace_folder}" \
        --remove-existing-container
}

# Execute command in devcontainer
# Args: $1 = workspace folder, $2 = command
exec_in_devcontainer() {
    local workspace_folder="$1"
    shift
    devcontainer exec --workspace-folder "${workspace_folder}" "$@"
}

# Stop and clean up devcontainer
# Args: $1 = workspace folder
cleanup_devcontainer() {
    local workspace_folder="$1"
    # Get container ID and stop/remove
    local container_id
    container_id=$(devcontainer up --workspace-folder "${workspace_folder}" \
        --expect-existing-container 2>/dev/null | jq -r '.containerId // empty')
    if [[ -n "${container_id}" ]]; then
        docker stop "${container_id}" 2>/dev/null || true
        docker rm -f "${container_id}" 2>/dev/null || true
    fi
}

# Verify command exists in devcontainer
# Args: $1 = workspace folder, $2 = command name
verify_devcontainer_command() {
    local workspace_folder="$1"
    local cmd="$2"
    exec_in_devcontainer "${workspace_folder}" which "${cmd}"
}

# Get command version in devcontainer
# Args: $1 = workspace folder, $2 = command name
get_devcontainer_command_version() {
    local workspace_folder="$1"
    local cmd="$2"
    exec_in_devcontainer "${workspace_folder}" "${cmd}" --version
}
```

### 2. Node.js Template (`templates/node/.devcontainer/devcontainer.json`)

Add Bun feature:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "22"
    },
    "ghcr.io/shyim/devcontainers-features/bun:latest": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode"
      ]
    }
  }
}
```

Note: Using `ghcr.io/shyim/devcontainers-features/bun` which is a well-maintained community feature.

### 3. Playwright Plugin

#### 3.1 Configuration File (`templates/playwright/playwright.config.mjs`)

```javascript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
```

#### 3.2 Plugin Update (`templates/playwright/plugin.sh`)

Add config file copy to `plugin_post_copy()`:

```bash
plugin_post_copy() {
    local target_dir="$1"

    # Copy playwright.config.mjs
    if [[ -f "${PLUGIN_DIR}/playwright.config.mjs" ]]; then
        cp "${PLUGIN_DIR}/playwright.config.mjs" "${target_dir}/"
        print_success "Playwright config file copied"
    fi

    # Existing devcontainer.json merge logic...
}
```

### 4. E2E Test Updates

#### 4.1 `test_node_template.bats`

Key changes:
- Add `skip` if devcontainer CLI unavailable
- Replace `docker build` with `devcontainer up`
- Replace `docker exec` with `devcontainer exec`
- Update cleanup to use devcontainer cleanup

#### 4.2 `test_playwright_option.bats`

Same pattern as Node.js tests.

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `tests/helpers/docker.bash` | Modify | Add devcontainer CLI helper functions |
| `tests/e2e/test_node_template.bats` | Modify | Use devcontainer CLI instead of docker |
| `tests/e2e/test_playwright_option.bats` | Modify | Use devcontainer CLI instead of docker |
| `templates/node/.devcontainer/devcontainer.json` | Modify | Add Bun feature |
| `templates/playwright/playwright.config.mjs` | Create | New Playwright config file |
| `templates/playwright/plugin.sh` | Modify | Copy config file in post_copy |

## Test Strategy

### Unit Tests
- Existing helper function tests should continue to pass
- New devcontainer helper functions are integration-tested via E2E

### E2E Tests
After fix, all 17 tests should pass:
- 11 Node.js template tests
- 6 Playwright option tests

### Verification Steps
1. `make test-e2e` passes all tests
2. Manual verification: `setup.sh --lang node --playwright -y test-project`
3. Generated project opens successfully in VS Code devcontainer

## Dependencies

- devcontainer CLI (`@devcontainers/cli`) - already installed in devcontainer
- Docker-in-Docker support - added in PR #19

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| devcontainer CLI not available | Skip tests with informative message |
| Increased test execution time | Accept trade-off for accurate testing |
| Bun feature version changes | Use `:latest` tag for automatic updates |

## Rollback Plan

If issues arise:
1. Revert to previous docker-based tests
2. Mark feature-dependent tests as `skip`
3. Document manual testing requirements
