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
`$implement`, `$review`, `$pr`, and `$flow`. The generated `AGENTS.md` also treats
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

### Maintaining an existing project

Tarnished prepares and maintains an AI-agent development foundation. The downstream developer owns the software under development and its settings. Tarnished maintainers publish shared skills and harness improvements centrally, so model-related workflow improvements do not require each project to rewrite its skills.

| Asset | Owner and maintenance authority |
| --- | --- |
| Application source, tests, docs, build/package files, Docker/CI files, root instructions and `post.sh` | Developer-owned scaffold seeds after creation; maintenance never overwrites or prunes them |
| Claude/Codex skills, commands, agents, scripts and shared workflow contracts | Distributed by Tarnished; update only with proven unchanged installed bytes |
| `.devcontainer/scripts/*.sh` helpers other than `post.sh` | Eligible for manifest upgrades when their installed provenance is proven |
| Profiles, model overrides, CLI settings, `refresh.json`, extra files and `.local` sidecars | Developer-owned configuration/customization; preserve during maintenance |
| Manifest and refresh state | Installed provenance, not an inventory of everything in a project |
| Conflicting or unknown file | Developer decision required; preserve and report current and candidate paths |

A bare setup rerun in an existing Tarnished project performs AI refresh. Explicit scaffold options are rejected there; add a monorepo module with `--add-module <name> --lang <language>`. `--overwrite` does not grant permission to re-scaffold an existing project.

Run the **current Tarnished checkout's** script from your downstream project directory:

```bash
bash /path/to/tarnished/setup.sh --refresh --dry-run
bash /path/to/tarnished/setup.sh --refresh -y
```

Refresh uses the current checkout's updater and distribution, preserving application code, settings, profile selection and role/model overrides. Container-start refresh uses the installed `.devcontainer/scripts/refresh-assets.sh` and the configured upstream. For the shipped `/opt/tarnished` cache only, when it is absent and `/opt` is unwritable, runtime refresh uses the validated `~/.cache/tarnished` cache. Existing unsafe, dirty or unrelated caches are preserved and never bypassed by fallback. Runtime failures warn with recovery instructions and return success so the container can start. Unknown CLI flags remain errors.

### AI distribution, customization and migration

`.tarnished/refresh.json` selects the upstream repository, branch, cache and managed paths. New defaults set `use_default_managed_paths: true`: a valid upstream catalog can add future mappings while project settings remain intact. The catalog covers Claude assets, applicable Codex `.agents/skills`, shared workflow `.md` contracts, and the separate erd projection. Codex skills refresh when the project selected Codex or already installed them; Claude/shared policy remains available for every profile. No model or profile is automatically selected or changed.

An absent/false `use_default_managed_paths` keeps the explicit `managed_paths` list authoritative, including an empty list. Current `setup.sh --refresh` creates missing configuration and opts in only exactly recognized shipped legacy catalogs whose opt-in key is absent, preserving other fields. Explicit `false` remains authoritative even when its mappings match an old shipped catalog. Custom catalogs receive guidance to add mappings from `templates/agent-workflows/.tarnished/refresh.json` or explicitly enable defaults once. Runtime refresh never rewrites configuration.

Refresh records successful installed/adopted hashes in `.tarnished/refresh-state.json`. It enumerates upstream assets and sidecars, not project files as owned. Unknown siblings, local edits and user deletions survive. Missing state permits adoption only of matching distribution bytes. An upstream removal deletes only its proven, unchanged upstream-origin file. Removed/reconfigured mappings preserve former files. Repeated runs still reconcile overlays and retry conflicts even when the upstream commit is unchanged.

To explicitly override a distributed asset, copy it to its configured `.local` sidecar and edit the sidecar:

```bash
mkdir -p .claude/commands.local/erd
cp .claude/commands/erd/brainstorm.md .claude/commands.local/erd/brainstorm.md
$EDITOR .claude/commands.local/erd/brainstorm.md
```

The live projection updates only when it matches its previous installed baseline. Direct edits to the live projection are preserved as conflicts. Removing a sidecar restores upstream only if the projection remains unchanged; overlay-origin files absent from both upstream and sidecar are preserved. Overlay-only added files are supported. For shared erd behavior, duplicate overrides into `.tarnished/workflows/erd.local/`; the two erd projections have separate sidecars. Codex uses `.agents/skills.local`; shared contracts use `.tarnished/workflows.local/<file>.md`.

For existing installations, inspect `--refresh --dry-run`, then run `--refresh`. The same command replaces a missing, exactly recognized shipped legacy, or unchanged helper with a trusted version-2 installed baseline with the current safe helper. It records that baseline for subsequent updater releases. An edited/unrecognized helper is preserved and its exact source and destination paths are reported: **review and explicitly copy the safe helper before the next container start**. A safe one-shot refresh does not make an unconverted legacy installed script safe. Custom hooks and settings are retained.

When a conflict is reported, compare the named project file with the named source/cache candidate. Keep an override in its corresponding `.local` path if desired, then explicitly copy the chosen upstream base into the live destination (or remove an unknown collision) and rerun. Exact matches can be adopted safely. Unknown legacy content that differs from today's distribution needs this one-time review; it is never silently declared owned. Older rendered workflow contracts may conflict with the current profile-neutral contracts: compare and adopt the current file once, keeping profile/model choices in `.tarnished/agent-profile.json`. Files already deleted by older scripts cannot be recovered by provenance migration.

Dry-run writes no target/config/state/summary files or persistent cache and uses a valid local source/cache for exact planned actions. If none exists, it reports that the upstream comparison is unavailable. Refresh state is generated local metadata: add `.tarnished/refresh-state.json` to your ignore rules if it is not already ignored; maintenance does not rewrite your `.gitignore`.

### Runtime-helper upgrades and provenance

AI distribution and manifest upgrades have disjoint ownership. `--upgrade` is limited to delivered `.devcontainer/scripts/*.sh` helpers other than `post.sh`; files outside that positive set are developer-owned. It stages plugins privately and never replays post-copy hooks against your project.

```bash
# First adoption for a project without a manifest: compare actual distribution bytes.
bash /path/to/tarnished/setup.sh --create-manifest -y
# Optional: compare an available historical distribution, not merely label current bytes.
bash /path/to/tarnished/setup.sh --create-manifest --from-version <ref> -y
bash /path/to/tarnished/setup.sh --upgrade --dry-run
bash /path/to/tarnished/setup.sh --upgrade -y
bash /path/to/tarnished/setup.sh --upgrade --target-version <ref> -y
bash /path/to/tarnished/setup.sh --upgrade --shared-only -y
bash /path/to/tarnished/setup.sh --upgrade --module backend -y
# Remove only proven unchanged helpers that disappeared upstream.
bash /path/to/tarnished/setup.sh --upgrade --prune -y
```

Manifest version 2 records successful installed or exact distribution matches. Fresh scaffolding records only successful template copies and rehashes those paths after rendering. Bootstrap compares eligible staged candidates, never walks the downstream repository to infer ownership. Legacy version-1 claims are untrusted: arbitrary source/settings and unknown obsolete files are preserved and their claims dropped; only exact eligible distribution matches can be adopted. A ref name or old manifest hash alone is not proof.

Edited/deleted files retain their installed baseline, as do upstream removals until explicitly pruned. Missing legacy helpers retain separate `deleted_paths` tombstones across repeated bootstrap, upgrade and refresh; these express deletion intent without claiming trusted content. Restore an exact distribution copy to explicitly adopt such a path again. Baselines advance only after installation or an exact current/desired match. `--force` bypasses the upgrade clean-tree precondition and never bypasses ownership or conflict checks.

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
