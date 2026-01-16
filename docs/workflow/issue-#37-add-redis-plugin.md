# Implementation Workflow: Redis Plugin

**Issue**: #37 - Add Redis plugin for cache/session development environment
**Milestone**: core
**Date**: 2026-01-16

## Phase 1: Directory Structure Setup

### Task 1.1: Create plugin directories
```bash
mkdir -p templates/redis/docker
mkdir -p templates/redis/init
mkdir -p templates/redis/.devcontainer
```

### Task 1.2: Create placeholder files
```bash
touch templates/redis/init/.gitkeep
```

**Checkpoint**: Directory structure matches design document

---

## Phase 2: Docker Compose Configuration

### Task 2.1: Create docker-compose.redis.yml

Create `templates/redis/docker/docker-compose.redis.yml` with:
- Redis 7 image
- Password authentication via command
- Port 6379 exposed
- Volume for data persistence
- Health check configuration
- Restart policy

**Reference**: `templates/postgresql/docker/docker-compose.postgresql.yml`

**Checkpoint**: YAML syntax valid

---

## Phase 3: Environment Configuration

### Task 3.1: Create .env.example

Create `templates/redis/.env.example` with:
```
# Redis Configuration
REDIS_PASSWORD=redis
```

**Checkpoint**: File created with correct format

---

## Phase 4: Devcontainer Configuration

### Task 4.1: Create devcontainer.json

Create `templates/redis/.devcontainer/devcontainer.json` with minimal configuration:
```json
{
  "customizations": {
    "vscode": {
      "extensions": []
    }
  }
}
```

**Checkpoint**: JSON syntax valid

---

## Phase 5: Plugin Script

### Task 5.1: Create plugin.sh

Create `templates/redis/plugin.sh` based on PostgreSQL plugin with:
- `plugin_name()` returning "redis"
- `plugin_description()` returning description
- `plugin_post_copy()` handling all merges

**Key Modifications from PostgreSQL**:
- Change all "postgresql" references to "redis"
- Change environment variable from `POSTGRES_*` to `REDIS_PASSWORD`
- Update grep check for existing env vars

**Reference**: `templates/postgresql/plugin.sh`

**Checkpoint**: Shellcheck passes

---

## Phase 6: Testing

### Task 6.1: Shellcheck validation
```bash
shellcheck templates/redis/plugin.sh
```

### Task 6.2: Setup.sh dry-run
```bash
./setup.sh --dry-run
```

### Task 6.3: Plugin detection verification
Verify plugin appears in available plugins list

**Checkpoint**: All tests pass

---

## Phase 7: Commit and Finalize

### Task 7.1: Commit implementation
```bash
git add templates/redis/
git commit -m "feat(redis): add Redis plugin for cache/session development environment (#37)"
```

### Task 7.2: Commit documentation
```bash
git add docs/
git commit -m "docs(redis): add design and workflow documents for Redis plugin (#37)"
```

**Checkpoint**: All changes committed

---

## Critical Path

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7
   │          │          │          │          │          │
   └──────────┴──────────┴──────────┴──────────┴──────────┘
                    All phases sequential
```

## Rollback Plan

If issues discovered:
1. Delete `templates/redis/` directory
2. Revert commits if already made
3. Document issues in GitHub issue comments

## Dependencies

- Existing plugin infrastructure in `setup.sh`
- Helper functions: `merge_docker_compose_services`, `merge_devcontainer_json`, `print_info`, `print_success`
