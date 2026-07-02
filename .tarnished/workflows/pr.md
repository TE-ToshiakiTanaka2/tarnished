# Workflow: pr

Prepare and create a pull request after implementation and independent review.

## Inputs

- Current feature branch.
- Target branch, defaulting to `develop`.
- Issue number and review artifact when available.

## Procedure

1. Run final analysis, improvements, cleanup, build, and tests.
2. Push the branch to `origin`.
3. Create a PR with a conventional-commit title and `Closes #<issue_number>` in the body.
4. Monitor CI and inspect failed logs before retrying.
5. Fix failures in follow-up commits and re-run validation.
6. Merge only when requested and when CI plus review validation pass.
7. After a successful merge, switch to the target branch and update it with `git pull --ff-only origin <target_branch>`.

## Output

- PR URL.
- CI and validation summary.
- Merge result when auto-merge was requested.
