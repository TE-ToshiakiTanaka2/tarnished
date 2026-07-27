# Workflow: flow

Run the lifecycle end to end for one issue, entering at the first incomplete stage. This is an orchestration entrypoint over the five stages, not a sixth stage — each stage's semantics are defined by its own contract.

## Inputs

- Issue number. When absent, infer it from the current branch, or ask.
- Base branch, defaulting to `develop`. One value is used for branch creation, the review diff base, and the PR target.
- Optional explicit entry stage.
- Optional merge request, forwarded to `pr`.

## Procedure

1. Resolve the issue number and the base branch.
2. Determine the entry stage from repository evidence, unless one was given explicitly:
   - no branch matching the issue → enter at `design`
   - branch exists, no design commit → enter at `design`
   - design commit, no later commits → enter at `implement`
   - implementation commits, no review artifact → enter at `review`
   - review artifact, no pull request → enter at `pr`
   - pull request exists → nothing to do; report and stop
   When an entry stage is given explicitly and its prerequisites are absent, report what is missing and stop.
3. Surface stage progress so a long run is observable.
4. Run each stage from the entry point through `pr`, following that stage's own contract and passing the base branch through unchanged.
5. Gate on approval before leaving `design` for `implement`.
6. Triage review findings before `pr`: fix Critical and Major findings. When intending to leave one unfixed, consult the advisor first and record the rationale.
7. Stop and report at the first stage that cannot complete, naming the stage and what blocked it.

## Roles

Work within each stage is routed by nature, not by stage — see the role vocabulary in `README.md`. Stage boundaries are not delegation boundaries.

## Output

- The entry stage and why it was chosen.
- Per-stage outcome, including stages skipped as already complete.
- The artifacts each stage produced.
- Review verdict and how each Critical or Major finding was resolved or deferred.
- Pull request URL, CI status, and merge result when merging was requested.
- Anything left incomplete, and what blocked it.
