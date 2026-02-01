# GitHub Project Integration Plugin

Provides GitHub Project integration workflows using the erd CLI tool.

## Features

- **Issue linking** - Automatically link new issues to GitHub Projects
- **PR status updates** - Update project status when PR is opened
- **Project configuration** - Generate `.github/project.yml` configuration file

## Prerequisites

1. Create a GitHub Personal Access Token (classic) with these scopes:
   - `repo` (Full control of private repositories)
   - `project` (Full control of projects)
2. Add the token as a repository secret named `PROJECT_TOKEN`

## Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `PROJECT_OWNER` | string | (empty) | GitHub username or organization owning the project |
| `PROJECT_NUMBER` | string | 1 | GitHub Project number |
| `DEFAULT_STATUS` | select | Backlog | Default status for new issues |
| `PR_OPEN_STATUS` | select | In Review | Status when PR is opened |

## Generated Files

### Workflows

- `.github/workflows/project-integration.yml` - Links new issues to project
- `.github/workflows/pr-project-status.yml` - Updates status when PR opens

### Configuration

- `.github/project.yml` - Project configuration for erd CLI

## Dependencies

- Requires `github-cli` feature

## Related

- [erd CLI](https://github.com/TE-ToshiakiTanaka2/tarnished) - The CLI tool used by these workflows
