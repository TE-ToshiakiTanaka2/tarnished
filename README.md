# erd

A GitHub Issue/Tag management CLI tool built in Rust.

## Features

- **Issue Management**: Create, view, edit, list, and close GitHub issues
- **Tag Management**: Create, delete, list tags, and bump versions
- **GitHub Actions Ready**: Works in CI/CD pipelines
- **Cross-Platform**: Linux, macOS, and Windows support

## Quick Start (DevContainer)

Set up a DevContainer environment with shared Claude Code / Codex workflows:

```bash
# Create a new project directory
mkdir my-project && cd my-project

# Run setup script
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
```

Then open the folder in VS Code and click "Reopen in Container" when prompted.

### AI workflow profiles

Tarnished keeps the implementation lifecycle in `.tarnished/workflows/` and
projects it into the agent-specific entrypoints used by Claude Code and Codex.
This keeps the workflow shape consistent across Claude-main and Codex-main
projects.

```bash
# Default: Claude Code primary
./setup.sh --ai-profile claude-main

# Codex primary, Claude Code as review handoff
./setup.sh --ai-profile codex-main

# Install both projections and document cross-agent operation
./setup.sh --ai-profile dual

# Backward-compatible alias: Claude primary + Codex reviewer
./setup.sh --codex
```

Generated projects include:

- `.tarnished/agent-profile.json` — selected profile and primary/review agents
- `.tarnished/workflows/` — shared lifecycle source
- `.tarnished/workflows/erd/` — Codex-readable projection of the existing erd command assets
- `CLAUDE.md` — Claude Code entrypoint when Claude is installed
- `AGENTS.md` — Codex entrypoint when Codex is installed
- `.agents/skills/` — Codex repo-local skills mirroring `issue`, `design`, `implement`, `review`, `pr`, and `flow`

Codex users can invoke the shared lifecycle with `$issue`, `$design`,
`$implement`, `$review`, and `$pr`. The generated `AGENTS.md` also treats
plain `issue` prompts and natural-language mentions of Claude-style `/issue`
as aliases for the same workflow. Codex's slash-command namespace remains
reserved for Codex built-ins, so `$issue` is the native skill invocation. If
your devcontainer already provides isolation and you want the same hands-off
behavior as Claude Code's `--dangerously-skip-permissions`, launch Codex
explicitly with:

```bash
codex --dangerously-bypass-approvals-and-sandbox
```

The default generated `.codex/config.toml` remains `workspace-write` +
`on-request` so projects do not silently disable approvals.

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

### Always-latest assets (`refresh-assets.sh`)

Operational assets that are intended to be **identical across every
project** — `.claude/commands/`, `.claude/skills/`, `.claude/scripts/`,
and language-agnostic rules such as `.claude/rules/shell.md` — are kept
always-latest by `refresh-assets.sh` rather than by the manifest-driven
`--upgrade` flow above. The script runs from your devcontainer's `postStartCommand`
on every container start (and from `post.sh` on the very first boot)
so a project scaffolded a month ago still picks up the latest
skill/command/script/shared-rule revisions automatically.

```text
DevContainer onCreate           DevContainer onStart (every container start)
─────────────────────           ────────────────────────────────────────────
  postCreateCommand                postStartCommand
       │                               │
       └─→ post.sh                     └─→ refresh-assets.sh
            │                                │
            ├─→ setup_plugins                ├─→ git ls-remote upstream HEAD
            ├─→ setup_codex                  ├─→ if SHA changed → git pull
            └─→ refresh_assets (FIRST RUN)   ├─→ rsync --delete  upstream → base
                                             ├─→ rsync (no-del)  *.local/ → base
                                             └─→ summary print
```

How it works:

- `<project>/.tarnished/refresh.json` declares the always-latest path
  whitelist (`schema_version: 1`). The defaults track the Claude template
  assets in upstream `develop`; override `upstream.repo_url` /
  `upstream.branch` / `clone_dir` to redirect to a fork or a pinned ref.
- The upstream clone lives at `/opt/tarnished` (or `~/.cache/tarnished`
  if `/opt` is not writable). `git ls-remote` checks the upstream HEAD
  on every invocation; only `git fetch` + `git reset --hard origin/<branch>`
  + `rsync` runs when the SHA differs.
- All failure paths emit a warning and exit 0 — container start is
  never blocked. Offline first-boot keeps the original scaffolded
  bytes; offline subsequent runs use the cached upstream as-is.

To customize an always-latest asset locally without losing the
upstream sync, write to the sidecar `.local/` directory mirroring
the upstream layout:

```bash
# Override the brainstorm command for this project only
mkdir -p .claude/commands.local/erd
cp .claude/commands/erd/brainstorm.md .claude/commands.local/erd/brainstorm.md
$EDITOR .claude/commands.local/erd/brainstorm.md
```

After the next container start (or `bash .devcontainer/scripts/refresh-assets.sh`),
`.claude/commands/erd/brainstorm.md` will reflect your `.local/`
override; everything else under `.claude/commands/` keeps tracking
upstream. The `.local/` directory is user-owned and never touched by
the refresh.

The always-latest mechanism and `--upgrade` are **disjoint per path**:
the always-latest whitelist is excluded from manifest tracking
(`scripts/lib/common.sh::MANIFEST_EXCLUDE_GLOBS`). Files outside the
whitelist continue to flow through the manifest-driven upgrade path.

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
