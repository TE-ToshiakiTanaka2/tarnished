# Devcontainer Boilerplate

A boilerplate project for quickly setting up Devcontainer environments with best practices.

## Quick Start

### Remote Execution (Recommended)

Run directly from GitHub without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
```

With options:

```bash
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --lang node --docker
```

### Local Execution

Clone and run locally:

```bash
git clone https://github.com/TE-ToshiakiTanaka2/tarnished.git
cd tarnished
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
- **Docker-in-Docker** (optional) - Container development inside devcontainer
- **Playwright** (optional) - E2E testing support

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

### Remote Execution

Execute setup.sh directly from GitHub:

```bash
# Basic usage (interactive mode)
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash

# With project name
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- my-project

# With options
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --lang node --docker

# Non-interactive with all options
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- my-project --lang python --yes
```

**Requirements for remote execution:**
- git (for downloading setup files)
- curl (for fetching the script)

**Note:** The script automatically detects remote execution and downloads required files to a temporary directory, which is cleaned up after setup completes.

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-d, --dry-run` | Preview files without creating them |
| `-y, --yes` | Skip confirmation prompts |
| `--lang <languages>` | Select language template(s), comma-separated |
| `--docker` | Include Docker-in-Docker (DinD) support |
| `--playwright` | Include Playwright for E2E testing |

### Examples

```bash
# Preview what files will be created
./setup.sh --dry-run my-app

# Create without confirmation
./setup.sh --yes my-project

# Node.js with Docker-in-Docker support
./setup.sh --lang node --docker my-project

# Node.js with Playwright for E2E testing
./setup.sh --lang node --playwright my-project

# Node.js with both Docker and Playwright
./setup.sh --lang node --docker --playwright my-app
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
- Docker & Docker Compose v2 (for running the container)
- VS Code with Dev Containers extension
- devcontainer CLI (for E2E tests)

## Next Steps After Setup

1. Open the project directory in VS Code
2. Click "Reopen in Container" when prompted
3. Or use Command Palette: `Dev Containers: Reopen in Container`

## Optional Features

### Docker-in-Docker (DinD)

Enable Docker-in-Docker support with the `--docker` flag:

```bash
./setup.sh --lang node --docker my-project
```

This adds:
- Docker-in-Docker devcontainer feature
- Docker Compose v2
- VS Code Docker extension

Use cases:
- Running Testcontainers for integration tests
- Building and testing Docker images
- Running docker-compose for local dependencies
- Container application development and debugging

### Playwright

Enable Playwright E2E testing with the `--playwright` flag:

```bash
./setup.sh --lang node --playwright my-project
```

This adds:
- Playwright devcontainer feature with browser dependencies
- VS Code Playwright extension
- Pre-configured playwright.config.mjs

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

**Prerequisites**:
- Docker & Docker Compose v2 (`docker compose` command)
- devcontainer CLI (`npm install -g @devcontainers/cli`)
- jq (JSON processor)

```bash
# Run E2E tests
bats tests/e2e/

# Run specific E2E test file
bats tests/e2e/test_node_template.bats
```

**Note**: If Docker is not available, E2E tests will be skipped automatically.

## Troubleshooting

### Language Selection Not Working (curl | bash)

**Symptoms**: When running `setup.sh` via `curl | bash`, the language selection UI appears but:
- SPACE key doesn't toggle selection
- Pressing any key immediately confirms selection
- Arrow keys don't navigate

**Cause**: This is typically caused by bash's IFS (Internal Field Separator) handling in combination with `/dev/tty` input. The issue has been fixed in the latest version.

**Solutions**:

1. **Update to the latest version**: The issue is fixed in versions after commit b94f660.

2. **Use non-interactive mode**: Specify all options directly:
   ```bash
   curl -fsSL <url>/setup.sh | bash -s -- --lang node --docker my-project -y
   ```

3. **Clone and run locally**: If interactive mode is required:
   ```bash
   git clone https://github.com/TE-ToshiakiTanaka2/tarnished.git
   cd tarnished
   ./setup.sh
   ```

### TTY Not Available Error

**Symptoms**: Error message "Interactive mode is not available"

**Cause**: The script is running in a non-interactive environment (CI/CD, piped input, etc.) without access to `/dev/tty`.

**Solution**: Use non-interactive mode with all required options:
```bash
./setup.sh --lang node --yes my-project
```

### Environment-Specific Issues

| Environment | Notes |
|-------------|-------|
| WSL2 | Fully supported. Use Windows Terminal for best experience. |
| Docker | Use non-interactive mode (`-y` flag) |
| CI/CD | Use non-interactive mode with explicit options |
| SSH | Works normally if terminal is allocated (`ssh -t`) |

## Roadmap

- [ ] Python template
- [ ] Rust template
- [ ] Deno template
- [x] Remote template download via curl/wget

## License

MIT
