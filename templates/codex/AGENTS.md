# {{PROJECT_NAME}} - Codex Agent

This project uses Tarnished's shared agent workflow layer. Codex should follow the same lifecycle and artifact contracts as Claude Code, even when invocation syntax differs.

## Agent Profile

- **Profile**: `{{AI_PROFILE}}`
- **Primary agent**: `{{AI_PRIMARY_AGENT}}`
- **Review agent**: `{{AI_REVIEW_AGENT}}`
- **Shared workflow source**: `.tarnished/workflows/`

## Operating Mode

If Codex CLI is the primary agent, drive the full lifecycle:

1. `issue` - clarify requirements and create a GitHub Issue.
2. `design` - create design artifacts before implementation.
3. `implement` - implement the issue in focused commits.
4. `review` - request independent review from the configured review agent.
5. `pr` - create the pull request and validate CI.

If Codex CLI is the review agent, focus on independent code review. Do not take over implementation unless the primary agent or user explicitly asks you to apply fixes.

## Shared Workflow Contract

Read `.tarnished/workflows/README.md` first, then follow the workflow file matching the task:

- `.tarnished/workflows/issue.md`
- `.tarnished/workflows/design.md`
- `.tarnished/workflows/implement.md`
- `.tarnished/workflows/review.md`
- `.tarnished/workflows/pr.md`

Detailed `erd:*` behavior is available under `.tarnished/workflows/erd/`. Use those files as Codex-readable equivalents of Claude Code's `.claude/commands/erd/*` slash-command docs.

The lifecycle should feel the same as Claude Code's `/issue`, `/design`, `/implement`, `/review`, and `/pr` skills. Claude-specific `SKILL.md` files and slash commands are projections of the same workflow intent, not a separate source of truth.

## Codex Skill Compatibility

Codex repo-local skills are shipped under `.agents/skills/`:

- `$issue` - create a GitHub Issue from requirements.
- `$design <issue_number>` - create/reuse the issue branch and write design artifacts.
- `$implement <issue_number>` - implement, build, test, and commit.
- `$review` - request or perform independent review and save `docs/review/#{issue_number}/review.md`.
- `$pr [target_branch] [--merge]` - create the PR, validate CI, optionally merge, and update the target branch.

Treat user prompts such as `issue`, `design`, `implement`, `review`, `pr`, and natural-language mentions of Claude-style `/issue`, `/design`, `/implement`, `/review`, and `/pr` as aliases for the matching Codex skill. If the skill is not visible in the current Codex session, read `.agents/skills/<name>/SKILL.md` directly and follow it. Codex's slash-command namespace remains reserved for Codex built-ins; `$issue` style invocation is the native skill path.

For Claude Code `--dangerously-skip-permissions` parity in externally sandboxed devcontainers, start Codex explicitly with:

```bash
codex --dangerously-bypass-approvals-and-sandbox
```

Do not make this the project default; it disables approval prompts and sandboxing.

## Review Responsibilities

When acting as reviewer, check:

1. **Correctness**: Does the code do what it is supposed to do?
2. **Security**: Are there vulnerabilities such as injection, XSS, unsafe shell usage, or hardcoded secrets?
3. **Error handling**: Are failures handled explicitly and usefully?
4. **Edge cases**: Are boundary conditions covered?
5. **Code style**: Does the code follow project conventions?
6. **Performance**: Are there obvious inefficient patterns?
7. **Tests**: Are new or changed behaviors verified?

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

## Project Context

- This project uses Devcontainer for development environments.
- Follow conventional commit format for suggested changes.
- Respect existing code patterns and architecture decisions.
- Preserve user-authored files and avoid broad destructive commands.
