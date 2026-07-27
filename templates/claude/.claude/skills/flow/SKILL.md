---
name: flow
description: Run the issue lifecycle end to end — issue, design, implement, review, pr — for one GitHub Issue, entering at the first incomplete stage. Can start from a raw requirement when no issue exists yet. Threads one base branch through every stage and gates on approval before design and before implementation.
argument-hint: "[--issue N] [--base <branch>] [--from <stage>] [--merge]"
disable-model-invocation: true
---

# Skill: Flow

Runs the lifecycle for one issue in a single pass. This is an orchestration entrypoint over the five stages, not a sixth stage — each stage's behavior stays defined by its own skill, and this skill reads and follows those skills rather than reimplementing them.

This skill is the Claude Code projection of `.tarnished/workflows/flow.md`. Keep the shared workflow source and this tool-specific entrypoint aligned. Projects scaffolded before `flow.md` shipped will not have it — `.tarnished/workflows/*.md` is not refresh-managed. Proceed on this skill and the per-stage contracts when it is absent.

## Usage

```
/flow --issue 123                     # enter at the first incomplete stage
/flow --issue 123 --base main         # branch from, review against, and target main
/flow --issue 123 --from implement    # force entry at implement
/flow --issue 123 --merge             # forward --merge to /pr
/flow --from issue                    # start from a raw requirement — /issue creates the number
/flow                                 # infer the issue from the branch, else offer both entries
```

| Argument | Default | Meaning |
| --- | --- | --- |
| `--issue N` | inferred | Issue to run |
| `--base <branch>` | `develop` | Branch creation base, review diff base, and PR target — one value end to end |
| `--from <stage>` | derived | `issue` \| `design` \| `implement` \| `review` \| `pr` |
| `--merge` | off | Forwarded to `/pr` |

## Roles

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary, the routing table, and the advisor's invocation points. Stage boundaries are not delegation boundaries: route each unit of work by its nature, so a stage can be part-inline and part-delegated.

## Stage 1: Resolve inputs

**First, reject contradictory argument pairs.** This happens before any precedence rule, because a first-match-wins table would otherwise short-circuit on rule 1 and never notice the conflicting flag:

- `--from issue` with `--issue N` — the stage creates the number the flag supplies. Report the contradiction and ask which was meant.
- `--from <stage after issue>` with no resolvable issue number — a later stage cannot run against an issue that does not exist yet. Ask for an existing issue number, or cancel. Do not offer the requirement-first entry here; it would override the `--from` the user just gave.

**Then** resolve the issue number by this precedence, first match wins:

| # | Condition | Result |
| --- | --- | --- |
| 1 | `--from issue` given | Skip number resolution entirely — the entry stage is `issue`, and `/issue` creates the number |
| 2 | `--issue N` given | `N` |
| 3 | Current branch matches `.../#<n>/...` | `<n>` |
| 4 | Nothing above resolved | Ask a structured question offering two entries: **name an existing issue**, or **start from a requirement** (the latter sets the entry stage to `issue`). When `--from` named a stage after `issue`, the contradiction check above has already narrowed this to the first option |

Rule 1 comes first by necessity, not convention. A rule that only offers the choice "when no number resolves" would still prompt on `--from issue`, because no number resolves there either — which is the bug this ordering exists to prevent. Consult the flag before asking the question.

Rule 4 asks rather than assuming, because "no number" is ambiguous: it means either genuinely new work or a forgotten `--issue`. Auto-entering `issue` would push the second case into an unwanted requirements brainstorm.

Resolve `--base`, defaulting to `develop`. Pass the same value to `/design`, `/implement`, `/review`, and `/pr` — a base that holds for the PR target but not for branch creation is the bug this argument exists to prevent.

## Stage 2: Determine the entry stage

Derive the entry point from repository evidence rather than a state file. Evidence is authoritative, survives a failed run, and needs no cleanup.

**When Stage 1 resolved the entry stage to `issue`, skip the rest of this stage** and go straight to Stage 3. There is no branch, no commit, and no artifact to read yet — `/design` creates the branch once `/issue` returns a number. Absence of evidence is accurate here rather than inconclusive: nothing has begun, so there is nothing to resume. Still set up the task tracking described at the end of this stage.

