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

Top-level scaffold and maintenance entry point.

| Mode | Trigger | Effect |
| --- | --- | --- |
| Initial single/monorepo | No Tarnished installation marker; existing scaffold flags | Creates project-owned seeds and foundation assets |
| Add-module | Explicit `--add-module` | Intended extension of an existing monorepo |
| Refresh | `--refresh` or bare existing-project rerun | Current updater/source safely refreshes AI assets; backs up and replaces distributed AI settings/assets; preserves application/profile and native local settings |
| Create-manifest | `--create-manifest` | Matches eligible staged distribution candidates; never inventories arbitrary project files |
| Upgrade | `--upgrade` | Updates trusted runtime helpers and root-scope AI assets/settings with backups; no application re-scaffolding; module-only retains scope |

Explicit scaffold flags against a recognized existing Tarnished target fail with maintenance/add-module guidance. `--refresh` accepts dry-run/yes and rejects scaffold and upgrade-only options. `--force` never bypasses ownership checks.

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
--zed                        [#323] Add Zed editor support (customizations.zed +
                                    .zed/settings.json) alongside the VS Code setup.
                                    Additive: customizations.vscode is always kept.
                                    Ignored with a warning in --add-module mode.
--postgresql                 Include PostgreSQL service
--mysql                      Include MySQL service
--redis                      Include Redis service
--celery                     Include Celery (auto-enables Redis + Python)
--github-actions             Include GitHub Project integration
--overwrite                  Overwrite existing files without confirmation (single mode)
--refresh                   Safely refresh AI skills/harness using the current checkout
--create-manifest            Establish provenance from eligible distribution matches
--from-version <ref>         Select source distribution for exact-match baseline comparison
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
| `--upgrade` against project without `.tarnished-manifest.json` (#265) | Root AI refresh runs; helpers skipped with nonzero result and `--create-manifest` guidance |
| `--upgrade` against dirty git tree (no `--force`) (#265) | Root AI refresh runs; helpers skipped with nonzero result; commit/stash or use helper-only `--force` bypass |

Examples:

```bash
# Single (existing behavior)
./setup.sh --lang rust -y
./setup.sh --lang python --postgresql -y

# Optional Zed editor support (#323) — openable in VS Code or Zed
./setup.sh --lang rust --zed -y

# Godot 4 .NET (GDScript + C#) (#331); headless by default
./setup.sh --lang godot -y
GODOT_GUI=true ./setup.sh --lang godot -y                               # WSL2: also run the editor GUI (WSLg)

# Monorepo init (#263)
./setup.sh                                                              # interactive
./setup.sh --monorepo --module jing:python --module kir:node -y         # CLI
./setup.sh --monorepo --module jing:python --postgresql --redis -y      # with services

# Add module (#263)
./setup.sh --add-module anisette --lang python -y                       # explicit
./setup.sh                                                              # safe AI refresh on existing target

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
Codex workflow: $issue → $design → $implement → $review → $pr
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
| `modules[].language` | string | One of `rust`, `python`, `node`, `deno`, `latex`, `go` (#274), `godot` (#331). |
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

The first four are also exposed as `workflow_call`-callable reusable workflows for downstream repos (e.g., freyja). The rest are tarnished-internal.

| Workflow | Triggers | `workflow_call` exposed? | Purpose |
| --- | --- | --- | --- |
| `auto-tag.yml` | `push: [develop, main]` | Yes (inputs: `config-path`, `erd-version`) | Compute next semver tag from branch prefix and push it |
| `pr-project-status.yml` | `pull_request: [opened, reopened]` | Yes (inputs: `pr-number`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Map PR open → `pr_status.on_open` for linked issues |
| `project-integration.yml` | `issues: [opened, reopened]` | Yes (inputs: `issue-number`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Run `erd issue link` on issue create/reopen — links the default project (#230 split: label-only routing moved to `project-label-routing.yml`, #244) |
| `project-label-routing.yml` | `issues: [labeled]` | Yes (inputs: `issue-number`, `label-name`, `config-path`, `erd-version`; secret: `PROJECT_TOKEN`) | Run `erd issue link --label-only` for label-keyed `label_projects` routing (#244 sub-feature opt-in) |
| `release-erd.yml` | `workflow_dispatch` (input: `tag`) | No | Build the `erd` Linux binary, run tests + coverage, upload artifacts, create GitHub Release |
| `rust-quality-check.yml` | `pull_request: [develop]`, `push: [develop]` | No | Tarnished-internal: `cargo check`, `clippy`, `fmt`, unit tests, integration tests |
| `asset-parity.yml` | `pull_request: [develop]` (AI asset / template paths), `push: [develop]` | No | Runs `scripts/verify-mirrors.sh` (#304) |
| `claude-code-review.yml` | `pull_request: [develop]` types `[opened, ready_for_review]` | No | First-pass Claude review of a PR (#308) |
| `scaffold-build.yml` | `pull_request: [develop]` (templates, `setup.sh`, `scripts/lib`, `scripts/ci`, root `docker/`, `mise.toml`), `push: [develop]`, `workflow_dispatch` | No | (#325) amd64 matrix — core, python, node, rust, go, deno, godot (#331; smoke `godot dotnet gdformat gdlint`), postgresql, mysql, redis, celery, plus the workspace image: scaffold with `setup.sh -y`, assert no `features`, `docker build` the generated `Dockerfile.dev` with gha cache and a `github_token` BuildKit secret, run `scripts/ci/smoke-runtimes.sh` under `bash -c` and `bash -ic`; the core entry also runs `post.sh` and asserts `claude --version`. latex excluded |

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

See "CLI Surface :: `setup.sh`" above for flags and modes (#263). The completion message is unchanged from #246. Per #279, `setup.sh`'s `--upgrade` mode automatically excludes the always-latest path whitelist via the `MANIFEST_EXCLUDE_GLOBS` extension — no new flags or modes are required, and the eight-case `manifest_decide` state machine is unchanged. Pre-#279 manifests that contain hashes for now-excluded paths become inert; the next `--create-manifest` produces a clean manifest.

Per #325 no flag changes: `--help` states that runtimes come from `mise.toml` and lists latex; `show_interactive_mode_error` lists only real flags (the phantom `--playwright`, `--docker`, `--neo4j` are gone); `check_dependencies` requires `jq` and `awk` (mise and Docker are container-side, not host prerequisites); `execute_plugin_dockerfiles` keeps its position between the copy and post-copy passes and warns once when the target `Dockerfile.dev` lacks `# >>> mise runtimes >>>`. Add-module ends with a hint to run `mise install` (or rebuild) for newly declared runtimes.

Per #331 no flag changes. `AVAILABLE_LANGUAGES` gains `godot`, appended so the
existing menu numbers stay stable, and `LANGUAGE_DISPLAY_NAMES[godot]` is
`Godot (GDScript + C#)`. `--help` lists godot, documents
`GODOT_GUI=true|false`, and adds godot examples.
`common.sh::show_interactive_mode_error` lists godot. In single mode,
`infer_scaffold_options` reports `godot` when `gdlintrc` or
`.github/workflows/godot-quality-check.yml` exists, so `--upgrade` staging
reproduces the flavor. `GODOT_GUI` is the only new input. It is read by the
godot plugin, not by `setup.sh`: `true` / `1` / `yes` enables the WSLg
overlay, and any other value disables it. When it is unset, the plugin
prompts on a TTY, except with `-y`, in `--upgrade` / `--create-manifest`, or
when the overlay is already enabled. `execute_plugin_post_copies` calls
`plugin_interactive_setup` only when `check_tty_available` succeeds, and does
not check `-y`. The plugin therefore resolves the variable in a non-prompting
helper, `_godot_resolve_gui_choice`. It calls that helper both from
`plugin_interactive_setup`, which adds only the prompt, and from
`plugin_post_copy_shared` whenever the choice is still undecided. This makes
`GODOT_GUI=true` effective in non-TTY runs (CI, `curl | bash`).

Per #323, `scaffold_options` gains the optional boolean `zed_enabled`, produced by `infer_scaffold_options` from the presence of `<scope>/.zed/settings.json` and restored into `ZED_ENABLED` by `populate_setup_state_from_manifest` so an `--upgrade` staging run reproduces the same tree it would have scaffolded. Because `.zed/settings.json` is outside `_manifest_path_eligible` (only `.devcontainer/scripts/*.sh` other than `post.sh` is maintenance-eligible), that fidelity affects staging only: `--create-manifest` never hashes the file, `--upgrade` never decides on it, and `--upgrade --prune` cannot delete it. No `MANIFEST_EXCLUDE_GLOBS` entry is needed.

### `setup.sh::derive_agent_names()` (#308)

Signature: `derive_agent_names <ai_profile>`. Sets the globals `AI_PRIMARY_AGENT` and `AI_REVIEW_AGENT` from an `ai_profile` value (`claude-main` / `codex-main` / `dual`), with `claude-main` as the fallback for an unrecognized value. Extracted from the previously inline case block so the scaffold path and the upgrade path share exactly one mapping.

Note the values are human display strings — `"Claude Code"`, `"Codex CLI"`, `"Manual review"`, `"Claude Code + Codex CLI"`, `"Cross-agent review"` — not dispatchable agent identifiers. Consumers that need a machine-readable binding read `.tarnished/agent-profile.json :: roles` instead.

### `setup.sh::stage_plugin_run()` placeholder rendering (#265, fixed #308)

Signature unchanged: `stage_plugin_run <upstream_dir> <staging_dir>` (and the per-module variant `stage_plugin_run_for_module <upstream_dir> <staging_dir> <lang> <module_name>`). Both now call `replace_placeholders` against `<staging_dir>` after `execute_plugin_post_copies`, using the project name derived from the target directory basename and the `ai_profile` read from the target's `.tarnished/agent-profile.json` (the same source `detect_scaffold_options` uses).

Without this, `--upgrade` staged **unrendered** template copies while the manifest held hashes of **rendered** files, so `manifest_decide` saw `current == old && new != old` and emitted `UPDATE` — writing `{{PROJECT_NAME}}` / `{{AI_PROFILE}}` / `{{AI_PRIMARY_AGENT}}` / `{{AI_REVIEW_AGENT}}` back over correctly rendered downstream files. Most placeholder-bearing files escaped this because they sit in `MANIFEST_EXCLUDE_GLOBS` (`CLAUDE.md`, `AGENTS.md`, `README.md`, `docker-compose.yml`, `.devcontainer/devcontainer.json`); the exposed set was exactly `.tarnished/agent-profile.json` and `.tarnished/workflows/{README,issue,design,implement,review,pr}.md`, which historically were manifest-tracked and placeholder-bearing; the profile is now project-owned and workflow contracts use refresh. The regression only fired when one of those files changed upstream — which #308 is the first change to do.

`replace_placeholders` carries a hard-coded file list (`scripts/lib/common.sh`), so any new placeholder-bearing scaffolded file must be added there. New contract files introduced by #308 (`.tarnished/workflows/flow.md`) are authored placeholder-free instead. #331 adds `docker-compose.godot-gui.yml`, which needs `{{PROJECT_NAME}}` as its service key. Unlike the service overlays it is never merged away, so it must be rendered in place.

### `scripts/lib/common.sh::sha256_file()` (#265)

Signature: `sha256_file <path>`. Cross-platform sha256 wrapper. Picks `sha256sum` (Linux/devcontainer default) or `shasum -a 256` (macOS), extracts the leading 64-hex-char digest, and emits `sha256:<lowercase-hex>` on stdout. Returns `1` if neither tool is available or if the file is missing. The `sha256:` prefix reserves space for future algorithm migrations (e.g., `blake3:`) without rewriting old manifests.

### `scripts/lib/common.sh::copy_with_confirm()` provenance extension

Preserve existing copy/confirmation interface. Record only successful eligible writes while recording is enabled; a skipped or declined copy grants no ownership. Rehash the finite recorded paths after transformations. Positive runtime-helper eligibility and exclusions protect project-owned seeds, settings, AI-refresh destinations, sidecars, and local state.

### `scripts/lib/common.sh::merge_devcontainer_json()`

Signature: `merge_devcontainer_json <base_file> <overlay_file> <output_file>`.
Merges devcontainer JSON files with special handling for
`customizations.vscode` and (since #323) `customizations.zed`. Since #325 no
shipped overlay carries `features`; the key is merged like any other
top-level key. Inputs may be
strict JSON or JSON with `//` and `/* */` comments. The helper normalizes each
input to strict JSON in private temp files before invoking `jq`; the merged
output is strict JSON and comments are not preserved. The function reads **no**
globals: Zed emission is gated by key presence, not by a flag, which keeps it
unit-testable and makes the non-Zed output byte-identical to pre-#323.

Merge semantics:

| Field | Behavior |
| --- | --- |
| Other top-level keys, including `features` (#325) | Deep-merged with overlay values taking precedence; emitted only when present on either side, so feature-free inputs produce no `features` key and a developer's own `features` survive. |
| `customizations.vscode.extensions` | Base and overlay arrays concatenated and de-duplicated with `unique`. Always emitted. |
| `customizations.vscode.settings` | Object merge: base settings overlaid by plugin settings. Always emitted. |
| `customizations.zed` | (#323) Emitted **only if** the base or the overlay has a non-null `customizations.zed`. When emitted: object merge of both sides, with `extensions` replaced by the `unique` union of both sides' `extensions`. A `zed` subtree present only in the base survives, so a non-Zed overlay cannot erase it. |
| other `customizations.*` namespaces (e.g. `codespaces`) | Still dropped by the rebuild. |

Private helpers:

| Function | Purpose |
| --- | --- |
| `_strip_json_comments <input_file>` | Streams input with `//` and `/* */` comments removed only outside string literals. Preserves URLs and escaped quotes inside strings. |
| `_jsonc_to_json_file <input_file> <output_file>` | Runs the comment stripper, validates the result with `jq empty`, and writes strict JSON to `output_file`. |

Failure behavior:

- Missing base or overlay file returns non-zero with the existing
  `print_error` message.
- Invalid comment syntax or invalid JSON after stripping returns non-zero,
  removes temp files, and removes the caller-provided output path.
- A failed final merge returns non-zero, removes temp files, and removes the
  caller-provided output path so stale `.devcontainer/devcontainer.json.tmp`
  files do not survive.

Scope boundary: direct plugin mutations that invoke `jq` themselves, such as
service plugins appending to `runServices`, remain strict JSON until they opt
into a shared devcontainer-filter helper.

### `scripts/lib/common.sh::merge_zed_settings()` (#323)

Signature: `merge_zed_settings <base_file> <overlay_file> <output_file>`.
Deep merge for Zed project settings (`.zed/settings.json`). Inputs may be
strict JSON or comment-bearing JSONC — Zed's own settings files are
canonically commented — normalized through the same `_jsonc_to_json_file`
primitives `merge_devcontainer_json` uses; the output is strict JSON and
comments are not preserved.

| Input pair | Behavior |
| --- | --- |
| object / object | Recursive key-wise merge. Base key order preserved; overlay-only keys appended. |
| array / array | `unique` union — de-duplicated and sorted. Arrays are treated as sets, which is correct for `file_scan_exclusions` and `language_servers`. |
| scalar, or mismatched types | Overlay wins. |
| key only in base | Preserved untouched — developer-authored settings survive re-runs. |

Failure behavior: missing base → `print_error` + return 1; missing overlay →
`cp base output` + return 0 (same accommodation as `merge_claude_settings`);
unparseable input or jq failure → temps and the caller-provided output path
removed, return 1. Idempotent by construction, so a repeated merge of the same
overlay produces identical bytes.

### `scripts/lib/common.sh::apply_zed_assets()` (#323)

Signature: `apply_zed_assets <target_dir> <plugin_dir>`. Installs one template
flavor's Zed contributions. The **only** reader of `ZED_ENABLED` in the
repository (via `${ZED_ENABLED:-false}`), so plugins carry no Zed conditional
and sourcing a plugin in isolation behaves as Zed-off.

1. Return 0 immediately unless `ZED_ENABLED == true` **and**
   `<plugin_dir>/.zed/` exists.
2. If `<plugin_dir>/.zed/devcontainer.json` and the target
   `.devcontainer/devcontainer.json` both exist, merge the former into the
   latter with `merge_devcontainer_json` (temp + `mv`).
3. If `<plugin_dir>/.zed/settings.json` exists, `mkdir -p <target_dir>/.zed`
   and either `copy_with_confirm` it (no target file yet — the first
   contributor, in practice `core`) or merge it with `merge_zed_settings`.

Contract: always returns 0 — a Zed failure must neither abort a scaffold nor
damage a live file. Each failing branch removes its temp file, emits
`print_warning` and leaves the target exactly as it was. `mkdir -p` is
required because `copy_with_confirm` does not create parent directories.

Call sites, one line each and never conditional:
`templates/core/plugin.sh::plugin_post_copy`;
`templates/languages/<lang>/plugin.sh::plugin_post_copy_shared` (immediately
after the existing devcontainer merge, because the six older language hooks can
`return` early from their `post.sh` marker branch (godot has no early return
but keeps the same position); and never from
`plugin_post_copy_module`, since `.zed/` is a root asset);
`templates/services/{postgresql,mysql,redis}/plugin.sh::plugin_post_copy`.

### `templates/<flavor>/.zed/` directory contract (#323)

A new permitted template subdirectory (`AGENTS.md` §4), and the only one that
is **not** copied verbatim into the target.

| File | Role |
| --- | --- |
| `devcontainer.json` | Devcontainer **merge overlay** whose only content is `customizations.zed.extensions`. Must never reach the target. May carry `//` comments. |
| `settings.json` | Fragment installed/merged as `<target>/.zed/settings.json`. Strict JSON. |

Shipped extension IDs — all verified to exist in `zed-industries/extensions`
(`extensions.toml` + `api.zed.dev/extensions`): `core` → `dockerfile`;
`languages/rust` and `languages/python` → `toml`; `languages/node` → `biome`;
`languages/deno` → `deno`; `languages/latex` → `latex`;
`languages/godot` → `gdscript`, `csharp` (#331; `gdscript` needs `nc`, which
the godot OS block installs); `services/postgresql` and `services/mysql` →
`sql`. `languages/go` ships a
settings fragment only, and `services/redis` ships no `.zed/` at all. Rust,
Python, Go, TypeScript/JavaScript, JSON, YAML, Markdown and Git are built into
Zed and get no extension. Rationale and rejected candidates:
`docs/design/#323/research.md`.

### `scripts/lib/manifest.sh` — manifest module (#265)

Loaded by `setup.sh` in `--create-manifest` and `--upgrade` modes. Provides manifest read/write, the `manifest_decide` lifecycle state machine, `manifest_apply`, and the end-of-run summary printer. Constants:

| Constant | Value | Purpose |
| --- | --- | --- |
| `MANIFEST_FILENAME` | `.tarnished-manifest.json` | Per-scope manifest filename |
| `MANIFEST_SUPPORTED_VERSION` | `2` | Read v1 only for conservative migration; reject newer unsupported versions |
| `MANIFEST_EXCLUDE_GLOBS` | array | FR-3 exclusion list. Merge-/dynamic-/user-owned files: `.gitignore`, `.tarnished-manifest.json`, `modules.json`, `docker-compose.yml`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.devcontainer/devcontainer.json`, `.codex/config.local.toml`. Always-latest directory-managed (#279/#281): `.claude/commands{,/*}`, `.claude/skills{,/*}`, `.claude/scripts{,/*}` and the `.local` sidecars. Always-latest file-managed (#279): `.claude/rules/shell.md`. User-owned CI / GitHub configuration (#286): `.github{,/*}`. |

| Function | Signature | Returns | Side effects |
| --- | --- | --- | --- |
| `manifest_path` | `<scope_root>` | `<root>/.tarnished-manifest.json` on stdout | none |
| `manifest_exists` | `<scope_root>` | exit `0` if file present | none |
| `manifest_read` | `<scope_root>` | parsed JSON on stdout (jq) | exits non-zero on missing file, malformed JSON, or `manifest_version > MANIFEST_SUPPORTED_VERSION` |
| `manifest_write` | `<scope_root> <version> <commit> <scaffold_options_json>` | exit `0` on success | atomic replace via `tmp + mv`; reads `MANIFEST_TRACKED` |
| `manifest_walk_directory` | `<root>` | `<rel_path>\t<hash>` lines on stdout | none. Private staging/source inventory only; never bootstrap ownership by scanning downstream. Honors positive eligibility plus exclusions. |
| `manifest_decide` | `<old_h_or_-> <current_h_or_-> <new_h_or_->` | one of `NOOP \| UPDATE \| SKIP_EDITED \| NEW \| SKIP_NEW_CONFLICT \| LEAVE_REMOVED \| PRUNE \| SKIP_USER_DELETED` on stdout | none. Pure function. Reads global `PRUNE_ENABLED` for the LEAVE_REMOVED/PRUNE branch. |
| `manifest_apply` | `<decision> <rel_path> <staging_path> <target_path> <expected_current_hash> <expected_desired_hash>` | tally + per-file output | validates expected hashes, copied bytes, final current content and installed postcondition; failed replacement/prune preserves the previous baseline |
| `manifest_diff_summary` | `<staging_path> <target_path>` | `(~K +N -M)` line on stdout | none |
| `manifest_summary_print` | `<old_version> <new_version>` | summary block on stderr | reads tally globals; sectioned by scope in monorepo mode |

The original eight outcomes remain useful for trusted baselines. Eligibility and legacy migration run before decisions; only successfully installed/matched bytes advance state. The current ownership decision table is in `docs/design/#316/design.md`.

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

Same idempotency contract as above. Appends Codex-specific blocks:

| Block | Marker (line-anchored) | Contents |
| --- | --- | --- |
| Codex whitelist | `# Codex CLI (track shared config only)` | `.codex/*` + `!.codex/config.toml` |
| Codex repo skills | `# Codex Agent Skills (track shared workflow skills)` | `.agents/*` + allowlist: `skills/` |

### `templates/languages/godot/plugin.sh::plugin_post_copy_shared` — gitignore step (#331)

Same contract (touch if missing, add a trailing newline when the file lacks
one, exact-line `grep -q "^<marker>$"`, append-only), at root scope:

| Block | Marker (line-anchored) | Contents |
| --- | --- | --- |
| Godot | `# Godot (engine caches and export output)` | `.godot/`, `.mono/`, `data_*/`, `mono_crash.*.json`, `*.translation`, `export_credentials.cfg`, `build/`, `export/` |

The patterns are unanchored, so they also match inside monorepo modules.

The Codex plugin touches `${target_dir}/.gitignore` if it is missing, then only appends marker-guarded blocks. This keeps fresh Codex projects and existing projects on the same idempotent path even though `setup.sh` runs plugin post-copy hooks before `update_gitignore`.

### `templates/codex/.agents/skills/*` (#Codex workflow parity)

Codex repo-local skills are copied verbatim by `templates/codex/plugin.sh::plugin_copy` into downstream `.agents/skills/`. They mirror the Claude lifecycle names while delegating detailed behavior to `.tarnished/workflows/` and, when present, `.claude/skills/*` compatibility references.

| Skill | Purpose |
| --- | --- |
| `issue` | Requirement discovery, estimation, and GitHub Issue creation |
| `design` | Issue branch creation/reuse and design artifact generation |
| `implement` | Implementation, build, test, and commits |
| `review` | Independent branch review and `docs/review/#{issue_number}/review.md` |
| `pr` | PR creation, CI validation, optional merge, and target branch update |
| `flow` | Lifecycle orchestration across the five stages (#308) |

Each skill directory also carries `agents/openai.yaml` declaring `interface.display_name` and `interface.short_description`.

### Lifecycle skill argument surface (#308, #310)

| Skill | Arguments |
| --- | --- |
| `/issue` | *(none)* |
| `/design` | `<issue_number> [--base <branch>]` |
| `/implement` | `<issue_number> [--base <branch>]` |
| `/review` | `[target_branch] [--codex\|--claude\|--builtin]` |
| `/pr` | `[target_branch] [--merge]` |
| `/flow` | `[--issue N] [--base <branch>] [--from <stage>] [--merge]` |

`--base` defaults to `develop` and is threaded to `_shared/branch` Issue mode. New branches are created directly from the freshly fetched remote base commit, in a separate worktree when needed; the local base is never pulled, merged, or reset implicitly. The same target is used for review and PR creation.

`/flow` derives its entry stage from repository evidence rather than a persisted state file. Check issue state and linked merged PRs first, then discover existing branches using the exact `/#<n>/` segment without creating one. Inspect the resolved issue branch/worktree, committed design and its review, actual implementation and required checks, and PRs across all states for the intended head/base. An open PR is reused only after incomplete earlier stages finish. Review reuse follows `.claude/skills/review/references/completion.md`: status, verified code, freshly fetched target commit, and issue-body digest must match; a filename or `Fixes Applied` heading alone is insufficient. Failed lookups mean unknown state. An explicit `--from <stage>` stops on missing prerequisites without repairing an earlier stage; `issue` is exempt because it creates them.

`/flow` resolves its issue number by a fixed precedence, first match wins (#310):

| # | Condition | Result |
| --- | --- | --- |
| 1 | `--from issue` | Skip number resolution; entry stage is `issue` |
| 2 | `--issue N` | `N` |
| 3 | Current branch matches `.../#<n>/...` | `<n>` |
| 4 | Nothing resolved | Structured choice: name an existing issue, or start from a requirement (entry stage `issue`) |

Rule 1 precedes rule 4 by necessity, not convention: a rule that only offers the choice "when no number resolves" still prompts on `--from issue`, since no number resolves there either.

Contradictory pairs are rejected **before** the precedence table is consulted, because first-match-wins would otherwise short-circuit on rule 1 and never notice the conflicting flag: `--from issue` with `--issue N` (the stage creates the number the flag supplies), and `--from <stage after issue>` with no resolvable number (a later stage cannot run against an issue that does not exist — rule 4 then offers only the existing-issue option).

`/flow` carries **no** approval gates (#312). Until #312 it stopped twice — after an issue the run created, and before implementation — and both gates existed because the party that could review an artifact against the requirement was a human, and the alternative (a read-only subagent) could not reach the user. The restructure inverts what is delegated: authoring moves to subagents and the review stays in the session, so the reviewing party is the same one that conducted the requirements dialogue and can escalate whenever it needs to. The stage order is `issue → design → implement → review → triage → pr`.

A `/flow` run stops for the user in exactly four places, and `flow/SKILL.md` states the list so the property is checkable rather than emergent: requirement gathering in `/issue`, an escalation the orchestrator cannot resolve (a subagent blocked-result, or a blocking review finding surviving two rounds), argument resolution (an unresolvable issue number, contradictory flags, or unmet prerequisites for an explicit `--from` stage), and a `/pr` failure.

The orchestrator reviews design artifacts before committing them. On resumption, inspect the committed artifacts and their review rather than treating a commit subject alone as proof of completion.

### Stage ownership and delegation (#312)

Each stage's **authoring** has a single owner; the orchestrator reviews rather than co-authors. A delegated subagent still routes its own internal work.

| Stage | Writes | Reviews |
| --- | --- | --- |
| `issue` | orchestrator (inline) | the user, through the requirements dialogue |
| `design` | designer | orchestrator, against the issue's Requirements |
| `implement` | executor | orchestrator, against both the design and issue Requirements |
| `review` | external-reviewer | orchestrator triages; executor applies the fixes |
| `pr` | executor drafts the body and monitors CI; orchestrator creates the PR | orchestrator checks content and owns the merge decision |

A pull request is outward-facing and a merge is irreversible, which is why neither is delegated to the stage's writing agent.

`/design` runs **write → review → commit**, with the commit performed by the orchestrator after the review clears. Before #312 the commit came first and the sign-off step second, so a design commit proved artifacts were written rather than approved; the new ordering makes the commit itself the record that the review happened, which is why `/flow`'s evidence derivation needs no additional artifact. The review loop is capped at 2 rounds and a blocking finding surviving round 2 escalates to the user. Findings are recorded in `docs/design/#{issue}/orchestrator-review.md` as an audit trail, not as an evidence key.

### Blocked-result contract (#312)

`designer` and `executor` route user decisions through the orchestrator. They resolve routine reversible choices using the issue, design, codebase, and accepted decisions; a blocked-result is required when a missing answer changes requirements, public behavior, design intent, or authority, or a required prerequisite cannot be recovered within scope. Complete independent authorized work before returning partial results.

| Field | Required | Purpose |
| --- | --- | --- |
| Question | Yes | What could not be resolved |
| Options | Yes | The readings or approaches visible, and what each implies |
| Evidence checked | Yes | What was already consulted — distinguishes a real block from an unasked question |
| Partial work | No | What was completed, so it is not redone |

Triggers include a requirement-level ambiguity producing different public interfaces, a design/convention conflict whose resolution would violate required behavior, or a required prerequisite that cannot be recovered within scope. Routine choices and recoverable inputs do not trigger escalation. The orchestrator resolves the question, or escalates when the answer is the user's to give.

### Role → model and effort binding (#312, #333)

| Role | Model channel | Model | Effort channel | Effort |
| --- | --- | --- | --- | --- |
| `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5-2` | `.claude/settings.json :: effortLevel` (`low`\|`medium`\|`high`\|`xhigh`) | `high` |
| `designer` | `.claude/agents/designer.md` frontmatter `model:` | `claude-opus-5-5[1m]` | `.claude/agents/designer.md` frontmatter `effort:` (`low`\|`medium`\|`high`\|`xhigh`\|`max`) | `high` |
| `executor` | `.claude/agents/executor.md` frontmatter `model:` | `claude-opus-5-5` | `.claude/agents/executor.md` frontmatter `effort:` (same set) | `medium` |
| `external-reviewer` | Reviewer's own CLI configuration (`.codex/config.toml :: model`) | Codex default: `gpt-6-astra` | Reviewer's own CLI configuration (`.codex/config.toml :: model_reasoning_effort`) | Codex default: `high` |

The table describes Claude dispatch. Codex-native `designer` and `executor` inherit the active Codex session model and reasoning effort unless a supported explicit override is set; Claude frontmatter `model:` and `effort:` do not apply to Codex. `roles.<role>.model` defaults to `null` for the three primary roles; `external-reviewer` has no model key, and no role has an effort key. A non-null override is vendor-specific to the actual dispatcher, including in `dual` mode. Keep it `null` for a profile shared across vendors, and report incompatible overrides rather than translating them. Claude dispatch model precedence is profile override → agent frontmatter → session inheritance; Claude dispatch effort precedence is `CLAUDE_CODE_EFFORT_LEVEL` → agent frontmatter → session effort. The session's own effort is the per-model `modelSettings.<model-id>.effortLevel` (written by `/effort`) when present, otherwise the top-level `effortLevel`. Codex precedence is supported profile override → active Codex session. `code-reviewer` carries no pin and inherits the session model and effort. `merge_claude_settings` carries both `model` and `effortLevel` through every scaffold merge (regression-tested in `tests/common_json.bats`).

`/review` carries two ground truths rather than one (#312): the design document and the issue's Requirements section, with a criterion for each. Criterion 8 asks whether the implementation matches the design; criterion 9 asks whether the branch carries every requirement in the issue. Only the second can catch a requirement dropped upstream of the design — without it, a requirement lost at the `/issue` stage flows through design, implementation, and review with every check returning green.

### `templates/codex/.codex/config.toml` (#261, #308)

Project-level Codex CLI configuration written verbatim into downstream projects (and into `/workspace/.codex/config.toml` for workspace dogfooding). Flat top-level TOML, four keys (full schema in `data-model.md::.codex/config.toml schema`):

| Key | Default value |
| --- | --- |
| `model` | `"gpt-6-astra"` |
| `model_reasoning_effort` | `"high"` |
| `approval_policy` | `"on-request"` |
| `sandbox_mode` | `"workspace-write"` |

Validate configuration with `codex exec --strict-config` and a minimal runtime check for model and effort availability. Schema acceptance alone does not prove the backend accepts the configured model.

When Codex is the external reviewer, this file supplies its default model and reasoning effort; the same defaults also apply to Codex-primary sessions. `roles.external-reviewer` has no `model` or `reasoning_effort` fields: the selected reviewer owns its configuration. `/review` records the actual runtime model and effort when available, labeling values read only from configuration as configured rather than resolved. `roles.external-reviewer.agent` selects which reviewer runs.

The workspace's own `/workspace/.codex/config.toml` MUST stay in sync with this template default so a `/review` run inside the tarnished repo behaves identically to a `/review` run inside any newly bootstrapped downstream project.

### Generated install contract (#325)

Generated projects carry no devcontainer `features`. Rationale and decision
log: `docs/design/#325/design.md`; external facts: `research/mise.md`.

**`docker/Dockerfile.dev` (core template; workspace copy byte-identical)**

| Region | Contents |
| --- | --- |
| Root section (POSIX `sh`) | apt: build-essential, ca-certificates, curl, git, gnupg, jq, minisign, openssh-client, procps, ripgrep, rsync, sudo, vim; `gh` from `cli.github.com` with a `signed-by` keyring checked against `ARG GH_KEYRING_FINGERPRINT`; mise from GitHub releases at `ARG MISE_VERSION`, verified by `minisign` (`ARG MISE_MINISIGN_PUBKEY`) and `sha256sum`, arch `amd64`→`linux-x64`, `arm64`→`linux-arm64`, else fail; `vscode` user with NOPASSWD sudo |
| Plugin OS blocks | Inserted above the single `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` line by `plugin_dockerfile` hooks |
| `# >>> mise runtimes >>>` … `# <<< mise runtimes <<<` | `USER vscode`; `ENV PATH=/home/vscode/.local/share/mise/shims:$PATH`, `MISE_TRUSTED_CONFIG_PATHS=/workspace`; `.bashrc` gains `eval "$(mise activate bash)"`; `COPY mise.toml`; `RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN,required=false mise install` |

No `latest` token and no `ln -sf /bin/bash /bin/sh`. The image's default user
is `vscode`.

**`post.sh` blocks and order** (placed by `post_sh_add_block`):

| Order | Marker | Owner | Sources / calls |
| --- | --- | --- | --- |
| 1 | `# mise Runtime Setup` | core | `setup_mise.sh` / `setup_mise` |
| 2 | `# Claude Code Setup` | core | `setup_claude.sh` / `setup_claude` |
| — | language / service blocks | languages, services | unchanged mechanisms; godot's `# Godot Engine Setup` (#331) is placed by `post_sh_add_block` and is informational only (versions, export-template hint, GUI/headless mode) |
| 3 | `# Codex CLI Setup` | codex | `setup_codex.sh` / `setup_codex` |
| 4 | `# Claude Code Plugin Setup` | claude | `setup_plugins.sh` / `setup_plugins` |

**Post-create helpers** (all `.devcontainer/scripts/*.sh`, manifest-eligible,
workspace ≡ template via `verify-mirrors.sh`):

| Helper | Entry | Contract |
| --- | --- | --- |
| `setup_mise.sh` (core) | `setup_mise()` | `mise` missing → `[WARN]`; no `mise.toml`/`.mise.toml`/`.tool-versions` → skip; `mise install` in the project root (derived from the script path); failure → `[WARN]` + manual command. Returns 0. |
| `npm_global_cli.sh` (core) | library: `install_npm_global_cli <display_name> <package_spec> <command>` | Skip when `<command> --version` succeeds (a stale shim fails this probe and triggers reinstall); `npm` missing → `[WARN]`; global prefix not writable → `[WARN]`, never sudo; `npm install -g` failure or still-unrunnable command (after `mise reshim`) → `[WARN]` + manual command. Returns 0. |
| `setup_claude.sh` (core) | `setup_claude()` | `install_npm_global_cli "Claude Code" "${CLAUDE_CODE_NPM_PACKAGE:-@anthropic-ai/claude-code}" claude`; `mkdir -p ~/.claude`; missing library → `[WARN]`. Returns 0. |
| `setup_codex.sh` (codex) | `setup_codex()` | `install_npm_global_cli "Codex CLI" "${CODEX_NPM_PACKAGE:-@openai/codex}" codex`; sign-in hint; missing library → `[WARN]`. Returns 0. |
| `setup_plugins.sh` (claude) | `setup_plugins()` | See below. Returns 0. |

npm globals live in mise's per-version Node prefix (user-owned, so no sudo);
mise's npm wrapper reshims after installs, so `claude`/`codex` resolve through
the shim directory in non-login shells and through activation in interactive
ones. A Node version change drops them until the next `post.sh` run, which is
why the CLI blocks follow the mise block.

On projects scaffolded before #325, `--upgrade` delivers these helpers but not
their `post.sh` wiring (post.sh is developer-owned); every helper skips or
warns cleanly when `mise`, `npm` or `enabledPlugins` is absent and never
replaces a feature-installed CLI that already runs.

### `scripts/lib/common.sh::mise_toml_ensure()` (#325)

Signature: `mise_toml_ensure <mise_toml> <section> <key> <toml_value>`.
`section` ∈ {`tools`, `env`, `settings`, `tool_alias` (#331)}; `key` matches
`^[A-Za-z0-9_][A-Za-z0-9_.-]*$`; `toml_value` is a single-line TOML literal
written verbatim. Creates the file (with a header comment) or the section when
missing; inserts after the section's last non-blank line; **skips** when the
key is already present as a bare or quoted key in the section, as a
`[section.key]` table, or as a top-level `section.key`. Atomic temp + `mv`.
Returns 1 only for invalid arguments or write failure; plugin callers
downgrade that to `print_warning`. Called only from
`plugin_post_copy_shared` (root scope), never from `plugin_post_copy_module`.

### `scripts/lib/common.sh::mise_toml_has_key()` (#331)

Signature: `mise_toml_has_key <mise_toml> <section> <key>`. Read-only
companion to `mise_toml_ensure`, sharing its presence predicate (bare or
quoted key under `[section]`, a `[section.key]` header, or a top-level
`section.key =`; commented lines and other sections do not count). Exit `0`
when present, `1` when absent or the file is missing (the file is never
created), `2` plus `print_error` for an invalid section or key. Silent on
0 and 1. Purpose: write a `[tool_alias] <k>` entry only when `[tools] <k>`
is absent, so an alias never retargets a developer's existing tool entry.
Caller: `templates/languages/godot/plugin.sh` (`godot`, `gdtoolkit`).

### `scripts/lib/common.sh::dockerfile_add_os_packages()` (#325)

Signature: `dockerfile_add_os_packages <dockerfile> <block_id> <package>...`.
Inserts, before the first `^SHELL ` line, a block delimited by
`# >>> <block_id> os-packages >>>` / `# <<< <block_id> os-packages <<<`
containing one `RUN apt-get update && apt-get install -y --no-install-recommends ... && rm -rf /var/lib/apt/lists/*`.
Exact-line marker guard in every mode. Missing Dockerfile or missing anchor →
`print_warning` (listing the packages), file unchanged, return 0. Callers:
`templates/services/postgresql/plugin.sh::plugin_dockerfile`
(`postgresql-client`), `templates/services/mysql/plugin.sh::plugin_dockerfile`
(`default-mysql-client`), `templates/languages/godot/plugin.sh::plugin_dockerfile`
(block id `godot`, #331: 28 trixie packages for X11/Wayland, Mesa incl. the
WSLg `d3d12` GL driver, Vulkan loader + lavapipe, ALSA/PulseAudio,
fontconfig, udev, dbus, `libicu76` + `libssl3t64` for the .NET SDK,
`netcat-openbsd`, `unzip`; installed unconditionally, whatever the GUI
choice). latex keeps its own #263 awk insertion at the same anchor.

### `scripts/lib/common.sh::post_sh_add_block()` (#325)

Signature: `post_sh_add_block <post_sh> <marker_line> [<before_marker_line>...]`,
body lines on stdin. Writes a blank line, a `# ----` rule, `<marker_line>`, a
rule, then the body. Skips when `<marker_line>` exists as an exact line or the
file is missing. When any `<before_marker_line>` exists, inserts before the
earliest one (moving up over its rule line and one blank line); otherwise
appends. Atomic temp + `mv`. Callers and before-lists: core
(`# mise Runtime Setup` before Claude/Codex/plugin markers;
`# Claude Code Setup` before Codex/plugin markers), codex
(`# Codex CLI Setup` before `# Claude Code Plugin Setup`), claude
(`# Claude Code Plugin Setup`, append), godot (`# Godot Engine Setup` before
`# Codex CLI Setup` / `# Claude Code Plugin Setup`, #331; the first language
block to use the helper, in every mode). The order is therefore independent
of plugin load order.

### `/workspace/.claude/settings.json` (workspace, #261, #299)

`permissions.allow` includes `"Bash(codex:*)"` so the `/review` skill can invoke `codex exec` and `codex review` without per-call approval (#261). Other downstream projects opt in via `templates/codex/.claude/settings.json`.

Since #299 the `permissions.deny` list uses canonical `Bash(prefix:*)` rules aligned with `deny-check.sh`'s regex list, the PreToolUse deny-check hook is addressed via `"$CLAUDE_PROJECT_DIR"/.claude/scripts/deny-check.sh`, and PostToolUse format hooks use `matcher: "Write|Edit"` with per-handler `if: "Write(*.ext)"` rules, reading the file path from the hook's stdin JSON (`.tool_input.file_path`). The workspace carries only the Rust hooks (dogfooding); language templates ship the same shape per language.

Since #325 both the workspace file and `templates/claude/.claude/settings.json` carry `extraKnownMarketplaces` (`claude-plugins-official` → `anthropics/claude-plugins-official`) and `enabledPlugins` (`context7@claude-plugins-official: true`); schema in data-model.md. `merge_claude_settings` (`$base * $overlay` followed by permission/hook unions) and `merge_claude_settings_hooks` (`$base * {hooks}`) preserve both keys without a code change, and the root AI refresh replaces the file with the distributed copy on every container start.

### `templates/github-actions/project-integration/plugin.sh` — gh helper contract (#276)

The project-integration plugin auto-detects GitHub Projects via the `gh` CLI during `plugin_interactive_setup`. All gh invocations go through a private `_gh_run` wrapper so that:

- gh's first-line stderr is captured to a process-wide tempfile `GH_LAST_ERROR_FILE` (path established once at plugin source time via `mktemp`; empty content on success). A tempfile is required because helpers are invoked inside `$(...)` command substitution and a plain variable would not survive the subshell.
- Each helper always returns `0` — failure is signaled by empty stdout, not exit status. This restores the non-fatal-warning invariant documented under `architecture.md :: "Cross-cutting Concerns / Plugin failures"`, broken pre-#276 by `var=$(gh ... 2>/dev/null)` aborting under `set -e`.
- Callers emit a `print_warning` that includes the captured cause via `_print_gh_warning`.
- No `EXIT` trap is installed on `GH_LAST_ERROR_FILE`: this plugin is sourced from inside `setup.sh`'s plugin dispatch, and `setup.sh --upgrade` registers `cleanup_upstream_dir EXIT` earlier; replacing that trap would leak the upstream clone.

| Function | Signature | Stdout on success | Stdout on failure | `GH_LAST_ERROR_FILE` |
| --- | --- | --- | --- | --- |
| `_gh_run` | `<cmd> [args...]` | gh's stdout | gh's stdout (often empty) | first line of gh's stderr (empty on success) |
| `check_gh_available` | `()` | (empty) | (empty) | unchanged |
| `get_current_repo` | `()` | `owner/repo` | (empty) | first-line gh stderr |
| `get_current_user` | `()` | `<login>` | (empty) | first-line gh stderr |
| `get_owner_projects` | `(owner)` | `<JSON>` | (empty) | first-line gh stderr |
| `get_project_fields` | `(owner, number)` | `<JSON>` | (empty) | first-line gh stderr |
| `get_project_fields_detailed` | `(owner, number)` | `<JSON>` (GraphQL or basic fallback) | (empty) | first-line gh stderr (last gh attempt) |
| `_print_gh_warning` | `(prefix)` | (none) | (none) | reads `GH_LAST_ERROR_FILE`; emits `print_warning` |

Control-flow guarantee: `plugin_interactive_setup` always reaches an interactive prompt (auto-selected project list or `prompt_manual_project_config` + `prompt_manual_field_defaults`). Silent default-fallback is forbidden. The decision tree is documented in `docs/design/#276/flowchart.md`.

### `templates/core/.devcontainer/scripts/refresh-assets.sh` and workspace counterpart

Standalone per-file updater invoked at first boot, every container start, or by current setup. Interface:

```text
refresh-assets.sh [--config PATH] [--project-root PATH] [--source-dir PATH]
                  [--dry-run] [--force-pull] [--quiet]
```

Explicit source is read-only and bypasses cache fetching; explicit root avoids targeting the setup checkout. Validate arguments, mappings, source/destination/state symlink boundaries and cache origin/cleanliness/project separation. Enumerate upstream/overlay files plus prior provenance; never mirror-delete destination trees. Unknown siblings remain intact. Currently distributed edited/unknown files require verified backups before replacement; deleted distributed targets are restored. Manifest v2 retains missing legacy helper deletion intent in optional `deleted_paths`, separately from trusted `files` hashes, until exact restored distribution bytes are adopted. Safe upstream removals require unchanged last-installed hashes, and overlay-origin content is never pruned. State persistence is atomic and only successful/exactly matched entries advance. Reconcile even at unchanged SHA.

Dry-run prints concrete file decisions with no target/persistent-cache writes; unavailable source is an explicitly incomplete preview. Warn with recovery hints on runtime failures and return 0; only unknown CLI flags return 1. Summaries distinguish installed, backed-up, unchanged, preserved/unsafe, removals and failures, and report backup locations.

### `templates/agent-workflows/.tarnished/refresh.json`

Project-owned schema 1, with optional `use_default_managed_paths`. See data-model.md for the full ownership/state contract. Defaults cover Claude assets/settings, applicable Codex skills/settings, shared lifecycle contract files and the erd projection, with nonoverlapping destination mappings and matching `.local` sidecars. The template/workspace copies and manifest exclusion lists remain synchronized. Runtime never rewrites project config/profile. Setup migrates only missing or exactly recognized legacy default catalogs; custom/empty mappings remain explicit project choices.

### `templates/core/plugin.sh::plugin_post_copy` — refresh-assets wiring (#279)

`templates/core/plugin.sh::plugin_post_copy` gains a marker-guarded `cat >> post.sh` block (mirroring the Codex pattern at `templates/codex/plugin.sh:113-128` and the Claude pattern at `templates/claude/plugin.sh:113-129`):

| Marker (line-anchored) | Block contents |
| --- | --- |
| `# Tarnished Asset Refresh` | `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` + `if [[ -x "${SCRIPT_DIR}/refresh-assets.sh" ]]; then "${SCRIPT_DIR}/refresh-assets.sh" || true; fi` |

The trailing `|| true` is defense in depth — `refresh-assets.sh` already always returns 0, but the guard is consistent with how `setup_plugins` and `setup_codex` are invoked (`source` inside an `if [[ -f ... ]]` shell, with each inner function `return 0`-ing).

Rationale for placing in `core` (not `claude`): `refresh-assets.sh` is universal infrastructure. A non-Claude scaffold receives the script + an empty (or absent) `refresh.json` `managed_paths[]` and the script becomes a no-op. The initial whitelist happens to be Claude-only, but the mechanism is flavor-agnostic.

### `templates/claude/plugin.sh::plugin_copy` — `.claude/rules/` distribution (#279)

`plugin_copy` gains one additional `copy_dir_with_confirm` call after the existing `commands/`, `skills/`, `scripts/` copies:

```bash
if [[ -d "${PLUGIN_DIR}/.claude/rules" ]]; then
    copy_dir_with_confirm "${PLUGIN_DIR}/.claude/rules" "${target_dir}/.claude/rules"
fi
```

The `templates/claude/.claude/rules/` directory is new (was missing pre-#279). Initial contents: `shell.md` (moved from `/workspace/.claude/rules/`). Language-specific rules (`rust.md`, `go.md`, `python.md`, `typescript.md`, `deno.md`) continue to ship via their respective language plugins (`templates/languages/<lang>/.claude/rules/<lang>.md`) — the always-latest pipeline only governs language-agnostic rules so language plugins stay self-contained.

`plugin_post_copy` is unchanged; the `post.sh` wiring lives in `templates/core/plugin.sh::plugin_post_copy` (see above).

### `setup_plugins.sh` (workspace + `templates/claude/.devcontainer/scripts/`, #249, #255, #273, #325)

Fallback installer for the declarative plugin set in `.claude/settings.json`
(`extraKnownMarketplaces` + `enabledPlugins`, #325). Claude Code applies the
settings but does not download external plugins on a new machine, so this
script installs what is enabled and missing. The workspace and template copies
are byte-identical (`verify-mirrors.sh`).

| Function | Purpose |
| --- | --- |
| `is_claude_authenticated()` | (#273) Returns `0` iff `$HOME/.claude/.credentials.json` is non-empty. No subprocess. |
| `setup_plugins()` | (1) `claude` and `jq` present; (2) settings file (default `<project>/.claude/settings.json`, overridable by `SETUP_PLUGINS_SETTINGS_FILE` for tests) exists and parses; (3) at least one `enabledPlugins` entry is `true`; (4) `is_claude_authenticated`; then (5) read installed ids from `claude plugin list --json` (failure → treat as none); (6) for each enabled, well-formed, missing `<name>@<marketplace>`: register the marketplace once from `extraKnownMarketplaces[<marketplace>].source` (`github` → `repo`, `git` → `url`; undeclared `claude-plugins-official` → `anthropics/claude-plugins-official`; otherwise warn and skip) and run `claude plugin install <id> --scope project`. |

Contract: under `set -e` (in `post.sh`) the function returns `0` in every
case. Steps 1–4 each end the run with a one-line warning or guidance; step 6
failures are isolated per id. `-y` / `--accept-command` are never passed, so a
plugin whose marketplace declares an install command is refused in a non-TTY
run and reported. The hard-coded context7/serena/playwright list and the
playwright prompt were removed in #325; `context7` is the only shipped
default.

### Language plugin contract (`templates/languages/<lang>/plugin.sh`, #263)

Language plugins (currently `python`, `rust`, `node`, `deno`, `latex`, `go`, `godot` — #274 added `go`, #331 added `godot`) expose a split `plugin_post_copy`:

```bash
# REQUIRED today, kept verbatim:
plugin_name()                       # echo "<id>"
plugin_description()                # echo "<desc>"
plugin_copy(target_dir)             # root-scoped (e.g. .github/workflows/<lang>-quality-check.yml;
                                    #   godot also copies docker-compose.godot-gui.yml)
plugin_dockerfile(target_dir)       # OPTIONAL, OS packages only (#325): latex (TeX Live) and
                                    #   godot (GUI/.NET libraries, #331)
plugin_interactive_setup()          # OPTIONAL, called only on a TTY: godot prompts for the GUI
                                    #   opt-in; non-prompting resolution also runs from
                                    #   plugin_post_copy_shared (#331)

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
| `plugin_post_copy_shared` | `target_dir` (= project root) | `target_dir/.devcontainer/` (feature-free `customizations` overlay; godot also appends to `dockerComposeFile` on GUI opt-in, #331), `target_dir/.claude/`, `target_dir/.zed/` via `apply_zed_assets` (#323), `target_dir/mise.toml` via `mise_toml_ensure` / `mise_toml_has_key` (#325, #331), marker-guarded blocks in `target_dir/.devcontainer/scripts/post.sh` and in the root `.gitignore` (godot, latex) | Module sub-directories |
| `plugin_post_copy_module` | `target_dir` (= `<root>/<module>` in monorepo mode, `<root>` in single mode), `module_name` | Files inside `target_dir`: `pyproject.toml`/`Cargo.toml`/`package.json`, lint config (`ruff.toml`, `biome.json`, etc.), `src/<module_name>/`, `tests/`, language-specific `.gitignore`, `CLAUDE.md` for the module | `target_dir/.devcontainer/`, `target_dir/.claude/`, `target_dir/.zed/`, `target_dir/docker/`, `target_dir/mise.toml`, root `docker-compose.yml` |

Both functions MUST be **idempotent** — re-running `setup.sh --add-module` for an already-registered language is a no-op for shared assets and obeys `--overwrite` for module assets. Marker-guarded blocks in `post.sh` (and latex's `Dockerfile.dev` block) provide block-level idempotency analogous to the gitignore policy (#259); `mise_toml_ensure` provides key-level idempotency for `mise.toml` (#325).

Runtime entries per language (#325): python → `python = "3.12"`, `uv`, and the `[env]` block (`UV_PYTHON` from `{{ tools.python.path }}`, `PYTHONDONTWRITEBYTECODE`, `PYTHONUNBUFFERED`, `UV_COMPILE_BYTECODE`, `UV_LINK_MODE`); node → `node = "22"`, `pnpm` (Corepack no longer used); rust → `rust = { version = "stable", components = ["rustfmt", "clippy"] }`; go → `go`; deno → `deno`; latex → none; godot (#331) → `[tool_alias] godot = "github:godotengine/godot"` + `tools.godot` (.NET `_mono_` asset via `asset_pattern`, `rename_exe` to `godot`), `dotnet` (.NET 10 LTS SDK), `uv` (python's pin), `[tool_alias] gdtoolkit = "pypi:gdtoolkit"` + `tools.gdtoolkit = { version, python = "3.12" }`, `[env] DOTNET_CLI_TELEMETRY_OPTOUT` / `DOTNET_NOLOGO` = `"1"`; each alias is written only when its tool key was absent (`mise_toml_has_key`). Exact uv/pnpm/go/deno/godot/dotnet/gdtoolkit pins are the current releases at implementation time. The rust and go `post.sh` blocks run `mise reshim` after `cargo install` / `go install`.

godot-specific module files (#331): `gdlintrc` and `.editorconfig` are copied by `plugin_post_copy_module`. The CI workflow `godot-quality-check.yml` has three jobs, each of which prints `::notice::` and succeeds when its input is absent: `lint` (gdlint + `gdformat --check`), `test` (`dotnet build` per `.csproj`, then headless GUT when `addons/gut` exists) and `export` (headless `--export-release` per preset with an `export_path` when `export_presets.cfg` exists; export templates cached and SHA-512-checked). It discovers every `project.godot` and installs tools from `mise.toml` with `jdx/mise-action@v4`. The plugin generates no `project.godot`, `export_presets.cfg` or `addons/`.

### Non-language plugin contract (`templates/{core,claude,codex,services/<svc>,github-actions/<wf>}/plugin.sh`)

Unchanged in shape. These plugins implement `plugin_post_copy(target_dir)` and operate on `target_dir = project root` in both single and monorepo modes. Since #325: `core` copies `mise.toml` and the `setup_mise.sh` / `setup_claude.sh` / `npm_global_cli.sh` helpers and places the `# mise Runtime Setup` and `# Claude Code Setup` blocks; `codex` has no devcontainer overlay and places `# Codex CLI Setup` before `# Claude Code Plugin Setup`; `postgresql` and `mysql` add a `plugin_dockerfile(target_dir)` that calls `dockerfile_add_os_packages`. Since #323, `core` and the three service plugins also call `apply_zed_assets "$target_dir" "$PLUGIN_DIR"` once — a no-op unless `--zed` was selected and the flavor ships a `.zed/` directory. Service plugins remain mode-agnostic because their existing `{{PROJECT_NAME}}-<svc>` naming convention naturally produces monorepo-correct service names (e.g., `myapp-db` in single mode, `elsur-db` in monorepo mode for project `elsur`).

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
| Plugin install failure | shell warning, continue | `setup_plugins.sh` per enabled id; non-fatal |
| Marketplace registration failure / undeclared non-official marketplace | shell warning, skip that marketplace's ids | `setup_plugins.sh` (#325) |
| Claude not yet authenticated (`~/.claude/.credentials.json` missing or empty) | shell info + guidance, `return 0` | `setup_plugins.sh` `is_claude_authenticated` gate (#273); `post.sh` continues |
| `claude` / `jq` / settings file / enabled `enabledPlugins` missing, or settings JSON invalid | shell warning, `return 0` | `setup_plugins.sh` (#325, FR-8) |
| `claude plugin list --json` failure | note, continue with an empty installed set | `setup_plugins.sh` (#325); install is idempotent, so retrying is safe |
| `mise` missing or `mise install` failure on post-create | `[WARN]` + recovery command, `return 0` | `setup_mise` (#325) |
| `npm` missing, non-writable global prefix, or `npm install -g` failure | `[WARN]` + recovery command, `return 0`; sudo never used | `install_npm_global_cli` via `setup_claude` / `setup_codex` (#325) |
| `npm_global_cli.sh` missing | `[WARN]` + "run `setup.sh --upgrade`", `return 0` | `setup_claude` / `setup_codex` (#325) |
| `mise_toml_ensure` invalid arguments or write failure | `print_error`, return 1 → caller `print_warning` | Scaffold continues; original `mise.toml` untouched (#325) |
| Plugin OS block without a `SHELL` anchor | `print_warning`, return 0 | `dockerfile_add_os_packages` (#325); packages listed for manual addition |
| Target `Dockerfile.dev` predates the mise runtime layer | `print_warning` once | `execute_plugin_dockerfiles` (#325); points at docs/maintenance.md |
| mise download signature/checksum mismatch, gh keyring fingerprint mismatch, unsupported CPU architecture | image build fails | Core `Dockerfile.dev` (#325, NFR-4/NFR-5) |
| `update_gitignore` write failure | shell error (propagates under `set -euo pipefail`) | `${target_dir}/.gitignore` not writable |
| Devcontainer JSON comment normalization failure | shell error, non-zero helper return | `merge_devcontainer_json` receives malformed comments or JSON invalid after comment stripping |
| Zed devcontainer overlay merge failure | shell warning, `apply_zed_assets` returns 0 (#323) | A flavor's `.zed/devcontainer.json` is unparseable; temp removed, the live `.devcontainer/devcontainer.json` is left unchanged |
| Zed project settings merge failure | shell warning, `apply_zed_assets` returns 0 (#323) | The developer's `.zed/settings.json` is invalid even after comment stripping, or jq failed; temp removed, the live file is left unchanged |
| Godot GUI activation impossible (missing or unparseable `devcontainer.json`, overlay file missing, write failure) | shell warning + manual one-line edit hint, return 0 (#331) | File left untouched; container stays headless |
| `mise_toml_has_key` invalid section or key | `print_error`, exit 2 → caller `print_warning` (#331) | The alias/tool pair is skipped |
| Godot GUI overlay enabled on a host without `/dev/dxg` | Docker refuses to start the container (#331) | Documented recovery: remove `"../docker-compose.godot-gui.yml"` from `dockerComposeFile` and rebuild; the default answer off-WSLg is `n` |
| `--zed` in `--add-module` mode | shell warning, flag reset to `false` (#323) | Mirrors `--codex`: root assets were installed by the original init |
| `--zed` against an existing Tarnished project | shell error, exit 1 (#323) | `scaffold_flags_supplied` counts `--zed` as a scaffold selection, so the existing "use --refresh / --add-module" guidance fires instead of a silent refresh |
| `scaffold_options.zed_enabled` present but not boolean | shell error, exit 1 (#323) | `manifest_options_valid` rejects it → `manifest_read` "Invalid manifest scaffold options" |
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
| `curl: (23) Failure writing output to destination` from remote bootstrap | (eliminated, #276) | Outer curl pipe inherited by `exec bash` in `setup.sh:29-69` bootstrap | Suppressed by `< /dev/null` on the `exec` line; never printed to user terminal |
| `gh` helper auth/API/empty-result failure | shell warning, non-fatal (#276) | `gh` unauthenticated, network error, or empty response inside `templates/github-actions/project-integration/plugin.sh` | `print_warning` includes captured first-line stderr (read from `GH_LAST_ERROR_FILE`); control flow falls through to `prompt_manual_project_config` + `prompt_manual_field_defaults` |

## Versioning Policy

`erd` follows semver. Tag bumps are computed from branch prefix per `versioning.yml`. Default-bump fallback is `rc`. The CLI itself is at `0.1.0` (pre-1.0).

`modules.json` (#263) carries its own `version` field; current value is `1`. Bumps follow a major-only convention (no minor/patch; field additions are non-breaking by tolerant readers).

### Host maintenance boundary (#316)

Setup and refresh require Bash 4.4+; BSD-like utilities are supported via portable root resolution/renames and a `shasum -a 256` fallback. Explicit project/source/staging/cache roots may resolve host ancestor aliases once, but symlink root leaves and all symlinks below each physical root are rejected. State/config paths are checked below that root, never individually canonicalized to bypass protection. Compare physical source/target roots before setup refresh writes. Check expected-current hashes immediately before mutation and verify installed ordinary-file bytes before recording success. Dry-run Git checks suppress optional index/lock writes.

### AI backup replacement interface

`run_refresh(root, source = invoked checkout)` uses the current updater with selected source bytes. Before atomic replacement of differing distributed AI files, verify a private backup at `.tarnished/backups/<run>/<relative-path>`. Report that path and backup/install counts; dry-run reports plans without target mutations. Full `.claude/settings.json` and applicable `.codex/config.toml` are catalog targets; native local settings and profile files stay project-owned. See [#318 design](../%23318/design.md) for failure and root-upgrade composition.
