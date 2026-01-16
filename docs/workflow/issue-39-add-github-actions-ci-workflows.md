# Implementation Workflow: GitHub Actions CI Workflows

**Issue**: #39
**Date**: 2026-01-16

## Phase Overview

| Phase | Description | Dependencies |
|-------|-------------|--------------|
| 1 | Python CI Implementation | None |
| 2 | Node.js CI Implementation | None |
| 3 | Integration Testing | Phase 1, 2 |
| 4 | Documentation | Phase 1, 2 |

## Phase 1: Python CI Implementation

### Step 1.1: Create pyproject.toml
- **File**: `templates/python/pyproject.toml`
- **Content**: uv-compatible project configuration with dev dependencies
- **Validation**: `uv sync` should work

### Step 1.2: Create python-ci.yml
- **File**: `templates/python/.github/workflows/python-ci.yml`
- **Jobs**: lint, unit-test, integration-test
- **Validation**: YAML syntax valid

### Step 1.3: Create Sample Tests
- **Files**:
  - `templates/python/tests/unit/test_sample.py`
  - `templates/python/tests/integration/test_sample_integration.py`
- **Validation**: Tests should pass with pytest

### Step 1.4: Update plugin.sh
- **File**: `templates/python/plugin.sh`
- **Changes**: Add copy logic for .github/, tests/, pyproject.toml
- **Validation**: shellcheck passes

### Step 1.5: Commit
```bash
git add templates/python/
git commit -m "✨ feat(python): add GitHub Actions CI workflow template (#39)"
```

## Phase 2: Node.js CI Implementation

### Step 2.1: Create package.json
- **File**: `templates/node/package.json`
- **Content**: pnpm-compatible with scripts and devDependencies
- **Validation**: `pnpm install` should work

### Step 2.2: Create biome.json
- **File**: `templates/node/biome.json`
- **Content**: Biome linter/formatter configuration
- **Validation**: JSON syntax valid

### Step 2.3: Create tsconfig.json
- **File**: `templates/node/tsconfig.json`
- **Content**: TypeScript compiler configuration
- **Validation**: JSON syntax valid

### Step 2.4: Create vitest.config.ts
- **File**: `templates/node/vitest.config.ts`
- **Content**: Vitest test configuration
- **Validation**: TypeScript syntax valid

### Step 2.5: Create node-ci.yml
- **File**: `templates/node/.github/workflows/node-ci.yml`
- **Jobs**: lint, unit-test, integration-test
- **Validation**: YAML syntax valid

### Step 2.6: Create Sample Tests
- **Files**:
  - `templates/node/tests/unit/sample.test.ts`
  - `templates/node/tests/integration/sample.integration.test.ts`
- **Validation**: Tests should pass with vitest

### Step 2.7: Update plugin.sh
- **File**: `templates/node/plugin.sh`
- **Changes**: Add copy logic for all new files
- **Validation**: shellcheck passes

### Step 2.8: Commit
```bash
git add templates/node/
git commit -m "✨ feat(node): add GitHub Actions CI workflow template (#39)"
```

## Phase 3: Integration Testing

### Step 3.1: Validate YAML Syntax
```bash
# Install actionlint if needed
actionlint templates/python/.github/workflows/python-ci.yml
actionlint templates/node/.github/workflows/node-ci.yml
```

### Step 3.2: Shell Script Validation
```bash
shellcheck templates/python/plugin.sh
shellcheck templates/node/plugin.sh
```

### Step 3.3: Dry Run Test
```bash
# Test setup.sh with Python template
./setup.sh --dry-run --lang python

# Test setup.sh with Node.js template
./setup.sh --dry-run --lang node
```

## Phase 4: Documentation

### Step 4.1: Commit Design & Workflow Docs
```bash
git add docs/
git commit -m "📝 docs: add design and workflow documents for CI workflows (#39)"
```

## Task Checklist

### Python CI
- [ ] `templates/python/pyproject.toml`
- [ ] `templates/python/.github/workflows/python-ci.yml`
- [ ] `templates/python/tests/unit/test_sample.py`
- [ ] `templates/python/tests/integration/test_sample_integration.py`
- [ ] `templates/python/plugin.sh` (update)

### Node.js CI
- [ ] `templates/node/package.json`
- [ ] `templates/node/biome.json`
- [ ] `templates/node/tsconfig.json`
- [ ] `templates/node/vitest.config.ts`
- [ ] `templates/node/.github/workflows/node-ci.yml`
- [ ] `templates/node/tests/unit/sample.test.ts`
- [ ] `templates/node/tests/integration/sample.integration.test.ts`
- [ ] `templates/node/plugin.sh` (update)

### Validation
- [ ] actionlint passes
- [ ] shellcheck passes
- [ ] All JSON/YAML files valid

## Critical Path

```
Python CI ──────────────────────────┐
                                    ├──▶ Integration Testing ──▶ Done
Node.js CI ─────────────────────────┘
```

Python and Node.js implementations can proceed in parallel.
