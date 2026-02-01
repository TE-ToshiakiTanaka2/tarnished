# Language Plugins

This directory contains language-specific plugins for the DevContainer setup.

## Plugin Structure

Each language plugin is a directory containing:

```
plugins/languages/<language>/
├── plugin.json        # Metadata and configuration (required)
├── plugin.sh          # Implementation functions (required)
├── templates/         # Workflow templates (optional)
│   └── *.yml.template
└── README.md          # Plugin documentation (optional)
```

## Creating a New Plugin

### 1. Create the plugin directory

```bash
mkdir -p plugins/languages/your-language/templates
```

### 2. Create `plugin.json`

```json
{
  "name": "your-language",
  "version": "1.0.0",
  "description": "Your Language development environment",
  "category": "languages",
  "dependencies": {
    "features": ["git"],
    "plugins": []
  },
  "variables": {
    "LANGUAGE_VERSION": {
      "description": "Language version to install",
      "type": "select",
      "default": "latest",
      "options": ["latest", "lts", "1.0.0"]
    }
  },
  "provides": {
    "features": [],
    "extensions": ["publisher.extension"],
    "hooks": true,
    "dockerfile": true,
    "post_setup": true,
    "workflows": true
  }
}
```

### 3. Create `plugin.sh`

The main plugin script must implement the following functions:

```bash
#!/bin/sh

# Return devcontainer features JSON fragment
get_features() {
    cat << 'EOF'
    "ghcr.io/devcontainers/features/your-feature:1": {
      "version": "${PLUGIN_VAR_LANGUAGE_VERSION:-latest}"
    }
EOF
}

# Return VSCode extensions JSON fragment
get_extensions() {
    cat << 'EOF'
        "publisher.extension-name"
EOF
}

# Return Dockerfile RUN commands
get_dockerfile_extras() {
    cat << 'EOF'
# Your Language dependencies
RUN apt-get update && apt-get install -y your-package
EOF
}

# Return post.sh setup script (can use PLUGIN_VAR_* variables)
get_post_setup() {
    version="${PLUGIN_VAR_LANGUAGE_VERSION:-latest}"
    cat << EOF
# Your Language Setup
setup_your_language() {
    echo "Setting up Your Language version $version..."
}
setup_your_language
EOF
}

# Return Claude Code hooks JSON fragment
get_hooks() {
    cat << 'EOF'
      {
        "matcher": "Write(*.ext)",
        "hooks": [
          {
            "type": "command",
            "command": "your-formatter $CLAUDE_FILE_PATH"
          }
        ]
      }
EOF
}
```

### 4. Test your plugin

```bash
# Validate plugin.json
cat plugins/languages/your-language/plugin.json | jq .

# Source and test functions
. plugins/languages/your-language/plugin.sh
get_features
get_extensions
```

## Variable Types

| Type | Description | UI |
|------|-------------|-----|
| `string` | Free text input | Text prompt |
| `select` | Single choice | Numbered list |
| `multiselect` | Multiple choices | Comma-separated numbers |
| `boolean` | Yes/No | Y/N prompt |

## Available Plugins

| Plugin | Description | Status |
|--------|-------------|--------|
| [rust](./rust/) | Rust development with rust-analyzer | Available |

## Planned Plugins

- **python** - Python development with uv and ruff
- **deno** - Deno/TypeScript development
- **go** - Go development with gopls
- **node** - Node.js development

## Contributing

To contribute a new language plugin:

1. Fork this repository
2. Create your plugin in `plugins/languages/your-language/`
3. Test the plugin with `setup.sh`
4. Submit a pull request

## Plugin Integration

When `setup.sh` runs with a language plugin:

1. **Discovery** - Plugins are discovered from `plugins/languages/*/plugin.json`
2. **Selection** - User selects plugins via interactive menu
3. **Dependencies** - Plugin dependencies are resolved automatically
4. **Configuration** - User configures plugin variables (if jq available)
5. **Integration** - Plugin outputs are merged into generated files:
   - Features from `get_features()` → devcontainer.json
   - Extensions from `get_extensions()` → devcontainer.json
   - Dockerfile extras from `get_dockerfile_extras()` → Dockerfile.dev
   - Post setup from `get_post_setup()` → post.sh
   - Hooks from `get_hooks()` → .claude/settings.json
   - Workflow templates → .github/workflows/
