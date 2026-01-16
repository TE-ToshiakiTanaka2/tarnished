# Design Document: Project Automation GitHub Action

**Issue**: #43 - Add project-automation GitHub Action for automatic issue-to-project linking
**Author**: Claude Code
**Date**: 2026-01-16

## Overview

This document describes the architecture and design for the `project-automation` GitHub Action, which automatically adds newly created issues to a specified GitHub Project and sets initial field values.

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Workflow                           │
│                  (project-automation.yml)                            │
├─────────────────────────────────────────────────────────────────────┤
│  Triggers: issues.opened, issues.labeled, issues.reopened           │
│                              │                                       │
│                              ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              project-automation Action                       │    │
│  │                                                              │    │
│  │  ┌──────────────────────────────────────────────────────┐   │    │
│  │  │  1. Load config (.github/project-automation.yml)     │   │    │
│  │  │  2. Validate configuration                           │   │    │
│  │  │  3. Fetch Project info via GraphQL                   │   │    │
│  │  │  4. Check if issue already in project (idempotency)  │   │    │
│  │  │  5. Add issue to project via GraphQL mutation        │   │    │
│  │  │  6. Set field values for each configured field       │   │    │
│  │  └──────────────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### Component Architecture

```
project-automation/
├── action.yml              # Action metadata and inputs/outputs
├── package.json            # Dependencies
├── tsconfig.json           # TypeScript configuration
├── src/
│   ├── index.ts            # Entry point
│   ├── config.ts           # Configuration loader and validator
│   ├── graphql/
│   │   ├── client.ts       # GraphQL client wrapper
│   │   ├── queries.ts      # GraphQL query definitions
│   │   └── mutations.ts    # GraphQL mutation definitions
│   ├── project/
│   │   ├── finder.ts       # Project lookup logic
│   │   ├── item.ts         # Project item management
│   │   └── fields.ts       # Field value setting logic
│   └── types.ts            # TypeScript type definitions
└── dist/
    └── index.js            # Bundled output (ncc)
```

## Data Flow

### Sequence Diagram

```
┌──────┐     ┌──────────┐     ┌────────┐     ┌─────────────┐
│GitHub│     │  Action  │     │ Config │     │ GraphQL API │
└──┬───┘     └────┬─────┘     └───┬────┘     └──────┬──────┘
   │              │               │                  │
   │ Issue Event  │               │                  │
   │─────────────>│               │                  │
   │              │               │                  │
   │              │ Load Config   │                  │
   │              │──────────────>│                  │
   │              │               │                  │
   │              │ Config Data   │                  │
   │              │<──────────────│                  │
   │              │               │                  │
   │              │ Get Project Info                 │
   │              │─────────────────────────────────>│
   │              │               │                  │
   │              │ Project + Fields                 │
   │              │<─────────────────────────────────│
   │              │               │                  │
   │              │ Check if item exists             │
   │              │─────────────────────────────────>│
   │              │               │                  │
   │              │ [If not exists] Add item         │
   │              │─────────────────────────────────>│
   │              │               │                  │
   │              │ Set field values (per field)     │
   │              │─────────────────────────────────>│
   │              │               │                  │
   │ Action Output│               │                  │
   │<─────────────│               │                  │
   │              │               │                  │
```

## Configuration Schema

### File: `.github/project-automation.yml`

```yaml
# Project Configuration
project:
  # Project type: 'organization' or 'repository'
  type: organization
  # Owner name (organization or user)
  owner: "my-org"
  # Project number (visible in project URL)
  number: 1

# Default field values to set when adding issues
defaults:
  # Status field (Single Select)
  status: "Backlog"
  # Priority field (Single Select)
  priority: "Medium"
  # Sprint/Iteration field (Iteration)
  # iteration: "Sprint 1"
  # Size field (Number or Single Select)
  # size: "M"
  # Custom fields (by field name)
  # custom_field_name: "value"
```

### Configuration Types

```typescript
interface ProjectConfig {
  project: {
    type: 'organization' | 'repository';
    owner: string;
    number: number;
  };
  defaults?: Record<string, string | number>;
}
```

## GraphQL API Integration

### Queries

#### Get Project Information

```graphql
query GetProject($owner: String!, $number: Int!) {
  organization(login: $owner) {
    projectV2(number: $number) {
      id
      title
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
          ... on ProjectV2IterationField {
            id
            name
            configuration {
              iterations {
                id
                title
              }
            }
          }
        }
      }
    }
  }
}
```

