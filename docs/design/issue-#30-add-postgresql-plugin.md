# Design Document: PostgreSQL Plugin

**Issue**: #30 - Add PostgreSQL plugin for database development environment
**Milestone**: core
**Created**: 2026-01-14

## 1. Overview

This document describes the design for a PostgreSQL plugin that adds database development environment support to Devcontainer projects. The plugin follows the established plugin architecture pattern used by Docker-in-Docker and other existing plugins.

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Devcontainer Network                       │
│                                                                 │
│  ┌─────────────────────┐         ┌─────────────────────────┐   │
│  │   App Container     │         │  PostgreSQL Container   │   │
│  │   ({{PROJECT_NAME}})│  ───►   │  (db)                   │   │
│  │                     │  5432   │                         │   │
│  │   - psql CLI        │         │  - postgres:17          │   │
│  │   - VS Code ext     │         │  - Data: postgres_data  │   │
│  │   - Application     │         │  - Init: init/*.sql     │   │
│  └─────────────────────┘         └─────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Plugin Structure

```
templates/postgresql/
├── plugin.sh                           # Plugin main script
├── .devcontainer/
│   └── devcontainer.json               # VS Code extensions
├── docker/
│   └── docker-compose.postgresql.yml   # PostgreSQL service
├── init/
│   └── .gitkeep                        # Init scripts directory
└── .env.example                        # Environment template
```

## 3. Component Design

### 3.1 Plugin Script (`plugin.sh`)

The plugin script implements the standard plugin interface:

| Function | Description |
|----------|-------------|
| `plugin_name()` | Returns `"postgresql"` |
| `plugin_description()` | Returns plugin description |
| `plugin_post_copy()` | Merges configurations |

#### Hook Implementation

```bash
plugin_post_copy() {
    # 1. Merge docker-compose.yml (add PostgreSQL service)
    # 2. Merge devcontainer.json (add VS Code extension)
    # 3. Copy .env.example (if .env doesn't exist)
    # 4. Copy init/ directory
}
```

### 3.2 Docker Compose Configuration

**Service Name**: `db` (standard convention for database services)

```yaml
services:
  db:
    image: postgres:17
    container_name: ${COMPOSE_PROJECT_NAME:-app}_db
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-postgres}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
      POSTGRES_DB: ${POSTGRES_DB:-app_development}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres} -d ${POSTGRES_DB:-app_development}"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

volumes:
  postgres_data:
```

### 3.3 VS Code Extension

**Extension**: `ckolkman.vscode-postgres`

Provides:
- Database explorer in VS Code sidebar
- SQL query execution
- Connection management
- Schema visualization

### 3.4 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `postgres` | Database superuser name |
| `POSTGRES_PASSWORD` | `postgres` | Superuser password |
| `POSTGRES_DB` | `app_development` | Default database name |

### 3.5 Connection Configuration

From within the devcontainer:
- **Host**: `db`
- **Port**: `5432`
- **Connection String**: `postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB}`

## 4. Integration Design

### 4.1 Docker Compose Merge Strategy

The plugin uses a YAML merge approach via `yq` or falls back to a jq-based JSON conversion:

```bash
merge_docker_compose() {
    # If yq available: direct YAML merge
    # Else: Convert to JSON, merge with jq, convert back
}
```

**Merge Rules**:
1. Add `db` service to `services` section
2. Add `postgres_data` to `volumes` section
3. Preserve all existing services and volumes

### 4.2 DevContainer JSON Merge

Uses existing `merge_devcontainer_json()` function from `common.sh`:
- Adds VS Code PostgreSQL extension to extensions array
- Preserves existing extensions and features

### 4.3 Plugin Loading Order

```
core → language(s) → claude → docker → postgresql → playwright
```

PostgreSQL loads after docker plugin (if enabled) to ensure proper service dependencies.

## 5. Setup.sh Integration

### 5.1 CLI Option

New flag: `--postgresql`

```bash
./setup.sh --lang node --postgresql    # Node.js with PostgreSQL
./setup.sh --lang python --postgresql  # Python with PostgreSQL
```

### 5.2 Plugin Discovery

The plugin is discovered automatically via `discover_available_languages()` but should be excluded from language selection (it's an infrastructure plugin like docker/playwright).

### 5.3 Variables and Tracking

```bash
POSTGRESQL_ENABLED=false  # Flag for PostgreSQL plugin
```

## 6. File Operations

### 6.1 Files Created

| File | Action | Description |
|------|--------|-------------|
| `docker-compose.yml` | Merge | Add PostgreSQL service |
| `.devcontainer/devcontainer.json` | Merge | Add VS Code extension |
| `.env` | Copy if missing | From `.env.example` |
| `init/` | Copy | Init scripts directory |

### 6.2 Files Modified

| File | Modification |
|------|--------------|
| `docker-compose.yml` | Add `db` service and `postgres_data` volume |
| `.devcontainer/devcontainer.json` | Add PostgreSQL VS Code extension |

## 7. Security Considerations

### 7.1 Credentials

- Default credentials are for **development only**
- `.env` file should be in `.gitignore` (handled by common.sh)
- Production deployments must use different credentials

### 7.2 Network Isolation

- PostgreSQL port (5432) is **not exposed** to host
- Only accessible within Docker network
- Reduces attack surface for development environments

### 7.3 Data Persistence

- Named volume `postgres_data` persists across container rebuilds
- Data survives `docker-compose down` (unless `-v` flag used)
- Clean slate: `docker volume rm <project>_postgres_data`

## 8. Testing Strategy

### 8.1 Unit Tests

- Plugin function validation (plugin_name, plugin_description)
- Docker Compose YAML syntax validation
- devcontainer.json merge verification

### 8.2 Integration Tests

- Full setup.sh flow with --postgresql flag
- Container startup and healthcheck
- psql connectivity test

### 8.3 E2E Tests

```bash
# Test PostgreSQL plugin
./setup.sh --lang node --postgresql --dry-run
./setup.sh --lang node --postgresql -y test-project
docker-compose up -d
docker-compose exec db pg_isready
```

## 9. Dependencies

### 9.1 Required Tools

| Tool | Purpose | Fallback |
|------|---------|----------|
| `jq` | JSON processing | Required (no fallback) |
| `yq` | YAML processing | JSON conversion fallback |

### 9.2 Docker Images

| Image | Version | Size |
|-------|---------|------|
| `postgres` | 17 | ~400MB |

## 10. Future Considerations

### 10.1 Potential Enhancements

- pgAdmin web UI option (separate plugin or flag)
- Multiple database support
- Backup/restore utilities
- Custom PostgreSQL configuration (postgresql.conf)

### 10.2 Related Plugins

- `mysql` - MySQL database plugin (similar pattern)
- `redis` - Redis cache plugin
- `mongodb` - MongoDB plugin

## 11. References

- [PostgreSQL Docker Image](https://hub.docker.com/_/postgres)
- [VS Code PostgreSQL Extension](https://marketplace.visualstudio.com/items?itemName=ckolkman.vscode-postgres)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)
- [Existing Plugin: templates/docker/plugin.sh](../../templates/docker/plugin.sh)
