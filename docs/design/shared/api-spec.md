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

## Versioning Policy

`erd` follows semver. Tag bumps are computed from branch prefix per `versioning.yml`. Default-bump fallback is `rc`. The CLI itself is at `0.1.0` (pre-1.0).
