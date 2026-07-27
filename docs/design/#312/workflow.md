# Workflow: #312 extend the advisor role to standing content review with fix proposals

Breadth-dominated work: ~24 files across three altitude levels under a byte-identity CI gate. The ordering below exists so that every semantic decision is made once, in the contract layer, and every later step is a derivation or a copy.

## Implementation Steps

### Step 1: Verify the `model: fable` frontmatter mechanism

- **Action**: Confirm Claude Code's agent-definition frontmatter accepts `model: fable`. The Agent tool's `model` enum includes it, but frontmatter is a separate code path. If rejected, fall back to carrying the name in `.tarnished/agent-profile.json :: roles.advisor.model` and revise FR-9's mechanism before Step 3 writes it.
- **Files**: none (investigation)
- **Depends on**: nothing
- **Done when**: the result is recorded and FR-9's mechanism is either confirmed or replaced

### Step 2: Rewrite the delegation contract

- **Action**: Add the `challenge` / `conformance` class distinction; rewrite the invocation-points table with a class column covering FR-2 through FR-6 and FR-13/FR-14; add the FR-15 escalation rule; add the FR-10 stage/role matrix; correct the Critical/Major trigger to Major-only (FR-11); state the NFR-5 ceiling with its derivation; clarify `model: null` resolution (FR-9).
- **Files**: `.claude/skills/_shared/delegation/SKILL.md`
- **Depends on**: Step 1 (for the FR-9 wording only)
- **Done when**: every invocation point carries a class; no judgment-dependent trigger remains; the ceiling table sums to 11

### Step 3: Extend the advisor definition

- **Action**: Add per-finding concrete fix proposals to the output contract (FR-1); add the conformance mode — inputs (verbatim source of truth, subject, round), the four verdicts, and the rule that a paraphrased source of truth is itself a reportable finding; add `model: fable` frontmatter per Step 1's result. Leave `tools:` and the READ-ONLY prose constraint untouched.
- **Files**: `.claude/agents/advisor.md`
- **Depends on**: Steps 1, 2
- **Done when**: both modes are specified and the tools list is unchanged

### Step 4: `/issue` — challenge consults and the conformance consult

- **Action**: Make the Phase 1 consult unconditional (FR-2); add the Phase 2 estimation consult (FR-4); add the post-composition conformance consult (FR-13) with the approved requirements summary quoted verbatim as source of truth and the post-approval delta as subject; add the FR-19 precedence sentence; extend Reporting.
- **Files**: `.claude/skills/issue/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: no consult carries a judgment-dependent trigger and the conformance subject is the delta, not the whole issue

### Step 5: `/design` — consults, the conformance record, and `--unattended`

- **Action**: Make the Phase 4 consult unconditional (FR-3); add the Phase 5 workflow-plan consult (FR-5); insert Phase 7.5 conformance consult between the snapshot regeneration and the commit (FR-14); specify `conformance.md` and stage it in Phase 8; add `--unattended` to the usage block and rewrite step 22 around it (FR-16); add `conformance.md` to the directory-structure listing and the Reporting list; state second-run overwrite semantics; add the FR-19 precedence sentence.
- **Files**: `.claude/skills/design/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: the consult is unambiguously before the commit, the record is written on every path including the skip, and `--unattended` appears in usage

### Step 6: `/review` — parallel advisor review and the second ground truth

