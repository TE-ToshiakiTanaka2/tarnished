# Design: #325 Replace devcontainer features with mise runtimes, Dockerfile OS packages, and post.sh AI CLI installs

## Context

Tarnished generates devcontainer boilerplates. `setup.sh` loads plugins in a
fixed order — `core` → `agent-workflows` → selected `languages/*` → selected
`services/*` → `claude` → `codex` (if `--codex`) → `github-actions/*` — and runs
three hook passes over them: `plugin_copy` (verbatim copies), `plugin_dockerfile`
(edits to `docker/Dockerfile.dev`), then `plugin_post_copy` (merges and
marker-guarded appends; language plugins split it into
`plugin_post_copy_shared(root)` + `plugin_post_copy_module(dir, name)` in
monorepo/add-module mode, #263). Add-module mode skips `core`, `claude`,
`codex` and `github-actions`. `--upgrade` replays the same pipeline into a
private staging tree and applies lifecycle decisions only to manifest-eligible
files: `.devcontainer/scripts/*.sh` other than `post.sh` (#265, #316). AI assets
and the complete `.claude/settings.json` are owned by `refresh-assets.sh`,
which replaces them (with verified backups) on every container start (#279,
#319). Everything else — `Dockerfile.dev`, `docker-compose.yml`,
`devcontainer.json`, `post.sh`, language seeds — is developer-owned after
scaffold.

Before this issue the generated environment mixes three install mechanisms
(see the issue's Background table): devcontainer `features` for git, gh,
Claude Code, Node.js (two conflicting pins), Python, uv, Rust, Go, Deno and the
PostgreSQL/MySQL clients; a marker-guarded `RUN` block for TeX Live; and
`post.sh` helpers for Codex CLI and Claude plugins. `Dockerfile.dev` and
`post.sh` carry nvm workarounds (`ln -sf /bin/bash /bin/sh`,
`setup_sudo_path`). Features only run under devcontainer-aware tooling, so a
plain `docker build` of the same `Dockerfile.dev` gets none of them.

Relevant shared truth: `../shared/architecture.md` (plugin layers, ownership
boundaries, idempotency flavours), `../shared/api-spec.md` (plugin contracts,
`merge_devcontainer_json`, `merge_claude_settings`, `setup_plugins.sh`,
`setup_codex.sh`), `../shared/data-model.md` (manifest eligibility, refresh
ownership). External facts: `../shared/research/mise.md` and
[`research.md`](./research.md).

## Architecture Overview (delta)

Generated projects move to a **three-layer install contract**:

| Layer | Owner file | Installed by | When |
| --- | --- | --- | --- |
| OS packages (git, gh, mise, build tools; plugin clients such as `postgresql-client`, TeX Live) | `docker/Dockerfile.dev` | `apt-get` as root | image build |
| Language runtimes (node, python, uv, pnpm, rust, go, deno) | project-root `mise.toml` | `mise install` as `vscode` | image build, and again in `post.sh` |
| AI CLIs (Claude Code, Codex CLI) and Claude plugins | `.devcontainer/scripts/setup_*.sh`, `.claude/settings.json` | `npm install -g` / `claude plugin install` as `vscode` | `post.sh` (post-create) |

`devcontainer.json` loses its `features` key in every flavor; it keeps
`customizations`, lifecycle commands and compose wiring. `mise.toml` becomes a
new **developer-owned** distributable: `core` ships it with `node = "22"`, and
language plugins add their entries through one `common.sh` helper that never
overwrites an existing entry. `plugin_dockerfile` becomes **OS packages only**:
language plugins drop it (python's ENV block moves to `mise.toml [env]`),
`postgresql` and `mysql` gain marker-guarded apt blocks, and `latex` is
unchanged.

`post.sh` gains two core-owned blocks — `# mise Runtime Setup` and
`# Claude Code Setup` — and a position-aware append helper guarantees the
load-bearing order **mise → Claude Code → Codex CLI → Claude Code plugins**, so
a Node.js bump (which removes npm globals) is followed by reinstalling both
CLIs before plugins are installed. Claude Code plugins become declarative
(`extraKnownMarketplaces` + `enabledPlugins`), with `setup_plugins.sh` reduced
to a settings-driven fallback. A new CI workflow scaffolds and `docker build`s
every language/service flavor (latex excluded) and smoke-checks runtime
versions.

## Decisions Not Settled by the Issue

| # | Topic | Decision | Reasoning |
| --- | --- | --- | --- |
| D1 | Open Question (a): Python source | mise `python` tool **plus** mise `uv` tool, with `UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }` | FR-5 already prescribes this `UV_PYTHON` entry, which only resolves when mise owns `python`. Precompiled python-build-standalone builds are attestation-verified and need no compiler. `python --version` then works through the shim (FR-5 acceptance), and one file (`mise.toml`) carries the version. `uv python install` would leave the interpreter outside mise (no shim, version recorded in a second place). |
| D2 | Open Question (b): emit `.tool-versions` | **No.** Only `mise.toml` is generated. | `.tool-versions` cannot express `[env]` or rust components, so it would be a second, lossy source that drifts. mise reads `.tool-versions` natively, so a developer who adds one is still honoured by `post.sh`'s `mise install`; `docs/setup.md` documents this for asdf users. The image build copies only `mise.toml`. |
| D3 | mise install method | GitHub release binary for `linux-x64` / `linux-arm64`, verified by minisign over `SHASUMS256.txt` then `sha256sum -c`, pinned by `ARG MISE_VERSION`; public key in `ARG MISE_MINISIGN_PUBKEY` | Only option meeting FR-2 (ARG pin), NFR-4 (verified download) and NFR-5 (arm64) at once. The Debian `extrepo` repo cannot be pinned; `mise.run` checks checksums only; `COPY --from` an image needs a digest pin as well. Comparison in `../shared/research/mise.md`. |
| D4 | mise data directory | Default per-user `~/.local/share/mise` of `vscode`; no `--system` install | `npm install -g` writes into the active Node's install directory; only a user-owned install keeps it sudo-free (FR-4, NFR-4). Compose mounts single files under `/home/vscode`, never the whole home, so build-time installs stay visible. |
| D5 | npm global prefix (FR-4) | mise's **per-version** prefix (no `NPM_CONFIG_PREFIX`, no `.npmrc prefix`) | Matches the issue's accepted consequence ("a Node version bump re-installs both CLIs") and lets mise's npm wrapper reshim after installs so `claude`/`codex` get shims. A shared prefix would survive bumps but leave native modules built for a stale Node ABI. |
| D6 | Resolving `claude`/`codex` outside interactive shells | `ENV PATH` starts with `/home/vscode/.local/share/mise/shims`; `~/.bashrc` runs `eval "$(mise activate bash)"` for interactive shells | Shims are mise's documented mechanism for non-interactive programs; activation adds `[env]` export and tool `bin` precedence at the prompt. Both FR-2 acceptance commands work. |
| D7 | Installed-probe for CLIs | Run `<cmd> --version`; never trust `command -v` alone | After a Node bump the old `claude` shim still exists but fails for the newly selected Node (research finding 2). A probe that runs the command detects this and reinstalls. |
| D8 | Where `setup_claude.sh` and the shared npm helper live | `templates/core/.devcontainer/scripts/` (`setup_claude.sh`, `npm_global_cli.sh`, `setup_mise.sh`) | Claude Code was a **core** feature; core's `.devcontainer/` is copied verbatim into every scaffold, so the helpers reach every project and are manifest-eligible for `--upgrade` (NFR-2). `setup_codex.sh` (codex flavor) sources the core helper; it degrades with `[WARN]` if the helper is absent. |
| D9 | `post.sh` block ordering mechanism | New `common.sh::post_sh_add_block <post_sh> <marker> [<before_marker>...]`: inserts before the earliest listed marker present, else appends | Plugin load order puts `claude` before `codex`, so today `# Claude Code Plugin Setup` lands before `# Codex CLI Setup` — the opposite of FR-3. Reordering plugin load would also reorder settings merges and gitignore blocks; a position-aware insert fixes only what FR-3 constrains and stays correct if load order changes later. |
| D10 | FR-9 block shape | Core appends a `# mise Runtime Setup` block that sources a manifest-managed `setup_mise.sh` (`setup_mise()`), rather than inlining `mise install` | Keeps the logic testable with bats and upgradable through `--upgrade`, and matches the `setup_<thing>()` contract in AGENTS.md §5. |
| D11 | Build tools in core | Core apt list adds `build-essential` (plus `curl`, `gnupg`, `git`, `minisign` needed by the install steps) | FR-6 removes `plugin_dockerfile` from language plugins, yet Rust needs a linker, Python sdists / Node native addons need a C toolchain and Go uses cgo. Features used to pull these in. Only core can provide them now. |
| D12 | `gh` source | Official `cli.github.com` apt repo with a `signed-by` keyring whose fingerprint is checked at build time; package version unpinned | Debian trixie's `gh` is 2.46 (too old). NFR-4 names `signed-by` explicitly. NFR-1 pins runtimes and mise; apt packages follow their repositories as every other apt package in the file does. |
| D13 | Default `USER` of the image | The Dockerfile ends as `USER vscode` | Shims and per-user installs resolve only for `vscode`; a process started as root would resolve the shim against root's empty data dir and auto-install a second copy. `remoteUser` is already `vscode`; `sudo` stays available. |
| D14 | Plugin OS-package anchor | Keep a single `SHELL [...]` line between the root section and the mise runtime layer; latex's existing awk (insert before `^SHELL `) and the new service blocks both insert there | FR-6 / Tasks keep latex unchanged. Placing the anchor above the runtime layer puts apt layers before `COPY mise.toml`, so editing `mise.toml` does not invalidate them. |
| D15 | Version pins | FR-5's named defaults verbatim (`node "22"`, `python "3.12"`, `rust` channel `stable`); every other tool pinned to its exact current release at implementation time (observed 2026-11-01: go `1.27.3`, deno `2.9.8`, uv `0.13.6`, pnpm `12.16.1`, mise `2026.10.25`) | FR-5 fixes the first three and asks for current-release pins for go and deno; applying the same rule to uv/pnpm satisfies NFR-1 ("explicit pins"). |
| D16 | Rust components | `rust = { version = "stable", components = ["rustfmt", "clippy"] }` | The removed feature used the `default` profile, which shipped rustfmt and clippy; the language template's hooks and CI call both. |
| D17 | `merge_devcontainer_json` and `features` | `features` loses its special case and is merged like any other top-level key: emitted only when the base or overlay has it | Today the jq always emits `features: {}`, so FR-1's acceptance (`has("features")` → `false`) would fail even with no feature anywhere. Treating it as an ordinary key (rather than deleting it) preserves a developer's own features on add-module. |
| D18 | `merge_claude_settings` | **No code change**; add regression tests | The #312 rewrite starts from `$base * $overlay`, so `extraKnownMarketplaces` and `enabledPlugins` already survive (FR-7). On `--upgrade` the root AI refresh replaces the whole file with the distributed `templates/claude/.claude/settings.json`, which now carries both keys. Per-developer opt-out belongs in `.claude/settings.local.json` (native local settings are never replaced). |
| D19 | `setup_plugins.sh` marketplace registration | Register only the marketplaces referenced by enabled ids, taking the source from `extraKnownMarketplaces`; `claude-plugins-official` falls back to `anthropics/claude-plugins-official` when not declared | Removes the hard-coded list while keeping first-run behaviour on machines that never opened an interactive session. |
| D20 | Pinning the AI CLIs | Unpinned by default; overridable without editing manifest-managed helpers through `CLAUDE_CODE_NPM_PACKAGE` / `CODEX_NPM_PACKAGE` (e.g. `@anthropic-ai/claude-code@2.1.300` via `containerEnv`) | Matches today's Codex behaviour and Claude's own updater; editing a helper would mark it `SKIP_EDITED` for future upgrades. |
| D21 | FR-10 "adjust `execute_plugin_dockerfiles` ordering" | Call order stays copies → dockerfiles → post-copies. What changes is (i) block placement: OS blocks land above the runtime layer anchor; (ii) `mise.toml` appends happen in `plugin_post_copy_shared`, after the Dockerfile pass, which is correct because the Dockerfile only `COPY`s the file; (iii) `execute_plugin_dockerfiles` warns once when the target Dockerfile has no mise runtime layer (pre-#325 project) | Read as an ordering of the generated artifact rather than of hook passes. The mise step is not a new hook, so the four-function interface is unchanged (Constraint). |
| D22 | CI scope additions | Besides FR-12's matrix: a `workspace` entry building the repo's own `docker/Dockerfile.dev`, and a post-create smoke on the `core` entry that runs `post.sh` in the built image and asserts `claude --version` | Gives FR-11 and FR-3's acceptance an automated check at roughly two extra minutes. |

## Module Structure (delta)

```
templates/core/
├── mise.toml                                   NEW  [tools] node = "22" + header comment
├── docker/Dockerfile.dev                       REWRITE  root apt/gh/mise section → SHELL anchor → mise runtime layer
├── .devcontainer/devcontainer.json             EDIT  remove "features"
└── .devcontainer/scripts/
    ├── post.sh                                 EDIT  drop setup_sudo_path + trailing "Claude Code Setup" section
    ├── setup_mise.sh                           NEW  setup_mise()  — FR-9
    ├── setup_claude.sh                         NEW  setup_claude() — FR-3
    └── npm_global_cli.sh                       NEW  library: install_npm_global_cli() — shared by claude/codex
templates/core/plugin.sh                        EDIT  copy mise.toml; append mise + Claude blocks via post_sh_add_block
templates/claude/.claude/settings.json          EDIT  + extraKnownMarketplaces, enabledPlugins
templates/claude/.devcontainer/scripts/setup_plugins.sh  REWRITE  settings-driven fallback (FR-8)
templates/claude/plugin.sh                      EDIT  plugin block via post_sh_add_block
templates/claude/CLAUDE.md                      EDIT  directory tree (mise.toml, .devcontainer/)
templates/codex/.devcontainer/devcontainer.json DELETE (only carried the node feature)
templates/codex/.devcontainer/scripts/setup_codex.sh  REWRITE  delegate to npm_global_cli.sh
templates/codex/plugin.sh                       EDIT  no devcontainer merge; block inserted before "# Claude Code Plugin Setup"
templates/languages/{python,node,rust,go,deno}/
├── .devcontainer/devcontainer.json             EDIT  remove "features" (customizations stay)
└── plugin.sh                                   EDIT  remove plugin_dockerfile (python); add mise_toml_ensure calls;
                                                      node: drop corepack branch; rust/go: mise reshim after installs
templates/languages/latex/                      UNCHANGED (plugin_dockerfile kept)
templates/services/{postgresql,mysql}/
├── .devcontainer/devcontainer.json             EDIT  remove "features"
└── plugin.sh                                   EDIT  + plugin_dockerfile → dockerfile_add_os_packages
scripts/lib/common.sh                           EDIT  + mise_toml_ensure, dockerfile_add_os_packages, post_sh_add_block;
                                                      merge_devcontainer_json drops the features special case;
                                                      show_interactive_mode_error text
setup.sh                                        EDIT  help text, check_dependencies (+awk),
                                                      execute_plugin_dockerfiles legacy warning, unset list unchanged
scripts/verify-mirrors.sh                       EDIT  + 4 pairs (setup_claude, setup_codex, setup_mise, npm_global_cli)
scripts/ci/smoke-runtimes.sh                    NEW  in-container version assertions (repo-only, not shipped)
.github/workflows/scaffold-build.yml            NEW  FR-12 matrix
# workspace dogfood (FR-11)
mise.toml                                       NEW  node "22", rust stable + components, uv pin
docker/Dockerfile.dev                           REWRITE  byte-identical to the new core template
.devcontainer/devcontainer.json                 EDIT  remove "features"
.devcontainer/devcontainer-lock.json            DELETE
.devcontainer/scripts/post.sh                   EDIT  drop setup_sudo_path; add mise + Claude blocks; codex before plugins;
                                                      remove the duplicated Rust block
.devcontainer/scripts/{setup_mise,setup_claude,npm_global_cli}.sh  NEW  copies of the core helpers
.devcontainer/scripts/{setup_codex,setup_plugins}.sh               EDIT  copies of the new template helpers
.claude/settings.json                           EDIT  + extraKnownMarketplaces, enabledPlugins
tests/                                          see workflow.md "Test Strategy"
README.md, docs/setup.md, docs/maintenance.md, AGENTS.md  EDIT  FR-13
```

## Interface Design (delta)

Full signatures, inputs, outputs and error tables are in
[`api-spec.md`](./api-spec.md). Summary:

### Public API / Functions

| Name | Signature | Description |
| --- | --- | --- |
| `mise_toml_ensure` | `(mise_toml, section, key, toml_value) -> 0\|1` | Ensure `key = value` exists in `[section]` (`tools`, `env`, `settings`). Creates the file/section when missing; **never modifies an existing key** (any value, any spelling). Atomic write. |
| `dockerfile_add_os_packages` | `(dockerfile, block_id, package...) -> 0\|1` | Insert a marker-guarded `RUN apt-get install` block before the first `^SHELL ` line. Skip when the marker exists; warn and skip when there is no anchor. |
| `post_sh_add_block` | `(post_sh, marker_line, [before_marker_line...]) -> 0\|1`, body on stdin | Append (or insert before the earliest listed marker present) a `# ---` / marker / `# ---` headed block. Skip when `marker_line` exists as an exact line. |
| `setup_mise` | `() -> 0` | `post.sh` entry: `mise install` in the project root. |
| `setup_claude` | `() -> 0` | `post.sh` entry: install Claude Code via `install_npm_global_cli`; `mkdir -p ~/.claude`. |
| `setup_codex` | `() -> 0` | `post.sh` entry: install Codex CLI via `install_npm_global_cli`. |
| `install_npm_global_cli` | `(display_name, package_spec, command) -> 0` | Library function: probe, install without sudo, verify, warn with recovery hint. |
| `setup_plugins` | `() -> 0` | `post.sh` entry: install enabled-but-missing Claude plugins from `.claude/settings.json`. |
| `merge_devcontainer_json` | unchanged signature | `features` no longer special-cased (D17). |

No `setup.sh` flag is added or removed. The plugin interface stays the four
required/optional functions plus the recognized `plugin_dockerfile` and
`plugin_interactive_setup`; `plugin_dockerfile` is now documented as OS
packages only.

### Type Definitions (delta)

#### Generated `mise.toml` (developer-owned, project root)

| Flavor | `[tools]` | `[env]` |
| --- | --- | --- |
| core (always) | `node = "22"` | — |
| python | `python = "3.12"`, `uv = "<current>"` | `UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }`, `PYTHONDONTWRITEBYTECODE = "1"`, `PYTHONUNBUFFERED = "1"`, `UV_COMPILE_BYTECODE = "1"`, `UV_LINK_MODE = "copy"` |
| node | `node = "22"` (no-op when core's entry exists), `pnpm = "<current>"` | — |
| rust | `rust = { version = "stable", components = ["rustfmt", "clippy"] }` | — |
| go | `go = "<current>"` | — |
| deno | `deno = "<current>"` | — |
| latex, services | — | — |

The python ENV block previously injected into `Dockerfile.dev` maps as:
`PYTHONDONTWRITEBYTECODE`, `PYTHONUNBUFFERED`, `UV_COMPILE_BYTECODE`,
`UV_LINK_MODE` → `[env]`; `UV_HOME` and its `PATH` entry → dropped (uv is a
mise tool); `UV_CACHE_DIR=/home/vscode/.cache/uv` → dropped (it equals uv's
default). Monorepo roots carry the union of all module languages. The file is
outside `_manifest_path_eligible`, has no refresh mapping, and is tracked by
git: no `MANIFEST_EXCLUDE_GLOBS` or gitignore change is needed.

#### Core `Dockerfile.dev` layout (illustrative; exact flags settled in implementation)

```dockerfile
# syntax=docker/dockerfile:1
FROM debian:trixie-slim

# ---- OS packages (root). Runtimes come from mise.toml, never from here. ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git gnupg jq minisign \
    openssh-client procps ripgrep rsync sudo vim \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI from the official apt repository (fingerprint-checked keyring).
ARG GH_KEYRING_FINGERPRINT=2C6106201985B60E6C7AC87323F3D4EA75716059
RUN <download keyring> && gpg --show-keys --with-colons <keyring> | grep -q "fpr:::::::::${GH_KEYRING_FINGERPRINT}:" \
    && <install to /etc/apt/keyrings, add signed-by source> \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# mise, pinned and signature-verified (amd64 → linux-x64, arm64 → linux-arm64).
ARG MISE_VERSION=2026.10.25
ARG MISE_MINISIGN_PUBKEY=RWTC3g8W3z4RZK3V3qv7fa1QY4JEWyBtqIHW+85QlJpZc5yG+uNYNBSZ
RUN <map dpkg arch or fail> && <download SHASUMS256.txt, .minisig, binary> \
    && minisign -Vm SHASUMS256.txt -P "${MISE_MINISIGN_PUBKEY}" \
    && <sha256sum -c the matching line> && install -m 0755 <binary> /usr/local/bin/mise

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd ... && useradd ... && <NOPASSWD sudoers drop-in>

# Plugin OS-package blocks (TeX Live, postgresql-client, MySQL client) are
# inserted above the SHELL line by plugin_dockerfile hooks.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# >>> mise runtimes >>>
USER ${USERNAME}
ENV PATH="/home/${USERNAME}/.local/share/mise/shims:${PATH}" \
    MISE_TRUSTED_CONFIG_PATHS=/workspace
RUN echo 'eval "$(mise activate bash)"' >> "/home/${USERNAME}/.bashrc"
WORKDIR /workspace
COPY --chown=${USERNAME}:${USERNAME} mise.toml /workspace/mise.toml
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN,required=false mise install
# <<< mise runtimes <<<

CMD ["sleep", "infinity"]
```

Invariants checked by tests: no `ln -sf /bin/bash /bin/sh`; no `latest`
token; `ARG MISE_VERSION=` present; exactly one `^SHELL ` line and it precedes
`# >>> mise runtimes >>>`; every `RUN` above `SHELL` is POSIX `sh` (no bash
extensions), since `/bin/sh` is dash again.

#### `post.sh` block catalog after a scaffold

| Order | Marker line | Owner | Mechanism |
| --- | --- | --- | --- |
| static | git / SSH sections | core template body | static (`setup_sudo_path` and the trailing Claude section removed) |
| 1 | `# Tarnished Asset Refresh` | core | existing append (unchanged) |
| 2 | `# mise Runtime Setup` | core | `post_sh_add_block` before `# Claude Code Setup` / `# Codex CLI Setup` / `# Claude Code Plugin Setup` |
| 3 | `# Claude Code Setup` | core | `post_sh_add_block` before `# Codex CLI Setup` / `# Claude Code Plugin Setup` |
| 4.. | `# >>> <lang> ... post-create >>>`, service blocks | language / service plugins | existing appends (unchanged mechanism) |
| n-1 | `# Codex CLI Setup` | codex | `post_sh_add_block` before `# Claude Code Plugin Setup` |
| n | `# Claude Code Plugin Setup` | claude | `post_sh_add_block` (append) |

Proof for the default load order: core appends 1–3; languages and services
append after them; claude appends `n`; codex, loaded after claude, inserts
before `n`. Result: mise → Claude Code → (language/service blocks) → Codex →
plugins, satisfying FR-3. The "before" lists make the same result hold under
any future load order. Add-module skips core/claude/codex, so it adds none of
these blocks; `--upgrade` never touches `post.sh`.

Each new block follows the existing pattern (`SCRIPT_DIR` re-derivation,
`source` inside `if [[ -f ... ]]`, call the entry function):

```bash
# -----------------------------------------------------------------------------
# mise Runtime Setup
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/setup_mise.sh" ]]; then
    source "${SCRIPT_DIR}/setup_mise.sh"
    setup_mise
fi
```

#### `.claude/settings.json` additions (template, workspace)

```json
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": { "source": "github", "repo": "anthropics/claude-plugins-official" }
    }
  },
  "enabledPlugins": {
    "context7@claude-plugins-official": true
  }
}
```

serena and playwright leave the defaults. The `.serena/` gitignore block
stays (#259 invariant, FR-10). `templates/claude/.devcontainer/devcontainer.json`
(serena/playwright `files.exclude`) is left as is: `claude/plugin.sh` never
merges it, so it does not reach generated projects and carries no feature.

## Data Flow

Three phases; the system-wide sequence is in
[`../shared/sequence.md`](../shared/sequence.md) ("Container build and
post-create"), and scaffold-time branching is in
[`flowchart.md`](./flowchart.md).

1. **Scaffold (`setup.sh`)**. `core::plugin_copy` copies `mise.toml`,
   `docker/`, `.devcontainer/` (including the three new helpers).
   `execute_plugin_dockerfiles` lets latex/postgresql/mysql insert OS blocks
   above `SHELL`. `plugin_post_copy` passes: core appends post.sh blocks 1–3;
   each language's `plugin_post_copy_shared` calls `mise_toml_ensure` on
   `<root>/mise.toml` and merges its feature-free devcontainer overlay;
   claude merges settings (keys arrive) and appends the plugin block; codex
   inserts its block before it.
2. **Image build (`docker build` / compose / devcontainer)**. Root installs
   OS packages, gh and mise; plugin OS blocks run; then as `vscode`:
   `COPY mise.toml` → `mise install`. Editing only `mise.toml` invalidates
   just the last two layers.
3. **Post-create (`post.sh`, non-login bash, `set -e`)**. `setup_mise`
   converges runtimes to the current `mise.toml` (edits since the build) →
   `setup_claude` reinstalls Claude Code if the selected Node lacks it →
   language blocks → `setup_codex` → `setup_plugins` reads `enabledPlugins`
   and installs what is missing. Every container start additionally runs
   `refresh-assets.sh`, which keeps `.claude/settings.json` (and so the
   plugin keys) at the distributed version.

## Error Handling

Shared policy (architecture.md "Plugin failures", AGENTS.md §5): scaffold-time
helpers return non-zero only for programming errors and callers downgrade
them to `print_warning`; `post.sh` helpers always `return 0`, print `[WARN]`
plus a recovery command, and never call `exit` or `sudo`.

| Condition | Where | Behaviour |
| --- | --- | --- |
| `mise.toml` write fails / bad section or key | `mise_toml_ensure` | `print_error`, return 1, original file untouched (temp + `mv`); caller prints a warning and continues |
| Existing key with a different value | `mise_toml_ensure` | `print_info "kept existing <section>.<key>"`, file byte-identical |
| No `^SHELL ` anchor in a developer-edited Dockerfile | `dockerfile_add_os_packages` | `print_warning` naming the packages to add by hand; file untouched; return 0 |
| Dockerfile without `# >>> mise runtimes >>>` | `execute_plugin_dockerfiles` | one `print_warning` pointing at `docs/maintenance.md`; scaffold continues |
| `mise` missing (pre-#325 image) | `setup_mise` | `[WARN]` + "rebuild from the current Dockerfile.dev / see docs/maintenance.md"; return 0 |
| No `mise.toml`/`.tool-versions` | `setup_mise` | info, return 0 |
| `mise install` fails | `setup_mise` | `[WARN]` + `cd <root> && mise install`; return 0 |
| CLI already runs (`<cmd> --version` ok) | `install_npm_global_cli` | log version, return 0 (covers feature-installed `claude` on old projects) |
| `npm` missing | `install_npm_global_cli` | `[WARN]` + `npm install -g <pkg>` hint; return 0 |
| Global prefix not writable | `install_npm_global_cli` | `[WARN]` explaining sudo is never used + hint (`mise use node@22` or a user prefix); return 0 |
| `npm install -g` fails / CLI still not runnable | `install_npm_global_cli` | `[WARN]` + manual command; return 0 |
| `npm_global_cli.sh` absent | `setup_claude`, `setup_codex` | `[WARN]` + "run `setup.sh --upgrade`"; return 0 |
| `claude` missing / settings file missing / invalid JSON / no enabled ids / not authenticated | `setup_plugins` | one-line warning or guidance; return 0 (FR-8) |
| Malformed plugin id or unknown marketplace source | `setup_plugins` | warn, skip that id, continue |
| `claude plugin list --json` fails | `setup_plugins` | note, treat installed set as empty, continue (install is idempotent) |
| `claude plugin install` fails | `setup_plugins` | warn, continue with the next id |

## Implementation Notes

### Requirement traceability

| Req | Carried by |
| --- | --- |
| FR-1 | Overlays lose `features`; codex overlay deleted; D17 merge change; CI + bats `has("features") == false` |
| FR-2 | Core Dockerfile (D3, D4, D6, D13), `MISE_TRUSTED_CONFIG_PATHS`; CI smoke runs `bash -c` and `bash -ic` |
| FR-3 | `setup_claude.sh` + `npm_global_cli.sh` (D8); claude-code feature removed; block order (D9); CI post-create smoke (D22) |
| FR-4 | D5/D6; `setup_sudo_path` and the `sh` symlink deleted |
| FR-5 | `templates/core/mise.toml`; `mise_toml_ensure` calls in five languages; pins (D15, D16); bats idempotency/user-entry tests |
| FR-6 | Core apt + gh + mise; `dockerfile_add_os_packages` for pg/mysql; python `plugin_dockerfile` removed; latex unchanged |
| FR-7 | Template settings keys; D18 tests |
| FR-8 | `setup_plugins.sh` rewrite (D19) |
| FR-9 | `setup_mise.sh` + `# mise Runtime Setup` (D10) |
| FR-10 | Help texts, three `common.sh` helpers, D21, `.serena/` block untouched |
| FR-11 | Workspace dogfood list above; `verify-mirrors.sh` pairs |
| FR-12 | `.github/workflows/scaffold-build.yml` + `scripts/ci/smoke-runtimes.sh` |
| FR-13 | Docs plan below |
| NFR-1 | Pins in `mise.toml`, `ARG MISE_VERSION`, no `latest` in the Dockerfile (bats) |
| NFR-2 | Helpers probe/skip and return 0; see "Existing projects" |
| NFR-3 | Every helper: `set -e`-safe, `[WARN]` + hint, `.claude/rules/shell.md` |
| NFR-4 | minisign + sha256 for mise; `signed-by` keyring with fingerprint check for gh; runtimes verified by mise; root only during build; no sudo in npm paths |
| NFR-5 | Arch mapping for the mise binary; apt multi-arch; mise resolves runtime arches |
| NFR-6 | workflow.md "Test Strategy" |

### `mise_toml_ensure` semantics (TOML-aware without a parser)

- Validates `section ∈ {tools, env, settings}`, `key` against
  `^[A-Za-z0-9_][A-Za-z0-9_.-]*$` (bare keys; dotted keys allowed for
  `settings`), and a non-empty single-line value. The value is written
  verbatim, so callers pass TOML literals (`'"22"'`,
  `'{ version = "stable", components = ["rustfmt", "clippy"] }'`).
- Presence check (one awk pass, tracking the current table header
  `^[[:space:]]*\[([^][]+)\][[:space:]]*(#.*)?$`, ignoring `[[array tables]]`):
  the key is **present** when, inside `[section]`, a line matches
  `^[[:space:]]*("?)KEY("?)[[:space:]]*=` (bare or quoted key); or a header
  `[section.KEY]` exists anywhere; or a top-level `section.KEY =` line exists
  before the first header. Present → no write, whatever the value. This is the
  user-entry protection: an edited version, a table form, or a quoted key all
  count as the developer's choice.
- Absent + section exists → insert `KEY = VALUE` after the last non-blank line
  of that section (before trailing blank lines and the next header).
  Absent + section missing → append `\n[section]\nKEY = VALUE\n`. File missing
  → create it with the core header comment first. A file lacking a trailing
  newline gets one before appending.
- Write via `mktemp` in the same directory + `mv`; on failure remove the temp
  and return 1.
- Known limit, documented: a developer who deletes an entry on purpose gets it
  back on the next `--add-module` for that language (absence is
  indistinguishable from "never added"). Multi-line values and comments are
  preserved because only one line is ever inserted.

### Monorepo, add-module and upgrade

- Monorepo init: each language's `plugin_post_copy_shared` runs once at the
  root, so `mise.toml` holds the union; `plugin_post_copy_module` never touches
  it (root asset, same rule as `.devcontainer/` and `.zed/`).
- Add-module: core is skipped, so the language plugin's
  `mise_toml_ensure` creates `mise.toml` if a pre-#325 root lacks one and
  appends only missing entries. `setup.sh` prints, at the end of add-module,
  "run `mise install` in the container (or rebuild) to install new runtimes".
  If the root Dockerfile predates the mise layer, D21's warning fires.
- `--upgrade`: staging re-runs the same hooks (harmless; `mise.toml`,
  `Dockerfile.dev`, `devcontainer.json`, `post.sh` are not eligible). New
  helpers (`setup_mise.sh`, `setup_claude.sh`, `npm_global_cli.sh`) arrive as
  `NEW`; changed `setup_codex.sh` / `setup_plugins.sh` arrive as `UPDATE` when
  unedited. `.claude/settings.json` arrives through the root AI refresh.

### Existing projects (NFR-2) — and a correction to the issue text

NFR-2 says the new `post.sh` blocks "ship through `--upgrade`". They do not:
`post.sh` is developer-owned and explicitly excluded from manifest eligibility
(`_manifest_path_eligible`, docs/maintenance.md: "Setup maintenance does not
add container-start wiring automatically"). This design keeps that boundary
(the issue's Constraints require it). Consequences on a feature-based project
after `--upgrade`:

- `setup_mise.sh`, `setup_claude.sh`, `npm_global_cli.sh` are installed but not
  wired; they run only after the developer adds the blocks (migration guide).
- `setup_codex.sh` (already wired): `codex --version` succeeds → skip; else
  installs through the feature's nvm Node, whose prefix is user-writable;
  never sudo.
- `setup_plugins.sh` (already wired): `enabledPlugins` arrives with the next
  refresh of `.claude/settings.json`; until then it warns "no enabledPlugins"
  and returns 0. serena/playwright installed earlier stay installed (the
  fallback never uninstalls).
- `setup_mise` / `setup_claude`, if wired by hand before the Dockerfile is
  migrated: `mise` missing → `[WARN]`; `claude` from the feature → skip.

### Language and service plugin edits

- python: delete `plugin_dockerfile` and its marker constant; add the
  `mise_toml_ensure` calls in `plugin_post_copy_shared` before the post.sh
  marker branch (which can `return` early); leave the uv post.sh block as is
  (it now uses mise's `uv`, and `uv venv` picks mise's Python through
  `UV_PYTHON`).
- node: `mise_toml_ensure` for node and pnpm; remove the
  `corepack enable` / `corepack prepare pnpm@latest` branch from both post.sh
  variants and replace it with a `[WARN]` "pnpm not found — add it to
  mise.toml and run `mise install`".
- rust / go: `mise_toml_ensure`; their post.sh blocks run
  `command -v mise &> /dev/null && mise reshim || true` after
  `cargo install` / `go install` so the new binaries get shims and the
  `command -v` idempotency checks succeed on the next run.
- deno: `mise_toml_ensure` only.
- postgresql / mysql: new `plugin_dockerfile(target_dir)` calling
  `dockerfile_add_os_packages "${target_dir}/docker/Dockerfile.dev" postgresql postgresql-client`
  / `... mysql default-mysql-client`; devcontainer overlays keep only
  `customizations`. `execute_plugin_dockerfiles` already dispatches the hook,
  so `plugin_post_copy` does not call it.
- Every "Merging <X> devcontainer features..." log line becomes
  "...devcontainer customizations...".

### `setup.sh` / `common.sh` text changes

- `show_help`: describe that runtimes are declared in `mise.toml`; language
  list gains `latex`; service lines stop implying a devcontainer feature.
- `common.sh::show_interactive_mode_error`: replace the stale option list
  (`--playwright`, `--docker`, `--neo4j`, a four-language `--lang`) with the
  real flags, or point at `./setup.sh --help` only. A bats test asserts
  `--playwright` appears in neither text.
- `check_dependencies`: add `awk` (now used by every language scaffold through
  `mise_toml_ensure`); `mise`/`docker` are not host prerequisites.

### Workspace dogfood (FR-11)

Files listed under Module Structure. `docker/Dockerfile.dev` becomes
byte-identical to the template (the workspace needs no plugin OS blocks).
Workspace `mise.toml` keeps agreement with `rust-toolchain.toml`
(`stable` + rustfmt + clippy); CI's `dtolnay/rust-toolchain` workflows are
unaffected. `verify-mirrors.sh` gains:
`.devcontainer/scripts/setup_claude.sh` ≡ `templates/core/...`,
`setup_mise.sh` ≡ `templates/core/...`, `npm_global_cli.sh` ≡
`templates/core/...`, `setup_codex.sh` ≡ `templates/codex/...`. Extend
`asset-parity.yml` path filters only if `.devcontainer/scripts/**` is not
already covered (it is).

### Documentation (FR-13)

- `README.md` "First-time setup": one paragraph — runtimes live in
  `mise.toml`; link to docs/setup.md.
- `docs/setup.md` new section "Runtime versions (`mise.toml`)": the
  three-layer contract table; how to change a version (edit, `mise install`,
  or rebuild); Node bumps also need `bash .devcontainer/scripts/post.sh` (or
  `source .devcontainer/scripts/setup_claude.sh && setup_claude`) to
  reinstall CLIs; `.tool-versions` is honoured if added; pinning the AI CLIs
  via `CLAUDE_CODE_NPM_PACKAGE` / `CODEX_NPM_PACKAGE`; enabling/disabling
  Claude plugins (`enabledPlugins`, per-developer opt-out in
  `.claude/settings.local.json`).
- `docs/maintenance.md` new section "Migrating a feature-based project
  (#325)":
  1. Replace `docker/Dockerfile.dev` with the current core template, then
     re-add project-specific apt lines above `SHELL` (TeX Live block, and
     `postgresql-client` / `default-mysql-client` replacing those features;
     drop the python `UV_HOME` ENV block).
  2. Create `mise.toml` from the feature mapping: `node:1` → `node = "22"`;
     `python:1` → `python = "3.12"`; uv feature → `uv`; `rust:1` → `rust`
     with components; `go:1` → `go`; deno feature → `deno`; add the python
     `[env]` block when applicable.
  3. Remove `features` from `.devcontainer/devcontainer.json`; delete
     `.devcontainer/devcontainer-lock.json`.
  4. Run `./setup.sh --upgrade` to receive `setup_mise.sh`,
     `setup_claude.sh`, `npm_global_cli.sh` and the new `setup_codex.sh` /
     `setup_plugins.sh` (or copy them from the template).
  5. Edit `post.sh`: delete `setup_sudo_path` and its call and the trailing
     "Claude Code Setup" `if command -v claude` section; add the
     `# mise Runtime Setup` and `# Claude Code Setup` blocks after the core
     sections; move `# Codex CLI Setup` before `# Claude Code Plugin Setup`.
  6. `.claude/settings.json` receives the plugin keys on the next container
     start (refresh); nothing to do by hand.
  7. Rebuild the container; verify `node --version`, `claude --version`, and
     each runtime.
- `templates/claude/CLAUDE.md`: tree gains `mise.toml` and
  `.devcontainer/scripts/`.
- `AGENTS.md`: §4 adds `mise.toml` as a core-only project-root distributable
  that language plugins extend through `mise_toml_ensure` (never by shipping
  their own file), and states that `plugin_dockerfile` is OS packages only;
  §5 records the block order (mise → Claude Code → Codex → plugins), the
  `post_sh_add_block` helper, and that `npm_global_cli.sh` is a sourced
  library rather than a `setup_<thing>()` entry helper; §1 lists the three new
  `common.sh` helpers among those plugins must use.

### Risks and follow-ups

- **mysql client compatibility**: `default-mysql-client` is MariaDB's client;
  verify a login against the `mysql:8.0` service once during implementation.
  If `caching_sha2_password` fails, document the server-side
  `--default-authentication-plugin` workaround or switch to Oracle's apt repo
  in a follow-up (not in this scope).
- **Build time**: `build-essential` + gh repo + mise download add roughly
  1–2 minutes to a cold build; rust adds rustup's download.
- **Root processes**: `docker exec -u root <cmd>` resolves shims against
  root's empty mise data dir and may auto-install a second copy; documented,
  not mitigated (the Constraint already rules out Node under sudo).
- **Downstream CI templates** (`templates/languages/*/.github/workflows`)
  still pin versions independently of `mise.toml` (`setup-uv`,
  `pnpm/action-setup`); aligning them via `jdx/mise-action` is a follow-up.
- **`go install ...@latest`** in the go post.sh block stays (NFR-1 governs
  `Dockerfile.dev` only).
