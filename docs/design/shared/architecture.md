# Architecture

## Overview

`tarnished` is the source repository for **`erd`**, a Rust CLI for GitHub Issue and Tag/release management, plus a collection of templates that downstream projects use to bootstrap their devcontainer, Claude Code, Codex CLI, languages, services, and GitHub Actions setups.

The repository serves two audiences:

1. **`erd` CLI users** — who consume the binary (or its installer) to manage issues, link them to GitHub Projects (with optional label-based routing), and produce semver tags from branch prefixes.
2. **Downstream project authors** — who run `setup.sh` to copy the relevant `templates/*` into their own repos, in either single-project or monorepo shape.

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
│   │   ├── plugin.sh                 # Single-mode + monorepo-aware (#263): writes modules.json,
│   │   │                             #   per-module CLAUDE.md
│   │   ├── modules.json.template     # Empty registry seed (#263, monorepo only)
│   │   ├── module.CLAUDE.md.template # Per-module CLAUDE.md stub (#263, monorepo only)
│   │   ├── docker-compose.yml        # Dev service `{{PROJECT_NAME}}`
│   │   └── docker/Dockerfile.dev     # Base image; language plugins append marker-guarded blocks
│   ├── languages/{deno,python,node,latex,rust,go}/
│   │   └── plugin.sh                 # Implements plugin_post_copy_shared + plugin_post_copy_module
│   │                                 #   (#263); legacy plugin_post_copy retained as backward-compat shim.
│   │                                 #   Go (#274) follows the Rust shape: gofmt/golangci-lint/gotestsum,
│   │                                 #   no auto `go mod init`, .golangci.yml is per-module
│   ├── services/{mysql,redis,celery,postgresql}/
│   │                                 # docker-compose overlay + plugin.sh.
│   │                                 #   Service names already use `{{PROJECT_NAME}}-<svc>`
│   │                                 #   (e.g., `myapp-db`); same convention works for monorepo where
│   │                                 #   `{{PROJECT_NAME}}` resolves to the monorepo name (#263)
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
│   ├── lib/common.sh                 # Shared shell utilities — output helpers, file copy, JSON merge,
│   │                                 #   docker-compose merge, gitignore seeding (#259), TTY detection,
│   │                                 #   prompts, modules.json helpers (#263), monorepo prompts (#263),
│   │                                 #   sha256_file wrapper + manifest-recording extension to
│   │                                 #   copy_with_confirm (#265). Sourced by setup.sh and every plugin.sh.
│   └── lib/manifest.sh               # Manifest read/write, lifecycle decisions, summary printer (#265).
│                                     #   Sourced by setup.sh in --create-manifest and --upgrade modes.
├── setup.sh                          # Top-level template-installer entry. Five operating modes:
│                                     #   single + monorepo init + add-module (#263) + create-manifest +
│                                     #   upgrade (#265). #246: command-list completion message.
└── tests/                            # Integration tests
```

A monorepo target produced by `setup.sh --monorepo` (#263) carries an additional root `modules.json` and per-module sub-directories. Once `setup.sh --create-manifest` (#265) has been run, each scope also carries a `.tarnished-manifest.json` that records sha256 hashes of every "verbatim copy" file, used by `setup.sh --upgrade` (#265) to distinguish unedited from user-edited files:

```
<project>/
├── .devcontainer/                   # shared (root)
├── .claude/                         # shared (root)
├── docker/Dockerfile.dev            # shared, union of all module-language toolchains
├── docker-compose.yml               # shared; dev service `<project>`, optional `<project>-db`/`-redis`/...
├── CLAUDE.md                        # shared; project-wide context
├── modules.json                     # registry (FR-4)
├── .tarnished-manifest.json         # manifest of shared/root verbatim files (#265)
├── jing/                            # module — own pyproject.toml/Cargo.toml/package.json + src/ + tests/
│   ├── CLAUDE.md
│   └── .tarnished-manifest.json     # per-module manifest (#265)
├── kir/                             # module
│   ├── CLAUDE.md
│   └── .tarnished-manifest.json
└── .gitignore
```

Single-mode targets carry one root-level `.tarnished-manifest.json` instead of the per-module split.

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

The shell side (`setup.sh` + `scripts/lib/{common,manifest}.sh` + per-template `plugin.sh`) follows a parallel layered shape:

```
setup.sh (orchestration; flag parsing; mode selection: single | monorepo init | add-module |
          create-manifest | upgrade; plugin discovery and post-copy dispatch;
          upgrade-mode staging area + lifecycle decision loop, #265)
    │
    ▼
scripts/lib/common.sh (shared utilities — output, copy, merge, gitignore seeding, TTY,
                       monorepo prompts, modules.json helpers, sha256_file (#265),
                       copy_with_confirm manifest-recording extension (#265))
scripts/lib/manifest.sh (manifest read/write, manifest_decide lifecycle state machine,
                         manifest_apply, summary printer — #265)
    │
    ▼
templates/<flavor>/plugin.sh (per-flavor copy + post-copy hooks: codex, claude, ...)
        │
        ├── language plugins (#263): plugin_post_copy splits into
        │     plugin_post_copy_shared(root) + plugin_post_copy_module(target, module_name)
        │
        └── core / claude / codex / services / github-actions plugins:
              plugin_post_copy(root) only (no per-module split needed; service plugins
              already use {{PROJECT_NAME}}-<svc> which works in both modes)
```

The `setup.sh` orchestrator dispatches the post-copy hook differently based on `MONOREPO_MODE` and the plugin's family (path under `templates/languages/` vs. elsewhere). Single mode dispatch is unchanged from prior to #263. In upgrade mode (#265) the same dispatch runs, but with the copy destination redirected into a per-scope staging directory; the lifecycle decision loop then compares (manifest_old, current_target, staging_new) hashes per file and applies the decision to the real target.

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
| Shell registry format | JSON via `jq` | `modules.json` registry is JSON; `jq` already a required dep |

Template plugins are POSIX shell. Claude/Codex setup uses `claude plugins install -s project` against the `claude-plugins-official` marketplace (#249, #255).

## Cross-cutting Concerns

- **Config loading**: Both `ProjectConfig` (`project.yml`) and `Config` (in `tag_config.rs`) use `#[serde(default)]` aggressively for backward compatibility (which once silently masked a wrong template format — see #228).
- **Logging / verbosity**: Routed through the global `Config` (verbose flag).
- **Idempotency**: All shell setup helpers (`setup_plugins.sh`, `plugin.sh`, marketplace registration, `update_gitignore`) MUST be idempotent. `set -e` in `post.sh` requires careful return-0 on non-fatal failures (#255). Idempotency comes in three flavors:
  1. **Line-level** (`grep -q "^<line>$"` before append, used for single-line cases).
  2. **Block-level** (`grep -q "^<marker>$"` keying off a comment marker that the function itself writes, used for multi-line whitelist blocks — see Gitignore policy below, #259, and the `Dockerfile.dev` / `post.sh` language toolchain blocks introduced by #263).
  3. **JSON-merge** (`merge_devcontainer_json`, `merge_docker_compose_services`): structural merge that is idempotent by construction.
- **Plugin failures**: Wrapped per-plugin so one failure does not abort the whole setup (#255). This includes optional integrations like the GitHub Project Integration plugin, whose `gh` CLI auto-detection helpers always return 0 — failures are surfaced via `print_warning` with a captured first-line gh stderr (held in the per-process tempfile `GH_LAST_ERROR_FILE`, established via `mktemp` at plugin source time so the path is unpredictable and the FS state survives the `$(...)` subshells that callers use), and control falls through to manual prompts (#276). The previous design `var=$(gh ... 2>/dev/null)` under `set -e` was fragile: a `gh` non-zero exit would abort the script before the manual fallback ran. The plugin deliberately does not register an `EXIT` trap on this tempfile — sourcing happens after `setup.sh --upgrade`'s `cleanup_upstream_dir EXIT` trap is set, and an unconditional trap would replace it and leak the upstream clone.
- **Remote bootstrap stdin invariant** (#276): When `setup.sh` is invoked as `curl -fsSL .../setup.sh | bash`, the bootstrap block (`setup.sh:29-69`) clones the repo and `exec bash "$TEMP/setup.sh" "$@" < /dev/null`. The `< /dev/null` is required: without it, the outer curl write pipe is inherited across `exec` and the residual write fails with EPIPE, printing a spurious `curl: (23) Failure writing output to destination` to the user's terminal mid-setup. The redirect makes the new process's stdin `/dev/null`; curl finishes cleanly. Local `./setup.sh` invocations skip the bootstrap block and are unaffected.
- **GitHub API**: All calls go through `github/client.rs`. Rate-limit errors propagate as `GitHubClientError`. Non-fatal issues (e.g., a label-routed project not found) are logged as warnings (#230).
- **Workflow triggers**: `project-integration.yml` triggers on `[opened, reopened, labeled]` so label routing fires when labels are added post-creation (#230). Optional sub-features are split out (#244).
- **GitHub Actions JS runtime** (#267): Every JavaScript action `uses:` pin in `.github/workflows/*.yml` targets a major whose `action.yml` declares `runs.using: node24`. Composite actions (`dtolnay/rust-toolchain@stable`, `taiki-e/install-action@*`) are exempt — they have no Node runtime. The selection rule is **earliest Node-24 major** so each upgrade introduces only the runtime change and not unrelated behavior shifts (e.g., `actions/checkout` is pinned to `@v5`, not `@v6` whose credential-persistence change is unneeded). The three reusable workflows (`auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`) are consumed by downstream repos via `workflow_call`; the callee's pins are what execute, so a tarnished-side bump propagates transparently to every consumer (e.g., freyja). The `templates/github-actions/*` and `templates/languages/*/...yml` distribution channel — which `setup.sh` copies *verbatim* into newly scaffolded downstream projects — is governed by the same rule but tracked separately (the #267 scope was the root workflows only).
- **Design artifact maintenance**: `/design` reads `docs/design/shared/*` first, regenerates them as a snapshot at the end (NFR-1: never append, always overwrite). `/implement` reads both layers (#257).
- **Gitignore policy** (#259): Downstream projects' `.gitignore` is seeded by `scripts/lib/common.sh::update_gitignore()` and per-plugin gitignore steps (e.g., `templates/codex/plugin.sh::plugin_post_copy`). The seed is **whitelist-style** for `.claude/` and `.codex/` — `.claude/*` and `.codex/*` are ignored, with explicit allowlist for project-tracked subdirectories (`commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, `settings.json` for Claude; `config.toml` for Codex). Always-ignore directives cover `.serena/` (Serena MCP working files) and `screenshots/` (manual UI testing). Block-level idempotency: each block is preceded by a stable comment marker; `grep -q` keys on the marker. User-authored lines between or after blocks are preserved. The tarnished workspace itself carries the Codex whitelist block (#261).
- **Workspace Codex dogfooding** (#261): The tarnished workspace carries its own copy of the artifacts that `templates/codex/` produces for downstream projects — root `AGENTS.md`, `.codex/config.toml`, `.devcontainer/scripts/setup_codex.sh`, the `Bash(codex:*)` Claude permission, and the gitignore whitelist block — so the `/review` skill (which requires `codex` on `$PATH`) can run against this repo. The plugin runtime is **not** invoked against the workspace; the files are hand-applied to preserve existing workspace customizations. `setup_codex()` itself is hooked into `post.sh` after `setup_plugins`, sharing the same `set -e` non-fatal-return-0 contract. Project-level Codex config (`/workspace/.codex/config.toml`) and the template default (`templates/codex/.codex/config.toml`) are kept in sync at the latest model + reasoning-effort settings so new projects inherit the same review quality as the workspace.
- **`setup.sh` operating mode** (#263, #265): `setup.sh` exposes five orthogonal modes: **single** (today's behavior, default), **monorepo init** (`--monorepo` or `--module`, or interactive "y" answer), **add-module** (`--add-module`, or auto-detected when CWD already contains `modules.json`), **create-manifest** (`--create-manifest`, #265), and **upgrade** (`--upgrade`, #265). Mode selection happens in `main()` after argument parsing and before language/service selection. Single mode is byte-identical to the pre-#263 flow (NFR-1). Monorepo mode introduces three new invariants: (a) `modules.json` is the source of truth for which modules exist and what languages they use; (b) language plugins partition their `plugin_post_copy` work into `_shared` (root-only writes) and `_module` (per-module writes), dispatched per-mode by the orchestrator; (c) `Dockerfile.dev` and `post.sh` language toolchain blocks become marker-guarded for block-level idempotency so add-module re-runs are safe. Service plugins remain mode-agnostic because their existing `{{PROJECT_NAME}}-<svc>` naming convention naturally produces monorepo-correct service names. Per-module `.devcontainer/<module>/devcontainer.json` (elsur-style "Reopen in Container per module") and GitHub Actions matrix workflows are explicit non-goals of #263, deferred to follow-up issues.
- **Manifest-driven upgrades** (#265): The single, monorepo-init, and add-module modes scaffold or extend a project. The new create-manifest and upgrade modes are *post-scaffold* — they operate against an existing target. Create-manifest walks the target tree, hashes every "verbatim copy" file (excluding merge/dynamic/user-owned files per FR-3), and writes `.tarnished-manifest.json`. Upgrade reads the manifest, clones upstream tarnished at `--target-version` (default: `${REMOTE_BRANCH}` HEAD), runs the same plugin pipeline against a staging directory with `MANIFEST_RECORDING` enabled, and then applies a per-file lifecycle decision (`manifest_decide` — 8 cases: NOOP / UPDATE / SKIP_EDITED / NEW / SKIP_NEW_CONFLICT / LEAVE_REMOVED / PRUNE / SKIP_USER_DELETED) keyed on `(old_hash, current_hash, new_hash)`. The "did the user edit this file" predicate is `current_hash == old_hash`, evaluated only inside `manifest_decide`. Plugin contract stays unchanged (NFR-1): tracking is achieved by extending `copy_with_confirm` to opportunistically populate a global `MANIFEST_TRACKED` map when recording is enabled. After verbatim-file decisions are applied, `plugin_post_copy` is re-run against the real target to re-apply merge logic (`.gitignore` whitelist blocks, `devcontainer.json` JSON merges, `.claude/settings.json` hooks merge) — this relies on the existing line-/block-/JSON-merge idempotency invariants. Upgrade is gated on a clean git tree (`git diff-index --quiet HEAD --`) unless `--force` is passed; honors `--dry-run` to preview without writing; and supports monorepo scope filters (`--shared-only`, `--module <name>` repeatable) and an opt-in `--prune` flag for files removed upstream.
