# Design Document: Fix project-automation.yml defaults generation

**Issue**: #72
**Type**: bugfix
**Milestone**: github-actions

## Overview

Fix the `setup.sh` to properly generate the `defaults` section in `project-automation.yml`, including support for `Iteration`, `Start`, and `End` fields with dynamic values.

## Current State

### Problem
The `templates/github-actions/plugin.sh` only supports `Status` and `Priority` fields in the defaults section. The following fields are not generated:
- `Iteration` - Should support `@current_iteration` and specific iteration names
- `Start` - Should support `@today`
- `End` - Should support `@iteration_end`

### Current Code Structure

```
plugin.sh
├── setup_project_automation()     # Lines 176-310
│   ├── Token input
│   ├── Project type/owner/number input
│   ├── fetch_project_fields()
│   ├── Status field selection      # Lines 279-288
│   ├── Priority field selection    # Lines 290-299
│   └── create_project_config()
├── fetch_project_fields()          # Lines 313-364
├── create_minimal_project_config() # Lines 368-395
├── create_project_config()         # Lines 398-440
├── plugin_interactive_setup()      # Lines 446-463
└── plugin_minimal_setup()          # Lines 469-486
```

## Proposed Solution

### Architecture Changes

```
plugin.sh (modified)
├── setup_project_automation()
│   ├── ... (existing)
│   ├── Status field selection
│   ├── Priority field selection
│   ├── [NEW] Iteration field selection
│   │   ├── Detect ITERATION type field
│   │   ├── Show options (@current_iteration + iterations)
│   │   └── Auto-set Start/End if Iteration selected
│   └── create_project_config() (updated call)
├── fetch_project_fields()
│   └── [MODIFIED] Include iteration configurations
├── create_minimal_project_config()
│   └── [MODIFIED] Include dynamic defaults enabled
└── create_project_config()
    └── [MODIFIED] Accept iteration/start/end parameters
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    setup_project_automation()                    │
├─────────────────────────────────────────────────────────────────┤
│  1. Fetch project fields via GraphQL API                        │
│     └─ fetch_project_fields() returns JSON with field metadata  │
│                                                                  │
│  2. Parse fields and detect types                               │
│     ├─ SINGLE_SELECT → Status, Priority                         │
│     └─ ITERATION → Iteration field (with iterations list)       │
│                                                                  │
│  3. User selection flow                                         │
│     ├─ Status: Show options from API                            │
│     ├─ Priority: Show options from API                          │
│     └─ Iteration: Show @current_iteration + iterations          │
│                                                                  │
│  4. Generate configuration                                      │
│     └─ create_project_config() with all field values            │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Design

### 1. GraphQL API Response Enhancement

The `fetch_project_fields()` function already fetches `ProjectV2IterationField` but the response needs to include iteration configurations:

```graphql
... on ProjectV2IterationField {
  name
  dataType
  configuration {
    iterations {
      id
      title
      startDate
      duration
    }
  }
}
```

### 2. Iteration Field Detection

```bash
# Detect iteration field from JSON response
local iteration_field
iteration_field=$(echo "$fields_json" | jq -r '.[] | select(.type == "ITERATION") | .name' 2>/dev/null)
```

### 3. User Selection UI

```
Available Iteration options:
  1) @current_iteration (現在のイテレーション)
  2) Sprint 1
  3) Sprint 2
  4) Sprint 3
Default Iteration [1]:
```

Selection logic:
- Option 1 → `@current_iteration`
- Option 2+ → Specific iteration title
- Empty (Enter) → Default to option 1

### 4. Automatic Start/End Setting

When Iteration is selected:
- `Start` field → `@today`
- `End` field → `@iteration_end`

### 5. create_project_config() Parameter Updates

```bash
create_project_config() {
    local config_file="$1"
    local project_type="$2"
    local owner="$3"
    local number="$4"
    local status_field="$5"      # Field name from API
    local status_value="$6"      # Selected value
    local priority_field="$7"    # Field name from API
    local priority_value="$8"    # Selected value
    local iteration_field="$9"   # Field name from API
    local iteration_value="${10}" # Selected value
    local start_field="${11}"    # Field name from API (usually "Start")
    local start_value="${12}"    # @today
    local end_field="${13}"      # Field name from API (usually "End")
    local end_value="${14}"      # @iteration_end
    # ...
}
```

### 6. create_minimal_project_config() Updates

```yaml
# Default field values
# Dynamic values: @current_iteration, @today, @iteration_end
defaults:
  Status: "Ready"
  Iteration: "@current_iteration"
  Start: "@today"
  End: "@iteration_end"
```

## File Changes

| File | Changes |
|------|---------|
| `templates/github-actions/plugin.sh` | Update 3 functions |

### Function-level Changes

#### setup_project_automation() (~Lines 176-310)
- Add Iteration field detection after Priority selection
- Add iteration options display
- Add user selection handling
- Add Start/End auto-setting
- Update create_project_config() call with new parameters

#### fetch_project_fields() (~Lines 313-364)
- Update GraphQL query to include iteration configurations
- Return iteration list in JSON response

#### create_project_config() (~Lines 398-440)
- Add new parameters for iteration, start, end
- Update defaults section generation to include all fields
- Use field names from API (preserve case)

#### create_minimal_project_config() (~Lines 368-395)
- Change from commented defaults to active defaults
- Include Iteration, Start, End with dynamic values

## Test Strategy

### Unit Tests (Manual Verification)
1. Run `setup.sh` with a project that has Iteration field
2. Verify selection UI displays correctly
3. Verify generated YAML has correct field names and values

### Integration Tests
1. `shellcheck templates/github-actions/plugin.sh`
2. Verify YAML syntax of generated configuration

### Edge Cases
- Project without Iteration field → Skip iteration/date fields
- Empty selection → Use default (@current_iteration)
- Invalid selection number → Prompt again or use default

## Rollback Plan

If issues are found:
1. Revert changes to `plugin.sh`
2. The existing project-automation.yml files are not affected
3. Users can manually edit their configuration files
