# GitHub Actions Plugins

This directory contains CI/CD workflow template plugins.

## Available Plugins

| Plugin | Description | Status |
|--------|-------------|--------|
| `project-integration` | GitHub Project integration workflows | Available |

## Plugin Behavior

GitHub Actions plugins generate workflow files to `.github/workflows/` directory.

### Template Variables

Templates support the following variables:
- `{{PROJECT_NAME}}` - Project name
- `{{PROJECT_NAME_LOWER}}` - Project name in lowercase kebab-case

## Creating a GitHub Actions Plugin

1. Create plugin directory with `plugin.json` and `plugin.sh`
2. Add workflow templates in `templates/` directory
3. Templates should use `.yml.template` extension
