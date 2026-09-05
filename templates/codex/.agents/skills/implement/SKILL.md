---
name: implement
description: Implement and test a GitHub Issue using Tarnished design artifacts. Use when the user says implement, /implement, $implement, 実装, テスト, or asks Codex to build the designed issue.
---

# Implement

## Overview

Implement an issue in focused commits, then verify with build, lint, and tests. This is the Codex equivalent of Claude Code's `/implement`.

Read `.agents/skills/flow/references/execution.md` for scope, Codex tool and model routing, delegation, and verification rules.

## Procedure

1. Require an issue number. If none is provided, infer it from the branch or ask for it.
2. Read `.tarnished/workflows/implement.md`.
3. If present, read `.claude/skills/implement/SKILL.md` and `.claude/skills/_shared/branch/SKILL.md` for compatibility details.
4. Reuse the design branch when it exists; otherwise create the issue branch using the project convention, cutting from the requested base branch (default `develop`).
5. Load both design layers:
   - `docs/design/shared/*`
   - `docs/design/#{issue_number}/*`
6. Inspect relevant code before editing. Prefer narrow, reviewable changes. Where a subagent mechanism is available, delegate implementation to the `executor` role; routine implementation choices follow repository evidence; questions that change requirements or design intent return as a blocked-result. Otherwise implement inline and say so in the report.
7. Use `.tarnished/workflows/erd/index-repo.md`, `implement.md`, `build.md`, `test.md`, `analyze.md`, `improve.md`, and `troubleshoot.md` as needed.
8. Run required formatting, lint, build, and tests appropriate to the affected behavior. Reuse valid results for unchanged code; report checks that do not apply or cannot run.
9. Commit each logical unit with conventional commit subjects.
10. Review the result against both the design and the issue's Requirements. Send blocking findings back, capped at two rounds, then escalate.

## Output

Report the branch, commits, verification commands, failures or skipped checks, the review outcome, whether implementation was delegated or inline, and remaining risks.

Do not create or merge a pull request in this skill.
