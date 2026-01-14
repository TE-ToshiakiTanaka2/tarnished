# Devcontainer Boilerplate

A boilerplate project for quickly setting up Devcontainer environments with best practices.

## Quick Start

Create a new Devcontainer environment in your project:

```bash
# Clone this repository
git clone https://github.com/TE-ToshiakiTanaka2/tarnished.git
cd tarnished

# Run setup script
./setup.sh
```

Or with a project name directly:

```bash
./setup.sh my-project
```

## Features

- **Node.js 22.x LTS** - Latest LTS version with TypeScript support
- **Git & GitHub CLI** - Pre-configured for version control
- **Claude Code** - AI-powered coding assistant
- **VS Code Extensions** - ESLint, Prettier, GitLens, Git Graph

## Usage

### Interactive Mode

```bash
./setup.sh
```

The script will prompt you for a project name.

### Non-Interactive Mode

```bash
./setup.sh my-project
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-d, --dry-run` | Preview files without creating them |
| `-y, --yes` | Skip confirmation prompts |

### Examples

```bash
# Preview what files will be created
./setup.sh --dry-run my-app

# Create without confirmation
./setup.sh --yes my-project
```

## Generated Files

After running the setup script, the following files are created:

```
your-project/
├── .devcontainer/
│   ├── devcontainer.json      # VS Code Devcontainer configuration
│   └── scripts/
│       └── post.sh            # Post-creation setup script
├── docker/
│   └── Dockerfile.dev         # Development Docker image
├── docker-compose.yml         # Docker Compose configuration
└── .claude/
    └── settings.json          # Claude Code settings
```

## Template Structure

This project uses a modular template system:

```
templates/
├── core/                      # Common base template
│   ├── .devcontainer/
│   ├── docker/
│   ├── .claude/
│   └── docker-compose.yml
└── node/                      # Node.js-specific settings
    └── .devcontainer/
        └── devcontainer.json
```

- **core**: Language-independent base (Git, GitHub CLI, Claude Code)
- **node**: Node.js-specific features (will be merged with core)

## Requirements

- Bash
- jq (JSON processor)
- Docker & Docker Compose (for running the container)
- VS Code with Dev Containers extension

## Next Steps After Setup

1. Open the project directory in VS Code
2. Click "Reopen in Container" when prompted
3. Or use Command Palette: `Dev Containers: Reopen in Container`

## Testing

This project includes a comprehensive test suite using [Bats](https://github.com/bats-core/bats-core).

### Running Tests

```bash
# Run all tests
bats tests/

# Run specific test categories
bats tests/unit/        # Unit tests
bats tests/integration/ # Integration tests
bats tests/e2e/         # E2E tests (requires Docker)
```

### E2E Tests

E2E tests verify that generated projects can be built and run successfully in Docker.

**Prerequisites**: E2E tests require Docker to be available. In Devcontainer environments, Docker-in-Docker (DinD) is enabled automatically.

```bash
# Run E2E tests (inside Devcontainer)
bats tests/e2e/

# Run specific E2E test file
bats tests/e2e/test_node_template.bats
```

**Note**: If Docker is not available, E2E tests will be skipped automatically.

## Roadmap

- [ ] Python template
- [ ] Rust template
- [ ] Deno template
- [ ] Remote template download via curl/wget

## License

MIT