#### Check Existing Item

```graphql
query GetProjectItem($projectId: ID!, $contentId: ID!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: 100) {
        nodes {
          id
          content {
            ... on Issue {
              id
            }
          }
        }
      }
    }
  }
}
```

### Mutations

#### Add Issue to Project

```graphql
mutation AddProjectItem($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: {
    projectId: $projectId
    contentId: $contentId
  }) {
    item {
      id
    }
  }
}
```

#### Update Field Value (Single Select)

```graphql
mutation UpdateSingleSelectField($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: {
      singleSelectOptionId: $optionId
    }
  }) {
    projectV2Item {
      id
    }
  }
}
```

## Action Inputs/Outputs

### Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `token` | GitHub token with project permissions | Yes | - |
| `config-path` | Path to configuration file | No | `.github/project-automation.yml` |

### Outputs

| Output | Description |
|--------|-------------|
| `item-id` | The project item ID (if added) |
| `project-id` | The project ID |
| `already-exists` | Whether the item already existed |

## Error Handling

### Error Categories

| Error Type | Behavior | Exit Code |
|------------|----------|-----------|
| Project not found | Fail workflow | 1 |
| Invalid configuration | Fail workflow | 1 |
| Field not found | Skip field, log warning | 0 |
| Invalid field value | Skip field, log warning | 0 |
| Item already exists | Skip add, continue with fields | 0 |
| API rate limit | Retry with backoff | 1 (after retries) |

### Idempotency

The action ensures idempotency by:
1. Checking if the issue is already in the project before adding
2. Using upsert-like behavior for field values
3. Gracefully handling duplicate operations

## Security Considerations

### Token Permissions

The action requires a Personal Access Token (PAT) with:
- `project` scope (for Project V2 API access)
- `repo` scope (for issue access)

**Note**: The default `GITHUB_TOKEN` does not have sufficient permissions for Project V2 API.

### Secrets Management

- Token should be stored as a repository secret (`PROJECT_TOKEN`)
- Token is never logged or exposed in outputs
- Configuration file should not contain sensitive data

## Plugin Integration

### plugin.sh Modifications

The `plugin.sh` will be extended to:
1. Add `project-automation` to `AVAILABLE_ACTIONS` array
2. Implement interactive setup for configuration generation

### Interactive Setup Flow

```bash
# 1. Prompt for PAT (temporary, not saved)
? GitHub Personal Access Token (for field discovery): ********

# 2. Fetch available projects
Fetching projects...

# 3. Project selection
? Project type:
  > Organization Project
    Repository Project

? Owner/Organization name: my-org
? Project number: 1

# 4. Field discovery and selection
Fetching project fields...

? Default Status:
  > Backlog
    Todo
    In Progress
    Done
    (Skip)

? Default Priority:
  > Medium
    High
    Low
    (Skip)

# 5. Generate configuration file
Generated: .github/project-automation.yml
```

## Testing Strategy

### Unit Tests

- Configuration parsing and validation
- GraphQL query/mutation construction
- Error handling logic
- Field value mapping

### Integration Tests

- End-to-end workflow with mock API
- Real API integration (manual testing)

### Test Configuration

```yaml
# test/fixtures/valid-config.yml
project:
  type: organization
  owner: "test-org"
  number: 1
defaults:
  status: "Backlog"
```

## Dependencies

### Runtime Dependencies

- `@actions/core` - GitHub Actions toolkit
- `@actions/github` - GitHub API client
- `@octokit/graphql` - GraphQL client
- `js-yaml` - YAML parser

### Dev Dependencies

- `typescript` - TypeScript compiler
- `@vercel/ncc` - Bundler
- `@types/node` - Node.js types
- `vitest` - Test framework

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `templates/github-actions/.github/actions/project-automation/` | Create | New action directory |
| `templates/github-actions/.github/workflows/project-automation.yml` | Create | Workflow file |
| `templates/github-actions/plugin.sh` | Modify | Add interactive setup |

## References

- [GitHub Project V2 API Documentation](https://docs.github.com/en/graphql/reference/objects#projectv2)
- [actions/add-to-project](https://github.com/actions/add-to-project) - Official reference implementation
- [GitHub Actions Toolkit](https://github.com/actions/toolkit)
