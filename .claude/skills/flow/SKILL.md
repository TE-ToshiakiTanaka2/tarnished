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

Use repository evidence and the review completion contract in `.claude/skills/review/references/completion.md`. A failed lookup is unknown state, not evidence that a branch, artifact, or PR is absent.

For a requirement-first entry, go straight to `issue`; there is no existing issue state to inspect. Otherwise:

1. Check the issue's state and linked merged PRs **before** resolving or checking out its branch. Completed issues may have no surviving branch; report completion without recreating one.
2. Resolve the issue branch using `_shared/branch/SKILL.md`, including dirty-worktree and multiple-match handling. Read evidence from that branch, not an unrelated `HEAD`.
3. Query PRs across all states for the repository, head branch, and intended base. A merged PR means report completion; a closed unmerged PR or ambiguous matches require direction. An open PR is reused after any incomplete earlier stages; it does not override missing review evidence.
4. Select the earliest incomplete stage using the table below. Evaluate explicit `--from` requests against the same prerequisites; they do not bypass incomplete validation.

| Evidence on the issue branch | Entry stage |
| --- | --- |
| Open issue, no issue branch | `design` |
| No committed per-issue design and no implementation | `design` |
| Design artifacts exist, implementation not yet started | `implement` |
| Implementation exists but is partial or fails its required checks | `implement` |
| Implementation is ready, review is missing, incomplete, or stale under the completion contract | `review` |
| Implementation and current review are complete | `pr` — reuse an existing open PR when present |

A design commit uses the documented subject, but recognize equivalent committed artifacts and their orchestrator review when the subject differs. Do not infer completion from a commit subject alone. A design is optional for standalone `implement`; when an existing implementation has no design, assess it against issue requirements rather than inventing a missing-design blocker.

Before entering `review` or `pr`, inspect implementation against the issue, available design, and recorded checks. Commit presence alone can be interrupted partial work. Reuse valid checks; fill missing evidence and finish incomplete implementation first. Exclude commits confined to `docs/design/` or `docs/review/` from the simple implementation-commit heuristic, then inspect the issue's actual deliverable (including documentation-only work).

When resuming a completed review, verify `review_status`, `verified_head`, target commit, issue body digest, and current changes. Review-artifact-only commits preserve freshness; subsequent implementation or design changes require reassessment. An old `Fixes Applied` heading or an open PR does not skip this check.

Track stage progress using the available task mechanism or concise updates, and record why a stage was reused or resumed.

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
| `pr` | `.claude/skills/pr/SKILL.md` | `--base` as the target branch, `--merge` when given | `executor` drafts and monitors; `orchestrator` checks, creates, and merges |

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

Follow `/pr`. When resuming onto an existing open PR, reuse it after checking current implementation and review evidence. Skip creation; revalidate changes and CI for its current head.

The executor runs the quality pass, drafts the PR body, pushes, and monitors CI. It returns the draft to the orchestrator, which checks it and runs `gh pr create`. The orchestrator also owns the merge decision and command, including under `--merge`.

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