Otherwise, first **resolve the issue branch itself** and evaluate every subsequent question against that ref — not against `HEAD`. `/flow --issue N` is frequently run from `develop` or from another issue's branch, and reading `HEAD` there reports another issue's progress as this one's. Fetch the branch when it exists only on the remote, and check it out before running any stage.

Before reading branch evidence, **check the issue itself**. `/pr --merge` deletes the source branch both locally and remotely, so a completed issue leaves no branch behind and "no branch" would otherwise be read as "not started":

```bash
gh issue view <n> --json state,stateReason,closedByPullRequestsReferences
```

A `CLOSED`/`COMPLETED` issue, or one with a merged pull request in `closedByPullRequestsReferences`, is finished — report and stop. Recover the branch name from that pull request's `headRefName` when you need it for reporting.

The requirement-first entry never reaches this table — Stage 1 already set it and the paragraph above skips the derivation. The table covers only runs that carry an issue number.

| Evidence, evaluated on the issue branch ref | Entry stage |
| --- | --- |
| Issue closed as completed, or closed by a merged PR | Nothing to do — report and stop |
| No branch matching `#<n>/`, local or remote, and the issue is open | `design` |
| Branch exists, no `docs: add design documents for #<n>` commit on it | `design` |
| Design commit present, no later commit touching anything outside `docs/design/` | `implement` |
| Implementation commits present, no `docs/review/#<n>/review.md` on the branch, or one with no "Fixes Applied" section | `review` |
| Review artifact complete, no pull request for the branch | `pr` |
| Open pull request for the branch | Resume at `pr` — CI validation and, with `--merge`, the merge still have to run |
| Merged pull request for the branch | Nothing to do — report and stop |
| Closed but unmerged pull request | Report it and stop; reopening or superseding it is the user's call |

Two evidence rules are deliberately stricter than "the file exists":

- **Implementation** is a commit that touches something outside `docs/design/`. The design stage itself can produce follow-up doc commits, and treating any later commit as implementation skips the implement stage on a branch that has none.
- **Review completion** is a review artifact carrying its Phase 5 "Fixes Applied" section. `/review` writes the artifact in Phase 4, before fixes are applied and dispositions recorded, so mere existence would let an interrupted run resume past the triage in Stage 5.

Query pull requests across all states (`gh pr list --head <branch> --state all`), not just open ones — the default open-only view reports a merged PR as absent and sends the run back into PR creation.

`--from <stage>` overrides the derivation. When the named stage's prerequisites are absent, report what is missing and stop rather than proceeding on a guess. The `issue` stage is the exception: it has **no** prerequisites, because it creates them — never treat a missing issue number as a missing prerequisite for it.

Track the stages as tasks so a long run stays observable, and keep the task state current as each stage completes.

## Stage 3: Run the stages

Run from the entry stage through `pr` in this exact order, honouring each gate **as it is reached** — not as a review afterwards:

```
issue → Gate A → design → Gate B → implement → review → triage → pr
```

Both gates are defined in Stage 4. A gate that comes before your entry stage does not apply. Never run a later stage before a gate that precedes it has cleared.

For each stage, read its skill and follow it.

When the entry stage is `issue`, run `/issue` with no arguments, capture the number it returns, and use that number for every later stage. Stage 1 rules 1 and 4 are the two routes into it.

| Stage | Skill | Arguments passed |
| --- | --- | --- |
| `issue` | `.claude/skills/issue/SKILL.md` | — |
| `design` | `.claude/skills/design/SKILL.md` | issue number, `--base` |
| `implement` | `.claude/skills/implement/SKILL.md` | issue number, `--base` |
| `review` | `.claude/skills/review/SKILL.md` | `--base` as the target branch |
| `pr` | `.claude/skills/pr/SKILL.md` | `--base` as the target branch, `--merge` when given |

Report each stage's own output as that stage completes, rather than accumulating everything to the end.

## Stage 4: Approval gates

Two gates, with deliberately different resume semantics.

### Gate A — before `design`, when this run created the issue

When the run entered at `issue`, present the created issue for approval before spending a design cycle on it.

