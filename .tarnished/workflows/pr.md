# Workflow: pr

Prepare and create a pull request after implementation. Independent review is a prerequisite under `flow` or when repository policy requires it; standalone `pr` otherwise reports whether review was performed.

## Inputs

- Current feature branch.
- Target branch, defaulting to `develop`.
- Issue number and review artifact when available.

## Procedure

Before preparation, resolve existing PRs for the repository, source, and target. Reuse a unique open PR; report a merged one, and request direction for ambiguous or closed-unmerged matches. Re-query after uncertain creation outcomes. Check review freshness against current code, target commit, and issue body using `.claude/skills/review/references/completion.md` when available. Under `flow`, finish missing or stale review first; standalone `pr` discloses optional review not performed and respects any repository review requirement.

1. Check final readiness against existing review and verification results. Run missing required checks and those affected by subsequent changes; keep cleanup within the issue scope. Delegate preparation to the `executor`.
2. Push the branch to `origin`.
3. The executor returns a PR draft with a conventional-commit title and `Closes #<issue_number>` in the body. The orchestrator reads it and creates the PR only when none exists, using a structured body argument or `--body-file`.
4. Monitor CI and inspect failed logs before retrying.
5. Fix failures in follow-up commits and re-run affected validation, including review evidence changed by the fixes.
6. Merge only when requested and when CI plus applicable review validation pass for the current PR head; bind the merge with `--match-head-commit <validated_head>`. The merge decision and the merge command are the orchestrator's; a merge is irreversible and is never delegated to the stage's writing agent.
7. Confirm GitHub reports `MERGED`; a queued/auto-merge request is still pending. Then update the target with `git pull --ff-only origin <target_branch>`, applying shared branch worktree rules to preserve unrelated edits.

## Output

- PR URL.
- CI and validation summary.
- Merge result when auto-merge was requested.
