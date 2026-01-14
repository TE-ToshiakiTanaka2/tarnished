# Implementation Workflow: Shell Script Testing Infrastructure

**Issue**: #15 - Add Shell script testing infrastructure with Bats (Unit/Integration/E2E)
**Milestone**: core
**Author**: Claude Code
**Created**: 2026-01-14

## Implementation Phases

### Phase 1: Test Infrastructure Foundation

**Priority**: High
**Dependencies**: None

#### Tasks

1. **Create directory structure**
   - Create `tests/` directory with subdirectories
   - Create `tests/unit/`, `tests/integration/`, `tests/e2e/`
   - Create `tests/fixtures/`, `tests/helpers/`
   - Create `tests/libs/` for Bats libraries

2. **Setup Bats libraries as submodules**
   ```bash
   git submodule add https://github.com/bats-core/bats-support tests/libs/bats-support
   git submodule add https://github.com/bats-core/bats-assert tests/libs/bats-assert
   git submodule add https://github.com/bats-core/bats-file tests/libs/bats-file
   ```

3. **Create common helper (tests/helpers/common.bash)**
   - `load_setup_functions()` - Source setup.sh for testing
   - `load_common_functions()` - Source common.sh for testing
   - `setup_temp_dir()` / `teardown_temp_dir()` - Temp directory management
   - `get_project_root()` - Get project root path

4. **Create Makefile with test targets**
   - `test-setup` - Install/verify bats
   - `test-unit` - Run unit tests
   - `test-integration` - Run integration tests
   - `test-e2e` - Run E2E tests
   - `test` - Run unit + integration
   - `test-all` - Run all tests

**Commit**: `✨ feat(tests): add test infrastructure foundation with Bats`

---

### Phase 2: Unit Tests Implementation

**Priority**: High
**Dependencies**: Phase 1

#### Tasks

1. **Create test fixtures**
   - `tests/fixtures/valid_project_names.txt`
   - `tests/fixtures/invalid_project_names.txt`
   - `tests/fixtures/sample_json/` with test JSON files

2. **Implement pure function tests (setup.sh)**
   - `tests/unit/test_validate_project_name.bats`
   - `tests/unit/test_parse_language_list.bats`
   - `tests/unit/test_get_language_display_name.bats`
   - `tests/unit/test_validate_languages.bats`

3. **Implement pure function tests (common.sh)**
   - `tests/unit/test_merge_json_files.bats`

4. **Implement output function tests (common.sh)**
   - `tests/unit/test_print_functions.bats`

**Commit**: `✅ test(unit): add unit tests for pure and output functions`

---

### Phase 3: Integration Tests Implementation

**Priority**: Medium
**Dependencies**: Phase 1, Phase 2

#### Tasks

1. **Create mock helper (tests/helpers/mock.bash)**
   - Mock functions for interactive prompts
   - Mock functions for file operations
   - Hook call tracking

2. **Implement integration tests**
   - `tests/integration/test_plugin_loading.bats`
   - `tests/integration/test_setup_flow.bats`

**Commit**: `✅ test(integration): add integration tests for setup.sh flow`

---

### Phase 4: E2E Tests Implementation

**Priority**: Medium
**Dependencies**: Phase 1, Phase 2, Phase 3

#### Tasks

1. **Create Docker helper (tests/helpers/docker.bash)**
   - `build_test_project()` - Build Docker image from generated project
   - `start_container()` - Start container
   - `stop_container()` - Stop and cleanup
   - `exec_in_container()` - Execute commands
   - `verify_command_exists()` - Check command availability

2. **Implement E2E tests**
   - `tests/e2e/test_python_template.bats`
   - `tests/e2e/test_node_template.bats`
   - `tests/e2e/test_rust_template.bats`
   - `tests/e2e/test_deno_template.bats`
   - `tests/e2e/test_playwright_option.bats`

**Commit**: `✅ test(e2e): add E2E tests for all language templates`

---

### Phase 5: GitHub Actions CI Setup

**Priority**: High
**Dependencies**: Phase 1, Phase 2, Phase 3

#### Tasks

1. **Create CI workflow**
   - `.github/workflows/test.yml`
   - Trigger: push to main/develop, PR
   - Steps: checkout, install bats, run unit tests, run integration tests

2. **Verify CI configuration**
   - Test workflow syntax with actionlint
   - Verify bats installation in CI

**Commit**: `👷 ci: add GitHub Actions workflow for shell script tests`

---

## Task Breakdown Summary

| Phase | Task | Priority | Estimated Complexity |
|-------|------|----------|---------------------|
| 1 | Directory structure | High | Low |
| 1 | Bats submodules | High | Low |
| 1 | Common helper | High | Medium |
| 1 | Makefile | High | Medium |
| 2 | Test fixtures | High | Low |
| 2 | Pure function tests (setup.sh) | High | Medium |
| 2 | Pure function tests (common.sh) | High | Medium |
| 2 | Output function tests | High | Low |
| 3 | Mock helper | Medium | Medium |
| 3 | Integration tests | Medium | High |
| 4 | Docker helper | Medium | Medium |
| 4 | E2E tests | Medium | High |
| 5 | GitHub Actions workflow | High | Medium |

## Critical Path

```
Phase 1 (Foundation)
    ↓
Phase 2 (Unit Tests) → Phase 5 (CI)
    ↓
Phase 3 (Integration Tests)
    ↓
Phase 4 (E2E Tests)
```

## Rollback Considerations

- Each phase is independently committable
- Tests can be disabled in CI if issues arise
- E2E tests are isolated (local only)
- No changes to existing production code

## Testing Strategy Per Phase

| Phase | Test Method |
|-------|-------------|
| 1 | Manual verification of directory structure, `make test-setup` |
| 2 | `make test-unit` - all unit tests pass |
| 3 | `make test-integration` - all integration tests pass |
| 4 | `make test-e2e` - all E2E tests pass (local) |
| 5 | GitHub Actions workflow runs successfully |

## Success Criteria

- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] All E2E tests pass (local execution)
- [ ] GitHub Actions CI passes
- [ ] Makefile targets work correctly
- [ ] Documentation is complete
