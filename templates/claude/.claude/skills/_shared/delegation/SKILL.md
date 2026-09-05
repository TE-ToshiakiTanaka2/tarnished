---
name: _shared/delegation
description: Internal shared skill defining the role vocabulary, stage ownership, model binding, and the subagent escalation protocol used across the lifecycle skills
---

# Shared Skill: Roles, Stage Ownership, and Escalation

Internal reference that defines who executes what across the lifecycle. Referenced by `/issue`, `/design`, `/implement`, `/review`, `/pr`, and `/flow`.

**This skill is NOT directly invocable by users.** It is a reference document included by other skills.

Skills name **roles**, never models. A model name written into a skill cannot be changed by a downstream project without forking the file; a role can be rebound in one place.

User instructions and existing authorization take precedence over this procedural guidance, subject to system, developer, and tool restrictions. Do not introduce approval gates for routine choices within the accepted scope. If a skill requires a pause, identify the exact instruction and the missing decision or capability.

Where this file disagrees with `.tarnished/workflows/*.md` or `.agents/skills/*/SKILL.md`, this file is authoritative. `.claude/skills/` and `.claude/agents/` are refresh-managed; `.tarnished/workflows/` and `.agents/` are not. A project can therefore be running current skills against both a stale contract and a stale Codex projection, and the two stale altitudes can disagree with each other as well — resolve every such conflict here.

## Roles

| Role | Execution | Responsibility | Writes? |
| --- | --- | --- | --- |
| `orchestrator` | Inline — it **is** the main session | Requirements dialogue, issue authoring, review of every delegated artifact, review triage, merge decision, escalation to the user | Yes |
| `designer` | Delegated subagent | Design artifacts, once the specification is settled | Yes |
| `executor` | Delegated subagent | Implementation, review-fix application, PR authoring and CI monitoring | Yes |
| `external-reviewer` | Separate vendor CLI or a fresh context | Independent review of the branch diff | No |

The orchestrator is the only role that can interact with the user. Everything that needs an answer from the user reaches them through it.

## Stage ownership

| Stage | Writes | Reviews |
| --- | --- | --- |
| `issue` | `orchestrator` | the user, through the requirements dialogue |
| `design` | `designer` | `orchestrator`, against the issue's Requirements |
| `implement` | `executor` | `orchestrator`, against the design |
| `review` | `external-reviewer` | `orchestrator` triages; `executor` applies the fixes |
| `pr` | `executor` drafts the body and monitors CI; `orchestrator` creates the PR | `orchestrator` checks the content and owns the merge decision |

**Route by stage authorship, not by the nature of each unit of work.** Each stage's authoring has one owner and the orchestrator reviews rather than co-authors. Within a delegated stage, the subagent routes its own internal work. This replaces the earlier rule that routed work by nature *within* a stage so that a stage could be part-inline and part-delegated; that rule assumed the orchestrator was the only capable writer, and it produced stages with no single accountable author.

The executor returns the drafted PR body. The orchestrator checks it and runs the authorized PR creation command. It also owns the merge decision and command; merging requires the user's explicit request or `--merge`.

## Model binding

Each role's model comes from its dispatch channel. The table below describes Claude-primary dispatch. For Codex-native designer/executor dispatch, use a supported `roles.<role>.model` override when present; otherwise inherit the active Codex session model and reasoning effort. Claude agent frontmatter pins are not Codex model IDs. The Codex session default lives in `.codex/config.toml`; the external reviewer always uses its own CLI config. Report unsupported explicit overrides rather than silently substituting another model.

