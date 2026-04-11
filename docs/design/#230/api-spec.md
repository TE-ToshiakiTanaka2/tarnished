# API Specification: #230 Label-Based Project Routing

## Configuration Schema (`project.yml`)

### New Section: `label_projects`

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `label_projects` | `Map<String, LabelProjectConfig>` | No | Maps issue label names to project configurations |

### `LabelProjectConfig` Object

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `owner` | `String` | Yes | GitHub user or organization that owns the project |
| `number` | `u32` | Yes | GitHub Project V2 number |
| `field_defaults` | `Map<String, String>` | No | Field defaults to apply when linking (independent from top-level `field_defaults`) |

### Full Config Example

```yaml
default_project:
  owner: "my-org"
  number: 6

field_defaults:
  Status: "Todo"

schedule_defaults:
  iteration: "current"

pr_status:
  on_open: "In Review"

label_projects:
  bugfix:
    owner: "my-org"
    number: 7
    field_defaults:
      Status: "Todo"
  incident:
    owner: "my-org"
    number: 10
    field_defaults:
      Status: "Triage"
      Priority: "P0"
  feature:
    owner: "my-org"
    number: 11
```

### Backward Compatibility

- `label_projects` is optional (`#[serde(default)]`)
- Existing configs without `label_projects` work unchanged
- No changes to `default_project`, `field_defaults`, `schedule_defaults`, or `pr_status`

## CLI Interface

### `erd issue link` (unchanged interface)

```
erd issue link <NUMBER> [OPTIONS]

Arguments:
  <NUMBER>  Issue number

Options:
  --project-number <N>     Override project number from config
  --project-owner <OWNER>  Override project owner from config
  --size <SIZE>            Override Size field value
  --priority <PRIORITY>    Override Priority field value
  --status <STATUS>        Override Status field value
  --parse-body <BOOL>      Parse Size/Priority from issue body [default: true]
```

No new CLI flags. Label routing is driven entirely by config + issue labels fetched from the API.

**Note**: CLI overrides (`--project-number`, `--project-owner`, `--size`, `--priority`, `--status`) apply only to the **default project** link. Label-routed projects use their own `field_defaults` from config exclusively.

## Rust Types

### New: `LabelProjectConfig` (`src/project_config.rs`)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LabelProjectConfig {
    pub owner: String,
    pub number: u32,
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,
}
```

### Modified: `ProjectConfig` (`src/project_config.rs`)

```rust
pub struct ProjectConfig {
    // ... existing fields unchanged ...
    #[serde(default)]
    pub label_projects: HashMap<String, LabelProjectConfig>,
}
```

### New: `IssueLabel` (`src/github/types.rs`)

```rust
#[derive(Debug, Deserialize)]
pub struct IssueLabel {
    pub name: String,
}
```

### Modified: `GetIssueResponse` (`src/github/types.rs`)

```rust
pub struct GetIssueResponse {
    // ... existing fields unchanged ...
    #[serde(default)]
    pub labels: Vec<IssueLabel>,
}
```

## Internal Function Changes

### `execute_link` (`src/cli/issue.rs`)

**Change**: After the existing default project link, add a loop over `label_projects`:

```
Input: issue (with labels), project_config (with label_projects)
For each label in issue.labels:
    If label.name exists as key in config.label_projects:
        Build temporary ProjectConfig from LabelProjectConfig
        Call link_issue_to_project with temporary config
        Log success or warning on failure
```

### `link_issue_to_project` (`src/cli/issue.rs`)

**Change**: Accept a `ProjectConfig` parameter instead of reading from `config.project_config_path` internally. This allows reuse for both default and label-routed links.

Current signature reads config internally. Refactored to accept config as parameter:

```rust
async fn link_issue_to_project(
    &self,
    client: &GitHubClient,
    config: &Config,           // global CLI config (for verbose flag)
    project_config: &ProjectConfig,  // NEW: passed in instead of loaded internally
    issue_node_id: &str,
) -> anyhow::Result<()>
```

## Workflow Changes

### `project-integration.yml`

**Trigger change**:
```yaml
# Before
on:
  issues:
    types: [opened, reopened]

# After
on:
  issues:
    types: [opened, reopened, labeled]
```

No other workflow changes needed. The `erd issue link` command handles label routing internally.

## Error Handling

| Error | Type | Description |
| --- | --- | --- |
| Invalid `label_projects` YAML | `serde_yaml::Error` (existing) | Config parse fails if label_projects has wrong types |
| Label project not found | Warning (logged, non-fatal) | Project number doesn't exist; skip this label route |
| Label project field_defaults invalid | Warning (logged, non-fatal) | Field name doesn't exist in target project; skip field |
| GitHub API rate limit | `GitHubClientError` (existing) | Propagated as error |
