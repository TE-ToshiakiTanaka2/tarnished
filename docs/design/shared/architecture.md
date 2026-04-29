# Architecture

## Overview

`tarnished` is the source repository for **`erd`**, a Rust CLI for GitHub Issue and Tag/release management, plus a collection of templates that downstream projects use to bootstrap their devcontainer, Claude Code, Codex CLI, languages, services, and GitHub Actions setups.

The repository serves two audiences:

1. **`erd` CLI users** — who consume the binary (or its installer) to manage issues, link them to GitHub Projects (with optional label-based routing), and produce semver tags from branch prefixes.
2. **Downstream project authors** — who run `setup.sh` to copy the relevant `templates/*` into their own repos.

Design artifacts are split into a shared cumulative layer (this directory) and per-issue deltas under `docs/design/#{issue}/`. The split keeps `/design` and `/implement` read costs constant rather than linear in completed-issue count (introduced by #257).

## Module Structure

```
.
├── src/                              # erd Rust crate
│   ├── main.rs                       # Binary entrypoint, clap CLI dispatch
│   ├── cli/                          # CLI subcommand handlers
│   │   └── issue.rs                  # `erd issue link` — links an issue to default + label-routed projects
│   ├── github/                       # GitHub REST/GraphQL client + types
│   │   ├── client.rs
│   │   └── types.rs                  # GetIssueResponse, IssueLabel, ProjectV2, ...
│   ├── config.rs                     # Global CLI config
│   ├── project_config.rs             # `.github/project.yml` schema (incl. label_projects, #230)
│   ├── tag_config.rs                 # `versioning.yml` schema with dual-format support (#228)
│   ├── version.rs                    # semver bump logic
│   ├── git_ops.rs                    # git invocation helpers
│   ├── date_parser.rs                # iteration date parsing
│   └── error.rs                      # thiserror error types
├── templates/
│   ├── claude/                       # Claude Code skills, settings, scripts, devcontainer
│   │   ├── .claude/
│   │   │   ├── skills/               # User-invocable skills (issue, design, implement, pr, review)
│   │   │   ├── skills/_shared/       # Internal shared skills (branch, issue, design-migration)
│   │   │   ├── commands/erd/         # Internalized SuperClaude-style commands (#240)
│   │   │   ├── settings.json
│   │   │   └── scripts/
│   │   ├── .devcontainer/            # Claude-flavored devcontainer + plugin install scripts (#249, #255)
│   │   ├── CLAUDE.md
│   │   └── plugin.sh
│   ├── codex/                        # Codex CLI flavor
│   ├── core/                         # Base devcontainer + docker-compose
│   ├── languages/{deno,python,node,latex,rust}/
│   ├── services/{mysql,redis,celery,postgresql}/
│   └── github-actions/
│       ├── auto-tag/                 # Tag/release workflow + plugin.sh
│       └── project-integration/      # Project linking workflows + plugin.sh (#244 sub-feature: label routing)
├── .claude/skills/                   # In-repo Claude Code skills (mirror of templates/claude/.claude/skills/)
├── .codex/config.toml                # Project-level Codex CLI config — workspace dogfooding of templates/codex/ (#261)
├── AGENTS.md                         # Tarnished-specific Codex review-agent definition (#261)
├── .devcontainer/
│   ├── devcontainer.json             # Workspace devcontainer (Rust, Claude Code, Node.js LTS for Codex CLI)
│   └── scripts/
│       ├── post.sh                   # Post-create: git/SSH/Rust/codespell/setup_plugins/setup_codex (#261)
│       ├── setup_plugins.sh          # Claude marketplace + plugin install (#249, #255)
│       └── setup_codex.sh            # Sudo-aware npm install of @openai/codex (#261)
├── docs/design/                      # Design artifacts
│   ├── shared/                       # Cumulative project truth (this layer, #257)
│   └── #{issue}/                     # Per-issue deltas
├── docker/, docker-compose.yml       # Dev environment
├── scripts/
│   └── lib/common.sh                 # Shared shell utilities — output helpers, file copy, JSON merge,
│                                     #   docker-compose merge, gitignore seeding (#259), TTY detection,
│                                     #   prompts. Sourced by setup.sh and every plugin.sh.
├── setup.sh                          # Top-level template-installer entry (#246: command-list message)
└── tests/                            # Integration tests
```

## Layer Boundaries

The Rust crate follows a thin layered structure:

```
main.rs (clap dispatch)
    │
    ▼
cli/* (subcommand handlers; orchestration only)
    │
    ▼
github/* (transport + types) ──── project_config.rs / tag_config.rs (config layer, serde)
    │
    ▼
git_ops.rs / version.rs / date_parser.rs (pure helpers)
    │
    ▼
error.rs (thiserror — common error type)
```

- **CLI layer** (`cli/*`) does no I/O of its own beyond what the GitHub or git_ops layers expose.
- **GitHub layer** owns all `reqwest` calls and is the only place that touches the network.
- **Config layer** (`project_config.rs`, `tag_config.rs`) owns all `serde_yaml` parsing.
- **Helpers** (`version.rs`, `git_ops.rs`, `date_parser.rs`) are pure or shell-only.
- **Errors** flow up via `anyhow::Result` at command boundaries; `thiserror` provides structured intermediate errors.

Templates are independent and have no Rust dependency — they are plain files copied by `setup.sh`.

The shell side (`setup.sh` + `scripts/lib/common.sh` + per-template `plugin.sh`) follows a parallel layered shape:

```
setup.sh (orchestration; flag parsing; plugin discovery)
    │
    ▼
scripts/lib/common.sh (shared utilities — output, copy, merge, gitignore seeding, TTY)
    │
    ▼
templates/<flavor>/plugin.sh (per-flavor copy + post-copy hooks: codex, claude, ...)
```

## Technology Choices

| Area | Choice | Rationale |
| --- | --- | --- |
| Language | Rust 2021, MSRV 1.74 | Single binary, strong types for config schemas |
| CLI | `clap` (derive + env) | Standard ergonomic CLI |
| HTTP | `reqwest` (rustls-tls, json) | rustls avoids OpenSSL toolchain in containers |
| YAML | `serde_yaml` 0.9 | Project/tag config files are YAML |
| Async | `tokio` (rt-multi-thread, macros) | Required by reqwest |
| Errors | `anyhow` + `thiserror` | `anyhow` at boundary, `thiserror` for structured kinds |
| Time | `chrono` (serde) | Iteration date math |
| Versioning | `semver` 1 | Tag bump computation |
| Lints | clippy `all` + `pedantic` (warn) | Aggressive baseline; per-line `allow` when warranted |
| Test | `assert_cmd` + `predicates` | Black-box CLI testing |

Template plugins are POSIX shell. Claude/Codex setup uses `claude plugins install -s project` against the `claude-plugins-official` marketplace (#249, #255).

## Cross-cutting Concerns

- **Config loading**: Both `ProjectConfig` (`project.yml`) and `Config` (in `tag_config.rs`) use `#[serde(default)]` aggressively for backward compatibility (which once silently masked a wrong template format — see #228).
- **Logging / verbosity**: Routed through the global `Config` (verbose flag).
- **Idempotency**: All shell setup helpers (`setup_plugins.sh`, `plugin.sh`, marketplace registration, `update_gitignore`) MUST be idempotent. `set -e` in `post.sh` requires careful return-0 on non-fatal failures (#255). Idempotency comes in two flavors: line-level (`grep -q "^<line>$"` before append, used for single-line cases) and block-level (`grep -q "^<marker>$"` keying off a comment marker that the function itself writes, used for multi-line whitelist blocks — see Gitignore policy below, #259).
- **Plugin failures**: Wrapped per-plugin so one failure does not abort the whole setup (#255).
- **GitHub API**: All calls go through `github/client.rs`. Rate-limit errors propagate as `GitHubClientError`. Non-fatal issues (e.g., a label-routed project not found) are logged as warnings (#230).
- **Workflow triggers**: `project-integration.yml` triggers on `[opened, reopened, labeled]` so label routing fires when labels are added post-creation (#230). Optional sub-features are split out (#244).
- **Design artifact maintenance**: `/design` reads `docs/design/shared/*` first, regenerates them as a snapshot at the end (NFR-1: never append, always overwrite). `/implement` reads both layers (#257).
- **Gitignore policy** (#259): Downstream projects' `.gitignore` is seeded by `scripts/lib/common.sh::update_gitignore()` and per-plugin gitignore steps (e.g., `templates/codex/plugin.sh::plugin_post_copy`). The seed is **whitelist-style** for `.claude/` and `.codex/` — `.claude/*` and `.codex/*` are ignored, with explicit allowlist for project-tracked subdirectories (`commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, `settings.json` for Claude; `config.toml` for Codex). Always-ignore directives cover `.serena/` (Serena MCP working files) and `screenshots/` (manual UI testing). Block-level idempotency: each block is preceded by a stable comment marker; `grep -q` keys on the marker. User-authored lines between or after blocks are preserved. The tarnished workspace itself carries the Codex whitelist block (#261).
- **Workspace Codex dogfooding** (#261): The tarnished workspace carries its own copy of the artifacts that `templates/codex/` produces for downstream projects — root `AGENTS.md`, `.codex/config.toml`, `.devcontainer/scripts/setup_codex.sh`, the `Bash(codex:*)` Claude permission, and the gitignore whitelist block — so the `/review` skill (which requires `codex` on `$PATH`) can run against this repo. The plugin runtime is **not** invoked against the workspace; the files are hand-applied to preserve existing workspace customizations. `setup_codex()` itself is hooked into `post.sh` after `setup_plugins`, sharing the same `set -e` non-fatal-return-0 contract. Project-level Codex config (`/workspace/.codex/config.toml`) and the template default (`templates/codex/.codex/config.toml`) are kept in sync at the latest model + reasoning-effort settings so new projects inherit the same review quality as the workspace.
