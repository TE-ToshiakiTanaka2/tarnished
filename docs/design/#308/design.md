# Design: #308 Rebase workflow skills on an Opus 5-class model policy

## Context

The AI lifecycle assets live at three altitudes, documented in `.tarnished/workflows/README.md`:

| Level | Location | Role |
| --- | --- | --- |
| Contract | `.tarnished/workflows/{issue,design,implement,review,pr}.md` | Agent-neutral per-stage semantics |
| Operational spec | `.claude/skills/*/SKILL.md` | Where behavior is authored |
| Codex projection | `.agents/skills/*/SKILL.md` | Thin pointers for Codex |

Two distribution channels carry them downstream, and they behave differently:

- **Refresh-managed** (`.tarnished/refresh.json :: managed_paths`): `.claude/{commands,skills,scripts,agents}`, `.claude/rules/shell.md`, `.tarnished/workflows/erd`. Re-synced from upstream `develop` on **every container start**; user overrides live in `.local/` sidecars.
- **Manifest-tracked** (`.tarnished-manifest.json` + `setup.sh --upgrade`): everything else copied verbatim, including `.tarnished/agent-profile.json` and `.tarnished/workflows/*.md`. Updated only when a user runs `--upgrade`.

Byte-identity between each workspace tree and its `templates/` mirror is enforced by `scripts/verify-mirrors.sh` (CI: `.github/workflows/asset-parity.yml`). Both are **upstream-only** — a scaffolded project has neither.

This issue is an audit of the lifecycle assets against an Opus-5-class primary agent, spanning four problem classes: real bugs and dead references, model-delegation policy, harness drift, and prompt over-prescription.

## Architecture Overview (delta)

Five structural moves, plus a prerequisite bug fix.

1. **Role vocabulary replaces model names.** Skills name four roles — `orchestrator`, `executor`, `external-reviewer`, `advisor`. Role→agent/model binding lives in one machine-readable place, `.tarnished/agent-profile.json :: roles`.
2. **A new `_shared/delegation` skill owns the routing table**, keyed by *nature of work* rather than by lifecycle stage. It sits in the refresh-managed channel so it updates in lockstep with the skills that consume it.
3. **A new `advisor` agent** provides a read-only second opinion at three bounded, mechanically-triggered points.
4. **A new `/flow` skill** binds the lifecycle stages into one run, with stage state derived from repository evidence rather than a state file.
5. **Review criteria and severity taxonomy are single-sourced** at the point where the reviewer prompt is *constructed*, not behind a path reference.

### Prerequisite: `--upgrade` does not render placeholders

`replace_placeholders` (`scripts/lib/common.sh:711`) is called exactly once, at the end of scaffold (`setup.sh:2533`). The upgrade staging run (`stage_plugin_run`, `setup.sh:1832`) re-runs every plugin copy into a staging tree but never renders. `manifest_decide` then compares:

- `old_hash` — the **rendered** file, hashed at scaffold end
- `current_hash` — the rendered, unedited downstream file → `current == old`
- `new_hash` — the **unrendered** staging copy

`current == old && new != old` → `UPDATE` → the unrendered file is written over the rendered one.

Most placeholder-bearing files escape this because they are in `MANIFEST_EXCLUDE_GLOBS` (`CLAUDE.md`, `AGENTS.md`, `README.md`, `docker-compose.yml`, `.devcontainer/devcontainer.json`). The exposed set is exactly the seven files this issue must edit:

```
.tarnished/agent-profile.json
.tarnished/workflows/{README,issue,design,implement,review,pr}.md
```

Any content change upstream detonates it. `/review`'s reviewer resolution already defends against "contains unrendered `{{...}}` placeholders" (`review/SKILL.md:54`) — evidence the failure mode occurs in the wild.

This is a pre-existing bug outside #308's task list, but #308 cannot land §1-2 or §2-1 without triggering it. It is therefore fixed here as a prerequisite, scoped to rendering the staging tree.

## Module Structure (delta)

