# Design: #312 restructure lifecycle roles around a long-context orchestrator with delegated designer and executor

## Context

The AI lifecycle in this repository is expressed at three altitudes that are projections of one another (`architecture.md` :: "Lifecycle asset altitudes"): the agent-neutral contract in `.tarnished/workflows/*.md`, the operational spec in `.claude/skills/*/SKILL.md` and `.claude/agents/*.md` where behavior is authored, and the thin Codex projection in `.agents/skills/*/SKILL.md`. `scripts/verify-mirrors.sh` (CI: `asset-parity.yml`) enforces byte-identity between each workspace tree and its `templates/` mirror.

Since #308 the lifecycle has named four **roles** rather than models — `orchestrator`, `executor`, `external-reviewer`, `advisor` — and routed work **by nature** rather than by stage, so a single stage could be part-inline and part-delegated. Role→agent binding lives in `.tarnished/agent-profile.json :: roles`; `roles.<role>.model` is `null` for every role.

`/flow` runs the five stages in one pass, derives its entry stage from repository evidence rather than a state file, and carries two human approval gates: after an issue the run created, and before implementation.

## Architecture Overview (delta)

The role model is restructured, not extended. Four roles remain, but who they are and what they do changes:

| Role | Execution | Owns | Model |
| --- | --- | --- | --- |
| `orchestrator` | **Inline — it *is* the main session** | Requirements dialogue, issue authoring, review of every delegated artifact, review triage, merge decision, escalation | `claude-fable-5` |
| `designer` | Delegated subagent | Design artifacts, once the specification is settled | `claude-opus-5[1m]` |
| `executor` | Delegated subagent | Implementation, review-fix application, PR authoring and CI monitoring | `claude-sonnet-5` |
| `external-reviewer` | Separate vendor CLI | Independent review of the branch diff | reviewer-owned |

`advisor` is removed. Its function — an independent check on an artifact before it is committed to — becomes the orchestrator's, which is a strictly better place for it (see below).

| Stage | Writes | Reviews |
| --- | --- | --- |
| `issue` | orchestrator | the user, through the requirements dialogue |
| `design` | designer | orchestrator |
| `implement` | executor | orchestrator |
| `review` | external-reviewer | orchestrator triages; executor applies fixes |
| `pr` | executor | orchestrator checks PR content and owns the merge decision |

### Why this shape

Three problems dissolve together.

**The model tier was inverted.** No level of the binding chain names a model for any role today — `roles.<role>.model` is `null`, no agent definition carries `model:`, and subagent frontmatter defaults to `inherit` — so every role runs on the session's model. An earlier revision of this issue proposed pinning the strongest model to the `advisor`, which would have put the most capable model in the one seat that cannot write, while the seat that makes and applies every decision stayed a tier below. Since the orchestrator applies every fix, correction quality is bounded by the orchestrator no matter how good the advice is. Putting the strongest model in the session and delegating authoring downward inverts that correctly.

**The conformance check was circular.** A read-only subagent's only input channel is the prompt the orchestrator writes, so asking it to verify an artifact against "the requirement" means the orchestrator supplies the very source of truth it is being checked against. Both derive from the same reading and the check returns `conform`. The previous revision designed real mitigations — verbatim quoting, a narrowed subject, treating a paraphrased source of truth as itself a finding — but they mitigate a structural flaw rather than remove it. Here the reviewing party **is** the session that conducted the requirements dialogue, so it holds the ground truth natively.

**Gates existed because the reviewer could not reach the user.** The recorded reason for keeping human gates was that subagents cannot interact with the user, so a sign-off could not be delegated. That constraint is real. This restructure inverts what gets delegated: the *writing* goes to subagents and the *review* stays in the session, so the reviewer can escalate whenever it needs to. The gates then have nothing left to add.

There is also a capability motive. With authoring delegated, the main session's context stays clean, which is what makes long-running multi-stage work viable on a 1M-context model.

### The write → review → commit order

`/design` currently commits its artifacts in Phase 8 and only then reaches its sign-off step. That ordering is why a design commit proved artifacts were *written* rather than *approved*, why Gate B had to re-run on resumed runs, and why the previous revision needed a durable conformance record purely so evidence derivation could tell the two states apart.

Moving the commit after the review removes all of it: **the design commit is itself the record that the review happened.** No new evidence artifact, no new evidence-table row, no verification-only re-entry path, no skip-vs-success record semantics. An interrupted run leaves uncommitted files, which the existing table already reads correctly as "no design commit → enter at design".

`docs/design/#{issue}/orchestrator-review.md` still records the findings, but as an audit trail rather than an evidence key — a distinction worth keeping explicit, because the previous design's complexity came entirely from the artifact being load-bearing.

## Module Structure (delta)

