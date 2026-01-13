# Design Document: MVP setup.sh Script for Devcontainer Environment

**Issue**: #3 - Add MVP setup.sh script for Devcontainer environment creation
**Milestone**: core
**Author**: Claude
**Date**: 2026-01-13

## 1. Overview

This document describes the architecture and design for the MVP setup.sh script that creates Devcontainer environments for new projects.

## 2. Architecture

### 2.1 High-Level Flow

```
[User]
    │
    ▼ curl -fsSL <URL> | bash
[setup.sh]
    │
    ├─ Interactive prompt (project name input)
    │
    ├─ Copy templates/core/
    │   └─ Common base files
    │
    ├─ Merge templates/node/
    │   └─ Language-specific settings (devcontainer.json features)
    │
    ├─ Replace placeholders
    │   └─ {{PROJECT_NAME}} → input value
    │
    └─ File generation complete
```

### 2.2 Template Structure

```
templates/
├── core/                           # Common base template
│   ├── .devcontainer/
│   │   ├── devcontainer.json       # Common features (git, gh, claude-code)
│   │   └── scripts/
│   │       └── post.sh             # Post-creation script
│   ├── docker/
│   │   └── Dockerfile.dev          # Base Docker image
│   ├── docker-compose.yml          # Docker Compose configuration
│   └── .claude/
│       └── settings.json           # Claude Code settings
│
└── node/                           # Node.js-specific template
    └── .devcontainer/
        └── devcontainer.json       # Node.js-specific features (node:22)
```

### 2.3 Generated Project Structure

```
<new-project>/
├── .devcontainer/
│   ├── devcontainer.json           # Merged core + node settings
│   └── scripts/
│       └── post.sh
├── docker/
│   └── Dockerfile.dev
├── docker-compose.yml
└── .claude/
    └── settings.json
```

## 3. Component Design

### 3.1 setup.sh Script

**Responsibilities:**
- Accept project name via interactive prompt
- Download/copy template files
- Merge devcontainer.json features from core and language templates
- Replace placeholders with user input
- Display completion message

**Key Functions:**

| Function | Description |
|----------|-------------|
| `prompt_project_name()` | Interactive prompt for project name |
| `validate_project_name()` | Validate project name format |
| `copy_core_template()` | Copy core template files |
| `merge_language_features()` | Merge language-specific features into devcontainer.json |
| `replace_placeholders()` | Replace {{PROJECT_NAME}} with actual value |
| `show_completion()` | Display success message and next steps |

### 3.2 Template Files

#### 3.2.1 Core devcontainer.json

```json
{
  "name": "{{PROJECT_NAME}}",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "{{PROJECT_NAME}}",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  }
}
```

#### 3.2.2 Node.js devcontainer.json

```json
{
  "features": {
    "ghcr.io/devcontainers/features/node:1": {
      "version": "22"
    }
  }
}
```

#### 3.2.3 Merged Result

```json
{
  "name": "my-project",
  "dockerComposeFile": ["../docker-compose.yml"],
  "service": "my-project",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {},
    "ghcr.io/devcontainers/features/node:1": {
      "version": "22"
    }
  }
}
```

### 3.3 Dockerfile.dev

**Base Image:** `mcr.microsoft.com/vscode/devcontainers/base:bookworm`

**Installed Packages:**
- curl, vim, git, ssh, sudo, bash
- ripgrep
- ca-certificates, wget

### 3.4 docker-compose.yml

**Key Settings:**
- Volume mounts for workspace and git config
- Working directory: /workspace
- Command: sleep infinity (keep container running)

## 4. Placeholder System

| Placeholder | Usage | Replacement |
|-------------|-------|-------------|
| `{{PROJECT_NAME}}` | devcontainer.json, docker-compose.yml | User-provided project name |

## 5. Merge Strategy

### 5.1 JSON Merge Logic

The setup.sh script merges devcontainer.json files using the following strategy:

1. Start with core/devcontainer.json as base
2. Deep merge language/devcontainer.json
3. For "features" object: combine all key-value pairs
4. Other fields: language template overrides core

### 5.2 Implementation Approach

Using `jq` for JSON manipulation:

```bash
jq -s '.[0] * .[1] | .features = (.[0].features * .[1].features)' \
    core/devcontainer.json \
    node/devcontainer.json
```

## 6. Error Handling

| Error Case | Handling |
|------------|----------|
| Empty project name | Re-prompt with error message |
| Invalid characters in name | Show allowed characters, re-prompt |
| Target directory exists | Ask to overwrite or abort |
| Missing dependencies (jq) | Install jq or show error |

## 7. Dependencies

| Tool | Purpose | Required |
|------|---------|----------|
| bash | Script execution | Yes |
| jq | JSON manipulation | Yes |
| curl/wget | Download templates (future) | No (MVP) |

## 8. Future Considerations

- Language selection prompt (Python, Rust, Deno)
- Remote template download via curl/wget
- Configuration options (VS Code extensions, additional features)
- Dry-run mode for preview
