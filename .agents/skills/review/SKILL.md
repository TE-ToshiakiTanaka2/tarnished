---
name: review
description: Run independent review for the current branch before PR creation. Use when the user says review, /review, $review, レビュー, 別モデルレビュー, or asks for a second opinion on the branch.
---

# Review

## Overview

Request or perform an independent review of the current branch before PR creation. This is the Codex equivalent of Claude Code's `/review`.

## Procedure

1. Read `.tarnished/workflows/review.md`.
2. If present, read `.claude/skills/review/SKILL.md` for compatibility details.
3. Detect the current branch, target branch, merge base, issue number, commit history, and diff.
4. Prefer the agent bound to the `external-reviewer` role in `.tarnished/agent-profile.json` — falling back to `review_agent` when the `roles` key is absent — when it is available and distinct from the current primary agent. Its model and reasoning effort come from the reviewer CLI's own config, which is their single source.
5. If an external review agent is unavailable, perform the review yourself and mark it as a fallback review.
6. Review against the canonical criteria — the "Review Criteria" section of the Review Prompt Template in `.claude/skills/review/SKILL.md`, restated in `AGENTS.md`. Insert them inline when constructing a reviewer prompt; do not hand a reviewer a path. Supply **two** ground truths: the design document and the issue's Requirements section. Comparing only against the design lets a requirement dropped before the design was written pass every check.
7. Save the complete result to `docs/review/#{issue_number}/review.md`, recording the reviewer along with the model and reasoning effort it resolved to.
8. Triage the findings, then fix Critical and Major before the pull request — delegating the application to the `executor` role where a subagent mechanism is available. Record a rationale for anything deliberately deferred. Then append a fix summary to the review artifact.

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
