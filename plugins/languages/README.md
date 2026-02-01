# Language Plugins

This directory contains language-specific plugins for the DevContainer setup.

## Plugin Structure

Each language plugin is a directory containing:

```
plugins/languages/<language>/
├── plugin.sh          # Main plugin script (required)
├── features.json      # Additional devcontainer features (optional)
├── extensions.json    # Additional VSCode extensions (optional)
├── hooks.json         # Claude Code hooks to add (optional)
└── README.md          # Plugin documentation (optional)
```

## Creating a New Plugin

### 1. Create the plugin directory

```bash
mkdir -p plugins/languages/your-language
```

### 2. Create `plugin.sh`

The main plugin script must implement the following functions:

```bash
#!/bin/bash

# Plugin metadata
PLUGIN_NAME="your-language"
PLUGIN_VERSION="1.0.0"
PLUGIN_DESCRIPTION="Your Language development environment"

# Called to get additional devcontainer features
# Output: JSON object of features
get_features() {
    cat << 'EOF'
{
    "ghcr.io/devcontainers/features/your-feature:1": {
        "version": "latest"
    }
}
EOF
}

# Called to get additional VSCode extensions
# Output: JSON array of extension IDs
get_extensions() {
    cat << 'EOF'
[
    "publisher.extension-name"
]
EOF
}

# Called to get additional Dockerfile commands
# Output: Dockerfile RUN commands
get_dockerfile_extras() {
    cat << 'EOF'
# Install additional packages
RUN apt-get update && apt-get install -y your-package
EOF
}

# Called to get additional post.sh setup steps
# Output: Bash script snippet
get_post_setup() {
    cat << 'EOF'
# Your Language Setup
setup_your_language() {
    echo "Setting up Your Language..."
    # Setup commands here
}
setup_your_language
EOF
}

# Called to get Claude Code hooks
# Output: JSON array of hook configurations
get_hooks() {
    cat << 'EOF'
[
    {
        "matcher": "Write(*.ext)",
        "hooks": [
            {
                "type": "command",
                "command": "your-formatter $CLAUDE_FILE_PATH"
            }
        ]
    }
]
EOF
}
```

### 3. Test your plugin

```bash
# Source the plugin
source plugins/languages/your-language/plugin.sh

# Test functions
get_features
get_extensions
```

## Available Plugins

| Plugin | Description | Status |
|--------|-------------|--------|
| (none) | No plugins yet | - |

## Future Plugins

Planned language plugins:

- **rust** - Rust development with rust-analyzer
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

1. Features from `get_features()` are merged into devcontainer.json
2. Extensions from `get_extensions()` are merged into devcontainer.json
3. Dockerfile extras from `get_dockerfile_extras()` are added to Dockerfile.dev
4. Post setup from `get_post_setup()` is added to post.sh
5. Hooks from `get_hooks()` are added to .claude/settings.json
