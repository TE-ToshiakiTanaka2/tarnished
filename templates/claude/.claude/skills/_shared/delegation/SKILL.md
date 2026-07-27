---
name: _shared/delegation
description: Internal shared skill defining the role vocabulary and the work-routing table used across the lifecycle skills
---

# Shared Skill: Role Vocabulary and Work Routing

Internal reference that defines who executes what across the lifecycle. Referenced by `/issue`, `/design`, `/implement`, `/review`, `/pr`, and `/flow`.

**This skill is NOT directly invocable by users.** It is a reference document included by other skills.

Skills name **roles**, never models. A model name written into a skill cannot be changed by a downstream project without forking the file; a role can be rebound in one JSON object.

## Roles

| Role | Responsibility | Writes? |
| --- | --- | --- |
| `orchestrator` | Judgment: requirement scoping, architecture, interpreting design intent, review triage, refactor selection, merge decision | Yes |
| `executor` | Mechanical, high-volume work with an objective success condition | Yes |
| `external-reviewer` | Independent review from a different vendor or a fresh context | No |
| `advisor` | Read-only second opinion on a decision, before it is committed to | No |

## Role Binding

Bindings live in `.tarnished/agent-profile.json`:

```json
"roles": {
  "orchestrator":      { "agent": "primary", "model": null },
  "executor":          { "agent": "primary", "model": null },
  "advisor":           { "agent": "primary", "model": null },
  "external-reviewer": { "agent": "review",  "model": null, "reasoning_effort": null }
}
```

- `"primary"` and `"review"` are indirections to the sibling `primary_agent` / `review_agent` fields.
- `model: null` means "use that agent's configured default". A project that wants a specific model per role sets it here.
- This file is not refresh-managed, so a downstream edit survives every container start.

**Resolution and fallback** — apply this in every consumer:

| Condition | Behavior |
| --- | --- |
| `roles` key absent (project predates it) | Bind every role to the primary agent; `external-reviewer` to `review_agent` |
| A value still contains an unrendered `{{...}}` token | Treat as absent |
| Unknown role key present | Ignore it; do not error |

Report which of the two paths was taken when a stage's output names a role.

## Routing: by nature of work, not by stage

Route work **before** attempting it. A stage is not a routing unit — most stages contain both kinds of work, and delegating a whole stage bundles judgment into a mechanical unit.

| Nature | Examples | Role | Execution |
| --- | --- | --- | --- |
| Judgment | Interpreting design intent; matching existing patterns; deciding what counts as a finding; choosing a behavior-preserving refactor; review triage; merge decision; scoping an issue | `orchestrator` | Inline |
| Mechanical | Repository survey / indexing; lint, format, and type-check fix loops; boilerplate test authoring; dead-code cleanup; CI log collection; bulk mechanical edits across many files | `executor` | Delegated |
| Independent verification | Reviewing the branch diff against the design | `external-reviewer` | Separate vendor or fresh context |
| Second opinion | Challenging an architecture; breaking a triage tie; sanity-checking scope | `advisor` | Read-only, bounded |

Worked examples of stages that split:

- `erd:implement` — interpreting the design and matching existing conventions is judgment and stays inline; a mechanical sweep applying an already-decided change across many files is delegated.
- `erd:analyze` / `erd:improve` — deciding what counts as a finding and which refactor preserves behavior is judgment; running the analyzers and collecting their output is mechanical.
- `erd:build` / `erd:test` — the fix loop is mechanical; deciding that a failing test encodes the wrong expectation is judgment.

## Escalation

Route by nature up front rather than delegating first and escalating on failure.

- Retry budgets exist **only** for mechanical steps, and **only** for command-level failure — "the command errored", not "the model misjudged".
- When a mechanical step exhausts its budget, the orchestrator takes over. The failure is by then no longer mechanical.
- Judgment work is never retried on the theory that a second attempt lands better. If a judgment turns out wrong, the orchestrator re-decides with the new information.

## Advisor invocation points

Bounded to three points, at most one consult each per run. Each has a mechanical trigger — an unbounded "consult when unsure" becomes consulting on everything.

| Point | Trigger | Question put to the advisor |
| --- | --- | --- |
| `/design`, before authoring `design.md` | Estimated size is M or larger | Challenge the chosen architecture with an alternative |
| `/flow`, review triage | The orchestrator intends to **not** fix a Critical or Major finding | Is deferring this defensible? |
| `/issue`, after the requirements summary | Scope is still ambiguous | Is the scope right-sized? |

The advisor is defined in `.claude/agents/advisor.md`. It is read-only and never writes, stages, or commits. Its output is advice; the orchestrator still decides and still owns the outcome.

Skip the consult, without failing the stage, when the advisor definition is absent or when the primary agent has no read-only subagent mechanism (for example a Codex-primary profile). Note the skip in the stage's report.
