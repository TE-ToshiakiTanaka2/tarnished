# Workflow: review

Request an independent second opinion on the current branch before PR creation.

## Inputs

- Current feature branch.
- Target branch (default `develop`).
- Merge base with the target branch.
- Commit history and diff.
- Design artifacts for the issue when available.

## Procedure

1. Detect the current branch, target branch, and merge base.
2. Extract the issue number from the branch name when possible.
3. Determine review scope from diff size and affected areas.
4. Resolve the reviewer in priority order:
   1. The configured review agent (`{{AI_REVIEW_AGENT}}`) when it is installed and distinct from the primary agent.
   2. An installed external review CLI (e.g. Codex).
   3. A fresh-context independent review by the primary agent itself (e.g. a read-only reviewer subagent), marked as a fallback review.
5. Review for correctness, security, edge cases, error handling, tests, performance, and architecture adherence to the design artifacts.
6. Save the full review output to `docs/review/#{issue_number}/review.md`, recording which reviewer produced it.
7. Fix critical and major findings, then append a fix summary to the review artifact.

## Output

- Review verdict: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
- Saved review artifact (with reviewer identity) and fix summary.
