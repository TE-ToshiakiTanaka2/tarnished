# Workflow: #325 Replace devcontainer features with mise runtimes, Dockerfile OS packages, and post.sh AI CLI installs

Follows the issue's edit order. Each step should leave `bats tests/` and
`scripts/verify-mirrors.sh` green before the next starts; mirror pairs are
updated in the same step as the file they mirror.

## Implementation Steps

### Step 1: `common.sh` helpers and merge change
- **Action**: Add `mise_toml_ensure`, `dockerfile_add_os_packages`,
  `post_sh_add_block` (contracts in `api-spec.md`). Remove the `features`
  special case from `merge_devcontainer_json` (D17). Rewrite
  `show_interactive_mode_error`'s option list.
- **Files**: `scripts/lib/common.sh`, `tests/common_mise.bats` (new),
  `tests/common_postsh.bats` (new), `tests/common_json.bats`
- **Depends on**: —
- **Done when**: new unit tests pass; `merge_devcontainer_json` on two
  feature-free inputs yields `has("features") == false`; a base-only
  `features` object survives a merge.

### Step 2: Core install substrate
- **Action**: New `templates/core/mise.toml`; rewrite
  `templates/core/docker/Dockerfile.dev` (layout in design.md); remove
  `features` from core `devcontainer.json`; in `post.sh` delete
  `setup_sudo_path` + call and the trailing "Claude Code Setup" section; add
  `setup_mise.sh`, `setup_claude.sh`, `npm_global_cli.sh`; `core/plugin.sh`
  copies `mise.toml` (`copy_with_confirm`) and appends the
  `# mise Runtime Setup` / `# Claude Code Setup` blocks via
  `post_sh_add_block`. Pin `MISE_VERSION` to the then-current release.
- **Files**: `templates/core/{mise.toml,plugin.sh,docker/Dockerfile.dev,.devcontainer/devcontainer.json}`,
  `templates/core/.devcontainer/scripts/{post.sh,setup_mise.sh,setup_claude.sh,npm_global_cli.sh}`
- **Depends on**: Step 1
- **Done when**: `docker build` of a core-only scaffold succeeds locally on
  amd64; `docker run --rm img bash -c 'node --version'` and
  `bash -ic 'node --version'` print v22; helper unit tests pass; arm64 build
  attempted once with `docker buildx build --platform linux/arm64` (QEMU) or
  on an arm64 host.

### Step 3: Claude plugin
- **Action**: Add `extraKnownMarketplaces` + `enabledPlugins` to
  `templates/claude/.claude/settings.json`; rewrite `setup_plugins.sh`
  (FR-8); switch the post.sh append to `post_sh_add_block`; update the
  CLAUDE.md tree.
- **Files**: `templates/claude/.claude/settings.json`,
  `templates/claude/.devcontainer/scripts/setup_plugins.sh`,
  `templates/claude/plugin.sh`, `templates/claude/CLAUDE.md`,
  workspace `.devcontainer/scripts/setup_plugins.sh` (mirror),
  `tests/setup_plugins.bats`, `tests/common_json.bats`
- **Depends on**: Step 1
- **Done when**: settings merge tests show both keys surviving
  `merge_claude_settings` and `merge_claude_settings_hooks`; setup_plugins
  tests pass; mirror pair identical.

### Step 4: Codex plugin
- **Action**: Delete `templates/codex/.devcontainer/devcontainer.json` and the
  merge step; rewrite `setup_codex.sh` on `install_npm_global_cli`; insert its
  post.sh block before `# Claude Code Plugin Setup`; update header comments.
- **Files**: `templates/codex/{plugin.sh,.devcontainer/scripts/setup_codex.sh}`,
  workspace `.devcontainer/scripts/setup_codex.sh`
- **Depends on**: Steps 1–3
- **Done when**: a `--codex` scaffold's post.sh has the four markers in order;
  codex idempotency test passes.

### Step 5: Language plugins
- **Action**: Remove `features` from python/node/rust/go/deno overlays; delete
  python's `plugin_dockerfile` and its marker constant; add
  `mise_toml_ensure` calls (pins per D15/D16) in `plugin_post_copy_shared`
  before any early `return`; node: drop corepack; rust/go: `mise reshim`
  after installs; rename "features" log lines.
