---
name: pr
description: Prepare, create, validate, and optionally merge a Pull Request. Use when the user says pr, /pr, $pr, pull request, PR作成, CI確認, merge, or asks to update the work branch after merge.
---

# PR

## Overview

Create and validate a pull request after implementation. Review is required under `$flow` or by repository policy; standalone `$pr` otherwise reports whether review was performed. This is the Codex equivalent of Claude Code's `/pr`.

Read `.agents/skills/flow/references/execution.md` for scope, Codex tool and model routing, delegation, and verification rules.

## Procedure

1. Read `.tarnished/workflows/pr.md`.
2. If present, read `.claude/skills/pr/SKILL.md` for compatibility details.
3. Parse arguments: default target branch is `develop`; merge only when the user passes `--merge` or explicitly requests merge.
   Resolve existing PRs for the repository, source, and target before creation. Reuse a unique open PR, report an already merged one, and clarify ambiguous or closed-unmerged matches. Validate review freshness using `.claude/skills/review/references/completion.md` when present; under `$flow`, refresh missing/stale review first. Standalone PR preparation discloses optional review not performed rather than claiming approval.
4. Check final readiness using existing review and verification results. Run missing required checks and checks affected by subsequent changes; scope cleanup to the issue. Delegate preparation to the `executor` role where a subagent mechanism is available.
5. Commit any final cleanup changes.
6. Push the branch to `origin`.
7. Have the executor return the PR draft with `Closes #<issue_number>` in the body, not the title. As orchestrator, read the draft and run `gh pr create --body-file <path>` yourself only when no matching PR exists. Reuse an existing PR; after an uncertain create result, query before retrying.
8. Monitor CI with `gh pr checks` or available GitHub connectors. Inspect logs before retrying failed jobs.
9. Fix CI or validation failures in follow-up commits, push, and re-check.
10. If merge was requested and validation passes for the current PR head, squash-merge with `--match-head-commit <validated_head>` and delete the source branch. The merge decision and the merge command are never delegated: a merge is irreversible.
11. Confirm the PR state is `MERGED`; queued/auto-merge is still pending. Then update the target with `git pull --ff-only origin <target_branch>` using the shared branch worktree rules, preserving unrelated edits.

## Output

Report the PR URL, CI status, validation summary, merge result when applicable, updated branch, and any remaining risks.
