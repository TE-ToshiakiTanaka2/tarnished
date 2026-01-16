# Design Document: Redis Plugin

**Issue**: #37 - Add Redis plugin for cache/session development environment
**Milestone**: core
**Date**: 2026-01-16

## Overview

Add a Redis plugin to the Devcontainer boilerplate project following the established plugin pattern used by PostgreSQL and Neo4j plugins.

## Architecture

### Plugin Structure

```
templates/redis/
├── docker/
│   └── docker-compose.redis.yml    # Redis service definition
├── init/
│   └── .gitkeep                    # Placeholder for init scripts
├── .devcontainer/
│   └── devcontainer.json           # VS Code configuration (minimal)
├── .env.example                    # Environment variable template
└── plugin.sh                       # Plugin hook script
```

### Component Design

#### 1. Docker Compose Service (`docker-compose.redis.yml`)

```yaml
services:
  redis:
    image: redis:7
    container_name: ${COMPOSE_PROJECT_NAME:-app}_redis
    command: redis-server --requirepass ${REDIS_PASSWORD:-redis}
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD:-redis}", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s
    restart: unless-stopped

volumes:
  redis_data:
```

**Design Decisions**:
- **Image**: `redis:7` - Latest stable version with security updates
- **Authentication**: Password via `--requirepass` flag (simpler than ACL for dev environments)
- **Persistence**: RDB snapshots via `/data` volume (default Redis behavior)
- **Health Check**: Uses `redis-cli ping` with authentication
- **Port**: Exposed on 6379 for host access during development

#### 2. Plugin Script (`plugin.sh`)

The plugin script follows the established pattern:
- `plugin_name()`: Returns "redis"
- `plugin_description()`: Returns description
- `plugin_post_copy()`: Handles:
  - Docker Compose merging
  - Devcontainer.json merging
  - Environment variable setup
  - Init directory creation
  - .gitignore update

#### 3. Environment Variables (`.env.example`)

```
# Redis Configuration
REDIS_PASSWORD=redis
```

Single variable for simplicity. Default password is `redis` for development convenience.

#### 4. Devcontainer Configuration

Minimal configuration with empty customizations block. VS Code extensions can be added later if needed.

## Integration Points

### With setup.sh

The plugin integrates through the existing plugin system:
1. `setup.sh` sources `plugin.sh`
2. Calls `plugin_post_copy()` after copying base templates
3. Plugin merges its configurations into target project

### With Other Plugins

Redis can coexist with:
- **PostgreSQL**: Different ports (5432 vs 6379), different volumes
- **Neo4j**: Different ports (7474/7687 vs 6379), different volumes

No conflicts expected.

## Security Considerations

- Password authentication enabled by default
- Credentials stored in `.env` file (gitignored)
- Development-only defaults (weak password acceptable for local dev)
- No external network exposure by default (localhost only)

## Testing Strategy

1. **Shellcheck**: Validate plugin.sh syntax
2. **Dry-run**: Test setup.sh with --dry-run flag
3. **Integration**: Verify Redis container starts and accepts connections
4. **Health check**: Confirm health check passes

## Future Enhancements (Out of Scope)

- Redis Insight GUI container
- Redis Cluster support
- ACL-based authentication
- VS Code Redis extension
- Lua script initialization
