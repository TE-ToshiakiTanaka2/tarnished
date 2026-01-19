# Design Document: Issue #94 - Add GitHub Project Field Auto-Configuration

## Overview

This document describes the design for adding automatic GitHub Project field configuration to the `/issue` command. After creating an issue, the system will wait for the `project-automation` GitHub Actions workflow to complete, then automatically set custom Project fields (Size, Priority, etc.) based on AI analysis of the issue content.

## Architecture

### Component Structure

```
/issue Command Flow
├── Existing Flow
│   ├── Issue Creation
│   ├── Label Assignment
│   ├── Milestone Assignment
│   └── Assignee Assignment
│
└── New: Project Field Configuration Flow (Step 10)
    ├── 1. Actions Monitoring Module
    │   └── Poll `gh run list` for project-automation workflow
    ├── 2. Project Field Retrieval Module
    │   └── GraphQL query to fetch project fields
    ├── 3. Field Value Judgment Module
    │   ├── Size Judgment Logic
    │   └── Priority Judgment Logic
    └── 4. Field Value Setting Module
        └── GraphQL mutation to update field values
```

### Sequence Diagram

```
User          /issue Command        GitHub API        GitHub Actions
  │                │                    │                   │
  │ Create Issue   │                    │                   │
  │───────────────>│                    │                   │
  │                │ gh issue create    │                   │
  │                │───────────────────>│                   │
  │                │                    │                   │
  │                │ Set labels/milestone│                  │
  │                │───────────────────>│                   │
  │                │                    │ Trigger workflow  │
  │                │                    │──────────────────>│
  │                │                    │                   │
  │                │ Poll run status    │                   │
  │                │───────────────────>│                   │
  │                │   (max 30 seconds) │                   │
  │                │                    │   Complete        │
  │                │                    │<──────────────────│
  │                │                    │                   │
  │                │ Get project fields │                   │
  │                │───────────────────>│                   │
  │                │                    │                   │
  │                │ Analyze issue      │                   │
  │                │ (Size, Priority)   │                   │
  │                │                    │                   │
  │                │ Update fields      │                   │
  │                │───────────────────>│                   │
  │                │                    │                   │
  │ Report results │                    │                   │
  │<───────────────│                    │                   │
```

## Component Details

### 1. Actions Monitoring Module

**Purpose**: Wait for `project-automation` workflow to complete after issue creation.

**Technical Approach**:
- Use `gh run list --workflow=project-automation.yml --limit=1` to get latest run
- Poll every 3 seconds until completion or timeout (30 seconds)
- Check run status: `completed`, `in_progress`, `queued`

**Error Handling**:
- Timeout: Display timeout message, skip field configuration
- Failure: Display error message, skip field configuration
- No retry logic (keep simple)

### 2. Project Field Retrieval Module

**Purpose**: Fetch available Project fields and their options from GitHub.

**Data Sources**:
1. `.github/project-automation.yml` - Project configuration
2. GitHub GraphQL API - Field details and options

**GraphQL Query**:
```graphql
query($owner: String!, $number: Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      id
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
          ... on ProjectV2Field {
            id
            name
            dataType
          }
        }
      }
    }
  }
}
```

**Configuration Reference** (from `.github/project-automation.yml`):
```yaml
project:
  type: user
  owner: "OWNER"
  number: PROJECT_NUMBER
```

### 3. Field Value Judgment Module

**Purpose**: AI-driven analysis of issue content to determine field values.

#### Size Judgment Guidelines

| Size | Criteria |
|------|----------|
| XS | Single file small change, configuration only |
| S | 1-2 files change, simple feature addition |
| M | 3-5 files change, moderate feature addition |
| L | Multiple files/components change |
| XL | Architecture change, large-scale refactoring |

**Factors to Consider**:
- Number of tasks in issue
- Technical complexity described
- Estimated number of files to modify
- Presence of architectural changes
- Dependencies on external systems

#### Priority Judgment Guidelines

| Priority | Criteria |
|----------|----------|
| High | Bug fix, security-related, blocker |
| Medium | Normal feature addition, improvement |
| Low | Documentation, refactoring, nice-to-have |

**Factors to Consider**:
- Issue label (bugfix → High, feature → Medium, documentation → Low)
- Keywords indicating urgency (critical, urgent, blocker, security)
- Milestone importance
- Issue description context

### 4. Field Value Setting Module

**Purpose**: Update Project item fields via GraphQL mutation.

**GraphQL Mutation**:
```graphql
mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { singleSelectOptionId: $optionId }
  }) {
    projectV2Item { id }
  }
}
```

**Field Types Supported**:
- `SINGLE_SELECT`: Size, Priority, Status
- `NUMBER`: Story points, estimates

## Integration Points

### Files to Modify

1. **`.claude/commands/issue.md`**
   - Add Step 10: Project Field Configuration
   - Document field judgment guidelines
   - Include GraphQL examples

2. **`templates/claude/.claude/commands/issue.md`**
   - Add equivalent functionality for template projects
   - Generic version without project-specific defaults

### Dependencies

- `project-automation.yml` must exist for this feature to activate
- GitHub token must have `project` scope
- Project must have Size/Priority fields defined

## Error Scenarios

| Scenario | Behavior |
|----------|----------|
| `project-automation.yml` not found | Skip field configuration silently |
| Actions workflow timeout (>30s) | Display warning, skip configuration |
| Actions workflow failure | Display error, skip configuration |
| Project field not found | Skip that specific field |
| GraphQL API error | Display error, skip configuration |

## Testing Strategy

### Manual Testing
1. Create issue via `/issue` command
2. Verify Actions workflow completes
3. Verify Project fields are set correctly
4. Test timeout scenario (slow Actions)
5. Test failure scenario (Actions fails)

### Validation Checklist
- [ ] Size field set based on issue complexity
- [ ] Priority field set based on issue urgency
- [ ] Error messages displayed appropriately
- [ ] Template version works correctly

## Future Considerations

- Support for additional field types (DATE, ITERATION)
- Custom field mappings via configuration
- User confirmation option before setting fields
- Learning from historical patterns
