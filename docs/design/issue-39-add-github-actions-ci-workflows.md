# Design Document: GitHub Actions CI Workflows for Language Templates

**Issue**: #39
**Date**: 2026-01-16
**Status**: Draft

## Overview

Add GitHub Actions CI workflow templates for Python and Node.js language templates. These workflows will be copied to user projects via `setup.sh` and provide immediate CI/CD capabilities.

## Architecture

### Component Structure

```
templates/
├── python/
│   ├── .github/
│   │   └── workflows/
│   │       └── python-ci.yml      # CI workflow
│   ├── tests/
│   │   ├── unit/
│   │   │   └── test_sample.py     # Sample unit test
│   │   └── integration/
│   │       └── test_sample_integration.py  # Sample integration test
│   ├── pyproject.toml             # NEW: uv project config
│   ├── plugin.sh                  # UPDATE: add copy logic
│   ├── ruff.toml                  # EXISTING
│   ├── mypy.ini                   # EXISTING
│   └── pytest.ini                 # EXISTING
│
└── node/
    ├── .github/
    │   └── workflows/
    │       └── node-ci.yml        # CI workflow
    ├── tests/
    │   ├── unit/
    │   │   └── sample.test.ts     # Sample unit test
    │   └── integration/
    │       └── sample.integration.test.ts  # Sample integration test
    ├── package.json               # NEW: pnpm project config
    ├── biome.json                 # NEW: Biome config
    ├── tsconfig.json              # NEW: TypeScript config
    ├── vitest.config.ts           # NEW: Vitest config
    └── plugin.sh                  # UPDATE: add copy logic
```

### Workflow Trigger Design

```yaml
# Common trigger pattern for both languages
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]
```

### Job Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                        CI Workflow Jobs                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐                                               │
│  │    lint      │  Always runs                                  │
│  │  (parallel)  │  - Linter check                               │
│  │              │  - Formatter check                            │
│  │              │  - Type check                                 │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │  unit-test   │  Always runs (needs: lint)                    │
│  │              │  - Run tests/unit/*                           │
│  └──────────────┘                                               │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────┐                                               │
│  │ integration  │  Only on push to main/develop                 │
│  │    -test     │  - Run tests/integration/*                    │
│  └──────────────┘                                               │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## File Specifications

### Python Files

#### pyproject.toml
```toml
[project]
name = "my-project"
version = "0.1.0"
requires-python = ">=3.12"

[tool.uv]
dev-dependencies = [
    "ruff>=0.8.0",
    "mypy>=1.14.0",
    "pytest>=8.3.0",
    "pytest-cov>=6.0.0",
]
```

#### python-ci.yml
- **lint job**: ruff check, ruff format --check, mypy
- **unit-test job**: pytest tests/unit -v --cov
- **integration-test job**: pytest tests/integration -v (conditional)

### Node.js Files

#### package.json
```json
{
  "name": "my-project",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format .",
    "format:fix": "biome format --write .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:unit": "vitest run tests/unit",
    "test:integration": "vitest run tests/integration",
    "test:watch": "vitest"
  },
  "devDependencies": {
    "@biomejs/biome": "^1.9.0",
    "typescript": "^5.7.0",
    "vitest": "^2.1.0"
  }
}
```

#### biome.json
- Linter rules: recommended
- Formatter: indent 2 spaces, single quotes
- Organize imports: enabled

#### tsconfig.json
- Target: ES2022
- Module: NodeNext
- Strict mode enabled

#### vitest.config.ts
- Test include: tests/**/*.test.ts
- Coverage: v8 provider

#### node-ci.yml
- **lint job**: biome check, tsc --noEmit
- **unit-test job**: pnpm test:unit
- **integration-test job**: pnpm test:integration (conditional)

## Plugin.sh Updates

### Python plugin.sh
Add to `plugin_post_copy()`:
1. Copy `.github/workflows/` directory (merge if exists)
2. Copy `tests/` directory structure (skip if exists)
3. Copy `pyproject.toml` (skip if exists)

### Node.js plugin.sh
Add to `plugin_post_copy()`:
1. Copy `.github/workflows/` directory (merge if exists)
2. Copy `tests/` directory structure (skip if exists)
3. Copy config files: `package.json`, `biome.json`, `tsconfig.json`, `vitest.config.ts`

## Test Strategy

### Sample Test Content

**Python Unit Test**: Simple function test demonstrating pytest usage
**Python Integration Test**: Multi-module interaction test (placeholder)
**Node.js Unit Test**: Simple function test demonstrating Vitest usage
**Node.js Integration Test**: Async operation test (placeholder)

### CI Validation
- Workflows should pass with sample tests
- Integration tests conditional on push events only

## Dependencies

### Python
- Python 3.12+
- uv (package manager)
- ruff, mypy, pytest (dev tools)

### Node.js
- Node.js 22.x (LTS)
- pnpm 9.x
- Biome, TypeScript, Vitest (dev tools)

## Rollback Considerations

- All changes are additive (new files/directories)
- plugin.sh updates use skip-if-exists pattern
- No breaking changes to existing functionality
