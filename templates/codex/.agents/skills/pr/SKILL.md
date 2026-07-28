---
name: pr
description: Prepare, create, validate, and optionally merge a Pull Request. Use when the user says pr, /pr, $pr, pull request, PR作成, CI確認, merge, or asks to update the work branch after merge.
---

# PR

## Overview

Create and validate a pull request after implementation and review. This is the Codex equivalent of Claude Code's `/pr`.

## Procedure

1. Read `.tarnished/workflows/pr.md`.
2. If present, read `.claude/skills/pr/SKILL.md` for compatibility details.
3. Parse arguments: default target branch is `develop`; merge only when the user passes `--merge` or explicitly requests merge.
4. Run final analysis, improvement, cleanup, formatting, build, and tests. Delegate the mechanical half to the `executor` role where a subagent mechanism is available.
5. Commit any final cleanup changes.
6. Push the branch to `origin`.
7. Create the PR with `gh pr create`; put `Closes #<issue_number>` in the body, not the title. Read the body before creating it — a pull request is outward-facing.
8. Monitor CI with `gh pr checks` or available GitHub connectors. Inspect logs before retrying failed jobs.
9. Fix CI or validation failures in follow-up commits, push, and re-check.
10. If merge was requested and validation passes, squash-merge the PR and delete the source branch. The merge decision and the merge command are never delegated: a merge is irreversible.
11. After a successful merge, switch to the target branch and update it with `git pull --ff-only origin <target_branch>`.

## Output

Report the PR URL, CI status, validation summary, merge result when applicable, updated branch, and any remaining risks.
