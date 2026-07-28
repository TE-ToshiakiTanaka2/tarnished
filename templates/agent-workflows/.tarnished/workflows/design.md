# Workflow: design

Design the implementation for a GitHub Issue before writing production code.

## Inputs

- GitHub Issue number.
- Base branch, defaulting to `develop`, used for branch creation.
- Existing shared design artifacts under `docs/design/shared/`.
- Relevant codebase context.

## Procedure

1. Read the issue and create or reuse the issue branch, cutting new branches from the requested base.
2. Load shared design artifacts and relevant per-issue artifacts.
3. Research external dependencies only when needed.
4. Delegate authoring to the `designer`: the per-issue design delta under `docs/design/#{issue_number}/`, and the regenerated shared snapshots under `docs/design/shared/`. A blocked-result comes back unanswered rather than guessed.
5. Review the returned artifacts against the issue's Requirements. Send blocking findings back, capped at two rounds, then escalate.
6. Commit design artifacts separately from implementation changes — **after** the review, so the commit records that the review happened. Record the findings in `docs/design/#{issue_number}/orchestrator-review.md`.

## Output

- `docs/design/#{issue_number}/design.md`
- `docs/design/#{issue_number}/workflow.md`
- Optional API, diagram, and research artifacts.
- `docs/design/#{issue_number}/orchestrator-review.md` — the review's findings, as an audit trail.
- Updated shared design snapshots when the issue changes project-wide truth.
