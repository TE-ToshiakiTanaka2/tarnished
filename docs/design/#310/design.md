# Design: #310 Make `/flow` reachable from a raw requirement

## Context

`/flow` (shipped in #308, merged as `292191c`) orchestrates the five lifecycle stages for one issue, deriving its entry point from repository evidence rather than a state file. It exists at three altitudes: the contract `.tarnished/workflows/flow.md`, the operational spec `.claude/skills/flow/SKILL.md`, and the Codex projection `.agents/skills/flow/SKILL.md`, each mirrored into `templates/` and checked by `scripts/verify-mirrors.sh`.

Requirement discovery itself already exists and is not in question: `/issue` carries `erd:brainstorm` Socratic dialogue, structured questions for enumerable choices, an advisor scope check, and an iterate-until-approved loop. What is broken is the path from `/flow` into it.

## Architecture Overview (delta)

The defect is an **ordering** bug, not a missing feature. `/flow` resolves the issue number in Stage 1 (`flow/SKILL.md:37`) but consults `--from` only in Stage 2 (`:65`). So `--from issue` — the documented requirement-first entry — is asked for a number before the flag that answers the question is ever read.

The fix is therefore not "add a fallback branch" but **restate Stage 1 as an ordered resolution**, so the flag is consulted before the question is asked. That single reformulation makes this class of bug structurally impossible rather than fixed once.

Five changes follow from it, plus one correction of a #308 miss.

## Interface Design (delta)

### Stage 1 becomes an ordered resolution

Replace the current single sentence with an explicit precedence list, first match wins:

| # | Condition | Result |
| --- | --- | --- |
| 1 | `--from issue` given | Skip number resolution entirely; entry stage is `issue` |
| 2 | `--issue N` given | `N` |
| 3 | Current branch matches `.../#<n>/...` | `<n>` |
| 4 | Nothing resolved | Structured choice: **name an existing issue** or **start from a requirement** (the latter sets entry `issue`) |

Rule 1 is the whole fix. A "present the choice when nothing resolves" rule alone would still prompt on `--from issue`, since no number resolves there either — re-creating the defect this issue exists to close.

`--from issue` together with `--issue N` is contradictory: the stage creates the number that the flag supplies. Report the contradiction and ask which was meant, rather than silently preferring one.

### Stage 2 needs a carve-out, not just a row

Three things in Stage 2 presuppose a number and must be scoped to the number-carrying path:

- The preamble (`:45`) mandates resolving, fetching, and checking out the issue branch **before running any stage**. In requirement-first entry no branch exists yet — `/design` creates it once `/issue` returns a number.
- The `--from` override rule (`:65`) stops when "the named stage's prerequisites are absent". Nothing defines the `issue` stage's prerequisites, so a literal reading treats the missing number as a missing prerequisite and stops. State explicitly that `issue` has none: it creates them.
- Task tracking (`:67`) must stay live on both paths.

The derivation table gains one row: no issue number and requirement-first chosen → entry is `issue`.

### A second approval gate: issue → design

`/issue`'s own approval loop (`issue/SKILL.md:42`) covers the **requirements summary** only. Estimation, Implementation Approach, and the Tasks checklist are produced afterwards in Phases 2-3 and never re-presented — yet those are exactly what scope every later stage. Without a flow-level gate, one `/flow` run goes from a raw requirement straight into a design cycle that commits artifacts, with nobody having seen the issue as filed.

The gate sits immediately after `/issue` returns, which is also immediately before `/design` — the same position. It presents the **delta** beyond what the requirements summary already covered, and offers "edit the issue, then proceed" rather than a bare approve/abort, so it does not train rubber-stamping.

**Resume semantics differ from the design gate, deliberately.** The design→implement gate re-runs on resumed runs, because a design commit proves artifacts were written, not approved. This gate is skipped on resume: a resumed run enters via `--issue N` at `design` or later, and re-asking would break the "no behavior change for runs that already carry a number" requirement. The consequence — an interrupted requirement-first run, resumed as `/flow --issue N`, proceeds on an issue nobody explicitly approved — is accepted, because by then the issue exists on GitHub and is reviewable out of band. This asymmetry is documented in the skill so it reads as a decision rather than an oversight.

### Codex projection parity

`.agents/skills/flow/SKILL.md` needs more than its step list:

| Location | Current | Change |
| --- | --- | --- |
| `:3` description | "from design through to a pull request" | Include the issue entry |
| `:10` Overview | "Run design → implement → review → pr" | Include `issue` |
| `:17` step 3 | "resolve the issue number: from the argument, else branch name, else ask" | Same ordered resolution as Stage 1 |
| `:19` step 6 | orchestration list omits `$issue` | Add `$issue` |
| `:20` step 7 | names only the design→implement confirmation | Both gates |

Fixing only the step list would satisfy the issue's checkbox while leaving the alignment requirement under-delivered.

### Claude-side surfaces beyond the stage bodies

- Frontmatter description (`:3`) enumerates "design, implement, review, pr" — no `issue`.
- Usage block (`:16-22`) shows only number-carrying invocations; `:21` reads "infer the issue from the branch, or ask".
- Error Handling (`:119`) says "Issue number unresolvable | Ask with a structured question; do not guess", which contradicts the two-way choice.

### Correction of a #308 miss

`.tarnished/workflows/flow.md:21` says "pull request exists → nothing to do; report and stop", while the SKILL distinguishes open (resume at `pr`), merged (stop), and closed-unmerged (report and stop). Both texts landed in `292191c`: the SKILL was updated when addressing the Codex review's PR-state finding, and the contract was not. This is drift introduced by #308, not pre-existing, and it is corrected here since this issue edits that file anyway.

## Data Flow

See [flowchart.md](./flowchart.md) for the ordered resolution and its interaction with entry derivation.

The "evidence is authoritative" property survives requirement-first entry. Before `/issue` creates a number there is nothing to resume, so the absence of a number is itself accurate evidence that the lifecycle has not begun. The number materialises at exactly the moment resumable state does, and resume thereafter is the ordinary `/flow --issue N` derivation.

The user choice in rule 4 is load-bearing rather than ceremony: "no number" is ambiguous between *genuinely new work* and *the user forgot `--issue`*. Auto-deriving `issue` entry would misroute the second case into an unwanted brainstorm.

## Error Handling

| Condition | Behavior |
| --- | --- |
| `--from issue` with `--issue N` | Report the contradiction and ask which was meant |
| `--from issue` | Never ask for a number; `issue` has no prerequisites |
| No number resolved | Two-way structured choice, never a bare number prompt |
| `/issue` returns no number (aborted) | Stop; do not proceed to `design` |
| Issue-approval gate declined | Stop, leaving the created issue in place for editing |

## Implementation Notes

No executable code changes — prompt documents only. `scripts/verify-mirrors.sh` is the completion criterion, and the three authored files are mirrored into `templates/` in the same commit.

No per-issue `api-spec.md`: `/flow`'s argument surface is unchanged (same four flags). What changes is the resolution precedence among them, which is behavior and belongs in this document; the cumulative `shared/api-spec.md` entry for the lifecycle argument surface is updated to record the precedence.
