# Implementation Workflow: PostgreSQL Plugin

**Issue**: #30 - Add PostgreSQL plugin for database development environment
**Design Doc**: [docs/design/issue-#30-add-postgresql-plugin.md](../design/issue-#30-add-postgresql-plugin.md)
**Created**: 2026-01-14

## Workflow Overview

```
Phase 1: Plugin Structure    Phase 2: Setup Integration    Phase 3: Testing & Docs
──────────────────────────   ─────────────────────────────   ─────────────────────────
[1.1] Create directory       [2.1] Add --postgresql flag     [3.1] Run shellcheck
         ↓                            ↓                              ↓
[1.2] plugin.sh              [2.2] Update help text          [3.2] Dry-run test
         ↓                            ↓                              ↓
[1.3] docker-compose.yml     [2.3] Plugin loading            [3.3] E2E test
         ↓                            ↓                              ↓
[1.4] devcontainer.json      [2.4] Merge function            [3.4] Update README
         ↓
[1.5] .env.example & init/
```

## Phase 1: Plugin Structure Creation

### Task 1.1: Create Directory Structure

**Files to create**:
```
templates/postgresql/
├── plugin.sh
├── .devcontainer/
│   └── devcontainer.json
├── docker/
│   └── docker-compose.postgresql.yml
├── init/
│   └── .gitkeep
└── .env.example
```

**Commands**:
```bash
mkdir -p templates/postgresql/{.devcontainer,docker,init}
touch templates/postgresql/init/.gitkeep
```

### Task 1.2: Implement plugin.sh

**Requirements**:
- Implement `plugin_name()` → returns "postgresql"
- Implement `plugin_description()` → returns description
- Implement `plugin_post_copy()` → merges configurations

**Template**:
```bash
#!/bin/bash
# Plugin: postgresql

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

plugin_name() { echo "postgresql"; }
plugin_description() { echo "PostgreSQL database support"; }

plugin_post_copy() {
    local target_dir="$1"
    # 1. Merge docker-compose.yml
    # 2. Merge devcontainer.json
    # 3. Copy .env.example if needed
    # 4. Copy init/ directory
}
```

**Dependencies**: None
**Validation**: Source file and check functions exist

### Task 1.3: Create Docker Compose Configuration

**File**: `templates/postgresql/docker/docker-compose.postgresql.yml`

**Requirements**:
- PostgreSQL 17 image
- Named volume for data persistence
- Healthcheck with pg_isready
- Environment variables from .env
- Init scripts mount

**Validation**: `docker-compose config` syntax check

### Task 1.4: Create DevContainer JSON

**File**: `templates/postgresql/.devcontainer/devcontainer.json`

**Requirements**:
- Add `ckolkman.vscode-postgres` extension
- Minimal configuration (only extension)

**Validation**: JSON syntax check with jq

### Task 1.5: Create Environment Template

**File**: `templates/postgresql/.env.example`

**Content**:
```env
# PostgreSQL Configuration
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=app_development
```

**Validation**: File exists and contains required variables

---

## Phase 2: Setup.sh Integration

### Task 2.1: Add --postgresql CLI Flag

**File**: `setup.sh`

**Changes**:
1. Add `POSTGRESQL_ENABLED=false` variable
2. Add `--postgresql` case in argument parsing
3. Load postgresql plugin when enabled

**Location**: After `DOCKER_ENABLED=false` declaration

### Task 2.2: Update Help Text

**File**: `setup.sh` - `show_help()` function

**Changes**:
- Add `--postgresql` option description
- Add usage example with --postgresql

### Task 2.3: Update Plugin Loading

**File**: `setup.sh` - `load_selected_plugins()` function

**Changes**:
- Add postgresql plugin loading after docker plugin
- Follow pattern: docker → postgresql → playwright

### Task 2.4: Add Docker Compose Merge Function

**File**: `scripts/lib/common.sh`

**New Function**: `merge_docker_compose_services()`

**Purpose**: Merge PostgreSQL service into existing docker-compose.yml

**Algorithm**:
```
1. Read base docker-compose.yml
2. Read postgresql docker-compose.yml
3. Merge services section (add db service)
4. Merge volumes section (add postgres_data)
5. Write merged result
```

---

## Phase 3: Testing & Documentation

### Task 3.1: Run Shellcheck

**Commands**:
```bash
shellcheck templates/postgresql/plugin.sh
shellcheck setup.sh
shellcheck scripts/lib/common.sh
```

**Acceptance**: No errors or warnings

### Task 3.2: Dry-Run Test

**Commands**:
```bash
./setup.sh --lang node --postgresql --dry-run
./setup.sh --lang python --postgresql --dry-run
```

**Acceptance**: Preview shows PostgreSQL plugin loaded

### Task 3.3: E2E Test

**Test File**: `tests/e2e/postgresql.bats`

**Test Cases**:
1. Plugin loads correctly
2. Docker Compose merges correctly
3. .env.example copied when .env missing
4. devcontainer.json has PostgreSQL extension

### Task 3.4: Update README

**File**: `README.md`

**Changes**:
- Add PostgreSQL to optional features section
- Add usage example with --postgresql flag
- Document connection information

---

## Dependency Graph

```
1.1 ─┬─► 1.2 ─┬─► 2.1 ─► 2.2
     │        │
     ├─► 1.3 ─┤
     │        │
     ├─► 1.4 ─┘
     │
     └─► 1.5

2.1 ─► 2.3 ─► 2.4

1.2 ─┬─► 3.1
2.4 ─┘

3.1 ─► 3.2 ─► 3.3 ─► 3.4
```

## Critical Path

```
1.1 → 1.2 → 1.3 → 2.1 → 2.3 → 2.4 → 3.1 → 3.2 → 3.3
```

## Rollback Plan

If issues encountered:
1. Revert setup.sh changes: `git checkout setup.sh`
2. Revert common.sh changes: `git checkout scripts/lib/common.sh`
3. Remove plugin directory: `rm -rf templates/postgresql`

## Success Criteria

| Criteria | Validation |
|----------|------------|
| Plugin loads | `setup.sh --postgresql --dry-run` shows plugin |
| Docker Compose valid | `docker-compose config` passes |
| DevContainer valid | jq parses devcontainer.json |
| Shellcheck passes | No errors in shell scripts |
| E2E tests pass | All bats tests green |

## Estimated Task Complexity

| Task | Complexity | Risk |
|------|------------|------|
| 1.1 Directory structure | Low | Low |
| 1.2 plugin.sh | Medium | Low |
| 1.3 docker-compose.yml | Low | Low |
| 1.4 devcontainer.json | Low | Low |
| 1.5 .env.example | Low | Low |
| 2.1 CLI flag | Low | Low |
| 2.2 Help text | Low | Low |
| 2.3 Plugin loading | Medium | Medium |
| 2.4 Merge function | High | Medium |
| 3.1-3.4 Testing | Medium | Low |

**Highest Risk**: Task 2.4 (Docker Compose merge) - requires careful YAML handling
