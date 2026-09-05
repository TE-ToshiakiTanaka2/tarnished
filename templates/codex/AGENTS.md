# {{PROJECT_NAME}} - Codex Agent

This project uses Tarnished's shared agent workflow layer. Codex should follow the same lifecycle and artifact contracts as Claude Code, even when invocation syntax differs.

## Agent Profile

- **Profile**: `{{AI_PROFILE}}`
- **Primary agent**: `{{AI_PRIMARY_AGENT}}`
- **Review agent**: `{{AI_REVIEW_AGENT}}`
- **Shared workflow source**: `.tarnished/workflows/`

## Operating Mode

Follow the user's requested scope. An ordinary edit or explanation does not require the full issue lifecycle. A review-only request produces findings without applying fixes; implement changes when requested.

Read `.agents/skills/flow/references/execution.md` when using lifecycle skills. Preserve prior authorization, make routine choices from repository evidence, and complete the requested work. Ask only when a missing decision materially changes the result or needs new authority. If a skill requires a pause, link and quote the instruction and explain the blocker. Keep progress and final reports concise while retaining the required artifact fields.

If Codex CLI is the primary agent, drive the full lifecycle:

1. `issue` - clarify requirements and create a GitHub Issue.
2. `design` - create design artifacts before implementation.
3. `implement` - implement the issue in focused commits.
4. `review` - request independent review from the configured review agent.
5. `pr` - create the pull request and validate CI.

`flow` runs these five end to end for one issue, entering at the first incomplete stage.

If Codex CLI is the review agent, focus on independent code review. Do not take over implementation unless the primary agent or user explicitly asks you to apply fixes.

## Shared Workflow Contract

Read `.tarnished/workflows/README.md` first, then follow the workflow file matching the task:

- `.tarnished/workflows/issue.md`
- `.tarnished/workflows/design.md`
- `.tarnished/workflows/implement.md`
- `.tarnished/workflows/review.md`
- `.tarnished/workflows/pr.md`
- `.tarnished/workflows/flow.md` (absent in projects scaffolded before it shipped — proceed on the per-stage contracts)

Detailed `erd:*` behavior is available under `.tarnished/workflows/erd/`. Use those files as Codex-readable equivalents of Claude Code's `.claude/commands/erd/*` slash-command docs.

The lifecycle should feel the same as Claude Code's `/issue`, `/design`, `/implement`, `/review`, and `/pr` skills. Claude-specific `SKILL.md` files and slash commands are projections of the same workflow intent, not a separate source of truth.

## Codex Skill Compatibility

Codex repo-local skills are shipped under `.agents/skills/`:

- `$issue` - create a GitHub Issue from requirements.
- `$design <issue_number>` - create/reuse the issue branch and write design artifacts.
- `$implement <issue_number>` - implement, build, test, and commit.
- `$review` - request or perform independent review and save `docs/review/#{issue_number}/review.md`.
- `$pr [target_branch] [--merge]` - create the PR, validate CI, optionally merge, and update the target branch.
- `$flow [--issue N] [--base <branch>] [--from <stage>] [--merge]` - run the stages above end to end for one issue, entering at the first incomplete stage.

Treat user prompts such as `issue`, `design`, `implement`, `review`, `pr`, `flow`, and natural-language mentions of Claude-style `/issue`, `/design`, `/implement`, `/review`, `/pr`, and `/flow` as aliases for the matching Codex skill. If the skill is not visible in the current Codex session, read `.agents/skills/<name>/SKILL.md` directly and follow it. Codex's slash-command namespace remains reserved for Codex built-ins; `$issue` style invocation is the native skill path.

For Claude Code `--dangerously-skip-permissions` parity in externally sandboxed devcontainers, start Codex explicitly with:

```bash
codex --dangerously-bypass-approvals-and-sandbox
```

Do not make this the project default; it disables approval prompts and sandboxing.

## Review Responsibilities

The canonical list lives in the "Review Criteria" section of the Review Prompt Template in `.claude/skills/review/SKILL.md`, which is what the `review` workflow sends to its reviewer. It is restated here because an ad-hoc Codex session never receives that prompt — this file is the only carrier.

When acting as reviewer, check:

1. **Bugs & Logic Errors**: incorrect behavior, off-by-one, null/undefined issues
2. **Security**: injection, auth issues, secrets exposure, input validation, unsafe shell usage
3. **Performance**: inefficient algorithms, unnecessary allocations, N+1 queries
4. **Code Quality**: readability, naming, DRY violations, overly complex logic
5. **Type Safety**: missing types, unsafe casts, improper use of the type system
6. **Error Handling**: unhandled exceptions, missing edge cases
7. **Test Coverage**: are new or changed behaviors verified? Name the untested paths
8. **Design Adherence**: does the implementation match the design artifacts?
9. **Requirement Adherence**: does the branch carry every requirement in the issue, including requirements omitted from the design?

Report gaps and defects, not stylistic nitpicks. A code-quality finding must materially affect maintainability or violate a documented project rule. Verify claims by reading the code before asserting them.

## Review Output Format

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

Critical and Major must be fixed before the pull request; Major may be deferred only with a recorded rationale. Minor is fixed when cheap. Suggestions carry no obligation. These four levels are used by every reviewer in the project, so no per-reviewer translation is needed at triage.

## Project Context

- This project uses Devcontainer for development environments.
- Follow conventional commit format for suggested changes.
- Respect existing code patterns and architecture decisions.
- Preserve user-authored files and avoid broad destructive commands.
