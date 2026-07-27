# Workflow: implement

Implement a GitHub Issue using the design artifacts and existing project conventions.

## Inputs

- GitHub Issue number.
- Base branch, defaulting to `develop`, used when a branch has to be created.
- Shared and per-issue design artifacts.
- Current branch or branch derived from the issue.

## Procedure

1. Load issue details and design artifacts.
2. Index or inspect the relevant code paths before editing.
3. Implement in small, reviewable changes that match existing conventions.
4. Run build, formatting, linting, and tests appropriate to the stack.
5. Apply quality improvements for correctness, error handling, security, and maintainability.
6. Commit per logical unit of work.

## Output

- Implementation commits.
- Verification summary with commands run and any remaining risks.
