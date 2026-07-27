# Design: #312 extend the advisor role to standing content review with fix proposals

## Context

The AI lifecycle in this repository is expressed at three altitudes that are projections of one another (`architecture.md` :: "Lifecycle asset altitudes"): the agent-neutral contract in `.tarnished/workflows/*.md`, the operational spec in `.claude/skills/*/SKILL.md` where behavior is authored, and the thin Codex projection in `.agents/skills/*/SKILL.md`. `scripts/verify-mirrors.sh` (CI: `asset-parity.yml`) enforces byte-identity between each workspace tree and its `templates/` mirror.

Work inside a stage is routed by **nature**, not by stage (`architecture.md` :: "Role-based delegation policy", #308). Four roles exist: `orchestrator` (judgment, inline), `executor` (mechanical, delegated), `external-reviewer` (independent cross-vendor review), and `advisor` (read-only second opinion). The routing table and the advisor's invocation points live once, in `.claude/skills/_shared/delegation/SKILL.md`. Role→agent/model binding lives in `.tarnished/agent-profile.json :: roles`, which is manifest-tracked rather than refresh-managed so a downstream retarget survives container restarts.

`/flow` runs the five stages in one pass and derives its entry stage from **repository evidence** rather than a state file — the issue's own state, an anchored `#<n>/` branch match, the design commit, later commits, the review artifact, and the pull-request list. Evidence is authoritative, survives a failed run, and needs no cleanup. Two of its evidence rules are deliberately stricter than "the file exists", because `/design` and `/review` both write artifacts *before* reaching their own completion step.

`/flow` currently carries two human approval gates: Gate A after an issue the run created, Gate B before implementation.

## Architecture Overview (delta)

This issue changes what the `advisor` role is for, not what roles exist.

Today every advisor consult fires **before** its stage writes anything, and asks *"is this the right choice?"*. No consult asks *"does the artifact carry the requirement it was supposed to carry?"* — that question is answered by the two `/flow` gates, i.e. by a human. The delta introduces a second consult class, `conformance`, staffs the question with the advisor, and removes the gates.

Three structural changes follow, in dependency order:

1. **Contract layer** — `_shared/delegation/SKILL.md` gains the `challenge` / `conformance` class distinction, a rewritten invocation table with a class column, the escalation rule, the stage/role matrix, and a stated per-run ceiling. Every stage reads this file, so it is edited first and the stage specs derive from it.
2. **Stage layer** — `/issue` and `/design` each gain one conformance consult and, in `/design`'s case, a durable record. `/review` gains a second ground truth. `/flow` loses its gates and gains the escalation path plus two evidence-table rows.
3. **Projection layer** — the same semantics restated in `.tarnished/workflows/*.md` and `.agents/skills/*/SKILL.md`, then mirrored into `templates/`.

The advisor stays read-only. It labels findings; the orchestrator decides, applies, and owns the outcome. Escalation to the user is an orchestrator action taken after its own correction failed twice — not the advisor withholding permission.

### Why the gates can be replaced but not simply deleted

Each gate was load-bearing for something, and each thing needs a new owner:

| Gate | What it actually guarded | New owner |
| --- | --- | --- |
| A | The estimation, approach, and task breakdown that `/issue` produces *after* its requirements summary is approved, and never re-presents | FR-13 conformance consult, subject narrowed to exactly that delta |
| B | That a design commit means "approved", not merely "written" — `/design` commits in Phase 8 *before* its sign-off step | FR-17 durable conformance record, which is what the evidence table keys on |
| A + B jointly | The last human sight of the work before implementation | FR-18: `/review` gains the issue's Requirements as a second ground truth, so a dropped requirement is catchable downstream |

FR-18 is what makes the trade defensible rather than merely cheaper. Without it, a requirement dropped at the `/issue` stage propagates unchallenged: the code matches the design, the design matches the reduced issue, `/review`'s criterion 8 compares implementation against design only, and every check returns green. One unproven check replaces two human looks. With it, the requirement is checked at two different altitudes by two different agents.

## Module Structure (delta)

```
.claude/skills/_shared/delegation/SKILL.md   # consult classes, invocation table, escalation, ceiling, role matrix
.claude/agents/advisor.md                    # fix proposals; conformance mode; model: fable
.claude/skills/issue/SKILL.md                # Phase 1 unconditional challenge; Phase 2 estimation challenge;
                                             #   Phase 3.5 conformance consult on the post-approval delta
.claude/skills/design/SKILL.md               # unconditional challenge; workflow-plan challenge;
                                             #   Phase 7.5 conformance consult; conformance.md; --unattended
.claude/skills/review/SKILL.md               # parallel advisor diff review + arbitration; issue Requirements
                                             #   as second ground truth; requirement-adherence criterion
.claude/skills/flow/SKILL.md                 # gates removed; escalation; two evidence rows; --unattended
.tarnished/workflows/{README,issue,design,review,flow}.md    # contract projection
.agents/skills/{issue,design,review,flow}/SKILL.md           # Codex projection
templates/claude/…, templates/agent-workflows/…, templates/codex/…   # byte-identical mirrors
docs/design/shared/{architecture,api-spec}.md                # snapshot regeneration
```

New artifact: `docs/design/#{issue}/conformance.md`, written by `/design`.

## Interface Design (delta)

### `--unattended`, an internal stage argument

`/flow` must be able to suppress `/design`'s sign-off gate without the gate's presence depending on who invoked the skill. There is no channel for that today: `/flow`'s Stage 3 table passes `issue number, --base`, and the Codex projection reads the skill with no notion of a caller. Left inferred, "the caller selects the behaviour" reduces to "the model remembers who invoked it" — the judgment-dependent trigger NFR-3 forbids, and the same defect class FR-2 and FR-3 exist to remove.

`--gates` / `--no-gates` was rejected as *user-facing* surface on `/flow`. An internal stage argument is a different object, and `--base` and `--merge` already establish the pattern of `/flow` parameterizing a stage skill.

| Skill | Arguments after this change |
| --- | --- |
| `/design` | `<issue_number> [--base <branch>] [--unattended]` |
| `/flow` → `/design` | issue number, `--base`, `--unattended` |

`/design` step 22 presents the design for approval **unless** `--unattended` was passed; with it, the conformance record stands in the gate's place and the report says so.

### Advisor model binding

The advisor's independence today is **contextual only**. `advisor.md` carries no `model:` field, Claude Code's subagent frontmatter defaults to `inherit`, `roles.advisor.model` is `null`, and `roles.advisor.agent` is `"primary"` — so nothing in the chain names a model and the advisor runs on exactly the orchestrator's weights. A fresh context that has not seen the reasoning is worth something; identical weights means identical blind spots. That is thin for a second opinion and untenable once the advisor takes over checks a human used to perform.

Resolution chain, stated normatively in `_shared/delegation/SKILL.md` because today it says only "use that agent's configured default" and never says what the default is:

| Precedence | Source | Refresh behaviour |
| --- | --- | --- |
| 1 | `roles.<role>.model` in `.tarnished/agent-profile.json` | Not refresh-managed — a downstream override survives every container start |
| 2 | `model:` in the agent definition frontmatter | `.claude/agents/` **is** refresh-managed — the shipped default reaches every project on the next start |
| 3 | `inherit` — the session model | What applies when neither above names a model; the current state of every role |

The shipped default becomes `model: claude-fable-5` in `advisor.md`. Verified against the Claude Code subagent documentation: the frontmatter `model` field accepts `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or `inherit`, and defaults to `inherit`.

A pinned ID rather than the `fable` alias, because the alias silently re-points at a new generation. This repository already pins exactly and bumps in a tracked commit — `.codex/config.toml` pins `gpt-5.6-sol`, #292 exists *because* a model value changed invisibly, and `/review` records the resolved model in the review artifact for the same reason. The cost of pinning is that a retired ID breaks every consult until bumped; the mitigation is that the pin lives in exactly one refresh-managed file, and bumping it follows an established path.

**Constraint worth writing down**: `scripts/verify-mirrors.sh` enforces byte-identity between `.tarnished/agent-profile.json` and its template, so **this repository cannot use precedence 1** — setting `roles.advisor.model` in the workspace fails the parity gate. The workspace copy also still carries unrendered `{{...}}` placeholders in `ai_profile` / `primary_agent` / `review_agent`, which the resolution contract treats as absent, so tarnished itself always runs the fallback path. Frontmatter is the only channel that works here. Precedence 1 stays available downstream, where the copy is rendered and manifest-tracked rather than parity-checked.

### Consult classes

| Class | Runs | Asks | Advisor's posture |
| --- | --- | --- | --- |
| `challenge` | Before the artifact is written | Is the intended choice right? | Argue for an alternative |
| `conformance` | After the artifact is written | Does it carry the requirement it was supposed to carry? | Compare artifact against source of truth; report mismatches |

The two are not interchangeable. A stage that runs only `challenge` is unverified — that is the gap the gates were covering.

### Conformance consult inputs and verdicts

| Field | Contract |
| --- | --- |
| Source of truth | Supplied **verbatim**. Quoting is mechanical; summarizing is not |
| Subject | The artifact under check, named by path or quoted in full |
| Verdict | `conform` \| `non-blocking gap` \| `blocking mismatch` \| `skipped — <reason>` |

`advisor.md`'s conformance mode states that a source of truth supplied as a paraphrase is **itself a reportable finding**. This is the guard against the check's central weakness: a read-only subagent's only input channel is the prompt the orchestrator writes, so an orchestrator that paraphrases hands the advisor its own reading of the requirement and asks whether the artifact matches it. Both derive from the same misunderstanding and the check returns `conform`. Gate A did not have this property, because its ground truth sat in the user's head.

Two properties bound the residual circularity for FR-13:

- The **approved requirements summary is user-approved text** — `/issue` iterates on it with the user until approved. Passed verbatim, it is an anchor the orchestrator cannot silently rewrite.
- The **subject is the post-approval delta**, not the whole issue. The Requirements section was already approved by the user directly; including it dilutes the check and drags approved text into the circular part.

### `docs/design/#{issue}/conformance.md`

```markdown
# Conformance: #{issue_number}

**Verdict**: conform | non-blocking gap | blocking mismatch (escalated, unresolved) | skipped — <reason>
**Rounds**: 1 | 2
**Checked**: <artifact paths>
**Against**: <source of truth>

## Findings
<per finding: severity label, what mismatches, what was corrected or why it stands>
```

The `**Verdict**:` line is machine-greppable by construction. Existence alone is not a verdict — `/flow` already keys review completeness on a *section* ("Fixes Applied") rather than file existence, precisely so an interrupted run cannot resume past the check, and a record reading "blocking mismatch, escalated, unresolved" satisfies existence.

A separate file rather than a section in `design.md`: `design.md` is the *subject* of the check, so a verdict inside it is self-certification, and a second `/design` run re-authors `design.md` and would silently drop the verdict. A separate file rather than a commit trailer: `/pr` squash-merges with `--delete-branch`, so a trailer does not survive into `develop`, while the per-issue directory is the documented durable audit surface. A second `/design` run **overwrites** the record, matching the snapshot discipline the rest of `/design` already follows.

### `/flow` Stage 2 evidence table (delta)

Two rows change, one is added **above** the existing design row:

| Evidence | Entry stage |
| --- | --- |
| Design commit present, **no conformance record** | Run the conformance consult against the already-committed artifacts, commit the record, continue at `implement` — **never** re-run `/design` |
| Design commit present, conformance record present, no later commit outside `docs/design/` | `implement` (unchanged) |

The verification-only re-entry is the load-bearing choice. Treating a missing record as "design incomplete" would send every branch designed before this change — including every downstream in-flight branch, and every branch produced under NFR-2's skip fallback — back through `/design`, whose Phase 7 **overwrites** `docs/design/shared/*` and re-authors `design.md`. That is a destructive redesign on every resume, permanently. Verification-only re-entry preserves Gate B's own resume semantics, which presented the already-committed design rather than re-deriving it, and composes with the table unchanged: the record commit touches only `docs/design/`, so the next resume still resolves to `implement`.

`--from <stage>` **bypasses** the conformance precondition and reports it as a warning rather than failing closed, matching the existing carve-out for `--from implement` with no design artifacts at all.

### `/review` prompt (delta)

The template gains the issue's Requirements section alongside the Design Reference, and a ninth criterion: *"Requirement adherence — does the branch carry every requirement in the issue?"*. Because the criteria are single-sourced into a piped `codex exec` prompt and into CI workflow YAML, the addition must be inline in the template, not a path reference.

## Data Flow

The conformance check is a bounded loop, identical in shape at both invocation points:

```
artifact written ─▶ consult (round 1)
                      ├─ conform / non-blocking gap ─▶ record, continue
                      └─ blocking mismatch ─▶ orchestrator corrects ─▶ consult (round 2)
                                                  ├─ resolved ─▶ record, continue
                                                  └─ still blocking ─▶ record + escalate to user
```

The cap is 2 rounds, consistent with FR-7. Reaching the cap with a blocking mismatch outstanding is always reported and always recorded; it is never passed over silently.

After this change a `/flow` run stops for the user in exactly four places: requirement gathering in `/issue` Phase 1, an FR-15 escalation, argument resolution (an unresolvable issue number or a contradictory flag pair), and a `/pr` failure. `flow/SKILL.md` states that list explicitly, so the property is checkable rather than emergent.

## Error Handling

| Condition | Behavior |
| --- | --- |
| Advisor definition absent, or the primary agent has no read-only subagent mechanism | Skip the consult, continue the stage, and **write the record with verdict `skipped — <reason>`**. A record written only on success deadlocks against NFR-2 |
| Blocking mismatch survives round 2 | Record `blocking mismatch (escalated, unresolved)`, escalate to the user with the finding and what was attempted |
| Conformance record missing on a resumed run | Verification-only re-entry (above). Never a redesign |
| `--from` names a stage whose conformance precondition is unmet | Warn and proceed. `--from` is an explicit user instruction |
| Refreshed skill disagrees with a stale `.tarnished/workflows/*.md` | The skill is authoritative. `.claude/skills/` is refresh-managed; `.tarnished/workflows/` and `.agents/` are not |

## Implementation Notes

- **Edit order is contract → stage → projection → mirror.** Both new consults are instances of the class distinction, and both new stage phases derive from the policy rather than restating it.
- **The `/design` consult belongs between Phase 7 and Phase 8**, not after the commit. After would produce a correction commit on top of a design commit the evidence table has already accepted as complete — the exact ambiguity FR-17 exists to close.
- **Sweep every gate-bearing location, not only `flow/SKILL.md` Stage 4.** The skill's frontmatter `description` is its discovery text; the Stage 3 stage-order line, the Stage 2 skip paragraph, the Reporting list, and the `Gate A declined` error row all carry gate semantics, as do `.tarnished/workflows/flow.md`'s procedure steps 6-7 and Output list, `.agents/skills/flow/SKILL.md`'s two "confirmations", `design/SKILL.md` step 22, and `docs/design/shared/api-spec.md`'s approval-gates paragraph.
- **`architecture.md`'s claim that the advisor is "bounded to three mechanically-triggered invocation points" stops being true** and is regenerated in Phase 7.
- **The model mechanism is verified, not assumed** (FR-9). Frontmatter `model` accepts a full model ID and defaults to `inherit`; no fallback mechanism is needed.
- **Cost is the main non-correctness risk.** The per-run ceiling rises from ≤1 advisor invocation to 11 (7 challenge + 4 conformance), and the advisor now runs on a separately-priced model rather than inheriting the session's. NFR-5 requires the derivation to be written down where the invocation points are documented.
- **The escalation path must be reachable and testable.** A conformance check that can never escalate is indistinguishable from no check at all.
