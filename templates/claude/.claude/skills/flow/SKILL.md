---
name: flow
description: Run the issue lifecycle end to end — issue, design, implement, review, pr — for one GitHub Issue, entering at the first incomplete stage. Can start from a raw requirement when no issue exists yet. Threads one base branch through every stage, delegating each stage's authoring and reviewing the result inline.
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

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary, stage ownership, and the blocked-result protocol; where it disagrees with `.tarnished/workflows/flow.md`, the skills are authoritative.

`/flow` runs as the **orchestrator**. It holds the requirements dialogue, dispatches the `designer` and the `executor`, reviews what each returns, triages review findings, and owns the merge decision. It is also the only role that can reach the user, which is why this skill carries no approval gates: the party that reviews each artifact is the session itself, and it escalates when it needs to rather than stopping by default.

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
| Implementation commits present, no `docs/review/#<n>/review.md` on the branch, or one with no "Fixes Applied" section | `review` — but **first re-run the implementation review** (see below) |
| Review artifact complete, no pull request for the branch | `pr` |
| Open pull request for the branch | Resume at `pr` — CI validation and, with `--merge`, the merge still have to run |
| Merged pull request for the branch | Nothing to do — report and stop |
| Closed but unmerged pull request | Report it and stop; reopening or superseding it is the user's call |

A resumed run entering `review` re-runs the orchestrator's implementation review before the external review. The executor commits incrementally, so an interrupted `/implement` leaves commits on the branch that were never reviewed — and "implementation commits exist" cannot distinguish reviewed work from abandoned partial work. Re-running the review is cheap, is idempotent, and needs no extra artifact; the alternative, a durable completion marker, reintroduces exactly the evidence bookkeeping that moving `/design`'s commit after its review removed.

Two evidence rules are deliberately stricter than "the file exists":

- **Implementation** is a commit that touches something outside `docs/design/`. The design stage itself can produce follow-up doc commits, and treating any later commit as implementation skips the implement stage on a branch that has none.
- **Review completion** is a review artifact carrying its Phase 5 "Fixes Applied" section. `/review` writes the artifact in Phase 4, before fixes are applied and dispositions recorded, so mere existence would let an interrupted run resume past the triage in Stage 5.

Query pull requests across all states (`gh pr list --head <branch> --state all`), not just open ones — the default open-only view reports a merged PR as absent and sends the run back into PR creation.

`--from <stage>` overrides the derivation. When the named stage's prerequisites are absent, report what is missing and stop rather than proceeding on a guess. The `issue` stage is the exception: it has **no** prerequisites, because it creates them — never treat a missing issue number as a missing prerequisite for it.

Track the stages as tasks so a long run stays observable, and keep the task state current as each stage completes.

## Stage 3: Run the stages

Run from the entry stage through `pr` in this exact order:

```
issue → design → implement → review → triage → pr
```

There are no approval gates between stages. Each delegated stage ends with the orchestrator's own review of what came back, defined by that stage's skill, and a blocking finding is sent back to its author before the run moves on — capped at 2 rounds, then escalated. Never advance past a stage whose review has not cleared.

For each stage, read its skill and follow it.

When the entry stage is `issue`, run `/issue` with no arguments, capture the number it returns, and use that number for every later stage. Stage 1 rules 1 and 4 are the two routes into it.

| Stage | Skill | Arguments passed | Authoring |
| --- | --- | --- | --- |
| `issue` | `.claude/skills/issue/SKILL.md` | — | orchestrator, inline |
| `design` | `.claude/skills/design/SKILL.md` | issue number, `--base` | `designer` subagent |
| `implement` | `.claude/skills/implement/SKILL.md` | issue number, `--base` | `executor` subagent |
| `review` | `.claude/skills/review/SKILL.md` | `--base` as the target branch | `external-reviewer`; fixes by `executor` |
| `pr` | `.claude/skills/pr/SKILL.md` | `--base` as the target branch, `--merge` when given | `executor`, except content check and merge |

Where the primary agent has no subagent mechanism, every stage runs inline under it and the report says so. The procedure is unchanged; what is lost is the model separation between roles.

Report each stage's own output as that stage completes, rather than accumulating everything to the end.

## Stage 4: Where the run stops for the user

