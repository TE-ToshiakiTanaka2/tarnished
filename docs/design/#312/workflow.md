# Workflow: #312 restructure lifecycle roles around a long-context orchestrator with delegated designer and executor

Breadth-dominated with a semantic core: ~28 files across three altitude levels under a byte-identity CI gate, but the role vocabulary, the routing principle, and the ownership of two high-judgment stages all change together. The ordering exists so every semantic decision is made once, in the contract layer, and every later step is a derivation or a copy.

## Implementation Steps

### Step 1: Verify the `[1m]` frontmatter suffix

- **Action**: Confirm whether `.claude/agents/*.md` frontmatter accepts `model: claude-opus-5[1m]`. The suffix is documented for `/model` and for `ANTHROPIC_DEFAULT_*` environment variables; frontmatter is a separate code path. If rejected, use `claude-opus-5` and record the fallback in `designer.md` and in the design.
- **Files**: none (investigation)
- **Depends on**: nothing
- **Done when**: the value used in Step 3 is confirmed to load

*Already verified and not re-litigated here*: frontmatter `model` accepts `sonnet` / `opus` / `haiku` / `fable` / a full model ID / `inherit` and defaults to `inherit`; `.claude/settings.json` supports a `model` key read once at session start.

### Step 2: Rewrite the delegation contract

- **Action**: Replace the role table with `orchestrator` / `designer` / `executor` / `external-reviewer` and remove `advisor` (FR-1, FR-6). Add the stage/role matrix (FR-2). Replace the routing principle: authoring per stage has a single owner and the orchestrator reviews, while a delegated subagent routes its own internal work — the old "route by nature within a stage" sentence must go, or it will keep justifying inline authoring. Add the per-role model binding table with its one-declaration-site rule and the parity constraint (FR-3). Add the subagent escalation protocol (FR-7). Correct the Critical/Major triage trigger to Major-only (FR-11).
- **Files**: `.claude/skills/_shared/delegation/SKILL.md`
- **Depends on**: Step 1 (for the pin value only)
- **Done when**: no `advisor` reference remains, every stage has a named authoring owner, and the escalation protocol has a concrete trigger

### Step 3: Author the two writing agents and delete the advisor

- **Action**: Create `designer.md` (`model: claude-opus-5[1m]` per Step 1, write-capable tools, scope limited to authoring from a settled spec, must not commit or re-decide scope, blocked-result protocol). Create `executor.md` (`model: claude-sonnet-5`, write-capable tools, implementation plus review-fix application plus the mechanical half of `/pr`, must not decide a merge, blocked-result protocol). Delete `advisor.md`. Leave `code-reviewer.md` untouched — it is the `/review` fallback and unrelated.
- **Files**: `.claude/agents/designer.md`, `.claude/agents/executor.md`, `.claude/agents/advisor.md` (deleted)
- **Depends on**: Steps 1, 2
- **Done when**: both definitions carry a pin, a tools list sufficient to write, and the blocked-result contract; `advisor.md` is gone

### Step 4: Pin the orchestrator's model

- **Action**: Set `"model": "claude-fable-5"` in `.claude/settings.json` and `templates/claude/.claude/settings.json`. The orchestrator is the session rather than a subagent, so no frontmatter channel reaches it.
- **Files**: `.claude/settings.json`, `templates/claude/.claude/settings.json`
- **Depends on**: Step 2
- **Done when**: both copies carry the key. Note this file is neither parity-checked nor manifest-tracked, so the two copies are edited independently and may diverge later

### Step 5: `/issue` — inline authoring

- **Action**: Remove the advisor consult. State that the orchestrator authors the issue inline in the same session that held the requirements dialogue, which is why the estimation, approach, and task breakdown need no separate conformance check. Leave the Socratic brainstorm and the approval loop untouched (NFR-4). Add the FR-15 precedence sentence.
- **Files**: `.claude/skills/issue/SKILL.md`
- **Depends on**: Step 2
- **Done when**: no advisor reference remains and the dialogue is unchanged

### Step 6: `/design` — delegate, review, then commit

- **Action**: Move artifact authoring to the designer. Add the orchestrator review against the issue's Requirements, the 2-round revise/re-review loop, and the escalation on a surviving blocking finding. **Move the commit after the review** and give it to the orchestrator. Add `orchestrator-review.md` to the directory listing and the Reporting list, marked as an audit trail rather than an evidence key. Remove the sign-off step — the review replaces it. Add the FR-15 precedence sentence.
- **Files**: `.claude/skills/design/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: no path commits before the review, and the phase table names an owner per phase

### Step 7: `/implement` — delegated authoring with the judgment carve-out

- **Action**: Move authoring to the executor with the orchestrator reviewing. Replace the "most often mis-delegated / stays with the orchestrator" paragraph with the new position **and its rationale** — the old text assumed the orchestrator was the only capable writer and that delegation had no return path; a model-pinned executor plus a mandatory blocked-result protocol changes the trade. Add the FR-15 precedence sentence.
- **Files**: `.claude/skills/implement/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: the reversal reads as intentional. A reader who finds the new instruction without the rationale will assume it is an error

### Step 8: `/review` — triage split and the second ground truth