```
.claude/skills/_shared/delegation/SKILL.md   # role vocabulary, stage/role matrix, model binding,
                                             #   escalation protocol, triage trigger fix
.claude/agents/designer.md                   # NEW — design authoring; model: claude-opus-5[1m]
.claude/agents/executor.md                   # NEW — implementation authoring; model: claude-sonnet-5
.claude/agents/advisor.md                    # DELETED
.claude/agents/code-reviewer.md              # unchanged — still the /review fallback reviewer
.claude/settings.json                        # model: claude-fable-5 (the orchestrator's only channel)
.claude/skills/issue/SKILL.md                # authored inline; advisor consult removed
.claude/skills/design/SKILL.md               # delegate authoring; review; commit after review
.claude/skills/implement/SKILL.md            # delegate authoring; record the reversal as intentional
.claude/skills/review/SKILL.md               # triage by orchestrator, fixes by executor;
                                             #   issue Requirements as a second ground truth
.claude/skills/pr/SKILL.md                   # executor authors and monitors; orchestrator merges
.claude/skills/flow/SKILL.md                 # gates removed; stop-point list; delegation targets
.tarnished/workflows/{README,issue,design,implement,review,pr,flow}.md   # contract projection
.agents/skills/{issue,design,implement,review,pr,flow}/SKILL.md          # Codex projection
templates/claude/…, templates/agent-workflows/…, templates/codex/…       # byte-identical mirrors
```

## Interface Design (delta)

### Role → model binding

Each role's model comes from exactly one place, chosen by how that role is dispatched.

