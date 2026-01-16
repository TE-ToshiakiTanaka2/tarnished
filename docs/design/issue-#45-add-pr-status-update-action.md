# Design Document: PR Status Update GitHub Action

**Issue**: #45
**Title**: Add PR status update GitHub Action for automatic project status change
**Author**: Claude
**Date**: 2026-01-16

## 1. Overview

This document describes the design for a new GitHub Action that automatically updates the status of linked Issues in a GitHub Project when a Pull Request is created or reopened.

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Workflow                       │
│                                                                   │
│  ┌──────────────┐    ┌─────────────────────┐    ┌─────────────┐ │
│  │ PR Event     │───▶│ pr-status-update    │───▶│ GitHub      │ │
│  │ (opened/     │    │ Action              │    │ Project V2  │ │
│  │  reopened)   │    │                     │    │ API         │ │
│  └──────────────┘    └─────────────────────┘    └─────────────┘ │
│                              │                                    │
│                              ▼                                    │
│                      ┌─────────────────┐                         │
│                      │ Config File     │                         │
│                      │ (.github/       │                         │
│                      │  project-       │                         │
│                      │  automation.yml)│                         │
│                      └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Structure

```
.github/actions/pr-status-update/
├── action.yml              # Action definition
├── package.json            # Dependencies
├── package-lock.json       # Lock file
├── tsconfig.json           # TypeScript configuration
├── vitest.config.ts        # Test configuration
├── src/
│   ├── index.ts            # Entry point
│   ├── config.ts           # Extended configuration loader
│   ├── types.ts            # Extended type definitions
│   ├── issue-detector.ts   # Issue number detection logic
│   ├── graphql/            # Reused from project-automation
│   │   ├── client.ts
│   │   ├── queries.ts
│   │   └── mutations.ts
│   └── project/            # Reused from project-automation
│       ├── finder.ts
│       ├── item.ts
│       └── fields.ts
└── __tests__/
    └── issue-detector.test.ts
```

## 3. Component Design

### 3.1 Issue Detection Module (`issue-detector.ts`)

Responsible for extracting Issue numbers from PR context.

#### 3.1.1 Keyword Detection

Detects Issue references in PR title and body using GitHub's standard linking syntax:

- `Closes #123`, `closes #123`
- `Fixes #123`, `fixes #123`, `fix #123`
- `Resolves #123`, `resolves #123`, `resolve #123`

**Regex Pattern:**
```typescript
/(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)/gi
```

#### 3.1.2 Branch Name Detection

Extracts Issue numbers from branch names using a configurable regex pattern.

**Default Pattern:** `^(?:feature|fix|bugfix|hotfix)[/-]?(\d+)`

**Examples:**
- `feature/123-add-feature` → `#123`
- `fix-456-bug` → `#456`
- `bugfix/789` → `#789`

### 3.2 Configuration Extension

Extends the existing `project-automation.yml` configuration:

```yaml
# Existing configuration
project:
  type: organization
  owner: "my-org"
  number: 1

defaults:
  Status: "Backlog"

# NEW: PR-specific configuration
pr:
  status: "In Review"        # Status to set when PR is opened/reopened
  branch_pattern: "^(?:feature|fix|bugfix|hotfix)[/-]?(\\d+)"  # Optional: custom regex
```

### 3.3 Extended Types

```typescript
// Extended configuration interface
export interface ExtendedProjectConfig extends ProjectConfig {
  pr?: {
    status: string;
    branch_pattern?: string;
  };
}

// Issue detection result
export interface DetectedIssues {
  fromKeywords: number[];
  fromBranch: number[];
  all: number[];  // Deduplicated union
}
```

### 3.4 Main Flow (`index.ts`)

