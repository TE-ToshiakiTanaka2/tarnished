# Workflow: #244 Separate project-label-routing as optional sub-feature

## Implementation Steps

### Step 1: Add global variables to `init_field_config_vars()`

- Add `ENABLE_LABEL_ROUTING="false"`
- Add `declare -gA LABEL_ROUTING_PROJECTS` (label → "owner:number")
- Add `declare -gA LABEL_ROUTING_FIELDS` ("label:field_name" → "value")

### Step 2: Implement `build_label_projects_yaml()`

- Iterate over `LABEL_ROUTING_PROJECTS` entries
- For each label, build YAML with owner, number, and field_defaults from `LABEL_ROUTING_FIELDS`
- Output complete `label_projects:` YAML section to stdout

### Step 3: Implement `prompt_label_routing_project()`

- Accept label name as argument
- Reuse `get_owner_projects()` for project selection (or manual fallback)
- Reuse `get_project_fields_detailed()` + `prompt_single_select_field_value()` for field_defaults
- Store results in `LABEL_ROUTING_PROJECTS` and `LABEL_ROUTING_FIELDS`

### Step 4: Implement `prompt_label_routing_setup()`

- Prompt "Enable label-based project routing? (y/n)"
- If no → return (ENABLE_LABEL_ROUTING stays "false")
- If yes → set ENABLE_LABEL_ROUTING="true"
- Loop: prompt label name → call `prompt_label_routing_project()` → "Add another?"
- Print summary of configured routes

### Step 5: Integrate into `plugin_interactive_setup()`

- Add call to `prompt_label_routing_setup()` at end (before success message)

### Step 6: Modify `plugin_copy()`

- Add condition to skip `project-label-routing.yml` when `ENABLE_LABEL_ROUTING != "true"`

### Step 7: Modify `plugin_post_copy()`

- When `ENABLE_LABEL_ROUTING == "true"`: call `build_label_projects_yaml()` and write active config
- When `ENABLE_LABEL_ROUTING != "true"`: keep current commented-out example

### Step 8: Test and verify

- Verify non-interactive mode defaults (no label routing)
- Verify opt-out flow (label routing declined)
- Verify opt-in flow with gh CLI detection
- Verify opt-in flow with manual fallback
- Verify generated project.yml output

## Task Dependencies

```
Step 1 (variables) ← independent
Step 2 (build_yaml) ← independent
Step 3 (prompt_project) ← depends on Step 1
Step 4 (prompt_setup) ← depends on Step 1, Step 3
Step 5 (integrate_setup) ← depends on Step 4
Step 6 (plugin_copy) ← depends on Step 1
Step 7 (plugin_post_copy) ← depends on Step 1, Step 2
Step 8 (test) ← depends on all
```

## Test Strategy

- **Manual test**: Run `setup.sh` with project-integration plugin and verify interactive flow
- **Non-interactive**: Ensure default behavior (no label routing) is preserved
- **YAML output**: Verify generated `project.yml` has correct `label_projects` format
- **Edge cases**:
  - Single project available → auto-select
  - Multiple projects → selection prompt
  - No gh CLI → manual fallback
  - Empty label input → skip
  - Multiple label mappings → all written correctly
