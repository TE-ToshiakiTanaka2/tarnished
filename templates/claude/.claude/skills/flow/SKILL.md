---
name: flow
description: Run the issue lifecycle end to end — design, implement, review, pr — for one GitHub Issue, entering at the first incomplete stage. Threads one base branch through every stage and gates on approval before implementation.
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
/flow                                 # infer the issue from the branch, or ask
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

Resolve the issue number from `--issue`, else from the current branch name (`.../#<n>/...`), else ask the user with a structured question rather than free text.

Resolve `--base`, defaulting to `develop`. Pass the same value to `/design`, `/implement`, `/review`, and `/pr` — a base that holds for the PR target but not for branch creation is the bug this argument exists to prevent.

## Stage 2: Determine the entry stage

Derive the entry point from repository evidence rather than a state file. Evidence is authoritative, survives a failed run, and needs no cleanup.

First **resolve the issue branch itself** and evaluate every subsequent question against that ref — not against `HEAD`. `/flow --issue N` is frequently run from `develop` or from another issue's branch, and reading `HEAD` there reports another issue's progress as this one's. Fetch the branch when it exists only on the remote, and check it out before running any stage.

| Evidence, evaluated on the issue branch ref | Entry stage |
| --- | --- |
| No branch matching `#<n>/`, local or remote | `design` |
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

`--from <stage>` overrides the derivation. When the named stage's prerequisites are absent, report what is missing and stop rather than proceeding on a guess.

Track the stages as tasks so a long run stays observable, and keep the task state current as each stage completes.

## Stage 3: Run the stages

Run from the entry stage through `pr`. For each stage, read its skill and follow it.

The `issue` stage is the one exception to "resolve the issue number first": it is what creates the number. When entering at `issue` — `--from issue`, or no issue number and the user asks to start from a requirement — run `/issue` with no arguments, capture the number it returns, and use that for every later stage.

| Stage | Skill | Arguments passed |
| --- | --- | --- |
| `issue` | `.claude/skills/issue/SKILL.md` | — |
| `design` | `.claude/skills/design/SKILL.md` | issue number, `--base` |
| `implement` | `.claude/skills/implement/SKILL.md` | issue number, `--base` |
| `review` | `.claude/skills/review/SKILL.md` | `--base` as the target branch |
| `pr` | `.claude/skills/pr/SKILL.md` | `--base` as the target branch, `--merge` when given |

Report each stage's own output as that stage completes, rather than accumulating everything to the end.

## Stage 4: Approval gate before implementation

Before `implement`, present the design for approval and do not proceed until the user approves.

The gate runs on **resumed** runs too, not only on runs that just executed `design`. `/design` commits its artifacts in Phase 8 and only then reaches its sign-off gate, so a design commit proves the artifacts were written, not that anyone approved them — an interrupted run would otherwise resume straight into implementation past a gate that never cleared. On a resumed run, present the already-committed design rather than re-deriving it.

## Stage 5: Review triage

After `review`, decide the disposition of each finding using the severity policy in `review/SKILL.md`: Critical and Major must be fixed before the PR.

Critical findings are not deferrable. A Critical finding blocks PR creation until it is fixed; there is no advisor consult and no rationale that clears it.

Major findings may be deferred. When intending to leave one unfixed, consult the `advisor` once — this is the mechanical trigger, not a judgment call about whether you feel uncertain — and record the rationale in the review artifact alongside the finding. Minor findings and suggestions are noted, not gated on.

## Stage 6: Pull request

Run `/pr` inline. When resuming onto an existing open PR, skip creation and continue from its CI validation. Its Phase 1 quality pass mixes judgment (which findings matter, which refactor preserves behavior) with mechanics (formatters, linters, cleanup); route within it per the delegation table rather than delegating the pass as a unit.

## Reporting

Report, in whatever shape fits the run:

- The entry stage and the evidence that selected it
- Per-stage outcome, naming stages skipped as already complete
- Artifacts each stage wrote
- Review verdict, and how each Critical and Major finding was resolved or deferred
- PR URL, CI status, and merge result when merging was requested
- Whether the advisor was consulted or skipped, and why
- Anything left incomplete, and what blocked it

## Error Handling

| Condition | Action |
| --- | --- |
| Issue number unresolvable | Ask with a structured question; do not guess |
| `--from <stage>` prerequisites absent | Report the missing prerequisite and stop |
| A stage cannot complete | Stop at that stage; report which and why. Do not run later stages on a broken prerequisite |
| Advisor unavailable | Skip the consult and note it. Advice never gates a stage |
| CI status unknown at the `/pr` timeout | Report and stop. Do not merge |

## Integration

- **Prerequisite**: a GitHub Issue exists, or `/flow` starts at the `issue` stage
- **Typical workflow**: `/flow --issue N` in place of running `/issue` → `/design` → `/implement` → `/review` → `/pr` by hand

ARGUMENTS:
$ARGUMENTS
