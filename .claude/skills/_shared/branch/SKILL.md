---
name: _shared/branch
description: Internal shared skill for consistent branch creation and reuse across skills
---

# Shared Skill: Branch Creation and Management

Internal utility skill that defines the standard procedure for creating and reusing branches. Referenced by `/design`, `/implement`, and other skills that need branch management.

**This skill is NOT directly invocable by users.** It is a reference document included by other skills.

## Mode

This skill currently supports Issue mode. Additional modes (Docs, Release) can be added in the future.

| Mode | Input | Branch Pattern | Used By |
|------|-------|---------------|---------|
| **Issue mode** | `issue_number` | `{label}/{assignee}/#{issue_number}/{title}` | `/design`, `/implement` |

## Issue Mode

### Branch Naming Convention

```
{label}/{assignee}/#{issue_number}/{title}
```

- `{label}`: Selected from issue labels using priority order (see below)
- `{assignee}`: Current GitHub authenticated user
- `{issue_number}`: GitHub Issue number (with `#` prefix)
- `{title}`: Issue title converted to kebab-case

Examples:

- `feature/alice/#123/add-user-authentication`
- `bugfix/bob/#456/fix-login-validation`
- `refactor/charlie/#789/optimize-database-queries`

### Procedure

Given an `issue_number`, follow these steps:

### Step 1: Fetch Issue Metadata

```bash
gh issue view <issue_number> --json title,labels
```

Extract `title` and `labels` from the response.

### Step 2: Determine Label

Select the branch label from the issue's labels using this priority order:

```
feature > bugfix > refactor > docs
```

**Algorithm:**
1. Fetch issue labels: `gh issue view <issue_number> --json labels --jq '.labels[].name'`
2. Check labels in priority order: `feature`, `bugfix`, `refactor`, `docs`
3. Use the first match
4. If no match → default to `feature`

### Step 3: Determine Assignee

Get the current GitHub authenticated user:

```bash
gh api user --jq '.login'
```

**Fallback**: If `gh api user` fails, try `gh auth status 2>&1 | grep "account" | head -1 | sed 's/.*account \(.*\) (.*/\1/'`. If both fail, report error and ask user to run `gh auth login`.

### Step 4: Normalize Title

Convert the issue title to kebab-case:

1. Remove prefix patterns like `feat:`, `fix:`, `refactor:`, `docs:` (conventional commit prefixes)
2. Convert to lowercase
3. Replace spaces and special characters with hyphens
4. Remove consecutive hyphens
5. Trim leading/trailing hyphens
6. Truncate to ~50 characters (break at word boundary)

### Step 5: Check for Existing Branches

```bash
git branch -a | grep "#{issue_number}"
```

### Step 6: Branch Decision

**If a branch for the issue already exists:**
- Checkout the existing branch: `git checkout <existing_branch_name>`
- If the existing branch is remote-only: `git checkout -b <local_name> origin/<remote_name>`
- If you need to create a new branch but want to preserve artifacts from the existing one:
  1. Create the new branch from `develop`
  2. Immediately merge the existing branch: `git merge <existing_branch> --no-edit`

**If no branch exists:**
```bash
git checkout develop
git pull origin develop
git checkout -b {label}/{assignee}/#{issue_number}/{title}
```

## Base Branch

Always use `develop` as the base branch when creating new branches.

## Error Handling

| Error | Action |
| --- | --- |
| `gh issue view` fails | Report error, ask user to verify issue number |
| No labels match priority list | Use `feature` as default |
| `gh api user` / `gh auth status` fails | Report error, ask user to run `gh auth login` |
| Branch creation fails | Report error with details |
| `develop` branch not found | Report error, ask user to verify branch exists |

## Integration

This skill is referenced by:
- `/design` — Phase 1 (Create branch) — Issue mode
- `/implement` — Phase 1 (Detect or create branch) — Issue mode

The branch created by `/design` is shared with `/implement`. The `/implement` skill will detect and reuse the branch created by `/design`.
