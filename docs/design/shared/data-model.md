# Data Model

This is the cumulative project-wide data model. Per-issue deltas may add or modify entries; this file is regenerated as a snapshot on every `/design` (NFR-1).

## Entities

| Entity | Defined in | Description |
| --- | --- | --- |
| `Config` | `src/config.rs` | Global CLI config (verbose flag, paths) |
| `ProjectConfig` | `src/project_config.rs` | `.github/project.yml` schema |
| `ProjectReference` | `src/project_config.rs` | `{owner, number}` for a single GitHub Project V2 |
| `LabelProjectConfig` | `src/project_config.rs` | Label-keyed project routing entry (#230) |
| `ScheduleDefaults` | `src/project_config.rs` | `{iteration, start, end}` defaults for schedule fields |
| `PrStatusConfig` | `src/project_config.rs` | `{on_open}` PR status mapping |
| `TagConfig` / `Config` (tag) | `src/tag_config.rs` | `versioning.yml` schema |
| `BranchPrefixes` | `src/tag_config.rs` | Internal canonical struct: `{major, minor, patch}` lists. Built from either Format A (legacy template) or Format B (canonical), via custom serde deserializer (#228) |
| `BumpType` | `src/tag_config.rs` / `src/version.rs` | `Major | Minor | Patch | Rc` |
| `GetIssueResponse` | `src/github/types.rs` | GitHub REST issue payload (incl. `labels`, #230) |
| `IssueLabel` | `src/github/types.rs` | `{name}` from issue labels payload |
| `ProjectV2` | `src/github/types.rs` | GraphQL project node info |
| `ModulesRegistry` (logical) | downstream `<project>/modules.json` (#263) | Monorepo module registry — `{ version, modules: [{ name, path, language, services }] }` |
| `Manifest` (logical) | downstream `<scope>/.tarnished-manifest.json` (#265) | Hash manifest of "verbatim copy" files for one upgrade scope (root or per-module) — `{ manifest_version, tarnished_version, tarnished_commit, created_at, scaffold_options, files: { path: "sha256:<hex>" } }` |
| `LifecycleDecision` (internal) | `scripts/lib/manifest.sh` (#265) | Pure enum used by `manifest_decide` to tag each file's upgrade outcome — `NOOP \| UPDATE \| SKIP_EDITED \| NEW \| SKIP_NEW_CONFLICT \| LEAVE_REMOVED \| PRUNE \| SKIP_USER_DELETED` |
| `RefreshConfig` (logical) | downstream `<project>/.tarnished/refresh.json` (#279) | Always-latest sync whitelist + overlay declaration — `{ schema_version, upstream: { repo_url, branch }, clone_dir, managed_paths: [{ src, dst, overlay }] }` |

## Type Definitions

### `ProjectConfig` (project-wide canonical schema)

```rust
pub struct ProjectConfig {
    pub default_project: ProjectReference,                      // required
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,
    #[serde(default)]
    pub schedule_defaults: Option<ScheduleDefaults>,
    #[serde(default)]
    pub pr_status: Option<PrStatusConfig>,
    #[serde(default)]
    pub label_projects: HashMap<String, LabelProjectConfig>,    // added in #230
}

pub struct LabelProjectConfig {
    pub owner: String,
    pub number: u32,
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,
}
```

Backward compatibility: every additive field is `#[serde(default)]`, so old configs continue to parse.

### `BranchPrefixes` and dual-format deserialization (#228)

```rust
pub struct BranchPrefixes {
    pub major: Vec<String>,
    pub minor: Vec<String>,
    pub patch: Vec<String>,
}
```

Custom `Deserialize` accepts:

- **Format A (legacy template)**: `branches: [{prefix, bump}]` — coalesced into `BranchPrefixes` by grouping `prefix` by `bump`.
- **Format B (canonical)**: `versioning.branch_prefixes: {major: [...], minor: [...], patch: [...]}` — direct.

When neither is present, all branches default to `BumpType::Rc`.

### `IssueLabel` and `GetIssueResponse` (#230)

```rust
pub struct IssueLabel {
    pub name: String,
}

pub struct GetIssueResponse {
    pub node_id: String,
    pub number: u64,
    pub title: String,
    pub body: Option<String>,
    pub html_url: String,
    #[serde(default)]
    pub labels: Vec<IssueLabel>,
}
```

`labels` is `default` so older mocked payloads without labels still deserialize.

### `modules.json` schema (monorepo registry, #263)

JSON file at the root of a monorepo target produced by `setup.sh --monorepo`. Read and mutated by `scripts/lib/common.sh` helpers via `jq`. There is no Rust counterpart — `erd` does not consume this file today.

```json
{
  "version": 1,
  "modules": [
    { "name": "jing", "path": "jing", "language": "python", "services": [] },
    { "name": "kir",  "path": "kir",  "language": "node",   "services": [] }
  ]
}
```

| Field | Type | Required | Constraints / notes |
| --- | --- | --- | --- |
| `version` | integer | yes | Schema version; readers MUST reject unknown majors. Currently `1`. |
| `modules` | array | yes | May be empty after init if user accepted no modules; FR-2 enforces ≥1 in interactive flow. |
| `modules[].name` | string | yes | `^[a-z][a-z0-9_-]*$`, max 50 chars, unique within file. |
| `modules[].path` | string | yes | Relative path from repo root. Currently equals `name`; field is reserved for future flexibility (nested layouts). |
| `modules[].language` | string | yes | One of the `AVAILABLE_LANGUAGES` ids: `rust`, `python`, `node`, `deno`, `latex`, `go` (#274). |
| `modules[].services` | array of string | yes (may be empty) | Informational record of services declared at registration. The actual compose runs project-wide using `{{PROJECT_NAME}}-<svc>` names, shared across modules. |

**Forward compatibility (NFR-2)**: Readers ignore unknown top-level keys and unknown per-module keys. Adding fields like `commands`, `version_file`, `package` (à la elsur) is non-breaking. The `version` field is the breaking-change escape hatch — bumping to `version: 2` allows incompatible changes that older `setup.sh` versions correctly reject with a clear error.

**Idempotency**: `add_module_entry <name> ...` returns exit `2` on duplicate `name`, which the caller (interactive add-module flow) translates into the FR-9 overwrite prompt.

### `.tarnished-manifest.json` schema (downstream upgrade manifest, #265)

JSON file at the root of any scope managed by `setup.sh --create-manifest` / `--upgrade`. In single-mode targets there is one root manifest. In monorepo targets there are two tiers: one root manifest covers shared assets (`.devcontainer/`, `.claude/`, `.codex/`, `docker/`, `.github/`) and one per-module manifest under each `<module>/` covers module-specific assets (`pyproject.toml`/`Cargo.toml`/`package.json`, lint configs, `src/`, `tests/`, etc.). All manifests follow the same schema.

```json
{
  "manifest_version": 1,
  "tarnished_version": "v0.0.76",
  "tarnished_commit": "<40-char-sha-or-empty>",
  "created_at": "2026-04-29T12:34:56Z",
  "scaffold_options": {
    "languages": ["rust"],
    "services": ["postgresql"],
    "github_actions_enabled": true,
    "auto_tag_enabled": false,
    "codex_enabled": true,
    "monorepo": false
  },
  "files": {
    ".devcontainer/devcontainer.json": "sha256:abc...",
    ".claude/commands/erd/build.md": "sha256:def..."
  }
}
```

| Field | Type | Required | Constraints / notes |
| --- | --- | --- | --- |
| `manifest_version` | integer | yes | Currently `1`. Readers MUST reject unknown majors. Stored in `MANIFEST_SUPPORTED_VERSION` constant in `scripts/lib/manifest.sh`. |
| `tarnished_version` | string | yes | git ref of upstream tarnished — tag (`v0.0.76`), branch (`develop`), or `unknown` for legacy bootstrap. |
| `tarnished_commit` | string | yes | 40-char SHA. May be `""` when `git describe` was unavailable at bootstrap. |
| `created_at` | string | yes | ISO-8601 UTC second-precision timestamp. |
| `scaffold_options.languages` | array of string | yes | Language ids selected at scaffold time. Per-module manifests carry a single-element array; root manifests carry the union. |
| `scaffold_options.services` | array of string | yes | Service ids selected at scaffold time. |
| `scaffold_options.github_actions_enabled` | boolean | yes | |
| `scaffold_options.auto_tag_enabled` | boolean | yes | |
| `scaffold_options.codex_enabled` | boolean | yes | |
| `scaffold_options.monorepo` | boolean | yes | true for the root manifest in monorepo targets; false for single-mode targets and per-module manifests. |
| `files` | object | yes | Map of scope-root-relative path → `"sha256:<lowercase-hex>"`. Empty `{}` is valid. |

**Tracked scope (FR-3)**: `files` only contains "verbatim copy" files — those that flow through `copy_with_confirm` during scaffolding. Merge files (`.gitignore`, `devcontainer.json`, `.claude/settings.json`), dynamically generated files (`docker-compose.yml`, `modules.json`), and user-owned files (`CLAUDE.md`, `AGENTS.md`, `README.md`) are deliberately excluded via `MANIFEST_EXCLUDE_GLOBS` in `scripts/lib/manifest.sh`. The same exclusion list governs both `--create-manifest` (which file paths to hash) and `--upgrade` (which destinations recorded by `copy_with_confirm` to persist).

**Forward compatibility**: Readers ignore unknown keys. The `manifest_version` field is the breaking-change escape hatch — bumping to `2` allows incompatible changes that older `setup.sh` versions correctly reject.

**Idempotency**: `--create-manifest` is idempotent — running it twice on the same target produces equivalent manifest content (only `created_at` differs). `--upgrade`'s lifecycle decisions are deterministic: same three-hash inputs always produce the same decision.

## Relationships

```mermaid
erDiagram
    ProjectConfig ||--|| ProjectReference : "default_project"
    ProjectConfig ||--o{ LabelProjectConfig : "label_projects (key=label name)"
    ProjectConfig ||--o| ScheduleDefaults : "schedule_defaults"
    ProjectConfig ||--o| PrStatusConfig : "pr_status"
    GetIssueResponse ||--o{ IssueLabel : "labels"
    LabelProjectConfig {
        string owner
        u32 number
        map field_defaults
    }
    ProjectReference {
        string owner
        u32 number
    }
    ModulesRegistry ||--o{ ModuleEntry : "modules"
    ModulesRegistry {
        int version
    }
    ModuleEntry {
        string name
        string path
        string language
        array services
    }
    Manifest ||--o{ ManifestFileEntry : "files (path -> hash)"
    Manifest ||--|| ScaffoldOptions : "scaffold_options"
    Manifest {
        int manifest_version
        string tarnished_version
        string tarnished_commit
        string created_at
    }
    ScaffoldOptions {
        array languages
        array services
        bool github_actions_enabled
        bool auto_tag_enabled
        bool codex_enabled
        bool monorepo
    }
    ManifestFileEntry {
        string path
        string sha256
    }
```

## Schemas / Migrations

This project is a single-binary CLI with no persistent database. The "schemas" are YAML config files, the JSON modules registry (#263), and a few generated text artifacts. Their evolution:

| File | Migration | Issue |
| --- | --- | --- |
| `versioning.yml` | Dual-format deserializer added; both Format A and Format B accepted, Format B canonical going forward | #228 |
| `.github/project.yml` | `label_projects` map added (optional) | #230 |
| `setup.sh` completion message | Expanded to 5 commands + workflow line | #246 |
| `setup_plugins.sh` (templates/claude/.devcontainer/scripts/) | `setup_mcp.sh` renamed; `claude mcp add` → `claude plugins install`; per-plugin failure isolation; marketplace registration helper added | #249, #255 |
| `setup_plugins.sh` (workspace + template) | `is_claude_authenticated` pre-flight gate added (`[[ -s "$HOME/.claude/.credentials.json" ]]`); skips with guidance when unauthenticated so first-run `post.sh` no longer aborts. Template variant also adopts `ensure_claude_marketplace` + `try_install_plugin` from the workspace variant; the two files are now structurally aligned. | #273 |
| `_shared/{branch,issue}/SKILL.md` | Common branch & issue creation logic extracted | #242 |
| `_shared/design-migration/SKILL.md` | One-shot migration of `docs/design/#{issue}/` → `docs/design/shared/*` | #257 |
| `docs/design/shared/*` | New layer for cumulative project truth | #257 |
| `.claude/commands/erd/*.md` | Internalized SuperClaude front-half skills as `/erd:*` slash commands | #240 |
| `.gitignore` (downstream-project seed) | Per-file blacklist (`.claude/settings.local.json`, `.codex/config.local.toml`) replaced with marker-guarded whitelist blocks for `.claude/*` and `.codex/*`; always-ignore added for `.serena/` and `screenshots/` | #259 |
| `.agents/skills/*` (Codex projects) | Repo-local Codex skills for `issue`, `design`, `implement`, `review`, `pr`, and (from #308) `flow`; copied by `templates/codex/plugin.sh` and allow-listed by the Codex skills gitignore block | Codex workflow parity / #308 |
| `.codex/config.toml` (workspace + template) | Workspace gains the file (new); template bumps `model` from `gpt-5.3-codex` → `gpt-5.4` and adds `model_reasoning_effort = "high"`. Workspace and template kept in sync. | #261 |
| `.codex/config.toml` (workspace + template) | `model` bumped `gpt-5.4` → `gpt-5.5`. Repairs the invalid `"gpt-5.5/"` value accidentally committed to the workspace copy in #288 and restores workspace/template parity. | #292 |
| `.codex/config.toml` (workspace + template) | `model` pinned to `gpt-5.6-sol` and `model_reasoning_effort` raised to `ultra`. `/review` now reads both back and records them in the review artifact header, so a config change is attributable rather than silent. | #308 |
| `.claude/skills/flow/`, `.tarnished/workflows/flow.md`, `.agents/skills/flow/` | New lifecycle orchestration entrypoint across all three altitudes. `workflows/flow.md` is manifest-tracked, not refresh-managed, so projects scaffolded earlier receive the SKILL without the contract — the SKILL tolerates its absence. | #308 |
| `.claude/skills/_shared/delegation/SKILL.md`, `.claude/agents/advisor.md` | Role vocabulary and work-routing table; read-only advisory subagent. Both refresh-managed, so they arrive downstream on the next container start. #312 adds the `challenge` / `conformance` consult classes, unconditional triggers, per-finding fix proposals, and the escalation rule. | #308 / #312 |
| `docs/design/#{issue}/conformance.md` | Durable record of the design-stage conformance verdict, written by `/design` Phase 7.5 and committed with the design artifacts. Carries a machine-greppable `**Verdict**:` line (`conform` / `non-blocking gap` / `blocking mismatch` / `skipped — <reason>`) plus `**Rounds**:`, `**Checked**:`, `**Against**:`, and `## Findings`. Written on every path including the capability skip; read by `/flow`'s Stage 2 evidence derivation. Overwritten by a second `/design` run. | #312 |
| `.gitignore` (workspace) | Codex whitelist block (`# Codex CLI (track shared config only)` + `.codex/*` + `!.codex/config.toml`) and Codex agent skills block (`.agents/*` + `!.agents/skills/` + `!.agents/skills/**`) appended to the workspace's own `.gitignore` so local agent/auth files are never committed | #261 / Codex workflow parity |
| `.claude/settings.json` (workspace) | `permissions.allow` gains `Bash(codex:*)` so `/review` can invoke the Codex CLI without per-call approval | #261 |
| `modules.json` (downstream monorepo target) | New schema introduced for monorepo support; `version: 1` with a `modules: []` array. Forward-compatible via unknown-key tolerance and a `version` escape hatch. | #263 |
| `modules.json :: modules[].language` accepted values | Widened from `{rust, python, node, deno, latex}` to add `go`. Schema `version` unchanged (additive widening is non-breaking per NFR-2: tolerant readers ignore unknown values). | #274 |
| Language plugin contract (`templates/languages/<lang>/plugin.sh`) | `plugin_post_copy` split into `plugin_post_copy_shared(target_dir)` + `plugin_post_copy_module(target_dir, module_name)`. Existing `plugin_post_copy` retained as a backward-compat shim. | #263 |
| `templates/languages/go/` (downstream Go scaffold) | New plugin following the Rust shape: gofmt + golangci-lint + gotestsum, per-module `.golangci.yml`, marker-guarded `post.sh` block keyed on `GO_POSTSH_MARKER`. `go mod init` and `src/` scaffolding intentionally omitted (user retains control). | #274 |
| `Dockerfile.dev` and `.devcontainer/scripts/post.sh` language toolchain blocks | Now wrapped in marker comments (`# >>> <lang> toolchain >>>` … `<<< <lang> toolchain <<<`) and gated by `grep -q` checks for block-level idempotency, so `setup.sh --add-module` re-runs are no-ops for shared assets. | #263 |
| `.tarnished-manifest.json` (downstream target) | New schema introduced for upgrade tracking; `manifest_version: 1`. Lives at the scope root (one root manifest in single-mode, root + per-module in monorepo). Forward-compatible via unknown-key tolerance and a `manifest_version` escape hatch. | #265 |
| `copy_with_confirm` / `copy_dir_with_confirm` (`scripts/lib/common.sh`) | Extended to opportunistically record `(<rel_path>, sha256)` into a global `MANIFEST_TRACKED` map when `MANIFEST_RECORDING=true`. Default off — pre-#265 callers see byte-equivalent behavior (NFR-1). | #265 |
| `templates/core/plugin.sh` and `templates/languages/<lang>/plugin.sh` | Direct `cp` calls migrated to `copy_with_confirm` so manifest recording captures every verbatim file. The plugin contract itself is unchanged. | #265 |
| `.github/workflows/*.yml` JS-action pins (root) | Migrated to Node-24-native majors: `actions/checkout@v5`, `actions/cache@v5`, `actions/github-script@v8`, `actions/upload-artifact@v6`, `softprops/action-gh-release@v3`. Composite actions (`dtolnay/rust-toolchain@stable`, `taiki-e/install-action`) unchanged. Selection rule: earliest major with `action.yml` `runs.using: node24` as default. Driven by GitHub's 2026-06-02 forced cutover and 2026-09-16 removal of Node 20 from runners. Templates under `templates/github-actions/*` and `templates/languages/*/.github/workflows/` are out of scope here and will be migrated in a follow-up issue. | #267 |
| `templates/agent-workflows/.tarnished/refresh.json` (downstream + workspace) | New file introduced for always-latest asset sync; `schema_version: 1`. Distributed verbatim with the rest of `.tarnished/` by `templates/agent-workflows/plugin.sh`. Forward-compatible via unknown-key tolerance and a `schema_version` escape hatch. | #279 |
| `templates/claude/.claude/rules/shell.md` | New file in the Claude template — moved from `/workspace/.claude/rules/shell.md` so the language-agnostic shell rules are distributed to every Claude-enabled scaffold (and refreshed always-latest by `refresh-assets.sh`). The workspace copy is kept in sync as dogfooding (#261-style). | #279 |
| `templates/core/.devcontainer/scripts/refresh-assets.sh` (downstream + workspace) | New script that performs the always-latest sync. Wired into `post.sh` by `templates/core/plugin.sh::plugin_post_copy` (marker-guarded block `# Tarnished Asset Refresh`) and into `templates/core/.devcontainer/devcontainer.json` as `postStartCommand`. Always returns `0` (FR-5). | #279 |
| `MANIFEST_EXCLUDE_GLOBS` (`scripts/lib/common.sh:126`) | Extended with always-latest `.claude/{commands,skills,scripts}` directories, file-managed `.claude/rules/shell.md`, and their `.local` overlay sidecars. Excludes always-latest paths from manifest tracking — keeps `--create-manifest` from hashing them and keeps `--upgrade` from applying lifecycle decisions to them. Pre-#279 manifests that already contain hashes for these paths become inert; the next `--create-manifest` produces a clean manifest. | #279, #281 |
| `MANIFEST_EXCLUDE_GLOBS` (`scripts/lib/common.sh:126`) | Further extended with directory-managed `.github{,/*}` so CI workflow / GitHub-side configuration files (`.github/project.yml`, `.github/versioning.yml`, `.github/workflows/*.yml` including the per-language `*-quality-check.yml`) are user-owned: scaffold still emits them, but `--upgrade` never records, decides, or prunes them. `apply_decisions_for_scope` (`setup.sh`) gains a defensive filter on `OLD_HASHES` that drops excluded paths before the lifecycle loop, so pre-#286 manifests still listing `.github/*` are migrated silently on the first post-#286 `--upgrade` (the new manifest written at end-of-scope no longer lists them). | #286 |
| `.claude/settings.json` + `.claude/scripts/deny-check.sh` (workspace + `templates/claude` + `templates/languages/*`) | Hook/permission repair: `deny-check.sh` reads the Bash command from the hook's stdin JSON (`.tool_input.command`) instead of the nonexistent `CLAUDE_BASH_COMMAND` env var; language-template PostToolUse hooks move file patterns from `matcher` (tool-name-only per Claude Code docs) to per-handler `if` rules and read the file path from stdin JSON (quoted) instead of the nonexistent `$CLAUDE_FILE_PATH`; deny rules normalized to canonical `Bash(prefix:*)` form and aligned with the script's regex list (`git config` deny narrowed to `--global`, `apt-get` / `sudo rm -rf` added); PreToolUse hook path is `$CLAUDE_PROJECT_DIR`-relative; node hook invokes `pnpm exec biome`. Prior to this fix none of the PostToolUse hooks or deny-check patterns had ever fired. | #299 |
| `templates/languages/latex/.claude/rules/latex.md` (downstream LaTeX scaffold) | New rules file — LaTeX gains `rules/latex.md` for parity with the other five languages; `latex/plugin.sh::plugin_post_copy_shared` copies the rules dir like the rust/node plugins. Also: `setup.sh::load_selected_plugins` warns when `node` and `deno` are both selected (their `*.ts`/`*.tsx` format hooks compete), and all `templates/**/plugin.sh` file modes normalized to 644 (they are sourced, never executed). | #301 |

No SQL, no database migrations — config files, the JSON modules registry, and the seeded `.gitignore` are the only schemas.

### `.tarnished/refresh.json` schema (always-latest asset sync, #279)

JSON file at `<project>/.tarnished/refresh.json`. Read by
`templates/core/.devcontainer/scripts/refresh-assets.sh` on every
container start (`postStartCommand`) and on first boot (via `post.sh`).
Distributed verbatim by `templates/agent-workflows/plugin.sh` along
with the rest of the `.tarnished/` directory.

```json
{
  "schema_version": 1,
  "upstream": {
    "repo_url": "https://github.com/TE-ToshiakiTanaka2/tarnished.git",
    "branch": "develop"
  },
  "clone_dir": "/opt/tarnished",
  "managed_paths": [
    { "src": "templates/claude/.claude/commands",       "dst": ".claude/commands",       "overlay": ".claude/commands.local" },
    { "src": "templates/claude/.claude/skills",         "dst": ".claude/skills",         "overlay": ".claude/skills.local" },
    { "src": "templates/claude/.claude/scripts",        "dst": ".claude/scripts",        "overlay": ".claude/scripts.local" },
    { "src": "templates/claude/.claude/rules/shell.md", "dst": ".claude/rules/shell.md", "overlay": ".claude/rules.local/shell.md" }
  ]
}
```

| Field | Type | Required | Constraints / notes |
| --- | --- | --- | --- |
| `schema_version` | integer | yes | Currently `1`. Readers MUST reject unknown majors with `print_warning` + exit 0 (never block container start). |
| `upstream.repo_url` | string | yes | git URL of upstream tarnished. Default: `https://github.com/TE-ToshiakiTanaka2/tarnished.git` (matches `setup.sh:25`'s `REMOTE_REPO_URL`). Env-overridable via `DEVCONTAINER_REPO_URL`. |
| `upstream.branch` | string | yes | Branch ref. Default: `develop` (matches `setup.sh:26`'s `REMOTE_BRANCH`). Env-overridable via `DEVCONTAINER_BRANCH`. |
| `clone_dir` | string | yes | Absolute path of the long-lived upstream cache. Default: `/opt/tarnished`. Falls back to `${HOME}/.cache/tarnished` when the parent is not writable; the script announces the fallback via `print_warning`. |
| `managed_paths` | array | yes | List of `{src, dst, overlay}` triples. May be empty (script becomes a no-op). |
| `managed_paths[].src` | string | yes | Path within the upstream clone, relative to `clone_dir`. |
| `managed_paths[].dst` | string | yes | Path within the project, relative to project root. |
| `managed_paths[].overlay` | string \| null | yes | Path within the project for the user-owned sidecar. `null` (or omitted) disables overlay for that path. |

**Override semantics**: Directory-managed paths run `rsync --delete <clone_dir>/<src>/ <project>/<dst>/` so the project mirror exactly tracks upstream. File-managed paths replace only that file, preserving siblings such as language-specific `.claude/rules/*.md` files. Pass 2 overlays `<project>/<overlay>` on top (without `--delete` for directories), so files in `<overlay>/` win. To override `commands/erd/brainstorm.md`, write `.claude/commands.local/erd/brainstorm.md`; to override `rules/shell.md`, write `.claude/rules.local/shell.md`.

**Mutual exclusivity with `.tarnished-manifest.json` tracking**: Every `managed_paths[].dst` (and every `managed_paths[].overlay`) MUST also be listed in `MANIFEST_EXCLUDE_GLOBS` (in `scripts/lib/common.sh`). This is enforced by code review and a unit test (`tests/refresh_assets.bats :: "refresh.json defaults subset of MANIFEST_EXCLUDE_GLOBS"`). Always-latest tracking and manifest-tracked upgrades are disjoint per path.

**Forward compatibility**: Unknown top-level keys ignored. Adding fields like `exclude_globs` or `upstream.pinned_commit` is non-breaking. The `schema_version` field is the breaking-change escape hatch.

**Idempotency**: `refresh-assets.sh` is fully idempotent. Running it twice in a row with no upstream change is a no-op (single `git ls-remote` call returns the same SHA, no `rsync` invoked).

### `.codex/config.toml` schema (project-level Codex CLI config, #261)

Flat top-level TOML. All keys optional from Codex's perspective; tarnished sets all four to lock in deterministic behavior across machines.

| Key | Type | Value (workspace + template) | Purpose |
| --- | --- | --- | --- |
| `model` | string | `"gpt-5.6-sol"` | Pinned review model (#308) |
| `model_reasoning_effort` | string | `"ultra"` | Deepest reasoning tier (paid only when `/review` runs) |
| `approval_policy` | string | `"on-request"` | Codex prompts before destructive actions |
| `sandbox_mode` | string | `"workspace-write"` | File writes restricted to workspace |

`model` and `model_reasoning_effort` are read back by `/review` at review time and recorded in the artifact metadata header (#308, task 2-5), so a config change is visible in the artifact instead of silently changing review quality. Unset or unreadable keys are recorded as `default`.

### `.tarnished/agent-profile.json` schema (agent and role binding, #261, extended #308)

Flat JSON object. Written by `templates/agent-workflows/plugin.sh` and rendered by `replace_placeholders`. Not refresh-managed, so a downstream edit survives every container start — the property that lets a project retarget models without forking skill files.

| Key | Type | Required | Description |
| --- | --- | --- | --- |
| `ai_profile` | string | Yes | `claude-main` \| `codex-main` \| `dual`. Read back by `setup.sh::detect_scaffold_options`. |
| `primary_agent` | string | Yes | Human display name, e.g. `"Claude Code"`. Rendered from `{{AI_PRIMARY_AGENT}}`. |
| `review_agent` | string | Yes | Human display name, e.g. `"Codex CLI"`. Rendered from `{{AI_REVIEW_AGENT}}`. |
| `workflow_source` | string | Yes | Path to the agent-neutral workflow contracts, `.tarnished/workflows`. |
| `roles` | object | No | Role→binding map (#308). Absent on projects scaffolded before #308. |

`roles` recognizes four role keys — `orchestrator`, `executor`, `advisor`, `external-reviewer`:

| Field | Type | Description |
| --- | --- | --- |
| `roles.<role>.agent` | string | `"primary"` / `"review"` (indirections to the sibling fields), or a concrete agent identifier |
| `roles.<role>.model` | string \| null | `null` = fall through to the agent definition's `model:` frontmatter, and failing that to `inherit` (the session model). See the precedence chain below. Read only for roles this repository dispatches itself — `advisor` and `executor` |

`roles` values are deliberately **placeholder-free**. `primary_agent` / `review_agent` render to display strings — including `"Claude Code + Codex CLI"` and `"Manual review"` for the `dual` and non-Codex profiles (`setup.sh::derive_agent_names`) — which are not dispatchable identifiers.

**Resolution contract** (identical across every consumer): `roles` absent, or any field still containing an unrendered `{{...}}` token, falls back to binding all roles to the primary agent and `external-reviewer` to `review_agent`. Unknown role keys are ignored rather than treated as errors. Consumers report whether the binding came from the profile or from the fallback.

**Model binding by role** (#312): each role's model comes from exactly one place, chosen by how that role is dispatched. Before #312 every cell resolved to "the session model", because no level of any chain named a model for any role — which made the `advisor`'s second opinion independent in context but not in weights.

| Role | Execution | Channel | Shipped value |
| --- | --- | --- | --- |
| `orchestrator` | Inline — it *is* the session | `.claude/settings.json :: model` | `claude-opus-5[1m]` |
| `executor` | Delegated subagent | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5` |
| `advisor` | Delegated subagent | `.claude/agents/advisor.md` frontmatter | `claude-fable-5` |
| `external-reviewer` | Separate vendor CLI | `.codex/config.toml` | reviewer-owned (`gpt-5.6-sol` / `ultra`) |

For the two delegated roles the precedence is `roles.<role>.model` when non-null → the agent definition's `model:` frontmatter → `inherit`. Claude Code's subagent frontmatter accepts `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or `inherit`, and defaults to `inherit`. Level 1 is not refresh-managed, so a downstream override survives every container start; level 2 lives in refresh-managed `.claude/agents/`, so a shipped default reaches every project on the next start.

The `orchestrator` is outside that chain entirely: it is the session rather than a subagent, so nothing dispatches it and no frontmatter applies. `.claude/settings.json :: model` is its only channel and is read once at session start. That file is neither parity-checked nor manifest-tracked (`MANIFEST_EXCLUDE_GLOBS` treats it as user-owned), so the workspace and template copies may diverge and the template value is a scaffold-time default that `--upgrade` never revisits.

The `external-reviewer` is also outside it: `roles.external-reviewer` no longer carries `model` or `reasoning_effort` (#312), because the reviewer is executed by a different vendor's CLI that already owns a config file and a second declaration site could only drift. `/review` reads `.codex/config.toml` alone and records the resolved values in the artifact header, so a config change stays attributable. Removing the keys is backward compatible in both directions — absent keys already fell back, and unknown keys are already ignored.

Values are pinned IDs rather than aliases, matching the `.codex/config.toml` convention of pinning exactly and bumping in a tracked commit (#292 exists because a model value changed invisibly). `claude-opus-5[1m]` carries the 1M-context suffix, which is valid on both aliases and full model names and a no-op where the model already runs with a 1M window; `claude-sonnet-5` takes no suffix, since Sonnet 5 always runs with the 1M window on the Anthropic API.

**Parity constraint on the workspace copy**: `scripts/verify-mirrors.sh` enforces byte-identity between `.tarnished/agent-profile.json` and `templates/agent-workflows/.tarnished/agent-profile.json`, so the tarnished workspace cannot populate `roles.<role>.model` without failing the parity gate — and its copy still carries unrendered `{{...}}` placeholders, which the resolution contract treats as absent, so the workspace always runs the fallback path. Frontmatter is the only model channel available in-repo. Downstream copies are rendered and manifest-tracked rather than parity-checked, so level 1 works there.

**Forward compatibility**: unknown top-level keys are ignored, so adding roles or per-role fields is non-breaking.

## Generated-Artifact Contracts

The `.gitignore` produced by `update_gitignore()` and Codex's `plugin_post_copy` is structured as a sequence of **marker-guarded blocks**. The marker (a comment line) is the keyed-on identity of the block; rewriting it without coordination would re-trigger the block-append on existing projects (a benign but visible side effect). The exact marker strings and block contents are defined in [api-spec.md](./api-spec.md) :: "Setup / Plugin Surface".

The same marker-guarded-block pattern (#263) governs the language toolchain blocks appended to `Dockerfile.dev` and `post.sh` by language plugins — see api-spec.md :: "Language plugin contract".
