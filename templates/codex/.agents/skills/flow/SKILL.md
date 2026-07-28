---
name: flow
description: Run the full issue lifecycle end to end for one GitHub Issue, optionally starting from a raw requirement when no issue exists yet. Use when the user says flow, /flow, $flow, 一連の流れ, 通しで, 要件から, design から pr まで, or asks to take a requirement or an issue through to a pull request in one go.
---

# Flow

## Overview

Run issue → design → implement → review → pr for one issue, entering at the first incomplete stage. A run can start from a raw requirement, in which case the issue stage creates the number the later stages use. This is the Codex equivalent of Claude Code's `/flow`. It orchestrates the existing stage skills; it does not redefine their behavior. You run as the orchestrator: you hold the requirements dialogue, review each stage's output, triage review findings, and own the merge decision.

## Procedure

1. Read `.tarnished/workflows/flow.md` when present. Projects scaffolded before it shipped will not have it — proceed on this skill and the per-stage contracts.
2. If present, read `.claude/skills/flow/SKILL.md` for compatibility details, and `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary, stage ownership, and the blocked-result protocol. Where those disagree with `.tarnished/workflows/flow.md`, the skills are authoritative — they are refresh-managed and the contract is not.
3. Reject contradictory argument pairs **before** applying any precedence, or a first-match-wins rule short-circuits and never notices the conflict: requirement-first combined with an explicit issue number (report it and ask which was meant), and a forced stage after `issue` with no resolvable number (ask for an existing issue number or cancel — do not offer the requirement-first entry, which would override the forced stage).
4. Then resolve the issue number by precedence, first match wins: (1) an explicit requirement-first entry — skip resolution, the entry stage is `issue`; (2) an issue number argument; (3) the current branch name; (4) nothing resolved — ask which entry is wanted, naming an existing issue or starting from a requirement. Check the requirement-first entry before asking, or the question is put to a user who already answered it.
5. Resolve the base branch, defaulting to `develop`. Use the same value for branch creation, the review diff base, and the PR target.
6. Determine the entry stage from repository evidence. Check the issue first with `gh issue view <n> --json state,stateReason,closedByPullRequestsReferences`: a merge deletes the source branch, so a completed issue leaves no branch and "no branch" would otherwise read as "not started" — a closed-completed issue means report and stop. Otherwise read the issue branch, the `docs: add design documents for #<n>` commit, later commits, `docs/review/#{issue_number}/review.md`, and `gh pr list --head <branch> --state all`. Skip this step entirely for a requirement-first entry: no branch or artifact exists yet, and absence of evidence is accurate rather than inconclusive. An explicit entry stage overrides this; if its prerequisites are absent, report what is missing and stop — except `issue`, which has none because it creates them.
7. Run each stage from the entry point through `pr` in this order: `$issue` → `$design` → `$implement` → `$review` → triage → `$pr`. Pass the base branch through unchanged. When the run starts at `$issue`, capture the number it returns and use it for every later stage.
8. There are no approval confirmations between stages. Each stage that delegates its authoring ends with your own review of what came back, and a blocking finding goes back to its author — capped at two rounds, then escalated. Never advance past a stage whose review has not cleared. A run stops for the user in exactly four places: requirement gathering in `$issue`, an escalation you cannot resolve, argument resolution, and a `$pr` failure. Where no subagent mechanism is available to you, every stage runs inline; say so in the report, and do not skip the reviews — they are yours either way. Inline execution is the capability fallback, not a property of any particular agent family.
9. Before `$pr`, triage the review findings. Critical findings are not deferrable and block PR creation until fixed. Major findings may be deferred only with the rationale recorded in the review artifact. Minor findings and suggestions are noted, not gated on.
10. Stop at the first stage that cannot complete, and report which stage and why.

## Output

Report the entry stage and why it was chosen, which stages were delegated and which ran inline, every point where the run stopped for the user, the per-stage outcome including stages skipped as already complete, the artifacts produced, the review verdict with the disposition of each Critical and Major finding, the PR URL and CI status, the merge result when merging was requested, and anything left incomplete.
