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
4. Prefer the configured review agent in `.tarnished/agent-profile.json` when it is available and distinct from the current primary agent.
5. If an external review agent is unavailable, perform the review yourself and mark it as a fallback review.
6. Review for correctness, security, error handling, edge cases, style, performance, tests, and architecture.
7. Save the complete result to `docs/review/#{issue_number}/review.md`.
8. Fix critical and major findings, then append a fix summary to the review artifact.

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
