# Shared Agent Workflows

This directory is the canonical workflow source for `{{PROJECT_NAME}}`.

Generated agent entrypoints (`CLAUDE.md`, `.claude/skills/*`, `.claude/commands/erd/*`, `AGENTS.md`, and `.codex/*`) should preserve the behavior described here. Tool-specific files may adapt invocation syntax, but should not fork the lifecycle semantics.

## Agent Profile

- **Profile**: `{{AI_PROFILE}}`
- **Primary agent**: `{{AI_PRIMARY_AGENT}}`
- **Review agent**: `{{AI_REVIEW_AGENT}}`

## Lifecycle

1. `issue` - discover requirements, estimate scope, and create a GitHub Issue.
2. `design` - create or update design artifacts before implementation.
3. `implement` - implement the issue in focused commits.
4. `review` - hand off the branch to an independent reviewer.
5. `pr` - clean up, create a pull request, validate CI, and optionally merge.

## Shared Artifacts

- `docs/design/shared/` stores cumulative project truth.
- `docs/design/#{issue_number}/` stores per-issue design deltas.
- `docs/review/#{issue_number}/review.md` stores independent review output and applied-fix summaries.

## ERD Command Source

The detailed command behavior is projected into both `.tarnished/workflows/erd/*` and `.claude/commands/erd/*`. Codex-facing instructions should reference `.tarnished/workflows/erd/*`; Claude Code slash commands may use `.claude/commands/erd/*`.
