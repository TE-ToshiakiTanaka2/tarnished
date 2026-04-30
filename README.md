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

### Monorepo support

`setup.sh` also supports monorepo layouts where multiple sub-projects live in
one repository, each with its own language scaffold but sharing the
`.devcontainer/`, `.claude/`, and `docker-compose.yml` at the root. A central
`modules.json` registry tracks the modules.

```bash
# One-shot interactive monorepo init
mkdir my-monorepo && cd my-monorepo
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
# Answer "y" to the "Monorepo configuration?" prompt, then enter modules in
# the dialogue loop. Empty module name finishes.

# Or non-interactively (use --postgresql or --mysql for the DB service)
curl -fsSL .../setup.sh | bash -s -- \
  --monorepo \
  --module backend:python \
  --module frontend:node \
  --postgresql -y

# Same shape with MySQL instead:
curl -fsSL .../setup.sh | bash -s -- \
  --monorepo \
  --module backend:python \
  --module frontend:node \
  --mysql -y

# Add a module to an existing monorepo (auto-detected via modules.json,
# or explicit via --add-module):
curl -fsSL .../setup.sh | bash -s -- --add-module worker --lang python -y
```

Resulting layout:

```
my-monorepo/
├── .devcontainer/        # shared (one devcontainer for the whole monorepo)
├── .claude/              # shared
├── docker/Dockerfile.dev # shared, union of all module-language toolchains
├── docker-compose.yml    # shared; service names use <project>-<svc>
├── CLAUDE.md             # project-wide
├── modules.json          # registry: { "version": 1, "modules": [...] }
├── backend/              # module — own pyproject.toml, src/backend/, tests/
│   └── CLAUDE.md
└── frontend/             # module — own package.json, biome.json, src/, tests/
    └── CLAUDE.md
```

Each language plugin's per-module hook generates the language-idiomatic
scaffold inside the module directory; the shared `.devcontainer/Dockerfile.dev`
contains the union of every module's language toolchain. Subsequent
`setup.sh --add-module` invocations are idempotent against the shared root
files (marker-guarded blocks).

### Upgrading an existing scaffold

`setup.sh --upgrade` refreshes a previously scaffolded project to the latest
(or `--target-version`-pinned) tarnished version while preserving any files
you have edited locally.

```bash
# First time only: bootstrap a manifest from the current state of files.
# Required for projects scaffolded before the manifest format existed.
./setup.sh --create-manifest --from-version v0.0.74 -y

# Subsequent updates:
./setup.sh --upgrade -y                           # Latest develop
./setup.sh --upgrade --target-version v0.0.76 -y  # Pin to a specific tag
./setup.sh --upgrade --dry-run                    # Preview without writing

# Monorepo: scope the upgrade
./setup.sh --upgrade --shared-only -y             # Only the root assets
./setup.sh --upgrade --module backend -y          # Only one module

# Aggressive: also delete tracked files removed upstream
./setup.sh --upgrade --prune -y

# Bypass the clean-tree precondition (advanced)
./setup.sh --upgrade --force -y
```

How it works:

- Each scaffolded scope (root in single mode, or root + per-module in
  monorepo mode) carries a `.tarnished-manifest.json` recording sha256
  hashes of every "verbatim copy" file from the originating scaffold.
- `--upgrade` re-runs the plugin pipeline against a temporary staging
  directory to discover what the current tarnished version would emit,
  then per-file compares (old hash, your current file's hash, new hash)
  and chooses one of: leave as-is (unchanged), overwrite (you didn't
  edit), skip (you edited — preserved with a diff summary), copy (new
  upstream file), warn (your file collides with a new upstream path),
  leave + warn (removed upstream — opt-in delete with `--prune`), or
  respect-deletion (you removed the file).
- Merge files (`.gitignore`, `devcontainer.json`, `.claude/settings.json`),
  dynamically generated files (`docker-compose.yml`, `modules.json`),
  and user-owned files (`CLAUDE.md`, `AGENTS.md`, `README.md`) are
  deliberately excluded from manifest tracking. Merge logic re-runs
  during the upgrade to absorb new whitelist blocks and merge entries.
- The pre-flight requires a clean git tree (use `git stash` or `--force`
  to override).

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