```typescript
async function run(): Promise<void> {
  // 1. Get inputs and PR context
  const token = core.getInput('token', { required: true });
  const configPath = core.getInput('config-path');
  const pr = github.context.payload.pull_request;

  // 2. Load extended configuration
  const config = loadExtendedConfig(configPath);

  // 3. Detect linked issues
  const issues = detectIssues(pr, config.pr?.branch_pattern);

  // 4. Initialize GraphQL client
  const client = new GraphQLClient(token);

  // 5. Find project
  const project = await findProject(client, config);

  // 6. For each detected issue:
  for (const issueNumber of issues.all) {
    // 6a. Get Issue node ID
    const issueNodeId = await getIssueNodeId(client, issueNumber);

    // 6b. Find or add to project
    let itemId = await findItemInProject(client, project.id, issueNodeId);
    if (!itemId) {
      itemId = await addItemToProject(client, project.id, issueNodeId);
    }

    // 6c. Update status field
    await setFieldValue({
      client, projectId: project.id, itemId,
      fields: project.fields,
      fieldName: 'Status',
      value: config.pr?.status ?? 'In Review'
    });
  }
}
```

## 4. API Design

### 4.1 Action Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | - | GitHub token with project permissions |
| `config-path` | No | `.github/project-automation.yml` | Path to configuration file |

### 4.2 Action Outputs

| Output | Description |
|--------|-------------|
| `issues-updated` | Comma-separated list of updated issue numbers |
| `issues-count` | Number of issues updated |
| `project-id` | The project ID |

## 5. Error Handling

### 5.1 Error Strategy

- **Non-blocking**: Errors should not fail the workflow (to not block PR merges)
- **Warning logs**: Issues are logged as warnings, not errors
- **Graceful degradation**: Continue processing other issues if one fails

### 5.2 Error Cases

| Case | Handling |
|------|----------|
| No issues detected | Log info, exit successfully |
| Issue not found in repo | Log warning, skip |
| Project not found | Log error, exit (fail) |
| Status field not found | Log warning, skip status update |
| GraphQL API error | Log warning, continue with next issue |

## 6. Configuration File Schema

```yaml
# Full schema for project-automation.yml

project:
  type: organization | repository  # Required
  owner: string                    # Required
  number: number                   # Required

defaults:                          # Optional
  Status: string
  Priority: string
  # ... other fields

pr:                               # Optional (new section)
  status: string                  # Status value for PR open/reopen
  branch_pattern: string          # Regex for branch name parsing
```

## 7. Workflow Template

```yaml
# .github/workflows/pr-status-update.yml

name: PR Status Update

on:
  pull_request:
    types: [opened, reopened]

jobs:
  update-status:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Update linked issue status
        uses: ./.github/actions/pr-status-update
        with:
          token: ${{ secrets.PROJECT_TOKEN }}
```

## 8. Code Reuse Strategy

### 8.1 Shared Modules

The following modules from `project-automation` will be copied and reused:

| Module | Reason |
|--------|--------|
| `graphql/client.ts` | GraphQL client wrapper |
| `graphql/queries.ts` | Project/Item queries |
| `graphql/mutations.ts` | Field update mutations |
| `project/finder.ts` | Project lookup |
| `project/item.ts` | Item management |
| `project/fields.ts` | Field value setting |
| `types.ts` | Type definitions (extended) |

### 8.2 New Modules

| Module | Purpose |
|--------|---------|
| `issue-detector.ts` | PR-specific Issue detection |
| `config.ts` | Extended config with PR section |

## 9. Testing Strategy

### 9.1 Unit Tests

- `issue-detector.test.ts`: Test keyword and branch pattern detection
- `config.test.ts`: Test extended configuration loading

### 9.2 Test Cases

```typescript
// Keyword detection tests
describe('detectIssuesFromKeywords', () => {
  it('detects "Closes #123"', ...);
  it('detects "fixes #456"', ...);
  it('detects multiple issues', ...);
  it('handles no matches', ...);
});

// Branch pattern tests
describe('detectIssuesFromBranch', () => {
  it('extracts from "feature/123-name"', ...);
  it('extracts from "fix-456-bug"', ...);
  it('handles custom patterns', ...);
  it('handles no match', ...);
});
```

## 10. Security Considerations

- Token requires `project` scope for Project V2 API access
- Token should be stored as a repository secret
- No sensitive data is logged

## 11. File Placement

| Type | Path |
|------|------|
| Source code | `.github/actions/pr-status-update/` |
| Built distribution | `templates/github-actions/.github/actions/pr-status-update/dist/` |
| Workflow template | `templates/github-actions/.github/workflows/pr-status-update.yml` |
| Action definition | `templates/github-actions/.github/actions/pr-status-update/action.yml` |
