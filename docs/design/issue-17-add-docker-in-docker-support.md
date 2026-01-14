# Design Document: Add Docker-in-Docker Support to Devcontainer

**Issue**: #17
**Milestone**: core
**Author**: Claude Code
**Date**: 2026-01-14

## Overview

This document describes the design for adding Docker-in-Docker (DinD) support to the Devcontainer environment, enabling E2E tests to run within the development container.

## Architecture

```
┌─────────────────────────────────────────┐
│           Host Machine                  │
│  ┌───────────────────────────────────┐  │
│  │       Devcontainer (DinD)         │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │   Docker Daemon (nested)    │  │  │
│  │  │  ┌───────┐  ┌───────┐      │  │  │
│  │  │  │E2E    │  │E2E    │      │  │  │
│  │  │  │Test   │  │Test   │      │  │  │
│  │  │  │Cont.  │  │Cont.  │      │  │  │
│  │  │  └───────┘  └───────┘      │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Key Points

- A dedicated Docker daemon runs inside the Devcontainer
- E2E test containers are managed by this nested daemon
- Complete isolation from host Docker environment
- No impact on host machine containers

## Design Decisions

### Decision 1: Docker-in-Docker vs Docker-outside-of-Docker

| Approach | Pros | Cons |
|----------|------|------|
| **DinD (Chosen)** | Complete isolation, secure, no host impact | Slight overhead |
| DooD | Lightweight | Shares host containers, security risk |

**Decision**: Use DinD for better isolation and security.

### Decision 2: Docker Compose Support

E2E tests use `docker-compose` commands:
- `docker-compose build` (test_node_template.bats:77)
- `docker-compose down` (test_node_template.bats:42)

**Decision**: Enable docker-compose v2 in DinD feature.

### Decision 3: CI Execution Scope

**Decision**: E2E tests with Docker are local-only. CI environment already has Docker available if needed.

## File Modifications

### 1. `.devcontainer/devcontainer.json`

Add Docker-in-Docker feature:

```json
"ghcr.io/devcontainers/features/docker-in-docker:2": {
  "dockerDashComposeVersion": "v2"
}
```

### 2. `README.md`

Add E2E test execution instructions:
- Prerequisites (Devcontainer environment)
- How to run E2E tests
- Expected behavior

## Test Strategy

### Verification Steps

1. Rebuild Devcontainer with new configuration
2. Verify `docker` command is available
3. Verify `docker-compose` command is available
4. Run E2E tests and confirm they execute (not skip)

### Test Commands

```bash
# Verify Docker availability
docker --version
docker-compose --version

# Run E2E tests
bats tests/e2e/
```

## Security Considerations

- DinD runs with privileged mode (required for nested Docker)
- Containers created in DinD are isolated from host
- No persistent volumes shared between host and nested Docker

## References

- [devcontainers/features - docker-in-docker](https://github.com/devcontainers/features/tree/main/src/docker-in-docker)
- [Docker-in-Docker documentation](https://docs.docker.com/engine/security/rootless/)
