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
| **Issue mode** | `issue_number`, `base` | `{label}/{assignee}/#{issue_number}/{title}` | `/design`, `/implement`, `/flow` |

## Issue Mode

### Parameters

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `issue_number` | Yes | — | GitHub Issue number |
| `base` | No | `develop` | Branch that new branches are cut from and pulled |

Callers that accept `--base <branch>` pass it through here. `base` is the same value the caller uses for its review diff base and PR target, so one flag holds end to end.

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
git branch -a | grep -F "#{issue_number}/"
```

The trailing `/` is a delimiter anchor, not decoration: the branch pattern always places `/` immediately after the issue number, so without it a search for `#12` also matches `#123`, `#124`, … and checks out an unrelated branch.

### Step 6: Branch Decision

**If a branch for the issue already exists:**
- Checkout the existing branch: `git checkout <existing_branch_name>`
- If the existing branch is remote-only: `git checkout -b <local_name> origin/<remote_name>`
- If you need to create a new branch but want to preserve artifacts from the existing one:
  1. Create the new branch from `{base}`
  2. Immediately merge the existing branch: `git merge <existing_branch> --no-edit`

**If no branch exists:**
```bash
git checkout {base}
git pull origin {base}
git checkout -b {label}/{assignee}/#{issue_number}/{title}
```

## Base Branch

`base` defaults to `develop`. Every step that names a base — checkout, pull, and the artifact-preserving merge path — uses the parameter, so a caller passing `--base main` gets a branch cut from `main` rather than one cut from `develop` while every later stage targets `main`.

## Error Handling

| Error | Action |
| --- | --- |
| `gh issue view` fails | Report error, ask user to verify issue number |
| No labels match priority list | Use `feature` as default |
| `gh api user` / `gh auth status` fails | Report error, ask user to run `gh auth login` |
| Branch creation fails | Report error with details |
| `{base}` branch not found | Report error naming the resolved base, ask user to verify it exists |

## Integration

This skill is referenced by:
- `/design` — Phase 1 (Create branch) — Issue mode
- `/implement` — Phase 1 (Detect or create branch) — Issue mode
- `/flow` — Stage 2 onward, threading its own `--base` through

The branch created by `/design` is shared with `/implement`. The `/implement` skill will detect and reuse the branch created by `/design`.