- **Files**: `templates/languages/{python,node,rust,go,deno}/{plugin.sh,.devcontainer/devcontainer.json}`
- **Depends on**: Steps 1–2
- **Done when**: each language scaffold has no `features`, the expected
  `mise.toml` entries, and a second `plugin_post_copy_shared` run leaves
  `mise.toml` byte-identical.

### Step 6: Service plugins
- **Action**: Remove `features` from postgresql/mysql overlays; add
  `plugin_dockerfile` using `dockerfile_add_os_packages`. latex untouched.
- **Files**: `templates/services/{postgresql,mysql}/{plugin.sh,.devcontainer/devcontainer.json}`,
  `tests/setup_service_selection.bats`
- **Depends on**: Steps 1–2
- **Done when**: scaffolds carry the marker-guarded apt block above `SHELL`;
  re-running the hook adds nothing.

### Step 7: `setup.sh`
- **Action**: Help text; `check_dependencies` adds `awk`;
  `execute_plugin_dockerfiles` legacy warning; add-module end-of-run hint
  about `mise install`.
- **Files**: `setup.sh`, `tests/setup_mise_scaffold.bats` (new)
- **Depends on**: Steps 2–6
- **Done when**: `--help` and the interactive-mode error mention no
  `--playwright`; end-to-end scaffold tests pass.

### Step 8: Workspace dogfood
- **Action**: Root `mise.toml`; `docker/Dockerfile.dev` = core template;
  remove `features`, delete `devcontainer-lock.json`; post.sh edits (drop
  `setup_sudo_path`, add mise + Claude blocks, codex before plugins, remove
  the duplicated Rust block); copy the three core helpers; settings keys;
  extend `scripts/verify-mirrors.sh` with four pairs.
- **Files**: see design.md "Workspace dogfood"
- **Depends on**: Steps 2–4
- **Done when**: `scripts/verify-mirrors.sh` passes; the workspace image
  builds and `cargo --version`, `node --version`, `uv --version` succeed in
  it.

### Step 9: CI workflow
- **Action**: Add `scripts/ci/smoke-runtimes.sh` and
  `.github/workflows/scaffold-build.yml` (below).
- **Depends on**: Steps 2–8
- **Done when**: workflow green on the PR for all 11 entries.

### Step 10: Documentation
- **Action**: README, docs/setup.md, docs/maintenance.md (migration guide),
  AGENTS.md §1/§4/§5, plus any remaining comments mentioning features/nvm.
- **Depends on**: Steps 1–9 (documents final behaviour)
- **Done when**: `grep -rn 'devcontainers/features\|ghcr.io/.*features\|nvm' templates/ setup.sh scripts/ .devcontainer/ docker/`
  returns nothing outside history/design docs; docs describe how to change a
  version and how to migrate.

## Task Dependencies

```
1 ──┬── 2 ──┬── 5 ──┐
    │       ├── 6 ──┤
    ├── 3 ──┼── 4 ──┼── 7 ── 8 ── 9 ── 10
    │       │       │
    └───────┴───────┘
```

Steps 3, 5 and 6 can proceed in parallel once 1 and 2 land.

## CI workflow (`.github/workflows/scaffold-build.yml`)

- **Triggers**: `pull_request` to `develop` with paths `templates/**`,
  `setup.sh`, `scripts/lib/**`, `scripts/ci/**`, `docker/**`, `mise.toml`,
  `.github/workflows/scaffold-build.yml`; `push` to `develop`;
  `workflow_dispatch`.
- **Runner / arch**: `ubuntu-latest`, amd64 only (FR-12). `timeout-minutes: 30`,
  `fail-fast: false`, `permissions: contents: read`.
- **Matrix** (`flavor` → `setup.sh` arguments, project name `ci-<flavor>`):

| flavor | args | smoke tools |
| --- | --- | --- |
| core | (none) | mise, git, gh, node, npm; **post-create**: `claude --version` |
| python | `--lang python` | + python, uv |
| node | `--lang node` | + pnpm |
| rust | `--lang rust` | + rustc, cargo, `cargo fmt`, `cargo clippy` |
| go | `--lang go` | + go |
| deno | `--lang deno` | + deno |
| postgresql | `--postgresql` | + psql |
| mysql | `--mysql` | + mysql |
| redis | `--redis` | core set |
| celery | `--lang python --celery` | + python, uv (`--celery` alone does not add Python non-interactively, so CI passes `--lang python` explicitly) |
| workspace | (none — builds the repo root) | node, cargo, uv |

