# Shared Agent Workflows

This directory holds the agent-neutral lifecycle contracts for `{{PROJECT_NAME}}`.

## Source-of-truth graph

The lifecycle is expressed at three altitude levels. Each level has a distinct job — they are projections of one another, not competing sources:

| Level | Location | Role |
| --- | --- | --- |
| **Contract** | `.tarnished/workflows/{issue,design,implement,review,pr,flow}.md` | Agent-neutral inputs/procedure/outputs per stage. Tool-specific entrypoints must preserve these semantics. |
| **Operational spec** | `.claude/skills/*/SKILL.md` | The detailed, executable procedure (phases, branch/commit/PR contracts, artifact destinations, reporting contracts). This is where behavior is authored. |
| **Codex projection** | `.agents/skills/*/SKILL.md` | Thin pointers that read the contract and the operational spec, translating Claude-specific tool references for Codex. |

Detailed sub-step behavior lives in the erd command docs. `.claude/commands/erd/*` is the authored copy; `.tarnished/workflows/erd/*` is a byte-identical projection for Codex-facing instructions (generated at scaffold time and kept current by `refresh-assets.sh` for projects whose `.tarnished/refresh.json` includes the `.tarnished/workflows/erd` and `.claude/agents` managed paths — projects scaffolded earlier must adopt those entries once from `templates/agent-workflows/.tarnished/refresh.json`).

When editing any level, keep the others aligned in the same commit. Upstream tarnished enforces byte-identity of its own mirrored template trees in CI; a scaffolded project carries no equivalent check, so alignment here is the author's responsibility.

## Agent Profile

- **Profile**: `{{AI_PROFILE}}`
- **Primary agent**: `{{AI_PRIMARY_AGENT}}`
- **Review agent**: `{{AI_REVIEW_AGENT}}`

## Roles

Workflows name roles, never models, so a project can retarget models without editing workflow or skill files.

| Role | Execution | Responsibility |
| --- | --- | --- |
| `orchestrator` | Inline — it **is** the main session | Requirements dialogue, issue authoring, review of every delegated artifact, review triage, merge decision, escalation to the user |
| `designer` | Delegated subagent | Design artifacts, once the specification is settled |
| `executor` | Delegated subagent | Implementation, review-fix application, PR authoring and CI monitoring |
| `external-reviewer` | Separate vendor CLI or a fresh context | Independent review of the branch diff |

Role bindings live in `.tarnished/agent-profile.json` under `roles`, which is the single authoritative place. When that key is absent — a project scaffolded before it shipped — every role binds to the primary agent and `external-reviewer` binds to the review agent.

Each stage's **authoring** has one owner and the orchestrator reviews rather than co-authors; a delegated subagent routes its own internal work. This replaces the earlier rule that routed work by nature *within* a stage.

| Stage | Writes | Reviews |
| --- | --- | --- |
| `issue` | `orchestrator` | the user, through the requirements dialogue |
| `design` | `designer` | `orchestrator`, against the issue's Requirements |
| `implement` | `executor` | `orchestrator`, against the design |
| `review` | `external-reviewer` | `orchestrator` triages; `executor` applies the fixes |
| `pr` | `executor` drafts the body and monitors CI; `orchestrator` creates the PR | `orchestrator` checks the content and owns the merge decision |

The orchestrator handles user decisions. `designer` and `executor` resolve routine choices within accepted requirements using repository evidence. A missing decision that changes scope, public behavior, design intent, or authority returns a **blocked-result** with the question, options, checked evidence, and completed independent work.

Delegation requires a primary agent that can run subagents. Where it cannot, every stage runs inline under the primary agent and the report says so; the procedure is unchanged, and what is lost is the model separation between roles.

The routing table, the model binding per role, and the blocked-result contract are specified in `.claude/skills/_shared/delegation/SKILL.md`. Where this contract and the skills disagree, the skills are authoritative: `.claude/skills/` and `.claude/agents/` are refresh-managed while this directory is not, so a project can be running current skills against a stale contract.

## Lifecycle

1. `issue` - discover requirements, estimate scope, and create a GitHub Issue.
2. `design` - create or update design artifacts before implementation.
3. `implement` - implement the issue in focused commits.
4. `review` - obtain an independent review of the branch (configured review agent, external review CLI, or a fresh-context fallback review).
5. `pr` - clean up, create a pull request, validate CI, and optionally merge.

`flow` runs these stages end to end for one issue, entering at the first incomplete stage. It is an orchestration entrypoint over the five stages, not a sixth stage.

## Shared Artifacts

- `docs/design/shared/` stores cumulative project truth.
- `docs/design/#{issue_number}/` stores per-issue design deltas.
- `docs/review/#{issue_number}/review.md` stores independent review output and applied-fix summaries.
