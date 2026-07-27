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
4. Write the per-issue design delta under `docs/design/#{issue_number}/`.
5. Regenerate affected shared design snapshots under `docs/design/shared/`.
6. Commit design artifacts separately from implementation changes.

## Output

- `docs/design/#{issue_number}/design.md`
- `docs/design/#{issue_number}/workflow.md`
- Optional API, diagram, and research artifacts.
- Updated shared design snapshots when the issue changes project-wide truth.