```
.claude/
├── agents/
│   ├── code-reviewer.md              # criteria restatement removed (4-5)
│   └── advisor.md                    # NEW — read-only decision advisor (2-2)
└── skills/
    ├── _shared/
    │   ├── branch/SKILL.md           # base parameter (1-1); anchored grep (1-3)
    │   └── delegation/SKILL.md       # NEW — role routing table (2-1, 2-3, 2-4)
    ├── flow/SKILL.md                 # NEW — lifecycle orchestration (D4)
    ├── issue/SKILL.md                # priority notation (1-6); structured questions (3-2)
    ├── design/SKILL.md               # base pass-through; diagram quotas removed (4-3)
    ├── implement/SKILL.md            # pipeline + skip conditions (4-2)
    ├── review/SKILL.md               # canonical criteria + taxonomy (4-5); model recording (2-5)
    └── pr/SKILL.md                   # argument-hint (1-7); CI wait ownership (3-3)

.tarnished/
├── agent-profile.json                # roles object (2-1)
└── workflows/
    ├── README.md                     # role vocabulary; CI-enforcement claim corrected (1-2)
    └── flow.md                       # NEW — flow contract

.agents/skills/flow/                  # NEW — Codex projection (1-8)
├── SKILL.md
└── agents/openai.yaml

.codex/config.toml                    # gpt-5.6-sol / ultra
scripts/verify-mirrors.sh             # flow pairs added
setup.sh                              # staging placeholder rendering (prerequisite)
.github/workflows/claude-code-review.yml   # taxonomy unified (4-5)
```

Every `.claude/`, `.agents/`, `.codex/`, and `.tarnished/` path above has a `templates/` mirror that must change in the same commit.

## Interface Design (delta)

### `agent-profile.json :: roles` (2-1)

```json
{
  "roles": {
    "orchestrator":      { "agent": "primary", "model": null },
    "executor":          { "agent": "primary", "model": null },
    "advisor":           { "agent": "primary", "model": null },
    "external-reviewer": { "agent": "review",  "model": null, "reasoning_effort": null }
  }
}
```

`"primary"` / `"review"` are indirections to the sibling `primary_agent` / `review_agent` fields. `null` means "use that agent's configured default".

**The values are deliberately not `{{AI_PRIMARY_AGENT}}` placeholders.** Those render to human display strings — `"Claude Code + Codex CLI"`, `"Manual review"` (`setup.sh:1223-1240`) — which are not dispatchable, and they would be re-poisoned by any future upgrade. Keeping `roles` placeholder-free also keeps this file inert with respect to `replace_placeholders`' hard-coded file list.

**Resolution contract** (every consumer implements the same fallback):

| Condition | Behavior |
| --- | --- |
| `roles` absent (project scaffolded before this change) | All roles bind to the primary agent; `external-reviewer` binds to `review_agent` |
| Field contains unrendered `{{...}}` | Treated as absent |
| `agent` is `"primary"` / `"review"` | Resolve through `primary_agent` / `review_agent` |
| `model` is `null` | Use the agent's own default |

`roles` is not refresh-managed, so a downstream edit survives every container start — which is the property that lets a project retarget models without forking skill files.

### `_shared/branch` base parameter (1-1)

| Parameter | Required | Default | Description |
| --- | --- | --- | --- |
| `issue_number` | Yes | — | GitHub Issue number |
| `base` | No | `develop` | Branch that new branches are cut from and pulled |

`/design`, `/implement`, and `/flow` accept `--base <branch>` and pass it through. When no branch exists for the issue, the procedure runs `git checkout <base> && git pull origin <base>` instead of hardcoded `develop`. The "preserve artifacts from an existing branch" path also branches from `<base>`.

### `/flow` arguments

