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
scaffold inside the module directory; the shared `docker/Dockerfile.dev`
contains the union of every module's language toolchain. Subsequent
`setup.sh --add-module` invocations are idempotent against the shared root
files (marker-guarded blocks).
