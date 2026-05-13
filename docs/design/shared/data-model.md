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
| `_shared/{branch,issue}/SKILL.md` | Common branch & issue creation logic extracted | #242 |
| `_shared/design-migration/SKILL.md` | One-shot migration of `docs/design/#{issue}/` → `docs/design/shared/*` | #257 |
| `docs/design/shared/*` | New layer for cumulative project truth | #257 |
| `.claude/commands/erd/*.md` | Internalized SuperClaude front-half skills as `/erd:*` slash commands | #240 |
| `.gitignore` (downstream-project seed) | Per-file blacklist (`.claude/settings.local.json`, `.codex/config.local.toml`) replaced with marker-guarded whitelist blocks for `.claude/*` and `.codex/*`; always-ignore added for `.serena/` and `screenshots/` | #259 |
| `.codex/config.toml` (workspace + template) | Workspace gains the file (new); template bumps `model` from `gpt-5.3-codex` → `gpt-5.4` and adds `model_reasoning_effort = "high"`. Workspace and template kept in sync. | #261 |
| `.gitignore` (workspace) | Codex whitelist block (`# Codex CLI (track shared config only)` + `.codex/*` + `!.codex/config.toml`) appended to the workspace's own `.gitignore` so `.codex/auth.json` etc. are never committed | #261 |
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

No SQL, no database migrations — config files, the JSON modules registry, and the seeded `.gitignore` are the only schemas.

### `.codex/config.toml` schema (project-level Codex CLI config, #261)

Flat top-level TOML. All keys optional from Codex's perspective; tarnished sets all four to lock in deterministic behavior across machines.

| Key | Type | Value (workspace + template) | Purpose |
| --- | --- | --- | --- |
| `model` | string | `"gpt-5.4"` | Always-latest reasoning model |
| `model_reasoning_effort` | string | `"high"` | Higher cost, deeper review (paid only when `/review` runs) |
| `approval_policy` | string | `"on-request"` | Codex prompts before destructive actions |
| `sandbox_mode` | string | `"workspace-write"` | File writes restricted to workspace |

## Generated-Artifact Contracts

The `.gitignore` produced by `update_gitignore()` and Codex's `plugin_post_copy` is structured as a sequence of **marker-guarded blocks**. The marker (a comment line) is the keyed-on identity of the block; rewriting it without coordination would re-trigger the block-append on existing projects (a benign but visible side effect). The exact marker strings and block contents are defined in [api-spec.md](./api-spec.md) :: "Setup / Plugin Surface".

The same marker-guarded-block pattern (#263) governs the language toolchain blocks appended to `Dockerfile.dev` and `post.sh` by language plugins — see api-spec.md :: "Language plugin contract".
