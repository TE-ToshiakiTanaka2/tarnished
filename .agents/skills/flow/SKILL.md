---
name: flow
description: Run the full issue lifecycle end to end for one GitHub Issue. Use when the user says flow, /flow, $flow, 一連の流れ, 通しで, design から pr まで, or asks to take an issue from design through to a pull request in one go.
---

# Flow

## Overview

Run design → implement → review → pr for one issue, entering at the first incomplete stage. This is the Codex equivalent of Claude Code's `/flow`. It orchestrates the existing stage skills; it does not redefine their behavior.

## Procedure

1. Read `.tarnished/workflows/flow.md` when present. Projects scaffolded before it shipped will not have it — proceed on this skill and the per-stage contracts.
2. If present, read `.claude/skills/flow/SKILL.md` for compatibility details, and `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and routing table.
3. Resolve the issue number: from the argument, else from the current branch name, else ask.
4. Resolve the base branch, defaulting to `develop`. Use the same value for branch creation, the review diff base, and the PR target.
5. Determine the entry stage from repository evidence — issue branch, the `docs: add design documents for #<n>` commit, later commits, `docs/review/#{issue_number}/review.md`, and `gh pr list --head <branch>`. An explicit entry stage overrides this; if its prerequisites are absent, report what is missing and stop.
6. Run each stage from the entry point through `pr` by following `$design`, `$implement`, `$review`, and `$pr` in order, passing the base branch through unchanged.
7. Confirm with the user before leaving design for implementation.
8. Before `pr`, triage the review findings: fix Critical and Major. Record a rationale for anything deliberately left unfixed.
9. Stop at the first stage that cannot complete, and report which stage and why.

## Output

Report the entry stage and why it was chosen, the per-stage outcome including stages skipped as already complete, the artifacts produced, the review verdict with the disposition of each Critical and Major finding, the PR URL and CI status, the merge result when merging was requested, and anything left incomplete.
