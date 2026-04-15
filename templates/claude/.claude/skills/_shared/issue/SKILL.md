---
name: _shared/issue
description: Internal shared skill for consistent GitHub Issue creation and metadata setting across skills
---

# Shared Skill: Issue Creation and Management

Internal utility skill that defines the standard procedure for creating GitHub Issues and setting metadata (labels, milestone, assignee, project fields). Referenced by `/issue` and other skills that create Issues.

**This skill is NOT directly invocable by users.** It is a reference document included by other skills.

## Parameters

The calling skill provides the following parameters before invoking this procedure:

| Parameter | Required | Description |
| --- | --- | --- |
| title | Yes | Issue title (English) |
| body | Yes | Issue body (Markdown) |
| labels | Yes | Comma-separated label names (e.g., `feature`, `bugfix`) |
| assignee | No | GitHub username. Defaults to current authenticated user. |
| milestone | No | Milestone name to assign |
| size | No | Size field value: `XS`, `S`, `M`, `L`, or `XL` |
| priority | No | Priority field value: `P0`, `P1`, or `P2` |

## Procedure

Given the parameters above, follow these steps:

### Step 1: Determine Assignee

If `assignee` is not provided, detect the current GitHub authenticated user:

```bash
gh api user --jq '.login'
```

**Fallback**: If `gh api user` fails, try `gh auth status 2>&1 | grep "account" | head -1 | sed 's/.*account \(.*\) (.*/\1/'`. If both fail, report error and ask user to provide assignee manually or run `gh auth login`.

### Step 2: Create Issue

```bash
gh issue create \
  --title "{title}" \
  --body "{body}" \
  --label "{labels}" \
  --assignee "{assignee}"
```

Extract the issue URL from the command output. The issue number can be parsed from the URL (last path segment).

**This is the only blocking step.** If this fails, report the error and stop.

### Step 3: Set Milestone (if provided)

```bash
gh issue edit {issue_number} --milestone "{milestone}"
```

If this fails, warn the user and continue (non-blocking).

### Step 4: Add to Project

Read project configuration from `.github/project.yml`:

```yaml
default_project:
  owner: "{project_owner}"
  number: {project_number}
```

```bash
gh project item-add {project_number} --owner {project_owner} --url {issue_url}
```

If `.github/project.yml` does not exist or this fails, warn the user and continue (non-blocking).

### Step 5: Set Project Fields (if size/priority given)

#### Step 5a: Get Project and Field IDs

```bash
# Get the project node ID
PROJECT_ID=$(gh project list --owner {project_owner} --format json \
  -q ".projects[] | select(.number == {project_number}) | .id")

# Get the item ID
ITEM_ID=$(gh project item-list {project_number} --owner {project_owner} --format json \
  -q ".items[] | select(.content.url == \"{issue_url}\") | .id")
```

#### Step 5b: Get Field IDs and Option IDs

```bash
# Get Size field ID and option IDs
SIZE_FIELD_ID=$(gh project field-list {project_number} --owner {project_owner} --format json \
  -q '.fields[] | select(.name == "Size") | .id')

SIZE_OPTION_ID=$(gh project field-list {project_number} --owner {project_owner} --format json \
  -q '.fields[] | select(.name == "Size") | .options[] | select(.name == "{size}") | .id')

# Get Priority field ID and option IDs
PRIORITY_FIELD_ID=$(gh project field-list {project_number} --owner {project_owner} --format json \
  -q '.fields[] | select(.name == "Priority") | .id')

PRIORITY_OPTION_ID=$(gh project field-list {project_number} --owner {project_owner} --format json \
  -q '.fields[] | select(.name == "Priority") | .options[] | select(.name == "{priority}") | .id')
```

#### Step 5c: Set Field Values

```bash
# Set Size
gh project item-edit --project-id {PROJECT_ID} --id {ITEM_ID} \
  --field-id {SIZE_FIELD_ID} --single-select-option-id {SIZE_OPTION_ID}

# Set Priority
gh project item-edit --project-id {PROJECT_ID} --id {ITEM_ID} \
  --field-id {PRIORITY_FIELD_ID} --single-select-option-id {PRIORITY_OPTION_ID}
```

If any project field operation fails, warn the user and continue (non-blocking).

### Step 6: Return Result

Return the following to the calling skill:

- **Issue number**: Extracted from the issue URL
- **Issue URL**: Full GitHub URL

## Error Handling

| Error | Blocking? | Action |
| --- | --- | --- |
| `gh issue create` fails | **Yes** | Report error with gh error message. Stop procedure. |
| `gh issue edit --milestone` fails | No | Warn user: "Could not set milestone: {error}". Continue. |
| `project.yml` not found | No | Warn user: "No project.yml found, skipping project integration". Continue. |
| `gh project item-add` fails | No | Warn user: "Could not add to project: {error}". Continue. |
| Project field query fails | No | Warn user: "Could not query project fields: {error}". Skip field setting. |
| `gh project item-edit` fails | No | Warn user: "Could not set {field}: {error}". Continue. |

**Design Principle**: Issue creation is the only blocking operation. All metadata operations are non-blocking — failures are warned but do not stop the workflow.

## Integration

This skill is referenced by:
- `/issue` — Phase 3 (Issue Creation and Configuration)
