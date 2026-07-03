# Shared Agent Workflows

This directory holds the agent-neutral lifecycle contracts for `{{PROJECT_NAME}}`.

## Source-of-truth graph

The lifecycle is expressed at three altitude levels. Each level has a distinct job — they are projections of one another, not competing sources:

| Level | Location | Role |
| --- | --- | --- |
| **Contract** | `.tarnished/workflows/{issue,design,implement,review,pr}.md` | Agent-neutral inputs/procedure/outputs per stage. Tool-specific entrypoints must preserve these semantics. |
| **Operational spec** | `.claude/skills/*/SKILL.md` | The detailed, executable procedure (phases, branch/commit/PR contracts, artifact destinations, output templates). This is where behavior is authored. |
| **Codex projection** | `.agents/skills/*/SKILL.md` | Thin pointers that read the contract and the operational spec, translating Claude-specific tool references for Codex. |

Detailed sub-step behavior lives in the erd command docs. `.claude/commands/erd/*` is the authored copy; `.tarnished/workflows/erd/*` is a byte-identical projection for Codex-facing instructions (generated at scaffold time and kept current by `refresh-assets.sh` for projects whose `.tarnished/refresh.json` includes the `.tarnished/workflows/erd` and `.claude/agents` managed paths — projects scaffolded earlier must adopt those entries once from `templates/agent-workflows/.tarnished/refresh.json`).

When editing any level, keep the others aligned in the same commit. Byte-identity of all mirrored trees is enforced by `scripts/verify-mirrors.sh` (CI: `asset-parity.yml`).

## Agent Profile

- **Profile**: `{{AI_PROFILE}}`
- **Primary agent**: `{{AI_PRIMARY_AGENT}}`
- **Review agent**: `{{AI_REVIEW_AGENT}}`

## Lifecycle

1. `issue` - discover requirements, estimate scope, and create a GitHub Issue.
2. `design` - create or update design artifacts before implementation.
3. `implement` - implement the issue in focused commits.
4. `review` - obtain an independent review of the branch (configured review agent, external review CLI, or a fresh-context fallback review).
5. `pr` - clean up, create a pull request, validate CI, and optionally merge.

## Shared Artifacts

- `docs/design/shared/` stores cumulative project truth.
- `docs/design/#{issue_number}/` stores per-issue design deltas.
- `docs/review/#{issue_number}/review.md` stores independent review output and applied-fix summaries.
