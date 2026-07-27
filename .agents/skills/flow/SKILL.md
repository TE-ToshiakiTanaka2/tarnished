---
name: flow
description: Run the full issue lifecycle end to end for one GitHub Issue, optionally starting from a raw requirement when no issue exists yet. Use when the user says flow, /flow, $flow, 一連の流れ, 通しで, 要件から, design から pr まで, or asks to take a requirement or an issue through to a pull request in one go.
---

# Flow

## Overview

Run issue → design → implement → review → pr for one issue, entering at the first incomplete stage. A run can start from a raw requirement, in which case the issue stage creates the number the later stages use. This is the Codex equivalent of Claude Code's `/flow`. It orchestrates the existing stage skills; it does not redefine their behavior.

## Procedure

1. Read `.tarnished/workflows/flow.md` when present. Projects scaffolded before it shipped will not have it — proceed on this skill and the per-stage contracts.
2. If present, read `.claude/skills/flow/SKILL.md` for compatibility details, and `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and routing table.
3. Resolve the issue number by precedence, first match wins: (1) an explicit requirement-first entry — skip resolution, the entry stage is `issue`; (2) an issue number argument; (3) the current branch name; (4) nothing resolved — ask which entry is wanted, naming an existing issue or starting from a requirement. Check the requirement-first entry before asking, or the question is put to a user who already answered it. Requirement-first combined with an explicit issue number is contradictory; report it and ask which was meant.
4. Resolve the base branch, defaulting to `develop`. Use the same value for branch creation, the review diff base, and the PR target.
5. Determine the entry stage from repository evidence — issue branch, the `docs: add design documents for #<n>` commit, later commits, `docs/review/#{issue_number}/review.md`, and `gh pr list --head <branch> --state all`. Skip this step entirely for a requirement-first entry: no branch or artifact exists yet, and absence of evidence is accurate rather than inconclusive. An explicit entry stage overrides this; if its prerequisites are absent, report what is missing and stop — except `issue`, which has none because it creates them.
6. Run each stage from the entry point through `pr` by following `$issue`, `$design`, `$implement`, `$review`, and `$pr` in order, passing the base branch through unchanged. When the run starts at `$issue`, capture the number it returns and use it for every later stage.
7. Confirm with the user at two points: after the issue stage created an issue, before spending a design cycle on it; and before leaving design for implementation. Skip the first when the run entered at design or later — a resumed run arrives with a number already. The second runs on resumed runs too, because a design commit proves the artifacts were written, not approved.
8. Before `pr`, triage the review findings: fix Critical and Major. Record a rationale for anything deliberately left unfixed.
9. Stop at the first stage that cannot complete, and report which stage and why.

## Output

Report the entry stage and why it was chosen, the per-stage outcome including stages skipped as already complete, the artifacts produced, the review verdict with the disposition of each Critical and Major finding, the PR URL and CI status, the merge result when merging was requested, and anything left incomplete.