`/issue`'s own approval loop covers the **requirements summary** only. Its estimation, implementation approach, and task breakdown are produced afterwards and never re-presented — and those are what scope every later stage. Without this gate, one run goes from a raw requirement straight into a design cycle that commits artifacts, with nobody having seen the issue as filed.

Present the delta beyond what was already approved inside `/issue`, not the whole issue again, and offer "edit the issue, then proceed" rather than a bare approve/abort. A gate that can only be accepted trains rubber-stamping.

Skip this gate when the run entered at `design` or later. A resumed run arrives via `--issue N`, and re-asking would change behavior for runs that already carry a number. The consequence is accepted: an interrupted requirement-first run, resumed later, proceeds on an issue nobody explicitly approved — by then the issue exists on GitHub and is reviewable out of band.

### Gate B — before `implement`

Present the design for approval and do not proceed until the user approves.

Unlike Gate A, this gate runs on **resumed** runs too. `/design` commits its artifacts in Phase 8 and only then reaches its sign-off gate, so a design commit proves the artifacts were written, not that anyone approved them — an interrupted run would otherwise resume straight into implementation past a gate that never cleared. On a resumed run, present the already-committed design rather than re-deriving it.

Two cases skip it:

- **Entering at `review` or `pr`** — implementation already happened, so a gate before it has nothing left to guard.
- **Entering at `implement` with no design artifacts** — `/implement` treats design as optional, so there may be nothing to present. Say so in the report rather than blocking; the user asked for that entry explicitly.

The asymmetry between the two is deliberate: Gate B has no way to tell an approved design from an unapproved one, while Gate A's subject is a GitHub issue that remains visible and editable after the run ends.

## Stage 5: Review triage

After `review`, decide the disposition of each finding using the severity policy in `review/SKILL.md`: Critical and Major must be fixed before the PR.

Critical findings are not deferrable. A Critical finding blocks PR creation until it is fixed; there is no advisor consult and no rationale that clears it.

Major findings may be deferred. When intending to leave one unfixed, consult the `advisor` once — this is the mechanical trigger, not a judgment call about whether you feel uncertain — and record the rationale in the review artifact alongside the finding. Minor findings and suggestions are noted, not gated on.

## Stage 6: Pull request

Run `/pr` inline. When resuming onto an existing open PR, skip creation and continue from its CI validation. Its Phase 1 quality pass mixes judgment (which findings matter, which refactor preserves behavior) with mechanics (formatters, linters, cleanup); route within it per the delegation table rather than delegating the pass as a unit.

## Reporting

Report, in whatever shape fits the run:

- The entry stage, and which Stage 1 rule or which evidence selected it
- Per-stage outcome, naming stages skipped as already complete
- Artifacts each stage wrote
- Review verdict, and how each Critical and Major finding was resolved or deferred
- PR URL, CI status, and merge result when merging was requested
- Which approval gates ran, which were skipped, and why
- Whether the advisor was consulted or skipped, and why
- Anything left incomplete, and what blocked it

## Error Handling

| Condition | Action |
| --- | --- |
| Issue number unresolvable, no `--from` after `issue` | Offer both entries — name an existing issue, or start from a requirement. Never a bare number prompt, and never a guess |
| Issue number unresolvable, `--from` names a stage after `issue` | Ask for an existing issue number, or cancel. The requirement-first entry is not offered — it would override the `--from` just given |
| `--from issue` given with `--issue N` | Report the contradiction and ask which was meant. Checked before the precedence rules, so rule 1 cannot short-circuit past it |
| `/issue` returns no number (aborted) | Stop. Do not proceed to `design` |
| Gate A declined | Stop, leaving the created issue in place for editing |
| `--from <stage>` prerequisites absent | Report the missing prerequisite and stop |
| A stage cannot complete | Stop at that stage; report which and why. Do not run later stages on a broken prerequisite |
| Advisor unavailable | Skip the consult and note it. Advice never gates a stage |
| CI status unknown at the `/pr` timeout | Report and stop. Do not merge |

## Integration

- **Prerequisite**: a GitHub Issue exists, or `/flow` starts at the `issue` stage
- **Typical workflow**: `/flow --issue N` in place of running `/issue` → `/design` → `/implement` → `/review` → `/pr` by hand

ARGUMENTS:
$ARGUMENTS
