---
name: design
description: Design a GitHub Issue before implementation using Tarnished design artifacts. Use when the user says design, /design, $design, 設計, branch作成から設計, or asks to prepare architecture for an issue.
---

# Design

## Overview

Create or update design artifacts before production code changes. This is the Codex equivalent of Claude Code's `/design`.

Read `.agents/skills/flow/references/execution.md` for scope, Codex tool and model routing, delegation, and verification rules.

## Procedure

1. Resolve the issue number from the request, conversation, or current issue branch. Ask only if it remains ambiguous or absent.
2. Read `.tarnished/workflows/design.md`.
3. If present, read `.claude/skills/design/SKILL.md` and `.claude/skills/_shared/branch/SKILL.md` for compatibility details.
4. Inspect the issue with `gh issue view <issue_number>`.
5. Create or reuse the issue branch using the project convention, cutting new branches from the requested base branch (default `develop`):

```text
{label}/{assignee}/#{issue_number}/{title}
```

6. Load `docs/design/shared/*` and relevant code paths before designing.
7. Use `.tarnished/workflows/erd/research.md`, `design.md`, and `workflow.md` as needed.
8. Write per-issue artifacts under `docs/design/#{issue_number}/`. Where a subagent mechanism is available, delegate this authoring to the `designer` role and treat a returned blocked-result as a question to answer rather than a guess to make; otherwise author inline and say so in the report.
9. Regenerate affected shared snapshots under `docs/design/shared/`.
10. Review the artifacts against the issue's Requirements before committing. Send blocking findings back to their author, capped at two rounds, then escalate. Record the findings in `docs/design/#{issue_number}/orchestrator-review.md`.
11. Commit design artifacts separately from implementation — after the review, so the commit records that the review happened.

## Output

Report the branch, commit hash, files written, skipped artifacts, the review outcome, whether authoring was delegated or inline, and the next command:

```text
Ready for $implement <issue_number>
```
