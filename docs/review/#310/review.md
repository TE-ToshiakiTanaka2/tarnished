# Code Review: #310

- **Branch**: bugfix/TE-ToshiakiTanaka2/#310/make-flow-reachable-from-a-raw-requirement
- **Base**: develop (merge base: 292191c)
- **Review scope**: Medium (10 files changed, 398 insertions(+), 58 deletions(-))
- **Reviewed at**: 2026-07-27T06:11:50Z
- **Reviewer**: Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra)

The `templates/` side of every mirror pair was excluded from the reviewed diff;
`scripts/verify-mirrors.sh` passes, so it is byte-identical to the reviewed
workspace trees.

---

### Major (must fix before PR)

- [.claude/skills/flow/SKILL.md:38](/workspace/.claude/skills/flow/SKILL.md:38) “First match wins” lets `--from issue` short-circuit before detecting `--issue 310`, contradicting line 53. Invocation 5 can therefore create a new issue instead of asking which flag was intended. Validate the conflicting pair before applying precedence, matching the flowchart’s ordering. The same conflict exists in the Codex projection, contract, and shared API snapshot.

- [.claude/skills/flow/SKILL.md:91](/workspace/.claude/skills/flow/SKILL.md:91) commands the actor to run through `pr` before introducing the approval gates at line 105. The Codex and contract procedures likewise run all stages in one step and confirm afterward. Invocation 2 can consequently enter `design` before Gate A. Interleave gates directly into the stage loop: `issue → Gate A → design → Gate B → implement`. Define Gate A’s edit actor/re-presentation loop, and state that Gate B is skipped when entering at `review` or `pr`.

- [.claude/skills/flow/SKILL.md:54](/workspace/.claude/skills/flow/SKILL.md:54) gives invocation 6 a special existing-issue-only path, but line 156 still mandates both choices, while [.agents/skills/flow/SKILL.md:16](/workspace/.agents/skills/flow/SKILL.md:16) and [.tarnished/workflows/flow.md:14](/workspace/.tarnished/workflows/flow.md:14) omit the carve-out entirely. Those altitudes can override explicit `--from implement` with requirement-first entry. Define one behavior everywhere: request an existing issue number or cancel. Then enumerate forced-stage prerequisites; currently Flow requires a design gate while `/implement` says design is optional.

- [.claude/skills/flow/SKILL.md:64](/workspace/.claude/skills/flow/SKILL.md:64) cannot reliably detect a completed PR after `/pr` deletes both local and remote source branches. With no branch, line 69 derives `design`, while the only PR lookup needs the now-unresolved `<branch>` name. A later `/flow --issue N` can restart a merged issue. Query all-state PRs by linked issue before concluding that no branch means `design`, then recover `headRefName`. Also update [docs/design/shared/api-spec.md:442](/workspace/docs/design/shared/api-spec.md:442), which still documents the default open-only command.

- [.agents/skills/flow/SKILL.md:21](/workspace/.agents/skills/flow/SKILL.md:21) permits a rationale for “anything” left unfixed, contradicting the newly aligned contract and Claude rules that Critical findings are nondeferrable and Major deferral requires an advisor. State the exact policy in the Codex projection and mirror.

### Minor (fix when cheap)

- [.agents/skills/flow/agents/openai.yaml:3](/workspace/.agents/skills/flow/agents/openai.yaml:3) still advertises a design-first lifecycle. Update it to mention starting from a requirement and mirror the template copy.

- [docs/design/#310/workflow.md:84](/workspace/docs/design/#310/workflow.md:84) verifies only four happy-path invocations. Add the conflicting-flags, forced-later-stage-without-number, and explicit-review traces—the omitted cases expose the defects above.

- [.claude/skills/flow/SKILL.md:62](/workspace/.claude/skills/flow/SKILL.md:62) skips the remainder of Stage 2 for requirement-first entry, making the requirement-first table row at line 68 unreachable. Label the table as a summary or remove the executable-looking redundant row.

### Positive

- Invocations 1, 3, and 4 resolve correctly; invocation 2 correctly avoids an issue-number prompt; invocation 7 correctly treats the absent review artifact as review output rather than a prerequisite when implementation exists.
- Target-branch inspection avoids reading an unrelated `HEAD`.
- All three changed workspace/template pairs are byte-identical, and `git diff --check` passes.

Final verdict: **REQUEST_CHANGES**.

---

## Fixes Applied

All 5 Major and all 3 Minor findings fixed. Nothing deferred; no Critical
findings were reported.

### Major

- **Contradiction detection now precedes the precedence table.** The table said
  "first match wins", so rule 1 (`--from issue`) short-circuited before rule 2
  could notice a conflicting `--issue N`, leaving the contradiction paragraph
  unreachable. This was the same ordering-bug class the issue exists to fix, one
  level up. Both contradictory pairs are now rejected in an explicit step before
  any precedence rule is consulted, at all three altitudes.
- **Gates are interleaved into the run loop.** Stage 3 said "run from the entry
  stage through `pr`" and the gates lived in Stage 4, so a literal reading ran
  every stage and then confirmed. Stage 3 now states the order explicitly —
  `issue -> Gate A -> design -> Gate B -> implement -> review -> triage -> pr` —
  with "never run a later stage before a gate that precedes it has cleared".
  Same change in the Codex projection (step 7) and the contract (step 6).
- **The `--from <later stage>` carve-out is defined everywhere.** It existed only
  in the Claude Stage 1; the Error Handling table still mandated both choices,
  and the Codex projection and contract omitted it entirely, so those altitudes
  could override an explicit `--from implement` with requirement-first entry.
  Gate B's skip conditions are now enumerated too: entering at `review`/`pr`
  (implementation already happened), and entering at `implement` with no design
  artifacts, since `/implement` treats design as optional.
- **Completed issues are detected before branch evidence.** `/pr --merge` deletes
  the source branch both locally and remotely, so "no branch matching `#<n>/`"
  read as "not started" and a later `/flow --issue N` would restart a merged
  issue. Stage 2 now checks `gh issue view <n> --json
  state,stateReason,closedByPullRequestsReferences` first and recovers
  `headRefName` from the closing PR. `shared/api-spec.md` updated to match, and
  its PR query corrected to `--state all`.
- **Codex triage policy made exact.** Step 8 permitted a rationale for "anything"
  left unfixed, contradicting the Critical-not-deferrable rule the contract and
  the Claude skill now share. It now states the full policy.

### Minor

- `agents/openai.yaml` no longer advertises a design-first lifecycle.
- The design's test strategy enumerates 8 invocations rather than 4 — the added
  cases (contradictory pair, forced later stage without a number, explicit
  `--from review`, completed-and-deleted branch) are precisely the ones that
  exposed the Majors above.
- The requirement-first row in the Stage 2 derivation table was unreachable,
  since the paragraph above it skips the whole derivation for that entry. The
  table is now labelled as covering only number-carrying runs.

### Verification

All 8 invocations re-traced against the final text; each reaches its intended
entry with no spurious prompt and no stage running ahead of a preceding gate.
`verify-mirrors.sh` green, `cargo fmt/clippy/test` and bats unchanged as
expected — this branch touches no executable code.
