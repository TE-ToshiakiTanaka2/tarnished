# Workflow: review

Request an independent second opinion on the current branch before PR creation.

## Inputs

- Current feature branch.
- Target branch (default `develop`).
- Merge base with the target branch.
- Commit history and diff.
- Design artifacts for the issue when available.

## Procedure

1. Detect the current branch, target branch, and merge base.
2. Extract the issue number from the branch name when possible.
3. Determine review scope from diff size and affected areas.
4. Resolve the reviewer in priority order:
   1. The agent bound to the `external-reviewer` role in `.tarnished/agent-profile.json`, defaulting to `{{AI_REVIEW_AGENT}}`, when it is installed and distinct from the primary agent. Its model and reasoning effort come from the reviewer CLI's own config, which is their single source.
   2. An installed external review CLI (e.g. Codex).
   3. A fresh-context independent review by the primary agent itself (e.g. a read-only reviewer subagent), marked as a fallback review.
5. Review for bugs and logic errors, security, performance, code quality, type safety, error handling, test coverage, adherence to the design artifacts, and adherence to the issue's own requirements. The design and the issue are two distinct ground truths: comparing only against the design lets a requirement dropped before the design was written pass every check. The canonical criteria list, worded for a reviewer prompt, is the "Review Criteria" section of the Review Prompt Template in `.claude/skills/review/SKILL.md`; insert it inline when constructing the prompt rather than referring the reviewer to a path.
6. Save the full review output to `docs/review/#{issue_number}/review.md`, recording which reviewer produced it along with the model and reasoning effort it actually resolved to.
7. Classify each finding as Critical, Major, Minor, or Suggestion — triage is the orchestrator's. Fix Critical and Major before the pull request, delegating the application to the `executor`; record a rationale for anything deliberately deferred. Then append a fix summary to the review artifact.

## Output

- Review verdict: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`.
- Saved review artifact, recording reviewer identity, model, and reasoning effort, plus the fix summary.
