# Workflow: flow

Run the lifecycle end to end for one issue, entering at the first incomplete stage. A run can begin from a raw requirement, before any issue exists. This is an orchestration entrypoint over the five stages, not a sixth stage — each stage's semantics are defined by its own contract.

## Inputs

- Issue number. When absent, infer it from the current branch; failing that, ask whether to name an existing issue or to start from a raw requirement, in which case the `issue` stage creates the number.
- Base branch, defaulting to `develop`. One value is used for branch creation, the review diff base, and the PR target.
- Optional explicit entry stage.
- Optional merge request, forwarded to `pr`.

## Procedure

1. Resolve the issue number by precedence, first match wins: an explicit requirement-first entry (skip resolution — the `issue` stage creates the number), an explicit issue number, the current branch name, or a question offering both entries. Check the requirement-first entry before asking, or the question is put to a user who already answered it. Requesting both is contradictory; report it rather than choosing.
2. Resolve the base branch.
3. Determine the entry stage from repository evidence, unless one was given explicitly. Skip this entirely for a requirement-first entry — nothing has begun, so there is nothing to resume:
   - requirement-first entry → enter at `issue`
   - no branch matching the issue → enter at `design`
   - branch exists, no design commit → enter at `design`
   - design commit, no later commits → enter at `implement`
   - implementation commits, no review artifact → enter at `review`
   - review artifact, no pull request → enter at `pr`
   - open pull request → resume at `pr`; CI validation and any merge still have to run
   - merged pull request → nothing to do; report and stop
   - closed but unmerged pull request → report it and stop
   When an entry stage is given explicitly and its prerequisites are absent, report what is missing and stop. The `issue` stage has no prerequisites, because it creates them.
4. Surface stage progress so a long run is observable.
5. Run each stage from the entry point through `pr`, following that stage's own contract and passing the base branch through unchanged. When the run starts at `issue`, capture the number it produces and use it for every later stage.
6. Gate on approval twice: after an issue this run created, before designing against it; and before leaving `design` for `implement`. Skip the first on a resumed run, which arrives with a number already. The second applies on resumed runs too, because a design commit records that artifacts were written, not that they were approved.
7. Triage review findings before `pr`: fix Critical and Major findings. Critical findings are not deferrable. When intending to leave a Major unfixed, consult the advisor first and record the rationale.
8. Stop and report at the first stage that cannot complete, naming the stage and what blocked it.

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