```
/flow [--issue N] [--base <branch>] [--from <stage>] [--merge]
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `--issue N` | — | Issue to run. Absent → ask via structured question, or infer from the current branch |
| `--base <branch>` | `develop` | Threaded to branch creation, review diff base, and PR target — one value end to end |
| `--from <stage>` | derived | Force entry at `issue`/`design`/`implement`/`review`/`pr` |
| `--merge` | off | Forwarded to `/pr` |

### Review artifact metadata (2-5)

The header gains the resolved reviewer identity:

```
- **Reviewer**: Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra)
```

Resolved by reading `model` and `model_reasoning_effort` from `.codex/config.toml` at review time; unset values are recorded as `default`. This makes a config change visible in the artifact instead of silently changing review quality.

## Data Flow

### Stage state is derived, not stored

`/flow` determines the entry stage from repository evidence rather than a state file. A state file goes stale, survives failed runs, and needs cleanup; repository evidence is authoritative and survives context loss.

| Evidence | Implies completed |
| --- | --- |
| Issue branch exists (`#<n>/` anchored match) | `issue` |
| Commit `docs: add design documents for #<n>` reachable from HEAD | `design` |
| Commits beyond the design commit | `implement` |
| `docs/review/#<n>/review.md` exists | `review` |
| `gh pr list --head <branch>` non-empty | `pr` |

`--from <stage>` overrides the derivation. See [flowchart.md](./flowchart.md).

### Delegation routing (2-3, 2-4)

Work is routed by nature **before** it is attempted, not escalated after a delegate fails:

| Nature | Examples | Role | Execution |
| --- | --- | --- | --- |
| Judgment | design intent, pattern matching, review triage, refactor selection, merge decision, scope | `orchestrator` | Inline |
| Mechanical | repo survey, lint/format/type fix loops, boilerplate tests, cleanup, CI log collection | `executor` | Delegated |
| Independent verification | branch review | `external-reviewer` | Separate vendor/context |
| Second opinion | architecture challenge, triage tie-break, scope sanity check | `advisor` | Read-only, bounded |

The old policy delegated whole stages (`erd:implement` → executor; `erd:analyze`/`erd:improve` → executor), which bundled the highest-judgment work in the lifecycle into a delegated unit. Splitting by nature lets a single stage be part-inline and part-delegated.

Retry budgets survive only for mechanical steps, and only for command-level failure — "the command errored", never "the model misjudged". A judgment step that goes wrong is re-decided by the orchestrator, not retried.

### Advisor invocation points (2-2)

Bounded to three points, at most one consult each per run, each with a mechanical trigger so "consult when unsure" cannot degenerate into consulting on everything:

| Point | Trigger | Question |
| --- | --- | --- |
| `/design`, before authoring `design.md` | Estimated size is M or larger | Challenge the chosen architecture with an alternative |
| `/flow`, review triage | The orchestrator intends to **not** fix a Critical or Major finding | Is deferring this defensible? |
| `/issue`, after brainstorm | Scope still ambiguous after the requirements summary | Is the scope right-sized? |

The advisor is read-only and never writes, stages, or commits. Its output is advice; the orchestrator still decides.

**Capability gate**: the contract states these points apply when the primary agent supports read-only subagents. Under the `codex-main` profile the primary agent has no subagent mechanism, so the points are skipped rather than silently unhonored.

### Review criteria single-sourcing (4-5)

The canonical criteria list and the severity taxonomy live in **`.claude/skills/review/SKILL.md`'s Review Prompt Template** — the point where the reviewer prompt is constructed.

Reference-by-path was rejected: `codex exec` receives its criteria inline in a piped prompt inside a read-only sandbox, and the CI reviewer receives them inline in workflow YAML. Replacing an inline list with a path bets that an external reviewer chases a file mid-review, which silently degrades the review.

| Consumer | How it gets the criteria |
| --- | --- |
| `codex exec` (Phase 3A) | Inlined into the piped prompt |
| `code-reviewer` subagent (Phase 3C) | Inlined into the task prompt; falls back to reading `review/SKILL.md` if absent |
| `.claude/agents/code-reviewer.md` | Restatement removed; points at the invoking prompt, then `review/SKILL.md` |
| `AGENTS.md` (Codex root prompt) | Keeps a compressed self-sufficient list — no prompt is ever piped in an ad-hoc Codex session |
| `.github/workflows/claude-code-review.yml` | Inlined in YAML; taxonomy corrected to four levels |
| `.tarnished/workflows/review.md` | One-line prose enumeration only — correct contract altitude |