This skill has no approval gates. Both of the gates it used to carry existed because the party that could check an artifact against the requirement was a human, and the alternative — a read-only subagent — could not reach the user. With authoring delegated and the review kept in the session, the reviewer is the same party that conducted the requirements dialogue and can escalate whenever it needs to.

A run therefore stops for the user in exactly four places. The list is stated so the property is checkable rather than emergent:

1. **Requirement gathering** in `/issue` — the Socratic dialogue and the requirements-summary approval loop. The user is the irreplaceable input here, and nothing about it is delegated.
2. **An escalation** — a blocked-result from the `designer` or the `executor` whose answer is the user's to give, or a blocking review finding that survives 2 rounds. Report the finding and what was attempted.
3. **Argument resolution** — an unresolvable issue number, or a contradictory flag pair (Stage 1).
4. **A `/pr` failure** — unknown CI status at the wait deadline, a merge conflict, or the fix loop exhausting its limit.

Anything else is the orchestrator's to decide. A stop that is not on this list is a bug in the run, not a courtesy.

Stage skills carry their own interactive prompts for degraded conditions, and under `/flow` those resolve automatically rather than becoming a fifth stop. In particular, `/review` offers a choice when the configured reviewer is missing or unauthenticated: under `/flow`, fall through its resolution ladder to the next available reviewer, mark the artifact as a fallback review, and record which reviewer was used and why. Stop only when **no** reviewer at all can be resolved — that is a stage that cannot complete, which is covered by the rule below rather than by a consent prompt.

## Stage 5: Review triage

After `review`, decide the disposition of each finding using the severity policy in `review/SKILL.md`.

Critical findings are not deferrable. A Critical finding blocks PR creation until it is fixed; no rationale clears it.

Major findings may be deferred, but only with the rationale recorded in the review artifact alongside the finding. Minor findings and suggestions are noted, not gated on.

Triage is the orchestrator's judgment; applying the fixes is the `executor`'s work. Dispatch it with the must-fix list rather than editing inline.

## Stage 6: Pull request

Follow `/pr`. When resuming onto an existing open PR, skip creation and continue from its CI validation.

The stage splits at the irreversible operation: the `executor` runs the quality pass, drafts the PR body, pushes, creates the PR, and monitors CI, while the orchestrator reads the body before creation and owns the merge decision including under `--merge`. The executor never runs `gh pr merge`.

## Reporting

Report, in whatever shape fits the run:

- The entry stage, and which Stage 1 rule or which evidence selected it
- Per-stage outcome, naming stages skipped as already complete
- Artifacts each stage wrote
- Review verdict, and how each Critical and Major finding was resolved or deferred
- PR URL, CI status, and merge result when merging was requested
- Which stages were delegated and which ran inline, and why
- Every point where the run stopped for the user, matched against the four in Stage 4
- Blocked-results received, how each was resolved, and any review loop that reached its 2-round cap
- Anything left incomplete, and what blocked it

## Error Handling

| Condition | Action |
| --- | --- |
| Issue number unresolvable, no `--from` after `issue` | Offer both entries — name an existing issue, or start from a requirement. Never a bare number prompt, and never a guess |
| Issue number unresolvable, `--from` names a stage after `issue` | Ask for an existing issue number, or cancel. The requirement-first entry is not offered — it would override the `--from` just given |
| `--from issue` given with `--issue N` | Report the contradiction and ask which was meant. Checked before the precedence rules, so rule 1 cannot short-circuit past it |
| `/issue` returns no number (aborted) | Stop. Do not proceed to `design` |
| A blocked-result the orchestrator cannot answer | Escalate to the user with the question, the options, and what the subagent already checked |
| A blocking review finding survives 2 rounds | Report it with what was attempted, and escalate. Do not advance the stage |
| `--from <stage>` prerequisites absent | Report the missing prerequisite and stop |
| A stage cannot complete | Stop at that stage; report which and why. Do not run later stages on a broken prerequisite |
| No subagent mechanism available | Run every stage inline under the primary agent and say so in the report. Never silently skip a stage's review |
| CI status unknown at the `/pr` timeout | Report and stop. Do not merge |

## Integration

- **Prerequisite**: a GitHub Issue exists, or `/flow` starts at the `issue` stage
- **Typical workflow**: `/flow --issue N` in place of running `/issue` → `/design` → `/implement` → `/review` → `/pr` by hand

ARGUMENTS:
$ARGUMENTS
