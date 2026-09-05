---
name: review
description: Run independent review for the current branch before PR creation. Use when the user says review, /review, $review, レビュー, 別モデルレビュー, or asks for a second opinion on the branch.
---

# Review

## Overview

Request or perform an independent review of the current branch before PR creation. This is the Codex equivalent of Claude Code's `/review`.

Read `.agents/skills/flow/references/execution.md` for scope, Codex tool and model routing, delegation, and verification rules.

## Procedure

1. Read `.tarnished/workflows/review.md`.
2. If present, read `.claude/skills/review/SKILL.md` for compatibility details.
3. Parse reviewer flags separately from the target branch; detect the current issue branch, freshly fetched target commit, merge base, issue number, commit history, and diff. Read `.claude/skills/review/references/completion.md` when present and record the review's input evidence.
4. Prefer the agent bound to the `external-reviewer` role in `.tarnished/agent-profile.json` — falling back to `review_agent` when the `roles` key is absent — when it is available and distinct from the current primary agent. Its model and reasoning effort come from the reviewer CLI's own config, which is their single source.
5. If an external reviewer is unavailable, use a fresh-context read-only reviewer subagent when permitted. Otherwise review inline, explicitly marking it as self-review without independence.
6. At every change size, review against all nine canonical criteria — the "Review Criteria" section of the Review Prompt Template in `.claude/skills/review/SKILL.md`, restated in `AGENTS.md`. Insert them inline when constructing a reviewer prompt; do not hand a reviewer a path. Supply **two** ground truths: the design document and the issue's Requirements section. Comparing only against the design lets a requirement dropped before the design was written pass every check.
7. Save the complete result to `docs/review/#{issue_number}/review.md`, recording the reviewer along with the model and reasoning effort it resolved to.
8. For a review-only request, report findings without applying fixes. When fixes are requested or this stage is part of `$flow`, triage the findings, then fix Critical and Major before the pull request — delegating the application to the `executor` role where a subagent mechanism is available. Record a rationale for anything deliberately deferred. Then append verified fix dispositions and completion evidence to the review artifact. A clean review needs no source edit or fix commit; record `None required`. Unresolved required fixes remain report-only when fixes were not requested.

## Output Format

```markdown
## Review Summary

**Overall**: APPROVE / REQUEST_CHANGES / COMMENT

## Critical Issues
- [file:line] Description and suggested fix

## Major Issues
- [file:line] Description and suggested fix

## Minor Issues
- [file:line] Description and suggested fix

## Suggestions
- [file:line] Optional improvements
```

If there are no findings in a category, say so explicitly.
