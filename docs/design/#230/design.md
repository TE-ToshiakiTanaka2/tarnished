# Design: #230 Support Label-Based Project Routing

## Architecture Overview

Extend the existing `erd issue link` command and `project.yml` configuration to support routing issues to additional GitHub Projects based on issue labels. The core principle is **additive**: the default project link is always performed (preserving backward compatibility), and label-matched projects are linked *in addition*.

The changes span three layers:
1. **Configuration** (`project_config.rs`) - New `label_projects` map in the YAML schema
2. **CLI / Business Logic** (`cli/issue.rs`) - Label-aware routing in `execute_link`
3. **Reusable Workflow** (`project-integration.yml`) - Trigger on `labeled` event

## Module Structure

```
src/
├── project_config.rs        # Modified: add LabelProjectConfig, label_projects field
├── cli/
│   └── issue.rs             # Modified: label routing in execute_link + link_issue_to_project
├── github/
│   ├── types.rs             # Modified: add labels to GetIssueResponse
│   └── client.rs            # No changes needed
.github/
├── project.yml              # Modified: add label_projects section (example)
└── workflows/
    └── project-integration.yml  # Modified: add 'labeled' trigger
```

## Interface Design

### Configuration Schema Extension

```yaml
# Existing (unchanged)
default_project:
  owner: "org"
  number: 6

field_defaults:
  Status: "Todo"

# NEW: label-based project routing
label_projects:
  bugfix:                    # matches issue label "bugfix"
    owner: "org"             # required
    number: 7                # required
    field_defaults:          # optional, independent from top-level field_defaults
      Status: "Todo"
  incident:
    owner: "org"
    number: 10
    field_defaults:
      Status: "Triage"
      Priority: "P0"
```

### New Rust Types

```rust
/// Configuration for a label-based project route
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LabelProjectConfig {
    /// Project owner (user or organization)
    pub owner: String,
    /// Project number
    pub number: u32,
    /// Field defaults specific to this label route
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,
}
```

### Extended `ProjectConfig`

```rust
pub struct ProjectConfig {
    pub default_project: ProjectReference,
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,
    #[serde(default)]
    pub schedule_defaults: Option<ScheduleDefaults>,
    #[serde(default)]
    pub pr_status: Option<PrStatusConfig>,
    // NEW
    #[serde(default)]
    pub label_projects: HashMap<String, LabelProjectConfig>,
}
```

### Extended `GetIssueResponse`

The GitHub REST API already returns labels on the issue endpoint. We just need to deserialize them:

```rust
pub struct GetIssueResponse {
    pub node_id: String,
    pub number: u64,
    pub title: String,
    pub body: Option<String>,
    pub html_url: String,
    // NEW
    #[serde(default)]
    pub labels: Vec<IssueLabel>,
}

#[derive(Debug, Deserialize)]
pub struct IssueLabel {
    pub name: String,
}
```

### Public API / Functions

| Name | Signature | Description |
| --- | --- | --- |
| `execute_link` | `(existing + unchanged)` | Extended internally to iterate label_projects |
| `link_issue_to_project` | `(existing + unchanged signature)` | Reused for each project link |
| `LabelProjectConfig` | `struct` | New config type for label routes |
| `IssueLabel` | `struct` | New type for deserialized issue labels |

## Data Flow

1. `erd issue link 42 --config .github/project.yml` is invoked
2. `execute_link` fetches issue #42 via REST API (now includes `labels`)
3. **Default link** (unchanged): loads `default_project` from config, calls `link_issue_to_project`
4. **Label routing** (new): iterates `config.label_projects`, for each entry where the key matches an issue label name:
   - Constructs a temporary `ProjectConfig` with that entry's `owner`, `number`, and `field_defaults`
   - Calls `link_issue_to_project` with the temporary config
5. All links are performed sequentially; failures on label routes are logged but do not abort the command (best-effort)

### Label Matching Rules

- **Exact match**: label name must exactly match the `label_projects` key (case-sensitive)
- **Multiple matches**: if an issue has labels `["bugfix", "incident"]` and both are configured, both projects are linked
- **No match**: if no labels match, only the default project is linked (backward compatible)

## Error Handling

| Scenario | Behavior |
| --- | --- |
| `label_projects` missing from config | No-op (backward compatible via `#[serde(default)]`) |
| Label matches but project link fails | Log warning, continue with remaining labels |
| Default project link fails | Error (existing behavior, unchanged) |
| Issue has no labels | Only default project linked |
| Same project in default and label route | Issue linked twice (GitHub Projects API is idempotent) |

## Implementation Notes

### Key Decisions

1. **Additive, not exclusive**: Label routing adds *additional* project links. It never replaces the default. This matches the issue specification and avoids breaking existing users.
2. **Best-effort for label routes**: If a label-routed project link fails, we log a warning and continue. The default project link failure remains a hard error. This prevents one misconfigured label route from blocking the entire operation.
3. **No CLI flag needed for labels**: The `execute_link` command already fetches the issue (to get `node_id`). Labels come for free from the REST API response. No new CLI flags are required.
4. **`LabelProjectConfig` is flat, not nested**: Each label config has its own `owner`, `number`, and `field_defaults`. This avoids the complexity of inheriting/merging with top-level `field_defaults`, keeping behavior predictable.
5. **Schedule defaults not supported for label routes**: `schedule_defaults` applies only to the default project. This keeps the initial implementation simple; it can be added later if needed.

### Edge Cases

- **Label added after issue creation**: The workflow triggers on `labeled` event, so adding a label later will re-run and link to the matching project. The default project link is idempotent.
- **Label removed**: No automatic unlinking. This is consistent with GitHub Projects behavior (items are not auto-removed).
- **Empty `field_defaults` in label config**: The issue is linked to the project with no field overrides (just the link).

### Performance

- One additional REST API call per label-matched project (to fetch project info + add item)
- Typical case: 0-2 additional projects per issue
- No concern for rate limiting in normal usage
