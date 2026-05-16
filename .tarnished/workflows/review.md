# Workflow: review

Request an independent second opinion on the current branch before PR creation.

## Inputs

- Current feature branch.
- Merge base with `develop`.
- Commit history and diff.
- Design artifacts for the issue when available.

## Procedure

1. Detect the current branch and merge base.
2. Extract the issue number from the branch name when possible.
3. Determine review scope from diff size and affected areas.
4. Ask the configured review agent (`{{AI_REVIEW_AGENT}}`) to review for correctness, security, edge cases, error handling, tests, performance, and architecture.
5. Save the full review output to `docs/review/#{issue_number}/review.md`.
6. Fix critical and major findings, then append a fix summary to the review artifact.

## Output

- Review verdict: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
- Saved review artifact and fix summary.
