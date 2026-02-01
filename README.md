# erd

A GitHub Issue/Tag management CLI tool built in Rust.

## Features

- **Issue Management**: Create, view, edit, list, and close GitHub issues
- **Tag Management**: Create, delete, list tags, and bump versions
- **GitHub Actions Ready**: Works in CI/CD pipelines
- **Cross-Platform**: Linux, macOS, and Windows support

## Quick Start (DevContainer)

Set up a DevContainer environment with Claude Code and SuperClaude support:

```bash
# Create a new project directory
mkdir my-project && cd my-project

# Run setup script
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
```

Then open the folder in VS Code and click "Reopen in Container" when prompted.

## Installation

```bash
cargo install --path .
```

## Usage

```bash
# Show help
erd --help

# Issue operations
erd issue list
erd issue create
erd issue view 123
erd issue edit 123
erd issue close 123

# Tag operations
erd tag list
erd tag create v1.0.0
erd tag delete v1.0.0
erd tag bump patch    # Options: major, minor, patch
```

### Global Options

| Option | Description |
|--------|-------------|
| `-r, --repo <OWNER/REPO>` | Target repository (or set `ERD_REPO` env var) |
| `-t, --token <TOKEN>` | GitHub token (or set `GITHUB_TOKEN` env var) |
| `-v, --verbose` | Enable verbose output |
| `-q, --quiet` | Suppress non-essential output |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `GITHUB_TOKEN` | GitHub API token for authentication |
| `ERD_REPO` | Default target repository |

## Development

```bash
# Build
cargo build

# Run tests
cargo test

# Run with verbose output
cargo run -- --verbose issue list
```

## License

MIT
