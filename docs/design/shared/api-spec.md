# API Specification (Project-wide)

Cumulative public surface of `erd` and the `setup.sh` ecosystem. Per-issue API deltas live in `docs/design/#{issue}/api-spec.md`.

## CLI Surface

### `erd issue link <NUMBER> [OPTIONS]`

Link a GitHub Issue to one or more GitHub Projects. The default project is always linked. Additional projects are linked when the issue carries labels listed in `project.yml :: label_projects` (#230).

```
Arguments:
  <NUMBER>  Issue number

Options:
  --project-number <N>     Override project number from config (applies to default link only)
  --project-owner <OWNER>  Override project owner from config (applies to default link only)
  --size <SIZE>            Override Size field value (default link only)
  --priority <PRIORITY>    Override Priority field value (default link only)
  --status <STATUS>        Override Status field value (default link only)
  --parse-body <BOOL>      Parse Size/Priority from issue body [default: true]
  -v, --verbose            Verbose logging
```

Behavior:

1. Always link to `default_project` (with overrides if provided).
2. For each label on the issue: if a matching key exists under `label_projects`, link to that project too, applying that entry's `field_defaults` (CLI overrides do NOT apply to label-routed links — they use config-only defaults).
3. Missing label-routed projects log a warning and continue (non-fatal).

### `setup.sh` (#246, #263, #265)

Top-level template installer. Five operating modes:

| Mode | Trigger | Effect |
| --- | --- | --- |
| **Single** (default) | no mode flag and no auto-detected `modules.json`/manifest | Today's behavior — generates a flat single-project layout. |
| **Monorepo init** | `--monorepo`, or `--module <n>:<l>`, or interactive "y" answer to "Monorepo configuration?" | Generates root assets + per-module sub-directories + `modules.json`. |
| **Add-module** | `--add-module <name>`, or auto-detected when CWD already contains `modules.json` (interactive "y" answer) | Adds one module to an existing monorepo. |
| **Create-manifest** (#265) | `--create-manifest` | Walks the existing target tree and writes `.tarnished-manifest.json` (root + per-module in monorepo). Required as a one-shot for legacy projects before their first `--upgrade`. |
| **Upgrade** (#265) | `--upgrade` | Refreshes "verbatim copy" files of an existing scaffolded project to the latest (or `--target-version`-pinned) tarnished version, skipping files the user has edited. |

Flags (additions in #263 / #265 marked):

```
-h, --help                   Show help
-d, --dry-run                Preview without writing files (applies to all modes incl. --upgrade #265)
-y, --yes                    Skip confirmation prompts
--lang <language>            Single mode + add-module mode: select language (repeatable in single mode)
--monorepo                   [#263] Enable monorepo mode for fresh init
--module <name>:<lang>       [#263] Repeatable; define a module (init mode). Implies --monorepo.
--module <name>              [#265] Repeatable; restrict --upgrade to the named monorepo module.
                                    Disambiguated from #263 by the absence of `:lang`.
--add-module <name>          [#263] Add a module to an existing monorepo. Pair with --lang.
--codex                      Include OpenAI Codex CLI integration
--postgresql                 Include PostgreSQL service
--mysql                      Include MySQL service
--redis                      Include Redis service
--celery                     Include Celery (auto-enables Redis + Python)
--github-actions             Include GitHub Project integration
--overwrite                  Overwrite existing files without confirmation (single mode)
--create-manifest            [#265] Bootstrap a manifest from current state of files
--from-version <ref>         [#265] Recorded as `tarnished_version` in the new manifest
                                    (defaults to "unknown")
--upgrade                    [#265] Refresh tracked files of an existing scaffolded project
--target-version <ref>       [#265] Target git ref of upstream tarnished for --upgrade
                                    (tag, branch, commit; default: ${REMOTE_BRANCH} HEAD)
--shared-only                [#265] Restrict --upgrade to the root-level (shared) manifest
--prune                      [#265] Delete tracked files removed upstream (and unedited locally)
--force                      [#265] Bypass --upgrade's clean-tree precondition
```

Mutually-exclusive combinations rejected with exit 1:

| Combination | Reason |
| --- | --- |
| `--monorepo --add-module <name>` | Init vs. add are exclusive operations |
| `--module ... --add-module <name>` | `--module` (init form) is init-only |
| `--monorepo --lang <lang>` (without `--module`) | In monorepo mode, language is per-module; use `--module name:lang` |
| `--add-module <name>` outside a monorepo (no CWD `modules.json`) | Run with `--monorepo` first |
| `--upgrade` combined with `--monorepo` / `--add-module` / `--create-manifest` (#265) | Mode mutex |
| `--create-manifest` combined with `--monorepo` / `--add-module` / `--upgrade` (#265) | Mode mutex |
| `--upgrade --module foo:python` (#265) | In upgrade mode, `--module` takes a name only |
| `--upgrade --module foo` against single-mode target (#265) | `--module` is monorepo-only |
| `--upgrade --module unknown` (#265) | Module not in target's `modules.json` |
| `--upgrade` against project without `.tarnished-manifest.json` (#265) | Run `--create-manifest` first |
| `--upgrade` against dirty git tree (no `--force`) (#265) | Commit/stash first, or use `--force` |

Examples:

```bash
# Single (existing behavior)
./setup.sh --lang rust -y
./setup.sh --lang python --postgresql -y

# Monorepo init (#263)
./setup.sh                                                              # interactive
./setup.sh --monorepo --module jing:python --module kir:node -y         # CLI
./setup.sh --monorepo --module jing:python --postgresql --redis -y      # with services

# Add module (#263)
./setup.sh --add-module anisette --lang python -y                       # explicit
./setup.sh                                                              # implicit if modules.json exists

# Bootstrap a legacy project's manifest (#265)
./setup.sh --create-manifest --from-version v0.0.74 -y

# Upgrade an existing scaffolded project (#265)
./setup.sh --upgrade -y                                                 # latest develop
./setup.sh --upgrade --target-version v0.0.76 -y                        # pinned tag
./setup.sh --upgrade --dry-run                                          # preview, no writes
./setup.sh --upgrade --shared-only -y                                   # monorepo: only shared assets
./setup.sh --upgrade --module backend --module worker -y                # monorepo: specific modules
./setup.sh --upgrade --prune -y                                         # also delete upstream-removed files
./setup.sh --upgrade --force -y                                         # bypass clean-tree check

# Curl pipe (primary distribution path)
curl -fsSL .../setup.sh | bash -s -- --lang rust -y
curl -fsSL .../setup.sh | bash -s -- --monorepo --module jing:python --module kir:node -y
curl -fsSL .../setup.sh | bash -s -- --upgrade --target-version v0.0.76 -y
```

Completion message (#246):

```
Available Claude Code commands:
  /issue     - Create a GitHub Issue
  /design    - Design architecture for a GitHub Issue
  /implement - Implement a GitHub Issue
  /review    - Code review via Codex CLI
  /pr        - Create a Pull Request

Workflow: /issue → /design → /implement → /review → /pr
```

## Configuration Files

### `.github/project.yml`

```yaml
default_project:           # required
  owner: "<gh-owner>"
  number: <u32>

field_defaults:            # optional, applies to default link
  Status: "Backlog"
  Size: "M"
  Priority: "P1"

schedule_defaults:         # optional
  iteration: "current"     # "current" | "next" | iteration name
  start: "today"           # ISO date or relative ("today", "+7d", "+2w")
  end: "+14d"

pr_status:                 # optional
  on_open: "In review"

label_projects:            # optional (added in #230)
  bugfix:
    owner: "<gh-owner>"
    number: <u32>
    field_defaults:
      Status: "Todo"
  incident:
    owner: "<gh-owner>"
    number: <u32>
    field_defaults:
      Status: "Triage"
      Priority: "P0"
```

### `versioning.yml`

Two formats accepted (#228); Format B is canonical.

**Format B (canonical)**:

```yaml
versioning:
  branch_prefixes:
    major: ["major/"]
    minor: ["release/"]
    patch: ["feature/", "bugfix/"]
default_bump: rc
```

**Format A (legacy template)** is still accepted but should be migrated to Format B over time:

```yaml
branches:
  - prefix: "major/"
    bump: major
  - prefix: "release/"
    bump: minor
default_bump: rc
```

### `modules.json` (downstream monorepo target, #263)

JSON registry of modules in a monorepo, written by `setup.sh --monorepo` and updated by `setup.sh --add-module`.

```json
{
  "version": 1,
  "modules": [
    { "name": "jing", "path": "jing", "language": "python", "services": [] },
    { "name": "kir",  "path": "kir",  "language": "node",   "services": [] }
  ]
}
```

Schema (full table in [data-model.md](./data-model.md) :: "modules.json schema"):

| Field | Type | Notes |
| --- | --- | --- |
| `version` | integer | Currently `1`. Readers MUST reject unknown majors. |
| `modules[].name` | string | `^[a-z][a-z0-9_-]*$`, max 50 chars, unique. |
| `modules[].path` | string | Relative to repo root; equals `name` for now. |
| `modules[].language` | string | One of `rust`, `python`, `node`, `deno`, `latex`. |
| `modules[].services` | array of string | Informational; actual compose runs project-wide. |

## Internal API (cross-module function contracts)

### `src/cli/issue.rs`

| Function | Signature | Notes |
| --- | --- | --- |
| `IssueCommands::execute_link` | `async fn(&self, config: &Config, number: u64, overrides: LinkOverrides) -> anyhow::Result<()>` | Orchestrates default + label routing |
| `link_issue_to_project` | `async fn(&self, client: &GitHubClient, config: &Config, project_config: &ProjectConfig, node_id: &str) -> anyhow::Result<()>` | Reusable for both default and label-routed links (refactor in #230) |

### `src/github/client.rs`

| Function | Description |
| --- | --- |
| `GitHubClient::get_issue(owner, repo, number)` | Returns `GetIssueResponse` (incl. labels) |
| `GitHubClient::get_project(owner, number)` | Returns `ProjectV2` |
| `GitHubClient::add_issue_to_project_with_defaults(project, node_id, project_config, verbose)` | Adds the issue and applies field defaults |

### `src/project_config.rs`

| Function | Description |
| --- | --- |
| `ProjectConfig::load_with_path(path)` | Load and parse `project.yml` |
| `ProjectConfig::get_field_default(field)` | Lookup field default by name |
| `ProjectConfig::get_pr_open_status()` | Convenience for `pr_status.on_open` |

## Workflow Triggers (`.github/workflows/`)

Six root workflow files. The first four are also exposed as `workflow_call`-callable reusable workflows for downstream repos (e.g., freyja). `release-erd.yml` and `rust-quality-check.yml` are tarnished-internal.

| Workflow | Triggers | `workflow_call` exposed? | Purpose |
| --- | --- | --- | --- |
| `auto-tag.yml` | `push: [develop, main]` | Yes (inputs: `config-path`, `erd-version`) | Compute next semver tag from branch prefix and push it |
| `pr-project-status.yml` | `pull_request: [opened, reopened]` | Yes (inputs: `pr-number`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Map PR open → `pr_status.on_open` for linked issues |
| `project-integration.yml` | `issues: [opened, reopened]` | Yes (inputs: `issue-number`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Run `erd issue link` on issue create/reopen — links the default project (#230 split: label-only routing moved to `project-label-routing.yml`, #244) |
| `project-label-routing.yml` | `issues: [labeled]` | Yes (inputs: `issue-number`, `label-name`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Run `erd issue link --label-only` for label-keyed `label_projects` routing (#244 sub-feature opt-in) |
| `release-erd.yml` | `workflow_dispatch` (input: `tag`) | No | Build the `erd` Linux binary, run tests + coverage, upload artifacts, create GitHub Release |
| `rust-quality-check.yml` | `pull_request: [develop]`, `push: [develop]` | No | Tarnished-internal: `cargo check`, `clippy`, `fmt`, unit tests, integration tests |

### JavaScript action runtime pin policy (#267)

Every `uses:` reference to a third-party JavaScript action across these six files is pinned to the **earliest major whose `action.yml` declares `runs.using: node24`** as the default runtime — the selection rule documented in `architecture.md` :: "Cross-cutting Concerns / GitHub Actions JS runtime". Concrete pins:

| Action | Pin | Rationale for this major |
| --- | --- | --- |
| `actions/checkout` | `@v5` | First Node-24 major; `@v6` adds an unrelated `$RUNNER_TEMP` credential-persist change unneeded by our usage |
| `actions/cache` | `@v5` | First Node-24 major; cache-key compatibility maintained from v4 |
| `actions/github-script` | `@v8` | First Node-24 major with no API change vs v7; `@v9` makes `@actions/github` ESM-only and reserves `getOctokit` |
| `actions/upload-artifact` | `@v6` | First major where default `runs.using` is `node24` (v5 supported but defaulted to `node20`); `@v7` adds an unrelated `archive: false` direct-upload flag |
| `softprops/action-gh-release` | `@v3` | First Node-24 major; input schema (`tag_name`, `name`, `prerelease`, `generate_release_notes`, `files`) unchanged from v2 |

Composite actions (`dtolnay/rust-toolchain@stable`, `taiki-e/install-action@*`) have no Node runtime and are unaffected. Bumping any of these pins on the tarnished side automatically propagates to downstream consumers via `workflow_call`'s callee-execution semantics — no consumer-side change is required.

## Setup / Plugin Surface

### `setup.sh`

See "CLI Surface :: `setup.sh`" above for flags and modes (#263). The completion message is unchanged from #246.

### `scripts/lib/common.sh::sha256_file()` (#265)

Signature: `sha256_file <path>`. Cross-platform sha256 wrapper. Picks `sha256sum` (Linux/devcontainer default) or `shasum -a 256` (macOS), extracts the leading 64-hex-char digest, and emits `sha256:<lowercase-hex>` on stdout. Returns `1` if neither tool is available or if the file is missing. The `sha256:` prefix reserves space for future algorithm migrations (e.g., `blake3:`) without rewriting old manifests.

### `scripts/lib/common.sh::copy_with_confirm()` manifest extension (#265)

`copy_with_confirm` and `copy_dir_with_confirm` retain their pre-#265 behavior by default. When the global `MANIFEST_RECORDING` is `true`, every successful copy additionally appends `(<rel_path>, "sha256:<hex>")` to the global associative array `MANIFEST_TRACKED`, where `<rel_path>` is computed against the global `MANIFEST_RECORDING_ROOT`. Paths matching `MANIFEST_EXCLUDE_GLOBS` (defined in `scripts/lib/manifest.sh`) and paths outside `MANIFEST_RECORDING_ROOT` are skipped. The plugin contract is unchanged — plugins that already use `copy_with_confirm` (per `.claude/rules/shell.md`) automatically participate in tracking.

| Function | Purpose |
| --- | --- |
| `manifest_recording_start <root>` | Sets `MANIFEST_RECORDING=true`, `MANIFEST_RECORDING_ROOT=<root>`, clears `MANIFEST_TRACKED`. Idempotent. |
| `manifest_recording_stop` | Sets `MANIFEST_RECORDING=false`. Does NOT clear `MANIFEST_TRACKED`. |

### `scripts/lib/manifest.sh` — manifest module (#265)

Loaded by `setup.sh` in `--create-manifest` and `--upgrade` modes. Provides manifest read/write, the `manifest_decide` lifecycle state machine, `manifest_apply`, and the end-of-run summary printer. Constants:

| Constant | Value | Purpose |
| --- | --- | --- |
| `MANIFEST_FILENAME` | `.tarnished-manifest.json` | Per-scope manifest filename |
| `MANIFEST_SUPPORTED_VERSION` | `1` | Reject `manifest_version > 1` |
| `MANIFEST_EXCLUDE_GLOBS` | array | FR-3 exclusion list: `.gitignore`, `.tarnished-manifest.json`, `modules.json`, `docker-compose.yml`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.devcontainer/devcontainer.json`, `.codex/config.local.toml` |

| Function | Signature | Returns | Side effects |
| --- | --- | --- | --- |
| `manifest_path` | `<scope_root>` | `<root>/.tarnished-manifest.json` on stdout | none |
| `manifest_exists` | `<scope_root>` | exit `0` if file present | none |
| `manifest_read` | `<scope_root>` | parsed JSON on stdout (jq) | exits non-zero on missing file, malformed JSON, or `manifest_version > MANIFEST_SUPPORTED_VERSION` |
| `manifest_write` | `<scope_root> <version> <commit> <scaffold_options_json>` | exit `0` on success | atomic replace via `tmp + mv`; reads `MANIFEST_TRACKED` |
| `manifest_walk_directory` | `<root>` | `<rel_path>\t<hash>` lines on stdout | none. Honors `MANIFEST_EXCLUDE_GLOBS`. |
| `manifest_decide` | `<old_h_or_-> <current_h_or_-> <new_h_or_->` | one of `NOOP \| UPDATE \| SKIP_EDITED \| NEW \| SKIP_NEW_CONFLICT \| LEAVE_REMOVED \| PRUNE \| SKIP_USER_DELETED` on stdout | none. Pure function. Reads global `PRUNE_ENABLED` for the LEAVE_REMOVED/PRUNE branch. |
| `manifest_apply` | `<decision> <staging_path> <target_path>` | exit `0` | mutates target tree per decision (write/delete); honors `DRY_RUN`; updates tally globals (`TALLY_*`) and per-decision file-list arrays |
| `manifest_diff_summary` | `<staging_path> <target_path>` | `(~K +N -M)` line on stdout | none |
| `manifest_summary_print` | `<old_version> <new_version>` | summary block on stderr | reads tally globals; sectioned by scope in monorepo mode |

The 8-row decision state table is documented in `docs/design/#265/design.md` and visualized in `docs/design/#265/flowchart.md`.

### `scripts/lib/common.sh::update_gitignore()` (#259)

Signature: `update_gitignore <target_dir>`. Seeds `${target_dir}/.gitignore` with three idempotent whitelist/ignore blocks. Each block is appended only if its line-anchored comment marker is absent (`grep -q "^<marker>$"`). User-authored content between or after blocks is preserved (FR-7).

| Block | Marker (line-anchored) | Contents |
| --- | --- | --- |
| Claude whitelist | `# Claude Code (track project configs only)` | `.claude/*` + allowlist: `commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, `settings.json` |
| Serena | `# Serena MCP working files` | `.serena/` |
| Screenshots | `# Local screenshots (manual UI testing)` | `screenshots/` |

`update_gitignore` calls `touch` on a missing `.gitignore` and emits exactly two messages (`[INFO] Updating .gitignore...`, `[OK] .gitignore updated`).

### `scripts/lib/common.sh` — monorepo helpers (#263)

| Function | Signature | Returns | Side effects |
| --- | --- | --- | --- |
| `detect_existing_monorepo` | `<target_dir>` | `0` if `<target_dir>/modules.json` exists | none |
| `prompt_monorepo_mode` | (none) | `"true"` / `"false"` on stdout | reads `/dev/tty`; output via `print_*` to stderr |
| `prompt_module_loop` | (none) | mutates global `MODULES` | reads `/dev/tty`; loops until empty `name`; re-prompts on validation fail |
| `prompt_add_module` | (none) | `<name>:<lang>` on stdout | reads `/dev/tty` |
| `validate_module_name` | `<name>` | `0` if valid, `1` otherwise | none. Regex: `^[a-z][a-z0-9_-]*$`, max 50 chars |
| `read_modules_json` | `<target_dir>` | parsed `modules` array on stdout (jq) | exits non-zero on malformed JSON or unsupported `version` |
| `write_modules_json` | `<target_dir> <jq_filter>` | `0` on success | atomic replace via tmp + `mv` |
| `add_module_entry` | `<target_dir> <name> <lang> [<services_csv>]` | `0` on success, `2` if name exists | mutates `modules.json` |
| `find_module_by_name` | `<target_dir> <name>` | `0` if present, `1` otherwise | none |
| `list_module_names` | `<target_dir>` | newline-separated names on stdout | none |
| `list_existing_compose_services` | `<target_dir>` | newline-separated service ids on stdout | none |

### `templates/codex/plugin.sh::plugin_post_copy` — gitignore step (#259)

Same idempotency contract as above. Appends one block:

| Block | Marker (line-anchored) | Contents |
| --- | --- | --- |
| Codex whitelist | `# Codex CLI (track shared config only)` | `.codex/*` + `!.codex/config.toml` |

The Codex block is gated on the existence of `${target_dir}/.gitignore` (created earlier by `update_gitignore`); the plugin only appends.

### `templates/codex/.codex/config.toml` (#261)

Project-level Codex CLI configuration written verbatim into downstream projects (and into `/workspace/.codex/config.toml` for workspace dogfooding). Flat top-level TOML, four keys (full schema in `data-model.md::.codex/config.toml schema`):

| Key | Default value |
| --- | --- |
| `model` | `"gpt-5.4"` (bumped from `"gpt-5.3-codex"` in #261) |
| `model_reasoning_effort` | `"high"` (added in #261) |
| `approval_policy` | `"on-request"` |
| `sandbox_mode` | `"workspace-write"` |

The workspace's own `/workspace/.codex/config.toml` MUST stay in sync with this template default so a `/review` run inside the tarnished repo behaves identically to a `/review` run inside any newly bootstrapped downstream project.

### `templates/codex/.devcontainer/scripts/setup_codex.sh` and workspace counterpart (#261)

| Function | Purpose |
| --- | --- |
| `setup_codex()` | Idempotent install of `@openai/codex` via npm. Single function, no args, always returns `0`. |

Behavior contract:

1. If `npm` is missing → log `[WARN]` and return `0`.
2. If `codex` is already on `$PATH` → log the version and return `0`.
3. Otherwise, probe `npm root -g`:
   - empty result → attempt install without sudo (optimistic);
   - existing prefix dir not user-writable, OR missing prefix whose parent is not user-writable → use `sudo -E npm install -g @openai/codex`;
   - else → install without sudo.
4. Run `npm install -g @openai/codex` (with or without `sudo -E`); on non-zero exit, log `[WARN] Failed to install Codex CLI` plus the manual recovery command, and return `0`.

Contract: under `set -e` (in `post.sh`), this function MUST return `0` even when install fails — same non-fatal invariant as `setup_plugins.sh`. The two-pronged write check (existing dir vs. parent dir) is required because `npm install -g` writes into the prefix when present and creates it otherwise; a single check is wrong in one of the two cases. The decision tree is documented in `docs/design/#261/flowchart.md`.

The function is sourced into `.devcontainer/scripts/post.sh` after `setup_plugins`, using the same `${SCRIPT_DIR}/setup_codex.sh` source pattern. The Node.js LTS devcontainer feature (`ghcr.io/devcontainers/features/node:1`) is the prerequisite for `npm` being present.

### `/workspace/.claude/settings.json` (workspace, #261)

`permissions.allow` includes `"Bash(codex:*)"` so the `/review` skill can invoke `codex exec` and `codex review` without per-call approval. The pre-existing `permissions.deny` list and `hooks` block are unchanged. Other downstream projects opt in via `templates/codex/.claude/settings.json`.

### `setup_plugins.sh` (workspace + `templates/claude/.devcontainer/scripts/`, #249, #255, #273)

The workspace dogfooded copy (`/workspace/.devcontainer/scripts/setup_plugins.sh`) and the downstream template copy (`templates/claude/.devcontainer/scripts/setup_plugins.sh`) are now structurally identical (#273); a future change to one MUST be applied to the other in the same commit, mirroring the workspace-Codex dogfooding convention from #261.

| Function | Purpose |
| --- | --- |
| `is_claude_authenticated()` | (#273) Pure read-only check — returns `0` iff `$HOME/.claude/.credentials.json` exists and is non-empty (`[[ -s … ]]`). No subprocess, no network. |
| `ensure_claude_marketplace(repo)` | Idempotent registration of `anthropics/claude-plugins-official` marketplace. Returns `1` only on registration failure. |
| `try_install_plugin(name, marketplace, plugins_output)` | Install one plugin via `claude plugins install <name>@<marketplace> -s project`; absorb failures so siblings continue. Always returns `0`. |
| `setup_plugins()` | (1) `command -v claude` prerequisite; (2) **`is_claude_authenticated` pre-flight gate (#273)** — if false, print guidance ("run `claude` to log in, then re-run setup_plugins.sh") and `return 0`; (3) `ensure_claude_marketplace`; (4) `try_install_plugin` for `context7`, `serena`, optionally `playwright` (interactive prompt). |

Contract: under `set -e` (in `post.sh`), this script MUST `return 0` even when individual plugins fail or when authentication is missing; surface auth-missing as one-line guidance and per-plugin failures as warnings. The auth gate (#273) ensures `claude plugins …` is never invoked on a fresh container, so `post.sh` continues to `setup_codex` on first run instead of aborting under `set -e`.

### Language plugin contract (`templates/languages/<lang>/plugin.sh`, #263)

Language plugins (currently `python`, `rust`, `node`, `deno`, `latex`) expose a split `plugin_post_copy`:

```bash
# REQUIRED today, kept verbatim:
plugin_name()                       # echo "<id>"
plugin_description()                # echo "<desc>"
plugin_copy(target_dir)             # root-scoped (e.g. .github/workflows/<lang>-quality-check.yml)
plugin_dockerfile(target_dir)       # appends marker-guarded language block to docker/Dockerfile.dev

# REQUIRED today, becomes a SHIM that delegates to the new pair:
plugin_post_copy(target_dir) {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}

# NEW for language plugins only (#263):
plugin_post_copy_shared(target_dir)
plugin_post_copy_module(target_dir, module_name)
```

| Hook | Arguments | What it MAY touch | What it MUST NOT touch |
| --- | --- | --- | --- |
| `plugin_post_copy_shared` | `target_dir` (= project root) | `target_dir/.devcontainer/`, `target_dir/.claude/`, marker-guarded blocks in `target_dir/docker/Dockerfile.dev` and `target_dir/.devcontainer/scripts/post.sh` | Module sub-directories |
| `plugin_post_copy_module` | `target_dir` (= `<root>/<module>` in monorepo mode, `<root>` in single mode), `module_name` | Files inside `target_dir`: `pyproject.toml`/`Cargo.toml`/`package.json`, lint config (`ruff.toml`, `biome.json`, etc.), `src/<module_name>/`, `tests/`, language-specific `.gitignore`, `CLAUDE.md` for the module | `target_dir/.devcontainer/`, `target_dir/.claude/`, `target_dir/docker/`, root `docker-compose.yml` |

Both functions MUST be **idempotent** — re-running `setup.sh --add-module` for an already-registered language is a no-op for shared assets and obeys `--overwrite` for module assets. Marker-guarded blocks (`# >>> <lang> toolchain >>>` … `<<< <lang> toolchain <<<`) in `Dockerfile.dev` and `post.sh` provide block-level idempotency analogous to the gitignore policy (#259).

### Non-language plugin contract (`templates/{core,claude,codex,services/<svc>,github-actions/<wf>}/plugin.sh`)

Unchanged. These plugins implement only `plugin_post_copy(target_dir)` and operate on `target_dir = project root` in both single and monorepo modes. Service plugins remain mode-agnostic because their existing `{{PROJECT_NAME}}-<svc>` naming convention naturally produces monorepo-correct service names (e.g., `myapp-db` in single mode, `elsur-db` in monorepo mode for project `elsur`).

`templates/core/plugin.sh::plugin_post_copy` gains an internal monorepo-mode branch (#263) gated on `${MONOREPO_MODE}` that writes `modules.json` from the registered `MODULES` array and writes `<module>/CLAUDE.md` per module — internal logic, not a contract change.

### Orchestrator dispatch (`setup.sh::execute_plugin_post_copies`, #263)

```
for plugin_path in LOADED_PLUGINS:
    is_lang := [[ "$plugin_path" == */templates/languages/* ]]
    source plugin_path
    if declare -f plugin_interactive_setup && check_tty_available:
        plugin_interactive_setup

    if MONOREPO_MODE && is_lang && declare -f plugin_post_copy_module:
        plugin_post_copy_shared root
        for module in MODULES where lang(module) == lang(plugin):
            mkdir -p root/<module>
            plugin_post_copy_module root/<module> <module>
    else:
        plugin_post_copy root
```

Single mode: takes the `else` branch for all plugins → identical to today's behavior (NFR-1).

## Error Responses

| Error | Type | When |
| --- | --- | --- |
| `serde_yaml::Error` | Config parse fail | Malformed `project.yml` or `versioning.yml` |
| `GitHubClientError::RateLimited` | API | GitHub rate limit |
| `GitHubClientError::NotFound` | API | Issue / project not found (default link → fatal; label-routed → warning) |
| `anyhow::Error` (boundary) | Anywhere | Wrapped at command boundary |
| Plugin install failure | shell warning | `setup_plugins.sh` per-plugin; non-fatal |
| Marketplace registration failure | shell warning, `return 0` | `setup_plugins.sh` ensure_claude_marketplace; non-fatal so `post.sh` continues |
| Claude not yet authenticated (`~/.claude/.credentials.json` missing or empty) | shell info + guidance, `return 0` | `setup_plugins.sh` `is_claude_authenticated` gate (#273); skips marketplace/plugin steps entirely so `post.sh` proceeds to `setup_codex` on first run |
| `update_gitignore` write failure | shell error (propagates under `set -euo pipefail`) | `${target_dir}/.gitignore` not writable |
| Mutually-exclusive setup.sh flags | shell error, exit 1 | `--monorepo --add-module`, `--module --add-module`, `--monorepo --lang` (no `--module`) (#263); `--upgrade --monorepo`, `--upgrade --add-module`, `--upgrade --create-manifest`, `--create-manifest --monorepo`, `--create-manifest --add-module` (#265) |
| `--add-module` outside monorepo | shell error, exit 1 | CWD lacks `modules.json` (#263) |
| Unknown `--module` language | shell error, exit 1 | `--module name:foo` where `foo` ∉ `AVAILABLE_LANGUAGES` (#263) |
| Invalid module name | shell warning + re-prompt (TTY) / shell error, exit 1 (CLI) | `validate_module_name` failure (#263) |
| Module name conflict | exit 2 from `add_module_entry` → "Overwrite? y/n" prompt (TTY) / exit 1 (CLI without `--overwrite`) | add-module against existing `name` (#263) |
| `modules.json` malformed | shell error, exit 1 | jq parse failure (#263) |
| `modules.json` unsupported `version` | shell error, exit 1 | `read_modules_json` rejects `version > 1` (#263) |
| Manifest absent in `--upgrade` | shell error, exit 1 | `--upgrade` invoked on a project that has never been bootstrapped (#265) — guidance: "run `setup.sh --create-manifest` first" |
| Manifest `manifest_version` unsupported | shell error, exit 1 | `manifest_read` rejects `manifest_version > MANIFEST_SUPPORTED_VERSION` (#265) |
| Manifest JSON malformed | shell error, exit 1 | jq parse failure (#265) |
| `--upgrade` against dirty git tree without `--force` | shell error, exit 1 | `git diff-index --quiet HEAD --` non-zero (#265) |
| `--upgrade --module` ambiguity (`:lang` suffix) | shell error, exit 1 | `--upgrade --module foo:python` — disambiguation message (#265) |
| `--upgrade --module unknown` | shell error, exit 1 | named module not in target's `modules.json` (#265) |
| `--upgrade --module foo` against single-mode target | shell error, exit 1 | "--module is monorepo-only" (#265) |
| `--target-version <ref>` not resolvable | shell error, exit 1 | upstream tarnished clone failure (#265) |
| Plugin failure during staged copy in `--upgrade` | per-plugin warning, continue | same isolation pattern as `setup_plugins.sh` (#255), reused (#265) |
| sha256 tool missing | shell error, exit 1 | `sha256_file` finds neither `sha256sum` nor `shasum` (#265) |

## Versioning Policy

`erd` follows semver. Tag bumps are computed from branch prefix per `versioning.yml`. Default-bump fallback is `rc`. The CLI itself is at `0.1.0` (pre-1.0).

`modules.json` (#263) carries its own `version` field; current value is `1`. Bumps follow a major-only convention (no minor/patch; field additions are non-breaking by tolerant readers).
