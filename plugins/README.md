# Plugin System

This directory contains plugins for the DevContainer setup script (`setup.sh`).

## Plugin Categories

| Category | Description | Examples |
|----------|-------------|----------|
| `languages/` | Programming language environments | Rust, Python, Deno, Go |
| `tools/` | Development tools | Docker, Kubernetes, Terraform |
| `github-actions/` | CI/CD workflow templates | Project integration, PR status |

## Plugin Structure

Each plugin follows this structure:

```
plugins/<category>/<plugin-name>/
├── plugin.json          # Metadata and configuration (required)
├── plugin.sh            # Implementation functions (required)
├── templates/           # Optional template files
│   └── *.template
└── README.md            # Plugin documentation (optional)
```

## Creating a Plugin

### 1. Create the plugin directory

```bash
mkdir -p plugins/<category>/<plugin-name>
```

### 2. Create `plugin.json`

```json
{
  "name": "your-plugin",
  "version": "1.0.0",
  "description": "Description of your plugin",
  "category": "languages",
  "dependencies": {
    "features": ["git"],
    "plugins": []
  },
  "variables": {
    "EXAMPLE_VAR": {
      "description": "An example variable",
      "type": "select",
      "default": "option1",
      "options": ["option1", "option2", "option3"]
    }
  },
  "provides": {
    "features": [],
    "extensions": ["publisher.extension"],
    "hooks": false,
    "dockerfile": true,
    "post_setup": true
  }
}
```

### 3. Create `plugin.sh`

```bash
#!/bin/sh
# Plugin implementation

# Return devcontainer features JSON object
get_features() {
    cat << 'EOF'
    "ghcr.io/devcontainers/features/your-feature:1": {}
EOF
}

# Return VSCode extensions JSON array
get_extensions() {
    cat << 'EOF'
        "publisher.extension-name"
EOF
}

# Return Dockerfile RUN commands
get_dockerfile_extras() {
    cat << 'EOF'
# Your plugin setup
RUN apt-get update && apt-get install -y your-package
EOF
}

# Return post.sh setup script
get_post_setup() {
    cat << 'EOF'
# Your Plugin Setup
setup_your_plugin() {
    echo "Setting up your plugin..."
    # Use PLUGIN_VAR_* environment variables
    echo "Variable value: $PLUGIN_VAR_EXAMPLE_VAR"
}
setup_your_plugin
EOF
}

# Return Claude Code hooks JSON array (or empty)
get_hooks() {
    cat << 'EOF'
EOF
}
```

## Variable Types

| Type | Description | UI Prompt |
|------|-------------|-----------|
| `string` | Free text input | Text prompt |
| `select` | Single choice from options | Numbered list |
| `multiselect` | Multiple choices from options | Comma-separated numbers |
| `boolean` | Yes/No choice | Y/N prompt |

## Dependencies

### Feature Dependencies

Plugins can depend on DevContainer features:
- `git` - Git feature
- `github-cli` - GitHub CLI feature
- `uv` - uv package manager (required for SuperClaude)
- `claude-code` - Claude Code CLI

### Plugin Dependencies

Plugins can depend on other plugins using `category/name` format:
- `languages/rust`
- `tools/docker`

Dependencies are automatically resolved and installed.

## Schema Validation

Plugin configurations are validated against `plugin-schema.json`.

## Available Plugins

See each category directory for available plugins:
- [Languages](./languages/README.md)
- [Tools](./tools/README.md)
- [GitHub Actions](./github-actions/README.md)
