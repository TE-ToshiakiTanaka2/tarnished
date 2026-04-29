# API Specification (Project-wide)

Cumulative public surface of `erd`. Per-issue API deltas live in `docs/design/#{issue}/api-spec.md`.

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

| Workflow | Triggers | Purpose |
| --- | --- | --- |
| `project-integration.yml` | `issues: [opened, reopened, labeled]` (#230) | Run `erd issue link` on issue events |
| `pr-project-status.yml` | `pull_request: [opened, reopened, ready_for_review]` | Map PR open → `pr_status.on_open` |
| `project-label-routing.yml` | (template, optional) | Sub-feature opt-in template for label routing (#244) |

## Setup / Plugin Surface

### `setup.sh`

Top-level installer. After completion prints (#246):

```
Available Claude Code commands:
  /issue     - Create a GitHub Issue
  /design    - Design architecture for a GitHub Issue
  /implement - Implement a GitHub Issue
  /review    - Code review via Codex CLI
  /pr        - Create a Pull Request

Workflow: /issue → /design → /implement → /review → /pr
```

### `scripts/lib/common.sh::update_gitignore()` (#259)

Signature: `update_gitignore <target_dir>`. Seeds `${target_dir}/.gitignore` with three idempotent whitelist/ignore blocks. Each block is appended only if its line-anchored comment marker is absent (`grep -q "^<marker>$"`). User-authored content between or after blocks is preserved (FR-7).

| Block | Marker (line-anchored) | Contents |
| --- | --- | --- |
| Claude whitelist | `# Claude Code (track project configs only)` | `.claude/*` + allowlist: `commands/`, `skills/`, `scripts/`, `agents/`, `rules/`, `hooks/`, `settings.json` |
| Serena | `# Serena MCP working files` | `.serena/` |
| Screenshots | `# Local screenshots (manual UI testing)` | `screenshots/` |

`update_gitignore` calls `touch` on a missing `.gitignore` and emits exactly two messages (`[INFO] Updating .gitignore...`, `[OK] .gitignore updated`).

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

### `templates/claude/.devcontainer/scripts/setup_plugins.sh` (#249, #255)

| Function | Purpose |
| --- | --- |
| `ensure_claude_marketplace()` | Idempotent registration of `anthropics/claude-plugins-official` marketplace |
| `try_install_plugin(name)` | Install one plugin via `claude plugins install <name>@claude-plugins-official -s project`; absorb failures so siblings continue |
| `setup_plugins()` | Calls `ensure_claude_marketplace`, then `try_install_plugin` for `context7`, `serena`, optionally `playwright` |

Contract: under `set -e` (in `post.sh`), this script MUST `return 0` even when individual plugins fail; surface them as warnings.

## Error Responses

| Error | Type | When |
| --- | --- | --- |
| `serde_yaml::Error` | Config parse fail | Malformed `project.yml` or `versioning.yml` |
| `GitHubClientError::RateLimited` | API | GitHub rate limit |
| `GitHubClientError::NotFound` | API | Issue / project not found (default link → fatal; label-routed → warning) |
| `anyhow::Error` (boundary) | Anywhere | Wrapped at command boundary |
| Plugin install failure | shell warning | `setup_plugins.sh` per-plugin; non-fatal |
| Marketplace registration failure | shell warning, `return 0` | `setup_plugins.sh` ensure_claude_marketplace; non-fatal so `post.sh` continues |
| `update_gitignore` write failure | shell error (propagates under `set -euo pipefail`) | `${target_dir}/.gitignore` not writable |

## Versioning Policy

`erd` follows semver. Tag bumps are computed from branch prefix per `versioning.yml`. Default-bump fallback is `rc`. The CLI itself is at `0.1.0` (pre-1.0).
