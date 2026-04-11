# Workflow: #230 Label-Based Project Routing

## Implementation Steps

### Step 1: Add `IssueLabel` type and extend `GetIssueResponse`

**File**: `src/github/types.rs`

- Add `IssueLabel` struct with `name: String` field
- Add `labels: Vec<IssueLabel>` to `GetIssueResponse` with `#[serde(default)]`

**Verification**: Existing tests pass (new field is optional with default)

### Step 2: Add `LabelProjectConfig` and extend `ProjectConfig`

**File**: `src/project_config.rs`

- Add `LabelProjectConfig` struct with `owner`, `number`, `field_defaults` fields
- Add `label_projects: HashMap<String, LabelProjectConfig>` to `ProjectConfig` with `#[serde(default)]`
- Add unit tests:
  - Deserialize config with `label_projects`
  - Deserialize config without `label_projects` (backward compat)
  - Deserialize config with empty `field_defaults` in label config

**Verification**: `cargo test` passes

### Step 3: Refactor `link_issue_to_project` to accept `ProjectConfig`

**File**: `src/cli/issue.rs`

- Change `link_issue_to_project` to accept `&ProjectConfig` as parameter instead of loading config internally
- Update the existing call site in `execute_link` to load config and pass it
- Update the existing call site in `execute_create` similarly
- This refactor enables reuse for label-routed links

**Verification**: `cargo test` + `cargo build` pass, behavior unchanged

### Step 4: Implement label routing in `execute_link`

**File**: `src/cli/issue.rs`

- After the existing default project link, add label routing logic:
  1. Load config once (already done in step 3 refactor)
  2. For each label in `issue.labels`:
     - Check if `config.label_projects` contains the label name
     - If match found, construct a temporary `ProjectConfig` from `LabelProjectConfig`
     - Call `link_issue_to_project` with the temporary config
     - Catch errors and log warnings (non-fatal)
- Add verbose logging for label routing decisions

**Verification**: `cargo build` passes, manual test with mock config

### Step 5: Add unit tests for label routing

**File**: `src/project_config.rs` (config tests) and `src/cli/issue.rs` (if applicable)

- Test `LabelProjectConfig` serialization/deserialization
- Test `ProjectConfig` with various `label_projects` configurations
- Test backward compatibility (no `label_projects` key)
- Test multiple label matches

**Verification**: `cargo test` passes

### Step 6: Update `project-integration.yml` workflow

**File**: `.github/workflows/project-integration.yml`

- Add `labeled` to the `issues.types` trigger array
- No other changes needed (erd handles label routing internally)

**Verification**: YAML is valid, workflow triggers correctly on labeled events

### Step 7: Update example config and documentation

- Update `.github/project.yml` with a commented `label_projects` example (or add to README)
- Ensure `--help` output is accurate (no CLI changes needed)

**Verification**: Config loads without errors

## Task Dependencies

```
Step 1 (types.rs)     ─┐
                        ├──> Step 3 (refactor) ──> Step 4 (label routing) ──> Step 5 (tests)
Step 2 (config)       ─┘
Step 6 (workflow) ────────> independent, can be done in parallel
Step 7 (docs)         ────> after Step 4
```

- Steps 1 and 2 are independent and can be done in parallel
- Step 3 depends on Steps 1 and 2
- Step 4 depends on Step 3
- Step 5 depends on Step 4
- Step 6 is independent of all code changes
- Step 7 depends on Step 4

## Test Strategy

### Unit Tests

| Test | Location | What It Verifies |
| --- | --- | --- |
| Config with label_projects | `project_config.rs` | YAML deserialization of new schema |
| Config without label_projects | `project_config.rs` | Backward compatibility |
| Config with empty label field_defaults | `project_config.rs` | Optional field_defaults |
| Config serialization roundtrip | `project_config.rs` | Serialize + deserialize |
| GetIssueResponse with labels | `types.rs` | Label deserialization from REST API |
| GetIssueResponse without labels | `types.rs` | Backward compat for label field |

### Integration Tests (Manual / CI)

| Test | How | What It Verifies |
| --- | --- | --- |
| Link issue with no labels | `erd issue link <N>` | Only default project linked (unchanged) |
| Link issue with matching label | `erd issue link <N>` with labeled issue | Default + label project both linked |
| Link issue with multiple matching labels | `erd issue link <N>` with multi-label issue | Default + all matching projects linked |
| Link issue with non-matching label | `erd issue link <N>` with unmatched label | Only default project linked |
| Label route project failure | Config with invalid project number | Warning logged, default link succeeds |
| Workflow triggers on label event | Add label to issue in GitHub | Workflow runs and links correctly |

### Edge Cases

- Issue with label matching a route but project doesn't exist
- Same project number in both default and label route (idempotent)
- Very large number of labels (>20) - verify no performance issues
- Label name with special characters (spaces, unicode)
- Config with `label_projects: {}` (empty map)

## Estimated Complexity

- **Config changes**: XS (add struct + field)
- **Type changes**: XS (add label field)
- **Refactor link_issue_to_project**: S (parameter change, update call sites)
- **Label routing logic**: M (new loop with error handling)
- **Tests**: S (config deserialization + label matching)
- **Workflow**: XS (one line change)

**Overall: M (Medium)**
