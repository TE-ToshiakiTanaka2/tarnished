# Workflow: Fix project-automation.yml defaults generation

**Issue**: #72
**Type**: bugfix
**Milestone**: github-actions

## Implementation Phases

### Phase 1: Update fetch_project_fields()
**Goal**: Enhance GraphQL query to include iteration configurations

1. Modify GraphQL query to fetch iteration details
2. Update JSON parsing to include iteration list

### Phase 2: Update create_project_config()
**Goal**: Accept and output iteration/start/end fields

1. Add new parameters to function signature
2. Update defaults section generation logic
3. Use field names from API parameters

### Phase 3: Update create_minimal_project_config()
**Goal**: Generate active defaults with dynamic values

1. Change commented defaults to active defaults
2. Include Iteration, Start, End fields

### Phase 4: Update setup_project_automation()
**Goal**: Add Iteration field detection and selection UI

1. Add Iteration field detection
2. Implement selection UI with @current_iteration option
3. Auto-set Start/End when Iteration selected
4. Update create_project_config() call

### Phase 5: Testing
**Goal**: Verify all changes work correctly

1. Run shellcheck
2. Verify YAML generation

## Detailed Tasks

### Task 1: fetch_project_fields() Enhancement

```bash
# Update GraphQL query to include:
... on ProjectV2IterationField {
  name
  dataType
  configuration {
    iterations {
      id
      title
    }
  }
}
```

### Task 2: create_project_config() Update

Parameters to add:
- `iteration_field` - Field name from API
- `iteration_value` - Selected value
- `start_field` - Field name (e.g., "Start")
- `start_value` - @today
- `end_field` - Field name (e.g., "End")
- `end_value` - @iteration_end

### Task 3: create_minimal_project_config() Update

Change output from:
```yaml
# defaults:
#   status: "Backlog"
#   priority: "Medium"
```

To:
```yaml
# Dynamic values: @current_iteration, @today, @iteration_end
defaults:
  Status: "Ready"
  Iteration: "@current_iteration"
  Start: "@today"
  End: "@iteration_end"
```

### Task 4: setup_project_automation() Enhancement

Add after Priority field selection (~line 299):

```bash
# Iteration field
local iteration_field=""
local iteration_value=""
local start_field=""
local start_value=""
local end_field=""
local end_value=""

iteration_field=$(echo "$fields_json" | jq -r '.[] | select(.type == "ITERATION") | .name' 2>/dev/null | head -1)
if [[ -n "$iteration_field" ]]; then
    # Get iteration options
    local iterations
    iterations=$(echo "$fields_json" | jq -r '.[] | select(.type == "ITERATION") | .iterations // [] | .[].title' 2>/dev/null)

    echo ""
    echo "Available ${iteration_field} options:"
    echo "  1) @current_iteration (現在のイテレーション)"
    local i=2
    while IFS= read -r iter; do
        [[ -n "$iter" ]] && echo "  $i) $iter"
        ((i++))
    done <<< "$iterations"

    echo -n "Default ${iteration_field} [1]: "
    IFS='' read -r iter_choice < /dev/tty

    # Process selection
    if [[ -z "$iter_choice" ]] || [[ "$iter_choice" == "1" ]]; then
        iteration_value="@current_iteration"
    else
        # Get specific iteration
        iteration_value=$(echo "$iterations" | sed -n "$((iter_choice-1))p")
    fi

    # Auto-set Start/End
    start_field=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "start") | .name' 2>/dev/null | head -1)
    end_field=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "end") | .name' 2>/dev/null | head -1)

    if [[ -n "$start_field" ]]; then
        start_value="@today"
    fi
    if [[ -n "$end_field" ]]; then
        end_value="@iteration_end"
    fi
fi
```

## Execution Order

1. **fetch_project_fields()** - No dependencies
2. **create_project_config()** - No dependencies
3. **create_minimal_project_config()** - No dependencies
4. **setup_project_automation()** - Depends on 1, 2, 3
5. **Testing** - Depends on all above

## Commit Plan

1. `🐛 fix(plugin): add iteration field support to project-automation setup`
   - All function updates
   - Design and workflow documents