- **Action**: Add the advisor diff review running in parallel with the external reviewer plus the arbitration rule and artifact format (FR-6); add the issue's Requirements to the prompt template and the ninth requirement-adherence criterion (FR-18); add the FR-19 precedence sentence.
- **Files**: `.claude/skills/review/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: both ground truths are inline in the template and the artifact distinguishes the two reviewers' outputs

### Step 7: `/flow` — remove the gates, add the escalation and the evidence rows

- **Action**: Delete Gates A and B from Stage 4 and put the FR-15 escalation rule in their place; pass `--unattended` in the Stage 3 argument table; add the verification-only re-entry row above the design row and the conformance precondition to the design row; add the `--from` carve-out; state the four remaining user-stop points; update the triage policy for FR-11; extend Reporting; add the FR-19 precedence sentence.
- **Files**: `.claude/skills/flow/SKILL.md`
- **Depends on**: Steps 2, 5
- **Done when**: `grep -in "gate"` over the file returns only the intentional references, and the frontmatter `description` no longer advertises approval gates

### Step 8: Sweep the residual gate-bearing locations

- **Action**: The gate semantics appear outside Stage 4 — the skill frontmatter `description` (its discovery text), the Stage 3 stage-order line, the Stage 2 skip paragraph, the Reporting list, and the `Gate A declined` error row. Fix each.
- **Files**: `.claude/skills/flow/SKILL.md`, `.claude/skills/design/SKILL.md`
- **Depends on**: Steps 5, 7
- **Done when**: no remaining text asserts a gate that no longer exists

### Step 9: Project into the agent-neutral contract

- **Action**: Restate the same semantics at contract altitude. `flow.md` procedure steps 6-7 and its Output list are the gate-bearing parts; `README.md` carries the role vocabulary.
- **Files**: `.tarnished/workflows/{README,issue,design,review,flow}.md`
- **Depends on**: Steps 4-8
- **Done when**: the contract and the skills agree on gates, classes, escalation, and evidence

### Step 10: Project into Codex

- **Action**: Update the thin projections; `.agents/skills/flow/SKILL.md` carries two "confirmations" in its stage list.
- **Files**: `.agents/skills/{issue,design,review,flow}/SKILL.md`
- **Depends on**: Step 9
- **Done when**: the Codex projection names no gate

### Step 11: Mirror

- **Action**: Copy each changed tree to its mirror: `.claude/skills` → `templates/claude/.claude/skills`, `.claude/agents` → `templates/claude/.claude/agents`, `.agents` → `templates/codex/.agents`, `.tarnished/workflows/*.md` → `templates/agent-workflows/.tarnished/workflows/*.md`. Byte-identity, not paraphrase — this is mechanical work.
- **Files**: the three `templates/` trees
- **Depends on**: Steps 4-10
- **Done when**: `scripts/verify-mirrors.sh` exits 0

### Step 12: Regenerate the shared design layer

- **Action**: `architecture.md`'s role-delegation bullet still says the advisor is "bounded to three mechanically-triggered invocation points"; `api-spec.md`'s `/flow` approval-gates paragraph describes gates that no longer exist. Overwrite both with merged current truth per NFR-1 — never append. Update the skill-workflow sequence diagram.
- **Files**: `docs/design/shared/{architecture,api-spec,sequence}.md`
- **Depends on**: Steps 4-10
- **Done when**: no shared file describes the pre-#312 gate model

## Task Dependencies

- Steps 2 and 3 are the semantic root; every later step derives from them
- Step 1 blocks only the FR-9 wording inside Steps 2 and 3
- Steps 4, 5, 6 are independent of one another and can proceed in parallel once Steps 2-3 land
- Step 7 depends on Step 5 because `--unattended` is defined by the `/design` side
- Step 8 is a sweep, so it must follow Steps 5 and 7 rather than run beside them
- Steps 9 and 10 are strictly sequential projections; neither may lead the skills
- Step 11 must be last among the content steps — mirroring an unfinished tree just has to be redone
- Step 12 is independent of Step 11 and may run in parallel with it

## Test Strategy

The change is documentation-only; there is no compiled surface. Verification is therefore textual and structural:

| Check | Method |
| --- | --- |
| Mirror byte-identity | `scripts/verify-mirrors.sh` exits 0 — the same gate CI runs |
| No orphaned gate references | `grep -rin "gate" .claude/skills .tarnished/workflows .agents templates/` reviewed by hand; every hit is either intentional or fixed |
| Every FR is landed | Walk FR-1..FR-19 against the diff; the issue is the checklist |
| Ceiling arithmetic | Count the invocation points in the rewritten table; it must sum to 11 |
| Class labelling is total | No invocation-table row lacks a class |
| Consult ordering in `/design` | The conformance phase is numbered between the snapshot and the commit, not after |
| Skip path writes a record | The `skipped — <reason>` verdict is reachable from the NFR-2 fallback text |
| Evidence table has no redesign path | No row leads from a missing conformance record back into `/design` |
| Requirement-adherence criterion | Present inline in the review prompt template, not by path reference |

Self-hosting note: this repository dogfoods its own lifecycle assets, so the `/review` and `/pr` stages of **this very issue** exercise the pre-change behavior, not the post-change behavior. The new conformance path is first exercised on the next issue. That is expected and should be stated in the PR body rather than treated as a gap.
