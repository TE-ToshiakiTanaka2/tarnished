# Workflow: flow

Run the lifecycle end to end for one issue, entering at the first incomplete stage. A run can begin from a raw requirement, before any issue exists. This is an orchestration entrypoint over the five stages, not a sixth stage — each stage's semantics are defined by its own contract.

## Inputs

- Issue number. When absent, infer it from the current branch; failing that, ask whether to name an existing issue or to start from a raw requirement, in which case the `issue` stage creates the number.
- Base branch, defaulting to `develop`. One value is used for branch creation, the review diff base, and the PR target.
- Optional explicit entry stage.
- Optional merge request, forwarded to `pr`.

## Procedure

1. Reject contradictory argument pairs before applying any precedence, since a first-match-wins rule would otherwise short-circuit and never notice the conflict: requirement-first together with an explicit issue number, and a forced stage after `issue` with no resolvable number. Report the conflict and ask; for the second, offer only an existing issue number or cancellation, never the requirement-first entry.
2. Resolve the issue number by precedence, first match wins: an explicit requirement-first entry (skip resolution — the `issue` stage creates the number), an explicit issue number, the current branch name, or a question offering both entries. Check the requirement-first entry before asking, or the question is put to a user who already answered it.
3. Resolve the base branch.
4. Determine the entry stage from repository evidence, unless one was given explicitly. Skip this entirely for a requirement-first entry — nothing has begun, so there is nothing to resume:
   - requirement-first entry → enter at `issue`
   - issue closed as completed, or closed by a merged pull request → nothing to do; report and stop. Check this before branch evidence: a merge deletes the source branch, so a finished issue leaves no branch and "no branch" would otherwise read as "not started"
   - no branch matching the issue, issue still open → enter at `design`
   - branch exists, no design commit → enter at `design`
   - design commit, no later commits → enter at `implement`
   - implementation commits, no review artifact → enter at `review`
   - review artifact, no pull request → enter at `pr`
   - open pull request → resume at `pr`; CI validation and any merge still have to run
   - merged pull request → nothing to do; report and stop
   - closed but unmerged pull request → report it and stop
   When an entry stage is given explicitly and its prerequisites are absent, report what is missing and stop. The `issue` stage has no prerequisites, because it creates them.
5. Surface stage progress so a long run is observable.
6. Run each stage from the entry point through `pr`, honouring each gate as it is reached rather than as a review afterwards: `issue` → gate → `design` → gate → `implement` → `review` → triage → `pr`. Follow each stage's own contract and pass the base branch through unchanged. When the run starts at `issue`, capture the number it produces and use it for every later stage.
7. The first gate covers an issue this run created and is skipped on a resumed run, which arrives with a number already. The second applies on resumed runs too, because a design commit records that artifacts were written, not that they were approved; skip it when entering at `review` or `pr`, and when entering at `implement` with no design artifacts, since `implement` treats design as optional.
8. Triage review findings before `pr`. Critical findings are not deferrable and block the pull request until fixed. Major findings may be deferred only after an advisor consult, with the rationale recorded.
9. Stop and report at the first stage that cannot complete, naming the stage and what blocked it.

## Roles

Work within each stage is routed by nature, not by stage — see the role vocabulary in `README.md`. Stage boundaries are not delegation boundaries.

## Output

- The entry stage and why it was chosen.
- Per-stage outcome, including stages skipped as already complete.
- Which approval gates ran and which were skipped.
- The artifacts each stage produced.
- Review verdict and how each Critical or Major finding was resolved or deferred.
- Pull request URL, CI status, and merge result when merging was requested.
- Anything left incomplete, and what blocked it.
