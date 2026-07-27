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

| Evidence | Entry stage |
| --- | --- |
| No branch matching `#<n>/` | `design` |
| Branch exists, no `docs: add design documents for #<n>` commit reachable from HEAD | `design` |
| Design commit present, no commits after it | `implement` |
| Commits after the design commit, no `docs/review/#<n>/review.md` | `review` |
| Review artifact present, `gh pr list --head <branch>` empty | `pr` |
| Pull request exists | Nothing to do — report and stop |

`--from <stage>` overrides the derivation. When the named stage's prerequisites are absent, report what is missing and stop rather than proceeding on a guess.

Track the stages as tasks so a long run stays observable, and keep the task state current as each stage completes.

## Stage 3: Run the stages

Run from the entry stage through `pr`. For each stage, read its skill and follow it:

| Stage | Skill | Arguments passed |
| --- | --- | --- |
| `issue` | `.claude/skills/issue/SKILL.md` | — |
| `design` | `.claude/skills/design/SKILL.md` | issue number, `--base` |
| `implement` | `.claude/skills/implement/SKILL.md` | issue number, `--base` |
| `review` | `.claude/skills/review/SKILL.md` | `--base` as the target branch |
| `pr` | `.claude/skills/pr/SKILL.md` | `--base` as the target branch, `--merge` when given |

Report each stage's own output as that stage completes, rather than accumulating everything to the end.

## Stage 4: Approval gate before implementation

After `design` and before `implement`, present the design for approval. Do not proceed to implementation until the user approves. Skip the gate only when entering at or after `implement`, since the design was approved on the run that produced it.

## Stage 5: Review triage

After `review`, decide the disposition of each finding using the severity policy in `review/SKILL.md`: Critical and Major must be fixed before the PR.

When intending to leave a Critical or Major finding unfixed, consult the `advisor` once — this is the mechanical trigger, not a judgment call about whether you feel uncertain — and record the rationale in the review artifact alongside the finding. Minor findings and suggestions are noted, not gated on.

## Stage 6: Pull request

Run `/pr` inline. Its Phase 1 quality pass mixes judgment (which findings matter, which refactor preserves behavior) with mechanics (formatters, linters, cleanup); route within it per the delegation table rather than delegating the pass as a unit.

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
