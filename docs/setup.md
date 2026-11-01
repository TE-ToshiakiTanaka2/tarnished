# Setup reference

See the [README](../README.md) for first-time setup and everyday maintenance.

## AI workflow profiles

Tarnished keeps the implementation lifecycle in `.tarnished/workflows/` and
projects it into the agent-specific entrypoints used by Claude Code and Codex.
This keeps the workflow shape consistent across Claude-main and Codex-main
projects.

Run the current checkout's script from your new project directory, or pass the
same options to the remote setup command in the [README](../README.md).

```bash
# Default: Claude Code primary
bash /path/to/tarnished/setup.sh --ai-profile claude-main

# Codex primary, Claude Code as review handoff
bash /path/to/tarnished/setup.sh --ai-profile codex-main

# Install both projections and document cross-agent operation
bash /path/to/tarnished/setup.sh --ai-profile dual

# Backward-compatible alias: Claude primary + Codex reviewer
bash /path/to/tarnished/setup.sh --codex
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

## Runtime versions (`mise.toml`)

A generated project installs software in three layers, and a plain
`docker build` of `docker/Dockerfile.dev` produces the same environment as
VS Code or Zed. No devcontainer `features` are used.

| Layer | Declared in | Installed by | When |
| --- | --- | --- | --- |
| OS packages (git, gh, mise, build tools, `postgresql-client`, `default-mysql-client`, TeX Live) | `docker/Dockerfile.dev` | `apt-get` as root | image build |
| Language runtimes (node, python, uv, pnpm, rust, go, deno) | `mise.toml` | `mise install` as `vscode` | image build, and again on post-create |
| Claude Code, Codex CLI, Claude Code plugins | `.devcontainer/scripts/setup_*.sh`, `.claude/settings.json` | `npm install -g` / `claude plugin install` as `vscode` | post-create (`post.sh`) |

`mise.toml` is developer-owned: core ships it with `node = "22"`, each language
plugin adds its own entries (`python` + `uv`, `pnpm`, `rust`, `go`, `deno`), and
neither `setup.sh --upgrade` nor `--add-module` ever changes an entry you edited.

To change a version:

1. Edit the entry in `mise.toml` (for example `node = "24"`).
2. Run `mise install` in the container, or rebuild it. `post.sh` also runs
   `mise install` on post-create, so a pulled `mise.toml` change converges
   without a rebuild.
3. After a Node.js bump, run `bash .devcontainer/scripts/post.sh` once: npm
   global packages belong to one Node version, so the Claude Code and Codex CLI
   are reinstalled by their `post.sh` blocks (which run after the mise block).

Notes:

- mise also reads a `.tool-versions` file if you add one (asdf users), but
  Tarnished only generates `mise.toml`.
- `[env]` values in `mise.toml` (for example the Python `UV_*` settings) apply to
  processes started through mise shims or an activated shell, not to a process
  that is exec'd by absolute path, such as an editor extension launching the
  interpreter directly.
- `npm install -g` writes into the active Node's own directory under
  `~/.local/share/mise`, which the `vscode` user owns, so no step needs `sudo`.
  mise shims are not visible under `sudo`.
- Pin the AI CLIs without editing the managed helpers by setting
  `CLAUDE_CODE_NPM_PACKAGE` / `CODEX_NPM_PACKAGE` (for example
  `@anthropic-ai/claude-code@2.1.300`) in `containerEnv`.
- Claude Code plugins are declared in `.claude/settings.json`
  (`extraKnownMarketplaces`, `enabledPlugins`); only `context7` is enabled by
  default. `setup_plugins.sh` installs enabled plugins that are not installed
  yet after you have logged in to Claude Code. To opt out per developer, set the
  plugin to `false` in `.claude/settings.local.json`.
- Add a package to the image (for example another apt tool) in
  `docker/Dockerfile.dev` above the `SHELL` line; generated plugin blocks use the
  same spot.
- A CI workflow (`.github/workflows/scaffold-build.yml`) scaffolds and builds
  every language and service flavor except `latex` on amd64.

## Monorepo support

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
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- \
  --monorepo \
  --module backend:python \
  --module frontend:node \
  --postgresql -y

# Same shape with MySQL instead:
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- \
  --monorepo \
  --module backend:python \
  --module frontend:node \
  --mysql -y

# Add a module to an existing monorepo (auto-detected via modules.json,
# or explicit via --add-module):
curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --add-module worker --lang python -y
```

Resulting layout:

```
my-monorepo/
├── .devcontainer/        # shared (one devcontainer for the whole monorepo)
├── .claude/              # shared
├── docker/Dockerfile.dev # shared (OS packages and the mise runtime layer)
├── mise.toml             # shared, union of all module-language runtimes
├── docker-compose.yml    # shared; service names use <project>-<svc>
├── CLAUDE.md             # project-wide
├── modules.json          # registry: { "version": 1, "modules": [...] }
├── backend/              # module — own pyproject.toml, src/backend/, tests/
│   └── CLAUDE.md
└── frontend/             # module — own package.json, biome.json, src/, tests/
    └── CLAUDE.md
```

Each language plugin's per-module hook generates the language-idiomatic
scaffold inside the module directory; the shared root `mise.toml` contains the
union of every module's language runtimes. Subsequent `setup.sh --add-module`
invocations are idempotent against the shared root files (marker-guarded
blocks, and `mise.toml` entries are only added, never changed); run
`mise install` in the container afterwards to install a newly added runtime.

## Zed editor support

Pass `--zed` (or answer "y" to the "Enable Zed editor support?" prompt) to
add [Zed](https://zed.dev) support alongside the VS Code setup. This adds:

- `customizations.zed.extensions` in the generated `.devcontainer/devcontainer.json`
  — `customizations.vscode` is always kept, so the project opens in either
  editor
- `.zed/settings.json`, seeded by the core template and merged with
  per-language LSP/formatter settings for each selected language

```bash
./setup.sh --lang rust --zed
```

To open the generated project in Zed:

1. `zed .`
2. Accept the "Open in Container" prompt (or run "Project: Open Remote" from
   the command palette)

Requires Docker or Podman on `PATH`. If you use Podman, set `"use_podman": true`
in Zed's own user `settings.json` — this is a Zed user setting, not a key in
the generated `devcontainer.json`.

Caveats:

- **No automatic rebuild.** Zed does not rebuild or reload the container when
  `devcontainer.json` changes; stop the container and reopen after editing
  it.
- **Do not run VS Code and Zed on the same project at the same time.** The
  two editors derive different Compose project names while
  `docker-compose.yml` pins `container_name`, so the second editor to start
  collides with the first.
- **`forwardPorts` is ignored by Zed.** No generated file sets it today, so
  this only matters if you add the key by hand later.
- Extensions declared under `customizations.zed.extensions` are also
  installed into your local Zed, not just the container.

`.zed/settings.json` is developer-owned: it is not an AI asset, so it is
never touched by `refresh-assets.sh` or `setup.sh --upgrade`.
