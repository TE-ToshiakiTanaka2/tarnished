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
3. Delegate implementation to the `executor`: small, reviewable changes that match existing conventions, committed per logical unit. Resolve routine implementation choices from repository evidence; return decisions that would change requirements or design intent as a blocked-result.
4. Run build, formatting, linting, and tests appropriate to the stack.
5. Apply quality improvements for correctness, error handling, security, and maintainability.
6. Review the result against both the design and the issue's Requirements. Send blocking findings back, capped at two rounds, then escalate.

## Output

- Implementation commits.
- Verification summary with commands run and any remaining risks.
- The review outcome, and whether implementation was delegated or run inline.
