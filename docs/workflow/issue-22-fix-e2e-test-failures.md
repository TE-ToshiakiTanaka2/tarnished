# Workflow Document: Fix E2E Test Failures

**Issue**: #22 - Fix E2E test failures for Node.js template and Playwright option
**Design**: `docs/design/issue-22-fix-e2e-test-failures.md`

## Implementation Phases

### Phase 1: Test Infrastructure Update

**Files**: `tests/helpers/docker.bash`

**Tasks**:
1. Add `check_devcontainer_cli()` function
2. Add `start_devcontainer()` function
3. Add `exec_in_devcontainer()` function
4. Add `cleanup_devcontainer()` function
5. Add `verify_devcontainer_command()` function
6. Add `get_devcontainer_command_version()` function

**Commit**: `feat(tests): add devcontainer CLI helper functions`

---

### Phase 2: Template Updates

**Files**:
- `templates/node/.devcontainer/devcontainer.json`
- `templates/playwright/playwright.config.mjs` (new)
- `templates/playwright/plugin.sh`

**Tasks**:

#### 2.1 Node.js Template
1. Add Bun feature to devcontainer.json

**Commit**: `feat(node): add Bun feature to devcontainer.json`

#### 2.2 Playwright Plugin
1. Create `playwright.config.mjs` with standard configuration
2. Update `plugin.sh` to copy config file in `plugin_post_copy()`

**Commit**: `feat(playwright): add playwright.config.mjs and update plugin`

---

### Phase 3: E2E Test Updates

**Files**:
- `tests/e2e/test_node_template.bats`
- `tests/e2e/test_playwright_option.bats`

**Tasks**:

#### 3.1 Node.js Template Tests
1. Add devcontainer CLI availability check in `setup()`
2. Create `create_node_devcontainer()` helper using devcontainer CLI
3. Update all tests to use devcontainer CLI functions
4. Update `teardown()` for devcontainer cleanup

#### 3.2 Playwright Option Tests
1. Add devcontainer CLI availability check in `setup()`
2. Create `create_playwright_devcontainer()` helper
3. Update all tests to use devcontainer CLI functions
4. Update `teardown()` for devcontainer cleanup

**Commit**: `fix(tests): update E2E tests to use devcontainer CLI`

---

### Phase 4: Verification

**Tasks**:
1. Run `make test-e2e` and verify all 17 tests pass
2. Run `shellcheck` on modified shell scripts
3. Manual verification of generated project

**Commit**: N/A (verification only)

---

## Task Checklist

### Phase 1: Test Infrastructure
- [ ] Add `check_devcontainer_cli()` to docker.bash
- [ ] Add `start_devcontainer()` to docker.bash
- [ ] Add `exec_in_devcontainer()` to docker.bash
- [ ] Add `cleanup_devcontainer()` to docker.bash
- [ ] Add `verify_devcontainer_command()` to docker.bash
- [ ] Add `get_devcontainer_command_version()` to docker.bash

### Phase 2: Template Updates
- [ ] Add Bun feature to `templates/node/.devcontainer/devcontainer.json`
- [ ] Create `templates/playwright/playwright.config.mjs`
- [ ] Update `templates/playwright/plugin.sh` to copy config file

### Phase 3: E2E Test Updates
- [ ] Update `test_node_template.bats` setup/teardown
- [ ] Update `test_node_template.bats` test cases
- [ ] Update `test_playwright_option.bats` setup/teardown
- [ ] Update `test_playwright_option.bats` test cases

### Phase 4: Verification
- [ ] `make test-e2e` passes all tests
- [ ] `shellcheck` passes on all modified scripts
- [ ] Manual project generation verification

---

## Dependency Graph

```
Phase 1: docker.bash helpers
         │
         ├──────────────────┐
         │                  │
         ▼                  ▼
Phase 2a: Node.js     Phase 2b: Playwright
template update        plugin update
         │                  │
         └──────────────────┤
                           │
                           ▼
              Phase 3: E2E test updates
                           │
                           ▼
              Phase 4: Verification
```

---

## Critical Path

1. **docker.bash** must be updated first (all E2E tests depend on it)
2. **Template updates** can be done in parallel
3. **E2E tests** must be updated after both helpers and templates are ready
4. **Verification** is the final step

---

## Rollback Considerations

If E2E tests still fail after implementation:

1. Check devcontainer CLI output for errors
2. Verify Docker-in-Docker is working correctly
3. Check feature installation logs in devcontainer
4. Consider increasing timeouts for container startup

If devcontainer CLI is unavailable:
- Tests will be skipped with appropriate message
- Document manual testing procedure