- **Steps per entry**:
  1. `actions/checkout`; `docker/setup-buildx-action` (pin each action to its
     earliest Node-24 major per the #267 rule; verify at implementation).
  2. Scaffold (skipped for `workspace`):
     `mkdir "$RUNNER_TEMP/ci-$flavor" && cd` there and run
     `bash "$GITHUB_WORKSPACE/setup.sh" $args -y ci-$flavor`. No TTY in
     Actions, so every prompt takes its non-interactive default and the
     GitHub-repository step is skipped.
  3. Static assertions: `jq -e 'has("features") | not' .devcontainer/devcontainer.json`;
     `! grep -q 'ln -sf /bin/bash /bin/sh' docker/Dockerfile.dev`;
     `! grep -qw latest docker/Dockerfile.dev`.
  4. Build with `docker/build-push-action`: context = project dir,
     `file: docker/Dockerfile.dev`, `load: true`, `tags: tarnished-ci:<flavor>`,
     `secrets: github_token=${{ secrets.GITHUB_TOKEN }}`,
     `cache-from: type=gha,scope=<flavor>`, `cache-to: type=gha,mode=max,scope=<flavor>`.
  5. Smoke: `docker run --rm -v "$GITHUB_WORKSPACE/scripts/ci:/ci:ro" -w /workspace tarnished-ci:<flavor> bash /ci/smoke-runtimes.sh <tools...>`
     — for each tool the script asserts the version reported by the binary
     matches `mise current <tool>` (node: `v<ver>`; python: `Python <ver>`;
     go: `go<ver>`; uv/pnpm/deno: contains `<ver>`; rust: `rustc` runs and
     `rustup show active-toolchain` contains `stable`), once via `bash -c`
     and once via `bash -ic` (FR-2 acceptance). OS tools (`gh`, `psql`,
     `mysql`) only need `--version` to succeed.
  6. `core` only — post-create: `docker run --rm -e CI=1 -v "$PWD:/workspace" -w /workspace tarnished-ci:core bash -c 'bash .devcontainer/scripts/post.sh && claude --version'`
     (FR-3 acceptance; `setup_plugins` skips for lack of credentials).
- **Budget**: cold build 4–8 min per entry (rust slowest), warm ≤ 2 min with
  the gha cache; entries run in parallel, so wall time ≈ the slowest entry.

## Test Strategy

### Unit Tests (bats)

| File | Cases | Covers |
| --- | --- | --- |
| `tests/common_mise.bats` (new) | creates missing file with header; adds key to existing `[tools]`; appends missing `[env]` section; **keeps a user-changed value byte-identical**; detects quoted key `"node" = …`; detects `[tools.node]` table form; detects top-level `tools.node =`; inline-table value written verbatim; second call byte-identical; file without trailing newline; comments and blank lines preserved; invalid section/key/value → return 1 and file unchanged; write failure leaves original | FR-5, NFR-6 |
| `tests/common_mise.bats` | `dockerfile_add_os_packages`: inserts before `SHELL`; idempotent; no `SHELL` → warning and unchanged; invalid id → 1 | FR-6 |
| `tests/common_postsh.bats` (new) | append when no before-marker; insert before `# Claude Code Plugin Setup`; earliest of several before-markers wins; marker present → no-op; missing post.sh → 0; generated block layout (blank, rule, marker, rule, body); full sequence core→claude→codex yields mise < claude < codex < plugins | FR-3, FR-9 |
| `tests/common_json.bats` (changed) | feature-specific merge tests rewritten: neither side has `features` → key absent; base-only `features` preserved; overlay deep-merged as an ordinary key. New: `merge_claude_settings` and `merge_claude_settings_hooks` keep `extraKnownMarketplaces` / `enabledPlugins` when present only in base, only in overlay, or both | FR-1, FR-7 |
| `tests/setup_plugins.bats` (rewritten) | under `set -e` with mocked `claude`/`jq` on PATH: missing claude → 0, no calls; missing settings → 0; invalid JSON → 0; no `enabledPlugins` → 0 with warning; missing credentials → 0, `claude` never invoked; installs only ids absent from `list --json`; `false` entries ignored; marketplace registered from `extraKnownMarketplaces` once; default official source when undeclared; unknown marketplace → skipped; `list --json` failure still attempts install; per-id install failure continues; never passes `-y`; workspace ≡ template byte-identity | FR-8, NFR-3 |
| `tests/setup_cli_helpers.bats` (new) | `install_npm_global_cli`: runnable command → npm never called; stale shim (`command -v` ok, `--version` fails) → install attempted; npm missing → `[WARN]`, 0; non-writable prefix → `[WARN]`, 0, no npm install; install failure → `[WARN]` + hint, 0; mocked `sudo` never invoked in any case. `setup_claude`/`setup_codex`: helper missing → `[WARN]`, 0; env override package spec passed through. `setup_mise`: mise missing → `[WARN]`, 0; no config → 0; install failure → `[WARN]`, 0; success path runs in the project root | FR-3, FR-4, FR-9, NFR-2, NFR-3, NFR-4 |

### Integration Tests (bats, end-to-end `setup.sh`)

| File | Cases | Covers |
| --- | --- | --- |
| `tests/setup_mise_scaffold.bats` (new) | for each of core, python, node, rust, go, deno, postgresql, mysql, redis, celery: `has("features") == false`; expected `mise.toml` entries per flavor; Dockerfile has `ARG MISE_VERSION=`, no `ln -sf /bin/bash /bin/sh`, no `latest`, one `SHELL` line before `# >>> mise runtimes >>>`; pg/mysql apt block above `SHELL`; `--codex` scaffold has the four post.sh markers in order and no `setup_sudo_path`; monorepo `jing:python` + `kir:node` → root `mise.toml` has python, uv, node, pnpm once each; add-module of an existing language leaves `mise.toml` byte-identical; add-module after the developer changed `node = "24"` keeps `"24"`; `--help` and the interactive-mode error do not contain `--playwright` | FR-1–FR-6, FR-9, FR-10, NFR-1 |
| `tests/plugin_idempotency.bats` (changed) | fixture Dockerfile keeps its `SHELL` line; add a `mise.toml` fixture; add idempotency cases for python/node/rust/deno `plugin_post_copy_shared` (mise.toml + post.sh) and for the postgresql/mysql `plugin_dockerfile`; existing codex/core/claude cases must still pass with the new blocks | FR-5, FR-6 |
| `tests/setup_service_selection.bats` (changed) | "devcontainer.json contains postgresql-client feature" / "…mysql-client feature" → "has no features" + "plugin_dockerfile adds the client package block" | FR-1, FR-6 |
| `tests/setup_upgrade.bats` (changed) | on a pre-#325-shaped project: `setup_mise.sh`, `setup_claude.sh`, `npm_global_cli.sh` installed as NEW; `post.sh`, `Dockerfile.dev`, `devcontainer.json`, `mise.toml` byte-identical before/after | NFR-2 |
| `tests/setup_create_manifest.bats` (changed) | the three new helpers are eligible and adopted on exact match; `mise.toml` never appears in `files` | NFR-2 |
| `tests/setup_zed.bats` | unchanged expectations except any that asserted the `features` key | — |
| `scripts/verify-mirrors.sh` | four new pairs | FR-11 |

### CI checks

| Check | Covers |
| --- | --- |
| `scaffold-build.yml` static assertions | FR-1, FR-4 (symlink), NFR-1 |
| `scaffold-build.yml` build + smoke (`bash -c` and `bash -ic`) | FR-2, FR-5, FR-6, FR-12 |
| `scaffold-build.yml` core post-create (`claude --version`) | FR-3 |
| `scaffold-build.yml` workspace entry | FR-11 |
| `asset-parity.yml` | FR-11 mirror pairs |

### Edge Cases

- `mise.toml` with Windows line endings or no trailing newline.
- A developer `[tools]` section placed after `[env]`; a `[tools.python]`
  table with options; a commented-out `# node = "20"` line (must **not** count
  as present).
- `post.sh` where the developer already moved `# Codex CLI Setup` after the
  plugins block (guard sees the marker and does nothing — no reordering of
  existing files).
- Node bump: change `node` in `mise.toml`, rerun `post.sh` → `setup_mise`
  installs the new Node, `setup_claude` / `setup_codex` probes fail on the
  stale shim and reinstall.
- Project scaffolded with `--ai-profile codex-main` still gets Claude Code
  (core-owned) — unchanged from the feature era.
- `--zed`: `customizations.zed` survives the feature-free merges.
- Manual (not automated): mysql client login against the `mysql:8.0` service;
  arm64 build.