| Role | Channel | Value |
| --- | --- | --- |
| `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5` |
| `designer` | `.claude/agents/designer.md` frontmatter | `claude-opus-5[1m]` |
| `executor` | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5` |
| `external-reviewer` | `.codex/config.toml` | reviewer-owned |

The orchestrator is the session rather than a subagent, so no frontmatter channel reaches it; `.claude/settings.json :: model` is its only channel and is read once at session start.

For Claude-dispatched designer and executor roles the precedence is:

| # | Source | Notes |
| --- | --- | --- |
| 1 | `roles.<role>.model` in `.tarnished/agent-profile.json` | Downstream override. Not refresh-managed, so it survives every container start |
| 2 | `model:` in the agent definition frontmatter | The shipped default. `.claude/agents/` is refresh-managed, so it reaches every project on the next start |
| 3 | `inherit` — the session's model | What applies when neither above names a model. This was the state of every role before the models were pinned |

`roles.<role>.model` ships as `null` for every role: the profile answers *which agent*, and the model comes from the channel above. Values are pinned model IDs rather than aliases, because an alias silently re-points at a new generation; bumping a pin is a tracked edit to one file.

## Role Binding

Bindings live in `.tarnished/agent-profile.json`:

```json
"roles": {
  "orchestrator":      { "agent": "primary", "model": null },
  "designer":          { "agent": "primary", "model": null },
  "executor":          { "agent": "primary", "model": null },
  "external-reviewer": { "agent": "review" }
}
```

`external-reviewer` carries no `model` key: its model and reasoning effort come from the reviewer CLI's own config, which is their single source.

- `"primary"` and `"review"` are indirections to the sibling `primary_agent` / `review_agent` fields.
- This file is not refresh-managed, so a downstream edit survives every container start.

**Resolution and fallback** — apply this in every consumer:

| Condition | Behavior |
| --- | --- |
| `roles` key absent (project predates it) | Bind every role to the primary agent; `external-reviewer` to `review_agent` |
| `roles` present but a role this policy names is **missing** from it | Bind that role as if `roles` were absent — to the primary agent, or to `review_agent` for `external-reviewer`. Resolve per role, never all-or-nothing |
| A value still contains an unrendered `{{...}}` token | Treat as absent |
| Unknown role key present (e.g. a retired `advisor` entry) | Ignore it; do not error |

The missing-key row is not hypothetical: a project scaffolded before `designer` existed carries a `roles` map with `advisor` and no `designer`, so an all-or-nothing fallback keyed on the *object* would leave `designer` unresolved while the map itself is present. Resolution is per role for that reason.

Report which path was taken when a stage's output names a role.

## Delegation and the blocked-result protocol

`designer` and `executor` route user decisions through the orchestrator. Resolve routine reversible choices from the issue, design, codebase, and accepted decisions supplied by the orchestrator. Return a blocked-result when a missing answer changes requirements, public behavior, design intent, or authority, or when a required prerequisite cannot be recovered within the assigned scope. Complete independent authorized work before returning partial results.

| Field | Required | Purpose |
| --- | --- | --- |
| Question | Yes | What could not be resolved, stated as a question |
| Options | Yes | The readings or approaches visible, and what each implies |
| Evidence checked | Yes | Issue, artifacts, and code paths already consulted |
| Partial work | No | What was completed before the block, so it is not redone |

"Evidence checked" is required rather than courteous: it is what distinguishes a genuine block from a question the subagent did not try to answer.

| Trigger | Definition |
| --- | --- |
| Requirement-level ambiguity | Two readings of an acceptance criterion that produce different interfaces |
| Design/convention conflict | Following the local convention would violate a required design behavior or constraint |
| Missing prerequisite | A required artifact is absent and cannot be recovered from available history or inputs within the assigned scope |

On receiving a blocked-result the orchestrator answers it and re-dispatches, or escalates to the user when the answer is the user's to give. A subagent that guesses past an ambiguity is the failure this protocol exists to prevent, and it is why delegating the two highest-judgment stages is defensible.

## Review of delegated work

The orchestrator reviews each delegated artifact before it is committed or built on:

- **Design** — against the issue's Requirements. The order is **write → review → commit**, and the orchestrator performs the commit. Because the commit follows the review, the commit itself records that the review happened; no separate approval artifact is needed.
- **Implementation** — against both the design and the issue's Requirements.
- **Review findings** — triaged by the orchestrator; fixes applied by the executor.

A blocking finding sends the artifact back to its author, and the orchestrator **re-reviews whatever comes back** — a return that is not re-reviewed is not a review loop. The count is of *return* rounds: the first review is round 0, the first send-back and its re-review is round 1, and the second is round 2. At most **2 returns**; a blocking finding still present after the second re-review is escalated to the user with the finding and what was attempted. Reaching the cap is always reported, never passed over silently.

## Triage policy

| Severity | Policy |
| --- | --- |
| **Critical** | Must fix before the PR. Not deferrable — no rationale clears it |
| **Major** | Must fix before the PR, unless deferred with a rationale recorded in the review artifact |
| **Minor** | Fix when cheap, otherwise record |
| **Suggestions** | Discuss; no obligation |

The full taxonomy and the review criteria are defined in `.claude/skills/review/SKILL.md`, which is their canonical source.

## Retries

Retry budgets exist **only** for mechanical steps, and **only** for command-level failure — "the command errored", not "the model misjudged". When a mechanical step exhausts its budget, the orchestrator takes over; the failure is by then no longer mechanical. A judgment is never retried on the theory that a second attempt lands better — if a judgment turns out wrong, the orchestrator re-decides with the new information.

## Capability fallback

Delegation requires a primary agent that can run subagents. Where the current runtime cannot delegate, or delegation is prohibited, **every stage runs inline under the primary agent**, and the stage report records that delegation was unavailable. The lifecycle stays functional rather than degrading quietly; what is lost is the model separation between roles, not any step of the procedure.