Severity unifies on the four-level taxonomy, which is strictly more expressive than Claude-side `Critical / Warnings / Suggestions`:

| Severity | Fix policy |
| --- | --- |
| Critical | Must fix before PR |
| Major | Must fix before PR, unless explicitly deferred with a recorded rationale |
| Minor | Fix when cheap; otherwise record |
| Suggestions | Discuss; no obligation |

Unifying removes the sole reason a taxonomy-neutral triage paragraph was needed in the first place.

## Error Handling

| Condition | Behavior |
| --- | --- |
| `roles` missing or unrendered in `agent-profile.json` | Fall back to primary/review agents; do not fail |
| `.tarnished/workflows/flow.md` missing (project scaffolded before it shipped) | `/flow` proceeds on the SKILL alone — `workflows/*.md` is not refresh-managed, so this is the normal state for existing projects |
| `.claude/agents/advisor.md` missing | Skip the consult; never block a stage on advice |
| Primary agent has no subagent mechanism | Skip advisor points |
| `.codex/config.toml` unreadable or key unset | Record `model: default` / `reasoning effort: default` |
| CI wait exceeds its timeout | Report CI status unknown and stop. Do not merge |
| `--from <stage>` names a stage whose prerequisites are absent | Report what is missing and stop |

## Implementation Notes

### Ordering

The prerequisite `setup.sh` fix lands **before** any edit to `.tarnished/agent-profile.json` or `.tarnished/workflows/README.md`, so no intermediate commit on this branch can ship the poisoning regression.

### Mirror discipline

`scripts/verify-mirrors.sh` covers `.claude/skills`, `.claude/agents`, and `.agents` as whole trees, so new files under those are checked automatically. Two additions are needed:

- `flow` in the `for f in issue design implement review pr` loop (`verify-mirrors.sh:76`)
- nothing else — `templates/agent-workflows/.tarnished/agent-profile.json` is already a checked pair

### Enumerations that must stay in sync

The five-stage lifecycle is written out in several places that a sixth entrypoint invalidates: `.tarnished/workflows/README.md` (Lifecycle), `templates/claude/CLAUDE.md`, `templates/codex/AGENTS.md` (including its `$name` alias list), and the repository `README.md`.

### `erd:*` invocation (3-1)

The prohibition on the Skill tool is removed. Preference order becomes: `Skill(erd:<name>)` when available → `Read(".claude/commands.local/erd/<name>.md")` when an overlay exists → `Read(".claude/commands/erd/<name>.md")`. The overlay step is what the original hardcoded path silently skipped.

### Priority notation (1-6)

`erd:estimate` continues to emit High/Medium/Low; it is three-way mirrored and shared with other flows. The High/Medium/Low → P0/P1/P2 mapping stays at the project-field boundary in `/issue`. The issue-side artifacts — body template and criteria table — unify on P0/P1/P2, which is what actually lands in the issue body.

### `claude-code-review.yml` (1-2)

The caller template documents itself as manual opt-in: it needs `__ERD_REF__` pinned and an `ANTHROPIC_API_KEY` secret that `setup.sh` cannot configure, and its template directory has no `plugin.sh`. Conditionalizing the references is the correct fix — and would be required anyway for projects that opt out. Unconditional references at `code-reviewer.md:21`, `review/SKILL.md:116,210`, and `pr/SKILL.md:85` become conditional; a real installer is left as a follow-up.

### `/flow` context budget

All five lifecycle skills carry `disable-model-invocation: true`, so `/flow` cannot Skill-invoke its stages; it reads each SKILL and follows it. The §4 compression pass runs first, which is what makes the combined read affordable. Interactive stages (`issue` brainstorm, `design` sign-off) run inline with approval gates; mechanical passes are delegated per the routing table.