- **Action**: Orchestrator triages; executor applies the fixes. Add the issue's Requirements to the prompt template and the ninth requirement-adherence criterion, inline (FR-12). Keep recording the resolved reviewer model and effort in the artifact header. Add the FR-15 precedence sentence.
- **Files**: `.claude/skills/review/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: both ground truths are inline in the template and fix application is delegated

### Step 9: `/pr` — split at the irreversible operation

- **Action**: Executor authors the PR body, runs the mechanical quality pass, creates the PR, and monitors CI. Orchestrator checks PR content before creation and owns the merge decision including under `--merge`. Add the FR-15 precedence sentence.
- **Files**: `.claude/skills/pr/SKILL.md`
- **Depends on**: Steps 2, 3
- **Done when**: no path lets the executor decide a merge

### Step 10: `/flow` — remove the gates

- **Action**: Delete Gates A and B. State the four remaining user stop points. Add the per-stage delegation target to the Stage 3 table. Leave the Stage 2 evidence derivation alone — the write→review→commit order preserves the meaning of every existing row. Update the triage policy for FR-11 and extend Reporting.
- **Files**: `.claude/skills/flow/SKILL.md`
- **Depends on**: Steps 6, 7, 9
- **Done when**: `grep -in "gate"` over the file returns only intentional references

### Step 11: Sweep the residual gate and advisor references

- **Action**: Gate semantics live outside Stage 4 — the skill frontmatter `description` (its discovery text), the Stage 3 stage-order line, the Stage 2 skip paragraph, the Reporting list, and the `Gate A declined` error row. Advisor references live across all six skills and the delegation policy. Fix every one.
- **Files**: `.claude/skills/flow/SKILL.md`, `.claude/skills/design/SKILL.md`, and any skill still naming `advisor`
- **Depends on**: Steps 5-10
- **Done when**: `grep -rin "advisor\|gate a\|gate b" .claude/skills .claude/agents` returns nothing unintended

### Step 12: Project into the agent-neutral contract

- **Action**: Restate the same semantics at contract altitude. `flow.md`'s procedure steps and Output list carry gate semantics; `README.md` carries the role vocabulary; every stage contract gains its authoring owner.
- **Files**: `.tarnished/workflows/{README,issue,design,implement,review,pr,flow}.md`
- **Depends on**: Steps 5-11
- **Done when**: the contract and the skills agree on roles, ownership, gates, and escalation

### Step 13: Project into Codex

- **Action**: Update the thin projections, including `.agents/skills/flow/SKILL.md`'s two "confirmations". Note in each that a profile without a subagent mechanism runs every stage inline (NFR-2) — this matters most here, since the Codex projection is exactly that case.
- **Files**: `.agents/skills/{issue,design,implement,review,pr,flow}/SKILL.md`
- **Depends on**: Step 12
- **Done when**: the Codex projection names no removed role and no gate

### Step 14: Mirror

- **Action**: Copy each changed tree to its mirror: `.claude/skills` → `templates/claude/.claude/skills`, `.claude/agents` → `templates/claude/.claude/agents` (including the deletion), `.agents` → `templates/codex/.agents`, `.tarnished/workflows/*.md` → `templates/agent-workflows/.tarnished/workflows/*.md`. Byte-identity, not paraphrase.
- **Files**: the three `templates/` trees
- **Depends on**: Steps 5-13
- **Done when**: `scripts/verify-mirrors.sh` exits 0

### Step 15: Regenerate the shared design layer

- **Action**: Overwrite with merged current truth per NFR-1 — never append. `architecture.md`'s role-delegation bullet describes the four-role advisory model; `api-spec.md` describes the `/flow` gates and the skill argument surface; `data-model.md` documents the `roles` schema; `sequence.md`'s lifecycle diagram shows no delegation.
- **Files**: `docs/design/shared/{architecture,api-spec,data-model,sequence}.md`
- **Depends on**: Steps 5-13
- **Done when**: no shared file describes the pre-#312 role model or the gates

## Task Dependencies

- Steps 2 and 3 are the semantic root; every later step derives from them
- Step 1 blocks only the pin value inside Step 3
- Step 4 is independent of Step 3 and can run beside it
- Steps 5, 6, 7, 8, 9 are independent of one another once Steps 2-3 land
- Step 10 depends on 6, 7, and 9 because it references their delegation targets
- Step 11 is a sweep, so it must follow the steps it sweeps
- Steps 12 and 13 are strictly sequential projections; neither may lead the skills
- Step 14 must be last among the content steps — mirroring an unfinished tree just has to be redone
- Step 15 is independent of Step 14 and may run in parallel with it

## Test Strategy

Documentation-only; there is no compiled surface. Verification is textual and structural.

| Check | Method |
| --- | --- |
| Mirror byte-identity | `scripts/verify-mirrors.sh` exits 0 — the same gate CI runs. `.claude/settings.json` is deliberately outside it |
| No orphaned advisor references | `grep -rin "advisor" .claude .tarnished .agents templates/` — every hit is either `code-reviewer`-related or fixed |
| No orphaned gate references | `grep -rin "gate" .claude/skills .tarnished/workflows .agents templates/` reviewed by hand |
| Every FR is landed | Walk FR-1..FR-15 against the diff; the issue is the checklist |
| One model source per role | Each of the four roles is named in exactly one file; `grep -rn "claude-fable-5\|claude-opus-5\|claude-sonnet-5\|gpt-5" .claude .tarnished .codex templates/` shows no second declaration site |
| Every stage has an authoring owner | The stage/role matrix and each stage skill agree |
| Escalation is reachable | Each of `designer.md` and `executor.md` states the blocked-result contract, and each stage skill states what the orchestrator does with one |
| Commit follows review in `/design` | No phase ordering permits a commit before the review |
| Agent definitions load | The `[1m]` value from Step 1 actually resolves |

**Self-hosting note**: this repository dogfoods its own lifecycle assets, so this issue's own `/implement`, `/review`, and `/pr` run under the **pre-change** model — inline authoring, no designer, no executor delegation. The new structure is first exercised on the next issue. State this in the PR body rather than treating it as a gap.
