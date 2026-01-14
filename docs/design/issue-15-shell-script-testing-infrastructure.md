# Design Document: Shell Script Testing Infrastructure

**Issue**: #15 - Add Shell script testing infrastructure with Bats (Unit/Integration/E2E)
**Milestone**: core
**Author**: Claude Code
**Created**: 2026-01-14

## Overview

This document describes the architecture and design for implementing a comprehensive testing infrastructure for Shell scripts in the Devcontainer boilerplate project.

## Architecture

### Test Layer Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Test Infrastructure                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐    ┌───────────────┐    ┌─────────────────┐  │
│  │   Unit   │    │  Integration  │    │      E2E        │  │
│  │  Tests   │    │    Tests      │    │     Tests       │  │
│  ├──────────┤    ├───────────────┤    ├─────────────────┤  │
│  │ Pure     │    │ setup.sh flow │    │ Docker env      │  │
│  │ Functions│    │ (with mocks)  │    │ Devcontainer    │  │
│  │ Output   │    │               │    │                 │  │
│  │ Functions│    │               │    │                 │  │
│  └────┬─────┘    └───────┬───────┘    └────────┬────────┘  │
│       │                  │                      │           │
│       └──────────┬───────┘                      │           │
│                  │                              │           │
│           ┌──────▼──────┐              ┌───────▼───────┐   │
│           │   CI (GHA)  │              │  Local Only   │   │
│           │ main/develop│              │  make e2e     │   │
│           │     PR      │              └───────────────┘   │
│           └─────────────┘                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Component Overview

| Layer | Purpose | Execution Environment |
|-------|---------|----------------------|
| Unit | Individual function testing | CI + Local |
| Integration | setup.sh full flow (mocked) | CI + Local |
| E2E | Real Devcontainer verification | Local only |

## Directory Structure

```
tests/
├── unit/                              # Unit tests
│   ├── test_validate_project_name.bats
│   ├── test_parse_language_list.bats
│   ├── test_get_language_display_name.bats
│   ├── test_validate_languages.bats
│   ├── test_merge_json_files.bats
│   └── test_print_functions.bats
├── integration/                       # Integration tests
│   ├── test_plugin_loading.bats
│   └── test_setup_flow.bats
├── e2e/                              # E2E tests
│   ├── test_python_template.bats
│   ├── test_node_template.bats
│   ├── test_rust_template.bats
│   ├── test_deno_template.bats
│   └── test_playwright_option.bats
├── fixtures/                          # Test data
│   ├── valid_project_names.txt
│   ├── invalid_project_names.txt
│   └── sample_json/
│       ├── base.json
│       └── overlay.json
└── helpers/                           # Test utilities
    ├── common.bash                    # Common helpers
    ├── mock.bash                      # Mock functions
    └── docker.bash                    # Docker operations

.github/workflows/
└── test.yml                           # CI configuration

Makefile                               # Test execution commands
```

## Test Framework

### Bats (Bash Automated Testing System)

- **Core**: `bats-core` - Main testing framework
- **Helper Libraries**:
  - `bats-support` - Basic assertion helpers
  - `bats-assert` - `assert_success`, `assert_output`, etc.
  - `bats-file` - File existence and directory operations

### Installation Strategy

Libraries will be installed as git submodules in `tests/libs/`:

```
tests/libs/
├── bats-support/
├── bats-assert/
└── bats-file/
```

## Test Targets

### Unit Tests

#### Pure Functions (setup.sh)

| Function | Test Cases |
|----------|------------|
| `validate_project_name` | Valid names, invalid names (spaces, special chars, empty) |
| `parse_language_list` | Single language, multiple languages, empty input |
| `get_language_display_name` | Known languages, unknown languages |
| `validate_languages` | Valid list, invalid language, mixed |

#### Pure Functions (common.sh)

| Function | Test Cases |
|----------|------------|
| `merge_json_files` | Merge objects, merge arrays, nested objects |

#### Output Functions (common.sh)

| Function | Test Cases |
|----------|------------|
| `print_success` | Correct color code (green), format |
| `print_error` | Correct color code (red), format |
| `print_warning` | Correct color code (yellow), format |
| `print_info` | Correct color code (blue), format |

### Integration Tests

| Test | Description |
|------|-------------|
| Plugin Loading | Load plugin → verify functions available |
| Setup Flow | Full setup.sh flow with mocked user input |

### E2E Tests

| Test | Verification |
|------|--------------|
| Python Template | docker build, container up, post.sh, python/pip/uv commands |
| Node Template | docker build, container up, post.sh, node/npm/bun commands |
| Rust Template | docker build, container up, post.sh, cargo/rustc commands |
| Deno Template | docker build, container up, post.sh, deno command |
| Playwright Option | playwright command available |

## Helper Functions Design

### common.bash

```bash
# Load source files for testing
load_setup_functions()     # Source setup.sh functions
load_common_functions()    # Source common.sh functions

# Temporary directory management
setup_temp_dir()           # Create temp directory
teardown_temp_dir()        # Clean up temp directory

# Test utilities
get_script_dir()           # Get test script directory
get_project_root()         # Get project root directory
```

### mock.bash

```bash
# Mock interactive functions
mock_prompt_project_name() # Return fixed project name
mock_prompt_language()     # Return fixed language selection
mock_prompt_playwright()   # Return fixed playwright choice

# Mock file operations (for integration tests)
mock_copy_template_dir()   # No-op or copy to temp
mock_execute_plugins_hook()# Track hook calls without execution
```

### docker.bash

```bash
# Docker operations for E2E
build_test_project()       # Run setup.sh and build Docker
start_container()          # Start container
stop_container()           # Stop and remove container
exec_in_container()        # Execute command in container
verify_command_exists()    # Check if command is available
```

## Makefile Targets

```makefile
# Test execution targets
test-unit        # Run unit tests only
test-integration # Run integration tests only
test-e2e         # Run E2E tests only (local)
test             # Run unit + integration (CI)
test-all         # Run all tests

# Setup targets
test-setup       # Install bats and helper libraries
test-clean       # Clean test artifacts

# CI targets
ci-test          # Run tests for CI (unit + integration)
```

## GitHub Actions Workflow

### Workflow Triggers

- Push to `main` or `develop`
- Pull Request to `main` or `develop`

### Workflow Steps

1. Checkout repository
2. Install Bats and helper libraries
3. Run unit tests
4. Run integration tests
5. Report results

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Test Framework | Bats | Widely used, good GitHub Actions integration |
| Helper Libraries | bats-support, bats-assert, bats-file | Standard assertion capabilities |
| Library Installation | Git submodules | Version control, no external dependencies |
| E2E Execution | Local only | Time-consuming, not suitable for CI |
| Coverage | Not initially | Complex setup, defer to later |
| Integration Mocking | File generation only | Test actual logic, mock I/O |

## Security Considerations

- E2E tests run in isolated Docker containers
- No production credentials or sensitive data in tests
- Test fixtures contain only sample/mock data

## Future Enhancements

- Code coverage with `kcov`
- Parallel test execution
- Test result caching
- Performance benchmarking
