# Architecture

## Overview

`tarnished` is the source repository for **`erd`**, a Rust CLI for GitHub Issue and Tag/release management, plus development-foundation templates. Developers use initial scaffolding to establish a project and ongoing maintenance to receive centrally optimized AI skills/harnesses without damaging application work. Tarnished maintainers own distributed defaults; downstream developers own application code, scaffold seeds, profiles/settings and customizations.

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
│   │   │   ├── skills/               # User-invocable skills (issue, design, implement, pr, review, flow #308)
│   │   │   ├── skills/_shared/       # Internal shared skills (branch, issue, design-migration, delegation #308)
│   │   │   ├── agents/               # Subagent definitions (code-reviewer; designer + executor #312,
│   │   │   │                         #   replacing advisor #308); always-latest (#279)
│   │   │   ├── commands/erd/         # Internalized SuperClaude-style commands (#240)
│   │   │   ├── rules/                # Language-agnostic coding rules distributed always-latest (#279, e.g. shell.md)
│   │   │   ├── settings.json
│   │   │   └── scripts/
│   │   ├── .devcontainer/scripts/setup_plugins.sh  # Fallback installer for enabledPlugins (#325)
│   │   ├── CLAUDE.md
│   │   └── plugin.sh
│   ├── codex/                        # Codex CLI flavor (AGENTS.md, .codex/, .agents/, setup_codex.sh;
│   │                                 #   no devcontainer overlay since #325)
│   ├── core/                         # Base devcontainer + docker-compose + install substrate (#325)
│   │   ├── plugin.sh                 # Single-mode + monorepo-aware (#263): writes modules.json,
│   │   │                             #   per-module CLAUDE.md; wires refresh-assets.sh into post.sh (#279);
│   │   │                             #   appends the mise + Claude Code post.sh blocks (#325)
│   │   ├── mise.toml                 # Runtime source of truth (#325): [tools] node = "22";
│   │   │                             #   language plugins add entries via mise_toml_ensure
│   │   ├── modules.json.template     # Empty registry seed (#263, monorepo only)
│   │   ├── module.CLAUDE.md.template # Per-module CLAUDE.md stub (#263, monorepo only)
│   │   ├── docker-compose.yml        # Dev service `{{PROJECT_NAME}}`
│   │   ├── docker/Dockerfile.dev     # Base image (#325): root apt (git, build tools), gh apt repo,
│   │   │                             #   pinned + minisign-verified mise, SHELL anchor for plugin
│   │   │                             #   OS-package blocks, then the `vscode` mise runtime layer
│   │   ├── .zed/                     # Optional Zed editor contribution (#323). NOT copied verbatim:
│   │   │                             #   devcontainer.json is a merge overlay carrying only
│   │   │                             #   customizations.zed; settings.json is installed as
│   │   │                             #   <target>/.zed/settings.json by common.sh::apply_zed_assets
│   │   └── .devcontainer/scripts/
│   │       ├── refresh-assets.sh     # Always-latest asset sync (#279): clones upstream tarnished into
│   │       │                         #   /opt/tarnished and safely updates owned paths on every container
│   │       │                         #   start (postStartCommand + first-boot call from post.sh)
│   │       ├── setup_mise.sh         # setup_mise(): `mise install` on post-create (#325)
│   │       ├── setup_claude.sh       # setup_claude(): npm install of Claude Code (#325)
│   │       └── npm_global_cli.sh     # Library shared by setup_claude / setup_codex (#325)
│   ├── languages/{deno,python,node,latex,rust,go,godot}/
│   │   ├── plugin.sh                 # Implements plugin_post_copy_shared + plugin_post_copy_module
│   │   │                             #   (#263); legacy plugin_post_copy retained as backward-compat shim.
│   │   │                             #   Runtimes are mise.toml entries (#325); plugin_dockerfile is
│   │   │                             #   implemented only for OS packages: latex (TeX Live) and
│   │   │                             #   godot (X11/Wayland/Mesa/Vulkan/audio + .NET prerequisites, #331).
│   │   │                             #   Go (#274) follows the Rust shape: gofmt/golangci-lint/gotestsum,
│   │   │                             #   no auto `go mod init`, .golangci.yml is per-module.
│   │   │                             #   Godot (#331) is tooling-only (no project.godot / export presets /
│   │   │                             #   GUT): .NET editor + dotnet + gdtoolkit in mise.toml (aliased
│   │   │                             #   github:/pypi: backends), gdlintrc + .editorconfig per module,
│   │   │                             #   plugin_interactive_setup for the WSLg GUI opt-in
│   │   ├── .zed/                     # Per-language Zed extensions + LSP/formatter fragment (#323);
│   │   │                             #   merged at root scope from plugin_post_copy_shared
│   │   └── godot/docker-compose.godot-gui.yml
│   │                                 # WSLg GUI overlay (#331): copied to the project root, never merged
│   │                                 #   into docker-compose.yml; active only while listed in
│   │                                 #   devcontainer.json dockerComposeFile
│   ├── services/{mysql,redis,celery,postgresql}/
│   │                                 # docker-compose overlay + plugin.sh (+ optional .zed/ for
│   │                                 #   postgresql/mysql, #323). postgresql/mysql install their
│   │                                 #   client through a marker-guarded plugin_dockerfile apt block (#325).
│   │                                 #   Service names already use `{{PROJECT_NAME}}-<svc>`
│   │                                 #   (e.g., `myapp-db`); same convention works for monorepo where
│   │                                 #   `{{PROJECT_NAME}}` resolves to the monorepo name (#263)
│   └── github-actions/
│       ├── auto-tag/                 # Tag/release workflow + plugin.sh
│       └── project-integration/      # Project linking workflows + plugin.sh (#244 sub-feature: label routing)
├── .claude/skills/                   # In-repo Claude Code skills (mirror of templates/claude/.claude/skills/)
├── .claude/agents/                   # In-repo subagent definitions (mirror of templates/claude/.claude/agents/)
├── .claude/rules/                    # In-repo coding rules (shell.md, language-specific rust.md/...)
│                                     #   shell.md is dogfooded from templates/claude/.claude/rules/shell.md (#279)
├── .codex/config.toml                # Project-level Codex CLI config — workspace dogfooding of templates/codex/ (#261)
├── .tarnished/refresh.json           # Workspace dogfooding of templates/agent-workflows/.tarnished/refresh.json (#279)
├── AGENTS.md                         # Tarnished-specific Codex review-agent definition (#261)
├── .zed/settings.json                # Workspace Zed project settings — dogfooding of what
│                                     #   `setup.sh --lang rust --zed` generates (#323). Developer-owned:
│                                     #   outside refresh and manifest ownership, tracked by git
├── mise.toml                         # Workspace runtimes (#325): node, rust (stable + rustfmt/clippy), uv
├── .devcontainer/
│   ├── devcontainer.json             # Workspace devcontainer, no features (#325);
│   │                                 #   postStartCommand invokes refresh-assets.sh (#279);
│   │                                 #   carries customizations.vscode AND customizations.zed (#323)
│   └── scripts/
│       ├── post.sh                   # Post-create: git/SSH, refresh, mise → Claude Code → Rust tools →
│       │                             #   Codex → Claude plugins (#261, #279, #325)
│       ├── setup_mise.sh             # Workspace copy of the core helper (#325)
│       ├── setup_claude.sh           # Workspace copy of the core helper (#325)
│       ├── npm_global_cli.sh         # Workspace copy of the core helper (#325)
│       ├── setup_plugins.sh          # enabledPlugins fallback installer (#325; mirror of claude template)
│       ├── setup_codex.sh            # npm install of @openai/codex via npm_global_cli (#261, #325)
│       └── refresh-assets.sh         # Always-latest asset sync (#279); workspace copy of the template
├── docs/design/                      # Design artifacts
│   ├── shared/                       # Cumulative project truth (this layer, #257)
│   └── #{issue}/                     # Per-issue deltas
├── docker/, docker-compose.yml       # Dev environment; docker/Dockerfile.dev is byte-identical to the
│                                     #   core template (#325)
├── scripts/
│   ├── ci/smoke-runtimes.sh          # In-container runtime version assertions for scaffold-build.yml (#325)
│   ├── lib/common.sh                 # Shared shell utilities — output helpers, file copy, JSON merge
│   │                                 #   (incl. merge_zed_settings + apply_zed_assets, #323),
│   │                                 #   mise_toml_ensure / dockerfile_add_os_packages /
│   │                                 #   post_sh_add_block (#325),
│   │                                 #   docker-compose merge, gitignore seeding (#259), TTY detection,
│   │                                 #   prompts, modules.json helpers (#263), monorepo prompts (#263),
│   │                                 #   sha256_file wrapper + manifest-recording extension to
│   │                                 #   copy_with_confirm (#265). Sourced by setup.sh and every plugin.sh.
│   └── lib/manifest.sh               # Manifest read/write, lifecycle decisions, summary printer (#265).
│                                     #   Sourced by setup.sh in --create-manifest and --upgrade modes.
├── setup.sh                          # Top-level template-installer entry. Five operating modes:
│                                     #   single + monorepo init + add-module (#263) + create-manifest +
│                                     #   upgrade (#265). #246: command-list completion message.
├── .github/workflows/scaffold-build.yml  # Scaffold + docker build matrix with runtime smoke checks (#325;
│                                     #   godot leg added by #331)
└── tests/                            # Integration tests
```

A monorepo target produced by `setup.sh --monorepo` (#263) carries an additional root `modules.json` and per-module sub-directories. Once `setup.sh --create-manifest` (#265) has been run, each scope also carries a `.tarnished-manifest.json` that records sha256 installed hashes of eligible template-delivered runtime helpers, used by `setup.sh --upgrade` (#265) to distinguish unedited from user-edited files:

```
<project>/
├── .devcontainer/                   # shared (root)
├── .claude/                         # shared (root)
├── mise.toml                        # shared, union of all module-language runtimes (#325)
├── docker/Dockerfile.dev            # shared; core OS packages + plugin OS blocks + mise runtime layer
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
        │     plugin_post_copy_shared(root) + plugin_post_copy_module(target, module_name);
        │     runtimes are declared through common.sh::mise_toml_ensure from the shared hook (#325)
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
| Generated base image | `debian:trixie-slim` + apt | OS packages only (#325); `gh` from the signed `cli.github.com` apt repo |
| Generated runtime manager | mise, pinned by `ARG MISE_VERSION`, minisign-verified | One `mise.toml` drives node/python/uv/pnpm/rust/go/deno/dotnet/godot/gdtoolkit for devcontainer and plain `docker build` alike (#325, #331; research in `research/mise.md`) |
| Non-registry tools in `mise.toml` | `[tool_alias] <name> = "<backend>:<id>"` + bare `[tools] <name>` entry | Keeps keys bare (what `mise_toml_ensure` accepts) and lets one entry carry backend options; used for the Godot .NET build (`github:godotengine/godot` + `asset_pattern`) and gdtoolkit (`pypi:gdtoolkit` with a private CPython) (#331) |
| Generated CI tool install (godot) | `jdx/mise-action@v4` reading `mise.toml` | Same pins in container and CI; first `node24` major (#267 rule) (#331) |
| Generated AI CLIs | `npm install -g` from `post.sh` helpers on mise's Node | Per-version, user-writable prefix; no sudo (#325) |

Template plugins use Bash. Claude Code plugins are declared in `.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`); `setup_plugins.sh` runs `claude plugin install <id> --scope project` only for enabled ids that are not yet installed on the machine (#325).

## Cross-cutting Concerns

- **Config loading**: Both `ProjectConfig` (`project.yml`) and `Config` (in `tag_config.rs`) use `#[serde(default)]` aggressively for backward compatibility (which once silently masked a wrong template format — see #228).
- **Logging / verbosity**: Routed through the global `Config` (verbose flag).
- **Idempotency**: All shell setup helpers (`setup_plugins.sh`, `plugin.sh`, marketplace registration, `update_gitignore`) MUST be idempotent. `set -e` in `post.sh` requires careful return-0 on non-fatal failures (#255). Idempotency comes in three flavors:
  1. **Line-level** (`grep -q "^<line>$"` before append, used for single-line cases).
  2. **Block-level** (`grep -q "^<marker>$"` keying off a comment marker that the function itself writes, used for multi-line whitelist blocks — see Gitignore policy below, #259, the `post.sh` language blocks and latex `Dockerfile.dev` block introduced by #263, and since #325 the `dockerfile_add_os_packages` and `post_sh_add_block` helpers).
  3. **JSON-merge** (`merge_devcontainer_json`, `merge_docker_compose_services`, `merge_zed_settings` #323): structural merge that is idempotent by construction — arrays become `unique` unions, objects merge key-wise.
  4. **Key-level TOML** (`mise_toml_ensure`, #325): an entry is added only when its key is absent from the section in any spelling; an existing key is never rewritten, which is also what protects developer-edited versions. Since #331 the read-only `mise_toml_has_key` exposes the same presence rule, so a plugin can write a `[tool_alias]` entry only together with the `[tools]` entry it backs. An alias must never retarget a tool entry the developer already has.
- **Devcontainer JSON parsing**: `merge_devcontainer_json` accepts strict JSON plus devcontainer-style comments (`//` and `/* */`) in the target or overlay file, normalizes them to strict JSON in private temp files, then runs the existing `jq` structural merge. The merged output is strict JSON and comments are not preserved. Comment stripping is stateful so URL strings and other string values containing `//` are not corrupted. Generic JSON helpers remain strict JSON unless their own contracts are widened. `merge_zed_settings` (#323) joins the JSONC-tolerant group, because Zed's own settings files are canonically comment-bearing.
- **Editor flavors** (#323): the generator targets VS Code by default and Zed additively. `setup.sh --zed` (or the interactive `Enable Zed editor support? (y/n) [n]` prompt) sets the single global `ZED_ENABLED`; `customizations.vscode` is *always* emitted, so a generated project opens in either editor. Zed's contributions are declared per flavor in `templates/<flavor>/.zed/` — `devcontainer.json` (a merge overlay carrying only `customizations.zed`) and `settings.json` (a `<target>/.zed/settings.json` fragment) — and installed by one shared helper, `common.sh::apply_zed_assets <target_dir> <plugin_dir>`, which every participating `plugin.sh` calls exactly once with no conditional of its own. Two properties are load-bearing. First, `.zed/` is the only template subdirectory that is **not** copied verbatim: a Zed key inside `templates/core/.devcontainer/` would reach every generated project, since that directory *is* copied, which is why the overlay lives outside it. Second, `merge_devcontainer_json` stays a pure function of its three arguments — it reads no global and emits `customizations.zed` only when the base or the overlay declares one — so a non-`--zed` run produces byte-identical output and the helper remains unit-testable. The ownership boundary is deliberate: `.zed/settings.json` is a developer-owned scaffold artifact, outside `refresh-assets.sh`/`refresh.json` (not an AI asset) and outside manifest eligibility (`_manifest_path_eligible` admits only `.devcontainer/scripts/*.sh`), so no `MANIFEST_EXCLUDE_GLOBS` entry is needed and `--upgrade`/`--prune` can never rewrite it. Zed honors `remoteUser`, `postCreateCommand` and `postStartCommand`, so the AI-refresh channel and the #325 post-create installs keep working under Zed (and since #325 no tool depends on devcontainer `features`); it ignores `forwardPorts` (no template sets it), does not rebuild on `devcontainer.json` changes, and derives the Compose project name differently from VS Code — with `container_name:` pinned in `docker-compose.yml`, the two editors must not run the same project simultaneously. Those three are documented caveats, not code.
- **Install contract** (#325): generated projects have no devcontainer `features`. Three layers replace them. (1) **OS packages** in `docker/Dockerfile.dev`, installed as root at build: core's apt list (git, build-essential, curl, gnupg, jq, minisign, …), `gh` from the `cli.github.com` repo through a fingerprint-checked `signed-by` keyring, and mise downloaded at `ARG MISE_VERSION` and verified with minisign + sha256 (`linux-x64`/`linux-arm64`). Plugins add OS packages only through `plugin_dockerfile` blocks inserted above the single `SHELL` line (latex: TeX Live; postgresql: `postgresql-client`; mysql: `default-mysql-client`; godot (#331): the X11/Wayland/Mesa/Vulkan/ALSA/PulseAudio/fontconfig/udev/dbus libraries, `libicu76` + `libssl3t64` for the .NET SDK, `netcat-openbsd`, `unzip`). Runtimes never go through the hook. (2) **Runtimes** from the project-root, developer-owned `mise.toml`: the image switches to `USER vscode`, puts `~/.local/share/mise/shims` on `ENV PATH`, sets `MISE_TRUSTED_CONFIG_PATHS=/workspace`, adds `mise activate bash` to `.bashrc`, copies `mise.toml` and runs `mise install` (optional BuildKit secret `github_token`). Core declares `node = "22"`; python/node/rust/go/deno/godot add entries via `mise_toml_ensure`; python's former `Dockerfile.dev` ENV block lives in `[env]` with `UV_PYTHON` pointing at mise's interpreter. Godot's .NET editor is not reachable through the `godot` registry shorthand (aqua, standard build only), so godot writes `[tool_alias] godot = "github:godotengine/godot"` with an `asset_pattern` for the `_mono_` asset, and gdtoolkit as `pypi:gdtoolkit` with a private CPython 3.12, independent of the python flavor (#331). `.tool-versions` is not generated but is honoured if a developer adds one. (3) **AI CLIs** from `post.sh`: `setup_claude` / `setup_codex` call `npm_global_cli.sh::install_npm_global_cli`, which probes by running `<cmd> --version`, installs into mise's per-version Node prefix without sudo, and warns otherwise. The `post.sh` block order mise → Claude Code → Codex → Claude plugins is load-bearing (a Node bump drops npm globals, so both CLIs reinstall before plugins) and is enforced by `post_sh_add_block`'s before-marker placement rather than by plugin load order. `post.sh`, `Dockerfile.dev`, `devcontainer.json` and `mise.toml` remain developer-owned: `--upgrade` delivers the new helper scripts (manifest-eligible) but never adds their `post.sh` wiring, so feature-based projects migrate by the manual steps in `docs/maintenance.md`. The nvm workarounds (`ln -sf /bin/bash /bin/sh`, `setup_sudo_path`) are gone; nothing may require Node under sudo.
- **Optional Compose overlays** (#331): an overlay that modifies the dev service, rather than adding a service, is **not** merged into `docker-compose.yml`. `merge_docker_compose_services` cannot do that safely: yq `*` replaces the service's `volumes` array, and the text fallback can only append new services. The overlay stays a separate root file, and Compose's own multi-file merge applies it once `.devcontainer/devcontainer.json :: dockerComposeFile` lists it after `../docker-compose.yml`. Compose appends `volumes` / `devices` by target path and merges `environment` by key. The first instance is `docker-compose.godot-gui.yml` (WSLg X11/Wayland/PulseAudio mounts, `/dev/dxg`, `/usr/lib/wsl`). It must be opt-in, because Docker refuses to start a container whose listed device is missing. Opting in is a scaffold-time choice (`plugin_interactive_setup` prompt, default from WSLg detection; `GODOT_GUI=true` for non-interactive runs). The plugin appends the list entry with an order-preserving direct jq edit, and turning it off means deleting that entry. Without the entry the container is headless.
- **Plugin failures**: Wrapped per-plugin so one failure does not abort the whole setup (#255). Every `post.sh` helper (`setup_mise`, `setup_claude`, `setup_codex`, `setup_plugins`) returns 0 and prints `[WARN]` with a recovery command (#325). `setup_plugins.sh` keeps the #273 `is_claude_authenticated` gate (`[[ -s "$HOME/.claude/.credentials.json" ]]`) and, since #325, also returns early with a warning when `claude`, `jq`, the settings file or any enabled `enabledPlugins` entry is missing; per-id install failures are isolated. The workspace and template copies are byte-identical (`verify-mirrors.sh`). This also includes optional integrations like the GitHub Project Integration plugin, whose `gh` CLI auto-detection helpers always return 0 — failures are surfaced via `print_warning` with a captured first-line gh stderr (held in the per-process tempfile `GH_LAST_ERROR_FILE`, established via `mktemp` at plugin source time so the path is unpredictable and the FS state survives the `$(...)` subshells that callers use), and control falls through to manual prompts (#276). The previous design `var=$(gh ... 2>/dev/null)` under `set -e` was fragile: a `gh` non-zero exit would abort the script before the manual fallback ran. The plugin deliberately does not register an `EXIT` trap on this tempfile — sourcing happens after `setup.sh --upgrade`'s `cleanup_upstream_dir EXIT` trap is set, and an unconditional trap would replace it and leak the upstream clone.
- **Remote bootstrap stdin invariant** (#276): When `setup.sh` is invoked as `curl -fsSL .../setup.sh | bash`, the bootstrap block (`setup.sh:29-69`) clones the repo and `exec bash "$TEMP/setup.sh" "$@" < /dev/null`. The `< /dev/null` is required: without it, the outer curl write pipe is inherited across `exec` and the residual write fails with EPIPE, printing a spurious `curl: (23) Failure writing output to destination` to the user's terminal mid-setup. The redirect makes the new process's stdin `/dev/null`; curl finishes cleanly. Local `./setup.sh` invocations skip the bootstrap block and are unaffected.
- **GitHub API**: All calls go through `github/client.rs`. Rate-limit errors propagate as `GitHubClientError`. Non-fatal issues (e.g., a label-routed project not found) are logged as warnings (#230).
- **Workflow triggers**: `project-integration.yml` triggers on `[opened, reopened, labeled]` so label routing fires when labels are added post-creation (#230). Optional sub-features are split out (#244).
- **GitHub Actions JS runtime** (#267): Every JavaScript action `uses:` pin in `.github/workflows/*.yml` targets a major whose `action.yml` declares `runs.using: node24`. Composite actions (`dtolnay/rust-toolchain@stable`, `taiki-e/install-action@*`) are exempt — they have no Node runtime. The selection rule is **earliest Node-24 major** so each upgrade introduces only the runtime change and not unrelated behavior shifts (e.g., `actions/checkout` is pinned to `@v5`, not `@v6` whose credential-persistence change is unneeded). The three reusable workflows (`auto-tag.yml`, `pr-project-status.yml`, `project-integration.yml`) are consumed by downstream repos via `workflow_call`; the callee's pins are what execute, so a tarnished-side bump propagates transparently to every consumer (e.g., freyja). The `templates/github-actions/*` and `templates/languages/*/...yml` distribution channel — which `setup.sh` copies *verbatim* into newly scaffolded downstream projects — is governed by the same rule but tracked separately (the #267 scope was the root workflows only).
- **Design artifact maintenance**: `/design` reads `docs/design/shared/*` first, regenerates them as a snapshot at the end (NFR-1: never append, always overwrite). `/implement` reads both layers (#257).
- **Lifecycle asset altitudes** (#261, #304): The AI lifecycle is expressed at three levels that are projections of one another, not competing sources — the agent-neutral contract (`.tarnished/workflows/{issue,design,implement,review,pr,flow}.md`), the operational spec where behavior is authored (`.claude/skills/*/SKILL.md`), and the thin Codex projection (`.agents/skills/*/SKILL.md`). Edits to one level must land with the others in the same commit. `scripts/verify-mirrors.sh` (CI: `asset-parity.yml`) enforces byte-identity between each workspace tree and its `templates/` mirror; both are upstream-only assets and are absent from scaffolded projects, so downstream-facing documentation must not promise CI enforcement of parity.
- **Role-based delegation policy** (#308, restructured in #312): Skills name **roles**, never models — a model name written into a skill cannot be changed by a downstream project without forking the file, while a role can be rebound in one JSON object. The routing table lives once in `.claude/skills/_shared/delegation/SKILL.md`, which sits in the refresh-managed channel so it updates in lockstep with the skills that consume it. Role→agent binding lives in `.tarnished/agent-profile.json :: roles`, which is project-owned and excluded from both maintenance inventories so a downstream retarget survives every container start. Retry budgets survive only for mechanical steps and only for command-level failure ("the command errored"), never for "the model misjudged". #308's original four roles (`orchestrator` / `executor` / `external-reviewer` / `advisor`, routed by *nature of work within a stage*) are superseded by the structure below.
- **Role restructure around a long-context orchestrator** (#312): the vocabulary becomes `orchestrator` / `designer` / `executor` / `external-reviewer`, and `advisor` is removed. The `orchestrator` **is the main session**: it conducts the requirements dialogue, authors the issue inline, reviews every delegated artifact, triages review findings, owns the merge decision, and is the only party that can reach the user. Authoring is delegated downward — `designer` writes design artifacts once the specification is settled, `executor` implements, applies review fixes, and runs the mechanical half of `/pr`. The routing principle changes with it: work was previously routed *by nature within a stage*, so a stage could be part-inline and part-delegated; now each stage's **authoring** has a single owner and the orchestrator reviews rather than co-authors, while a delegated subagent routes its own internal work. This reverses the pre-#312 position that `/implement` authoring "stays with the orchestrator" — recorded as an intentional reversal, since that position assumed the orchestrator was the only capable writer and that delegation had no return path.
- **Why the restructure rather than a stronger advisor** (#312): an earlier framing strengthened the read-only `advisor` and gave it a post-artifact "conformance" check to replace `/flow`'s two approval gates. Three problems killed it. The model tier was inverted — the strongest model sat in the one seat that cannot write, while the seat that applies every fix stayed a tier below, so correction quality was bounded by the orchestrator regardless of advice quality. The conformance check was circular — a read-only subagent's only input channel is the prompt the orchestrator writes, so the orchestrator supplied the very source of truth it was checked against. And the gates existed *because* subagents cannot reach the user. Inverting what gets delegated resolves all three: the writing goes to subagents, the review stays in the session, and the reviewer is the same party that conducted the dialogue.
- **Escalation instead of gates** (#312): designer and executor resolve routine reversible choices from repository evidence and accepted decisions. They return a structured blocked-result when missing information changes requirements, public behavior, design intent, or authority, or a required prerequisite cannot be recovered within scope. The orchestrator resolves it or escalates. `/flow` stops for requirement gathering, unresolved escalation or two unsuccessful fix returns, argument resolution (including unmet explicit-entry prerequisites), or a `/pr` failure.
- **Commit after review** (#312): the designer authors artifacts, the orchestrator reviews them against issue requirements over at most two return rounds, and the orchestrator commits after review clears. Resume logic inspects artifacts and their review; a commit subject alone does not establish design or implementation completion. Uncommitted work remains incomplete evidence.
- **Explicit model binding**: defaults follow the actual dispatcher. Claude orchestrator settings come from `.claude/settings.json`; Claude designer/executor defaults come from their agent frontmatter. Codex sessions use `.codex/config.toml` (`gpt-6-astra` / `high`), and Codex-native subagents inherit the active session unless a supported role override is set. Profile overrides default to `null` and are vendor-specific, including in `dual` mode; incompatible IDs are reported rather than translated. The external reviewer owns its CLI configuration. Record actual runtime settings when known, and distinguish configured from resolved values.
- **Review criteria single-sourcing** (#308): The canonical review criteria and the four-level `Critical / Major / Minor / Suggestions` severity taxonomy live in `.claude/skills/review/SKILL.md`'s Review Prompt Template — the point where the reviewer prompt is *constructed*. Reference-by-path is deliberately avoided for reviewer-facing prompts: `codex exec` receives its criteria inline in a piped prompt inside a read-only sandbox, and `claude-code-review.yml` receives them inline in workflow YAML, so a bare path would bet on an external reviewer chasing a file mid-review. `AGENTS.md` keeps a compressed self-sufficient list because an ad-hoc Codex session never receives a piped prompt; `.claude/agents/code-reviewer.md` and `.tarnished/workflows/review.md` reference rather than restate.
- **Upgrade placeholder rendering** (#265, fixed #308): `--upgrade` re-runs the plugin copy pipeline into a staging tree, then `manifest_decide` compares old/current/new hashes per file. Until #308 the staging run never called `replace_placeholders`, so staged copies of placeholder-bearing files hashed differently from their rendered downstream counterparts and were applied as `UPDATE`, reintroducing raw `{{...}}` tokens. `MANIFEST_EXCLUDE_GLOBS` incidentally shielded most such files; the exposed set was `.tarnished/agent-profile.json` and `.tarnished/workflows/*.md`; current ownership excludes the profile and refreshes workflows separately. `stage_plugin_run` and `stage_plugin_run_for_module` now render the staging tree using the project name derived from the target directory and the `ai_profile` read from the target's own `agent-profile.json`. New contract files are additionally authored placeholder-free, since `replace_placeholders` carries a hard-coded file list.
- **Gitignore policy** (#259): Downstream projects' `.gitignore` is seeded by `scripts/lib/common.sh::update_gitignore()` and per-plugin gitignore steps (e.g., `templates/codex/plugin.sh::plugin_post_copy`). The seed is **whitelist-style** for `.claude/`, `.codex/`, and Codex repo-local skill files — `.claude/*`, `.codex/*`, and `.agents/*` are ignored, with explicit allowlist for project-tracked subdirectories (`commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, `settings.json` for Claude; `config.toml` for Codex; `skills/` for Codex repo-local skills). Always-ignore directives cover `.serena/` (Serena MCP working files) and `screenshots/` (manual UI testing). Block-level idempotency: each block is preceded by a stable comment marker; `grep -q` keys on the marker. User-authored lines between or after blocks are preserved. The tarnished workspace itself carries the Codex whitelist blocks (#261).
- **Workspace Codex dogfooding** (#261): The tarnished workspace carries its own copy of the artifacts that `templates/codex/` produces for downstream projects — root `AGENTS.md`, `.codex/config.toml`, `.devcontainer/scripts/setup_codex.sh`, the `Bash(codex:*)` Claude permission, and the gitignore whitelist block — so the `/review` skill (which requires `codex` on `$PATH`) can run against this repo. The plugin runtime is **not** invoked against the workspace; the files are hand-applied to preserve existing workspace customizations. Since #325 `setup_codex()` runs **before** `setup_plugins` (the generated order), sharing the same `set -e` non-fatal-return-0 contract. Project-level Codex config (`/workspace/.codex/config.toml`) and the template default (`templates/codex/.codex/config.toml`) are kept in sync at the latest model + reasoning-effort settings so new projects inherit the same review quality as the workspace.
- **`setup.sh` operating mode**: Initial single/monorepo scaffolding and explicit add-module are distinct from maintenance. A bare invocation at a recognized existing Tarnished target selects `--refresh` before scaffold prompts/hooks; explicit scaffold flags there fail with guidance. Refresh uses the current setup checkout updater/source, not an old downstream script. Known unchanged legacy refresh helpers migrate using shipped-content proof; edited/unproven helpers are preserved and reported with exact recovery paths. Root-inclusive `--upgrade` also runs AI refresh from its resolved distribution; module-only upgrades do not refresh root AI assets. Explicit `--upgrade` handles owned runtime helpers and `--create-manifest` establishes conservative provenance. Monorepo registry/scope boundaries and explicit add-module remain supported.
- **Manifest-driven upgrades**: `--create-manifest` compares eligible private-staged distribution paths, never walks downstream files to infer ownership. Version-2 manifests record last-installed runtime helper hashes; version-1 entries are untrusted and migrate only through exact distribution matching without mutation. Initial language/application/build/docs/configuration seeds are developer-owned. Only copied `.devcontainer/scripts/*.sh` helpers other than `post.sh` are maintenance-eligible. `--upgrade` retains scope/ref/dry-run/prune controls and stages plugins privately, but never replays post-copy hooks against the target. Conflicts, local deletions and unpruned removals retain old baselines. No force option bypasses ownership.
- **User-owned `.github/`** (#286): `MANIFEST_EXCLUDE_GLOBS` is extended with the directory-managed pair `.github` and `.github/*`, moving every CI workflow and GitHub-side configuration file (`.github/project.yml`, `.github/versioning.yml`, `.github/workflows/auto-tag.yml`, `.github/workflows/project-integration.yml`, `.github/workflows/pr-project-status.yml`, `.github/workflows/project-label-routing.yml`, `.github/workflows/release-erd.yml`, and the per-language `.github/workflows/<lang>-quality-check.yml`) into the same user-owned bucket as `CLAUDE.md` (distributed `.claude/settings.json` is separately refreshed with backups). Scaffold (`setup.sh` single / monorepo init / add-module modes) still emits these files — `copy_with_confirm`'s actual copy is independent of the exclusion list — but `--create-manifest` no longer hashes them and `--upgrade` no longer records, decides, or prunes them. `apply_decisions_for_scope` (`setup.sh`) also filters `MANIFEST_EXCLUDE_GLOBS` matches out of `OLD_HASHES` before the lifecycle loop, so pre-#286 manifests that still list `.github/*` are migrated silently on the first post-#286 `--upgrade`; the new manifest written at end-of-scope no longer contains those paths, and `--upgrade --prune` cannot delete the user's workflow YAML via the LEAVE_REMOVED/PRUNE branch during the migration upgrade. Bash glob `*` inside `[[ string == pattern ]]` spans `/`, so one `.github/*` entry covers arbitrary depth under `.github/`.
- **AI asset refresh**: The standalone template/workspace `refresh-assets.sh` updates Claude assets, applicable Codex skills and shared workflow contracts from one distribution. It enumerates source/overlay files and prior `.tarnished/refresh-state.json` entries, never treats destination directories as owned. Currently distributed targets, including complete Claude/Codex settings files, are replaced after verified backup of differing live bytes; previously deleted distributed files are restored. Matching files are unchanged. Unknown siblings remain project-owned; only proven unchanged upstream-owned removals may be deleted. Private unique backups under `.tarnished/backups/<run>/<relative-path>` are retained and never managed/pruned. Sidecars remain explicit overrides and are never pruned. Every invocation reconciles the target even when upstream SHA is unchanged. State advances only for successfully installed or exactly matched bytes. Failures warn with recovery hints and exit 0, except unknown CLI flags. Validate paths, symlinks, mapping boundaries, clone origin/cleanliness and project/cache separation before mutations. Dry-run leaves target and persistent cache unchanged. Refresh config, agent profile and native local settings remain project-owned; distributed `.claude/settings.json` and applicable `.codex/config.toml` are backed up and replaced; recognized legacy defaults may migrate through current `setup.sh --refresh`, and optional `use_default_managed_paths` adopts future central mapping additions. All refresh destinations/sidecars/state are excluded from manifest ownership and template/workspace mirrors remain byte-identical.