| Role | Channel | Value | Parity / refresh behaviour |
| --- | --- | --- | --- |
| `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5` | Neither parity-checked nor manifest-tracked; user-owned downstream. Read once at session start |
| `designer` | `.claude/agents/designer.md` frontmatter | `claude-opus-5[1m]` | Parity-checked **and** refresh-managed — ships to every project on the next container start |
| `executor` | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5` | Same |
| `external-reviewer` | `.codex/config.toml` | `gpt-5.6-sol` / `ultra` | Parity-checked |

`roles.<role>.model` stays `null`. The profile keeps answering "which agent"; the model comes from the channel above. This is not merely a preference: `verify-mirrors.sh` enforces byte-identity between `.tarnished/agent-profile.json` and its template, so **this repository cannot populate `roles.<role>.model` at all** without failing CI — and its copy still carries unrendered `{{...}}` placeholders in `ai_profile` / `primary_agent` / `review_agent`, which the resolution contract treats as absent, so tarnished always runs the fallback path. Downstream copies are rendered and manifest-tracked rather than parity-checked, so a per-role override remains available there and takes precedence over the frontmatter.

**Pinned IDs rather than aliases.** An alias silently re-points at a new generation; this repository already pins exactly and bumps in a tracked commit, and #292 exists *because* a model value changed invisibly. The cost is that a retired ID breaks its consumer until bumped; the mitigation is that each pin lives in exactly one file.

**Only the designer's pin carries `[1m]`, and its acceptance is unverified.** Subagent frontmatter is documented to accept `sonnet` / `opus` / `haiku` / `fable`, a full model ID, or `inherit`; the `[1m]` suffix is documented for `/model` and for `ANTHROPIC_DEFAULT_*` environment variables, which is a different code path. The fallback is `claude-opus-5` plain. On the Anthropic API, Fable 5, Sonnet 5, and Opus 4.7 and later all default to the 1M window, so the suffix is inert there; it matters behind an LLM gateway and on Pro, where Opus with 1M requires usage credits. A designer subagent's context is bounded by construction, so the suffix is insurance rather than a capacity requirement — which is what makes the fallback acceptable rather than a compromise.

### Subagent escalation protocol

`designer` and `executor` cannot interact with the user. Both are therefore required to **stop and return a structured blocked-result** — the question, and the options they can see — rather than assume, whenever the answer is not derivable from the issue, the design artifacts, or the codebase.

| Trigger | Example |
| --- | --- |
| Requirement-level ambiguity | Two readings of an acceptance criterion that produce different interfaces |
| Design/convention conflict | The design implies a pattern the codebase consistently does otherwise |
| Missing prerequisite | A design artifact the stage depends on does not exist |

The orchestrator resolves the question when it can, and escalates to the user when the answer is the user's to give. This protocol is what makes delegating the two highest-judgment stages defensible: it is the mechanism that keeps "delegated authoring" from becoming "unsupervised guessing".

### `/design` — delegate, review, then commit

| Phase | Owner |
| --- | --- |
| Read the issue, resolve the branch, load `docs/design/shared/*` | orchestrator |
| Research, author `#{issue}/design.md`, `api-spec.md`, `workflow.md`, diagrams; regenerate the shared snapshot | **designer** |
| Review the artifacts against the issue's Requirements | orchestrator |
| Blocking finding → designer revises → re-review, capped at 2 rounds | both |
| Write `#{issue}/orchestrator-review.md`; stage and commit everything | orchestrator |

A blocking finding surviving round 2 escalates to the user. Reaching the cap is always reported, never passed over silently.

### `/implement` — delegated authoring with a judgment carve-out

Authoring moves to the executor; the orchestrator reviews. The carve-out is FR-7: the executor returns rather than deciding whenever the design does not settle a judgment.

This stage treats design artifacts as optional, so a run can reach it with none. In that case the issue's Requirements are the ground truth for both the executor and the review — otherwise the review would have nothing to check against and the executor nothing to build from.

This **deliberately overwrites** the position currently recorded in `implement/SKILL.md`, which states that this stage is "the one most often mis-delegated" and that interpreting the design and matching existing conventions "stays with the orchestrator". That position assumed the orchestrator was the only capable writer, and that delegation meant handing off with no return path. With a model-pinned executor and a mandatory return-on-judgment protocol, the trade differs. The reversal is recorded as intentional, with its reason, rather than left to contradict the old text silently — a reader who finds the new instruction without the rationale will reasonably assume it is an error.

### `/pr` — split at the irreversible operation

| Work | Owner |
| --- | --- |
| Mechanical quality pass, `git push`, PR body **drafting**, CI monitoring, log collection, fix commits | executor |
| Checking the drafted body, then running `gh pr create` | orchestrator |
| Merge decision, including under `--merge` | orchestrator |

A pull request is outward-facing and a merge is irreversible, so neither is delegated to the stage's writing agent.

Creation is the orchestrator's **command**, not merely its approval. "The executor creates it but the orchestrator checks first" has no executable boundary — by the time the orchestrator sees anything, the pull request exists and any correction is visible to everyone who was notified. The executor therefore returns the drafted body and stops.

## Data Flow

```
user ──dialogue──▶ orchestrator ──writes──▶ issue
                        │
                        ├──delegates──▶ designer ──▶ design artifacts
                        │                                │
                        │◀──────── review ───────────────┘
                        │   (≤2 rounds, then commit)
                        │
                        ├──delegates──▶ executor ──▶ implementation
                        │                                │
                        │◀──────── review ───────────────┘
                        │
                        ├──invokes───▶ external-reviewer ──▶ findings
                        │                                        │
                        │◀──── triage ───────────────────────────┘
                        │        └──delegates fixes──▶ executor
                        │
                        └──delegates──▶ executor ──▶ PR + CI
                                 orchestrator checks content, decides merge

escalation: designer/executor ──blocked-result──▶ orchestrator ──▶ user (only if the answer is the user's)
```

A `/flow` run stops for the user in exactly four places, and `flow/SKILL.md` states the list so the property is checkable rather than emergent: requirement gathering, an escalation the orchestrator cannot resolve, argument resolution, and a `/pr` failure.

## Error Handling

| Condition | Behavior |
| --- | --- |
| Subagent hits an ambiguity | Return a structured blocked-result; never assume. Orchestrator resolves or escalates |
| Blocking review finding survives round 2 | Report, record, escalate to the user |
| Primary agent has no subagent mechanism | Run every stage inline under the primary agent and record that delegation was unavailable. The lifecycle stays functional rather than degrading quietly |
| `[1m]` suffix rejected in frontmatter | Fall back to `claude-opus-5`; the suffix is insurance, not a capacity requirement |
| Pinned model ID retired | The consumer breaks until the pin is bumped. Each pin lives in one file; bumping follows the `.codex/config.toml` precedent |
| Refreshed skill disagrees with a stale `.tarnished/workflows/*.md` | The skill is authoritative |

## Implementation Notes

- **Edit order is contract → agents → stage skills → projections → mirrors.** Every stage skill reads the delegation policy, so the vocabulary and the stage/role matrix are authored once and the stage specs derive from them.
- **`advisor.md` is deleted in the same commit** that removes its last reference, so no dangling pointer survives a partial edit. `.claude/agents/` is refresh-managed and directory-managed, so the deletion propagates downstream on the next container start.
- **`code-reviewer.md` stays.** It is the `/review` fallback when no external reviewer is installed, and is unrelated to the removed advisory role.
- **The routing principle changes, not just the cast.** Until now work was routed by *nature* within a stage. Now each stage's authoring has a single owner and the orchestrator reviews rather than co-authors; within a delegated stage the subagent routes its own internal work. Both statements have to land in the delegation policy, or the old sentence will keep justifying inline authoring.
- **Self-hosting caveat**: this repository dogfoods its own lifecycle assets, so this issue's own `/implement`, `/review`, and `/pr` run under the *pre-change* model. The new structure is first exercised on the next issue. Say so in the PR body rather than treating it as a gap.
- **Cost is a redistribution, not a straight increase, and is unmeasured.** The session moves to the most capable tier and runs every turn; authoring moves to cheaper agents whose context is bounded by construction. What to measure is stated in NFR-5: per-run token split across the three agents, escalation rate, and review-loop round counts.
