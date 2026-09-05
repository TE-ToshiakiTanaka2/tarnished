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

Before checkout, pull, merge, or commit, inspect `git status --short` and `git worktree list`. Reuse the current issue worktree when appropriate. Preserve unrelated tracked, staged, and untracked work; never stash, reset, or commit it automatically. When switching would carry edits to another issue or overwrite files, use a separate worktree if possible. If the desired branch is already checked out elsewhere, use that worktree without moving the user's checkout. Ask only if ownership or a real conflict prevents progress. In every commit, stage only owned changes and inspect the staged diff for pre-existing staged content.

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
git for-each-ref --format='%(refname)' refs/heads refs/remotes
```

Match the exact `/#<issue_number>/` path segment. Deduplicate local branches and their remote-tracking counterparts. Fetch when remote state is needed; a failed fetch is not evidence that no branch exists. If multiple distinct issue branches match, prefer the current matching branch or the branch identified by the issue's open PR; otherwise ask which branch to use. Never pick the first textual match.

### Step 6: Branch Decision

Use resolved, quoted branch names and validate a generated name with `git check-ref-format --branch`. If title normalization produces an empty slug, use `issue-<number>`. A diverged base must not be merged or reset implicitly: create the new worktree/branch from the fetched remote base, preserving the local base, or report why that is unavailable.

**If a branch for the issue already exists:**
- Use the safe worktree selected above; checkout the existing branch only when that preserves the current worktree: `git checkout <existing_branch_name>`
- If the existing branch is remote-only: `git checkout -b <local_name> origin/<remote_name>`
- If the requested work requires a new branch preserving artifacts from the existing one, create it from the fetched remote base using the procedure below, then merge the resolved existing branch into that new branch: `git merge "$EXISTING_BRANCH" --no-edit`. Do not merge into or update the local base.

**If no branch exists:**

Bind `BASE` to the caller's base and `NEW_BRANCH` to the validated generated name. Fetch the explicit remote base; stop on fetch failure. Create directly from its commit, leaving the local base untouched:

```bash
git fetch origin "refs/heads/${BASE}"
BASE_COMMIT="$(git rev-parse --verify 'FETCH_HEAD^{commit}')"
git check-ref-format --branch "$NEW_BRANCH"
```

After inspecting status and worktrees as above, choose one creation path. In a safe current worktree, run `git switch --no-track -c "$NEW_BRANCH" "$BASE_COMMIT"`. When preserving the current checkout or its changes requires a separate worktree, resolve an unused `ISSUE_WORKTREE` path and run `git worktree add -b "$NEW_BRANCH" "$ISSUE_WORKTREE" "$BASE_COMMIT"`; continue the stage there. Do not run both paths.

## Base Branch

`base` defaults to `develop`. Every new-branch path uses the fetched remote commit of that parameter, including the artifact-preserving path. A caller passing `--base main` therefore branches from the remote `main` and uses `main` for later review and PR targeting without changing a local base branch.

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
