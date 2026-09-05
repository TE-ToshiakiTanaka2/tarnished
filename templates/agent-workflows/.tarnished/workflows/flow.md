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
   - partial implementation or missing required checks → enter at `implement`
   - implementation ready, review missing, incomplete, or stale → enter at `review`
   - implementation and current review complete → enter at `pr`
   - open pull request → reuse it after any incomplete earlier stages; its existence does not prove review completion
   - merged pull request → nothing to do; report and stop
   - closed but unmerged pull request → report it and stop
   When an entry stage is given explicitly and its prerequisites are absent, report what is missing and stop. The `issue` stage has no prerequisites, because it creates them.
   Use `.claude/skills/review/references/completion.md` when available to verify review status, code, fetched target commit, and issue body. A legacy `Fixes Applied` heading alone is insufficient. Recognize committed design artifacts with their review even when commit wording differs. Inspect the issue branch using only existing-branch discovery and safe worktree resolution; do not create a branch during entry detection. The selected authoring stage owns branch creation. Preserve dirty worktrees via the shared branch safeguards, and treat failed lookups as unknown rather than absent state.
5. Surface stage progress so a long run is observable.
6. Run each stage from the entry point through `pr`: `issue` → `design` → `implement` → `review` → triage → `pr`. Follow each stage's own contract and pass the base branch through unchanged. When the run starts at `issue`, capture the number it produces and use it for every later stage.
7. There are no approval gates. Each delegated stage ends with the orchestrator's own review of what its author returned, and a blocking finding goes back to that author — capped at two rounds, then escalated. Never advance past a stage whose review has not cleared. A run stops for the user in exactly four places: requirement gathering, an escalation the orchestrator cannot resolve, argument resolution (including unmet prerequisites for an explicit entry stage), and a `pr` failure.
8. Triage review findings before `pr`. Critical findings are not deferrable and block the pull request until fixed. Major findings may be deferred only with the rationale recorded. Triage is the orchestrator's judgment; applying the fixes is the executor's work.
9. Stop and report at the first stage that cannot complete, naming the stage and what blocked it.

## Roles

`flow` runs as the orchestrator: it holds the requirements dialogue, dispatches the `designer` and the `executor`, reviews what each returns, triages review findings, and owns the merge decision. Each stage's authoring has one owner — see the role vocabulary and stage ownership in `README.md`. The orchestrator is the only role that can reach the user, which is why this entrypoint carries no approval gates.

## Output

- The entry stage and why it was chosen.
- Per-stage outcome, including stages skipped as already complete.
- Which stages were delegated and which ran inline, and every point where the run stopped for the user.
- The artifacts each stage produced.
- Review verdict and how each Critical or Major finding was resolved or deferred.
- Blocked-results received, how each was resolved, and any review loop that reached its two-round cap.
- Pull request URL, CI status, and merge result when merging was requested.
- Anything left incomplete, and what blocked it.
