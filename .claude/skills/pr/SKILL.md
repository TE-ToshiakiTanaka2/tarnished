---
name: pr
description: Create a Pull Request with code analysis, quality checks, CI monitoring, and validation. Uses erd commands (erd:analyze, erd:improve, erd:cleanup, erd:reflect). Supports --merge for auto-merge after CI passes.
argument-hint: "[target_branch]"
disable-model-invocation: true
---

# Skill: PR (Pull Request)

Pull Request creation skill for projects. Handles code analysis, improvements, cleanup, PR creation, CI monitoring, and validation.

This skill is the Claude Code projection of `.tarnished/workflows/pr.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

## Usage

```
/pr [target_branch] [--merge]
```

Default target branch: `develop`

Options:
- `--merge`: Auto-merge the PR (squash merge) after CI passes and validation succeeds

Examples:

```
/pr
/pr develop
/pr main
/pr develop --merge
/pr --merge
```

## erd Command Invocation

All erd commands in this skill MUST be loaded via the **Read tool** and followed inline:

```
Read(".claude/commands/erd/<command>.md") → follow instructions inline
```

Do NOT use the Skill tool to invoke erd commands. Loading via Read keeps the entire workflow in a single turn, preventing flow interruption between phases.

## MCP Tools

Use the following MCP tools for code analysis:

- **serena**: `find_symbol`, `get_symbols_overview` — for understanding code structure during analysis and improvement phases

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search and file reading tools — do not stop or ask for installation.

## What This Skill Does

### Phase 1: Code Analysis and Improvement

1. **Load `/erd:analyze` and follow inline** - `Read(".claude/commands/erd/analyze.md")`:
   - Quality, security, performance, and architecture findings
2. **Load `/erd:improve` and follow inline** - `Read(".claude/commands/erd/improve.md")`:
   - Apply behavior-preserving improvements addressing the findings
3. **Load `/erd:cleanup` and follow inline** - `Read(".claude/commands/erd/cleanup.md")`:
   - Remove dead code, unused imports, and commented-out code
4. **Commit improvements** - Commit all improvement and cleanup changes

### Phase 2: Quality Checks

5. **Static analysis** - Run language-specific linters and formatters
6. **Run tests** - All test suites
7. **Fix and re-commit** - If any checks fail, fix and commit

### Phase 3: Pull Request Creation

8. **Collect change history** - Analyze commit history and diff against target branch
9. **Push to remote** - `git push -u origin <branch>`
10. **Create PR** - Create PR with `gh pr create` targeting the specified branch, using the "Pull Request Format" below

### Phase 4: CI Monitoring and Validation

11. **Monitor GitHub Actions** - Wait for CI completion using `gh run watch <run_id> --exit-status` with `run_in_background: true`. Do NOT use `sleep` to poll — it is blocked by the runtime. After the background task completes, check results with `gh pr checks <pr_number>`.
12. **Validate CI results** - Load `/erd:reflect` and follow inline - `Read(".claude/commands/erd/reflect.md")`:
    - Interpret CI pass/fail, assess coverage adequacy, verify the implementation matches the issue requirements, identify remaining risks
13. **Fix loop on CI failure**:
    - Analyze error content from CI logs (`gh run view <run_id> --log-failed`)
    - Implement fix, commit & push, re-check CI
    - If a CI first-pass review comment exists (from `claude-code-review.yml`), address Critical findings before merging
14. **Report completion** - Present PR URL and validation summary

### Phase 5: Auto-Merge (if `--merge` flag is specified)

15. **Merge PR** - Squash merge via `gh pr merge <pr_number> --squash --delete-branch`:
    - Only proceeds if CI has passed and validation is successful
    - If merge fails (e.g., merge conflict, branch protection), report the error to user
16. **Update local target branch** - After a successful merge, switch to the target branch and update it with `git pull --ff-only origin <target_branch>`
17. **Report merge result** - Present merge status and final commit

## erd Commands Used

| Command | Purpose | Phase |
| --- | --- | --- |
| `/erd:analyze` | Code analysis (quality, security, performance, architecture) | Phase 1 |
| `/erd:improve` | Behavior-preserving quality improvements | Phase 1 |
| `/erd:cleanup` | Dead code removal, import optimization, final cleanup | Phase 1 |
| `/erd:reflect` | CI result validation (coverage adequacy, requirement matching, risk identification) | Phase 4 |

## Pull Request Format

**Title** (English, Conventional Commit format):

```
{type}: {description}
```

**IMPORTANT**: Do NOT include the Issue number `(#XXX)` in the PR title. GitHub's squash merge automatically appends the PR number `(#N)` to the commit message. If the Issue number is also in the title, the commit message becomes `feat: ... (#issue) (#pr)`, which breaks auto-tag workflows.

The Issue number should only appear in the PR body as `Closes #XXX`.

Examples:

- `feat: add configuration file support`
- `fix: resolve CLI argument parsing error`
- `refactor: improve error handling in config module`

**Body**:

```markdown
## Summary

Brief description of changes (1-3 lines)

## Changes

- List of changes organized by module/layer

## Code Analysis Results (erd:analyze)

- Quality: Passed/Warning
- Security: Passed/Warning
- Performance: Passed/Warning

## Improvements Applied (erd:improve + erd:cleanup)

- List of improvements and cleanup actions

## Testing

- [x] Unit tests pass
- [x] Integration tests pass
- [x] Linting pass
- [x] Formatting pass
- [x] Type check pass

## Validation (erd:reflect)

- CI Status: Passed/Failed
- Coverage: Adequate/Needs improvement
- Requirements: Fully met / Partially met

## Related Issue

Closes #XXX
```

## Error Handling

- **CI timeout**: Show warning if status unknown after 5 minutes
- **Fix loop limit**: Report to user if still failing after 3 fix attempts
- **Merge conflict**: Notify user and provide resolution instructions
- **Merge failure** (with `--merge`): Report the error (e.g., branch protection, required reviews). Do NOT retry merge automatically

## Output Format

### On Success

```
Pull Request Created

PR: #XX - feat: add configuration file support
URL: https://github.com/owner/repo/pull/XX

Branches:
- Source: feature/username/#123/add-config-loader
- Target: develop

Code Analysis (erd:analyze):
- Quality: No issues
- Security: No issues
- Performance: No issues

Improvements Applied (erd:improve):
- Removed 2 unused imports
- Standardized error handling pattern

Cleanup Applied (erd:cleanup):
- Removed 3 commented-out code blocks
- Optimized import ordering in 4 files

CI Status: All checks passed

Validation (erd:reflect):
- CI: All green
- Coverage: Adequate (85% on changed files)
- Requirements: Fully met per Issue #123
- Risks: None identified

Related Issue: #123 (will be closed on merge)

Change Summary:
- 5 files changed
- 150 lines added
- 20 lines deleted

Ready for review.
```

### After CI Fix

```
Pull Request Updated

CI Fix Applied:
- Fixed: lint error in src/config.rs
- Commit: fix: resolve lint error in config module

CI Status: All checks passed (after 1 fix iteration)
```

### After Auto-Merge (with --merge)

```
Pull Request Merged

PR: #XX - feat: add configuration file support
URL: https://github.com/owner/repo/pull/XX
Merge: Squash merged into develop
Branch: feature/username/#123/add-config-loader (deleted)

Related Issue: #123 (closed)
```

## Best Practices

- **Analyze Before PR**: Discover issues early with `/erd:analyze`
- **Improve Proactively**: Enhance quality with `/erd:improve`
- **Clean Up Last**: Use `/erd:cleanup` for final polish
- **CI First**: Run same checks as CI locally beforehand
- **Validate Results**: Use `/erd:reflect` to ensure CI results are meaningful
- **Clear Description**: PR description easy for reviewers to understand
- **Issue Linking**: Always link related Issues in body, never in title

## Integration

- **Prerequisite**: Implementation completed with `/implement <issue_number>`, optionally reviewed with `/review`
- **CI Workflow**: Integrates with GitHub Actions workflows; `claude-code-review.yml` (when configured) posts a first-pass review on PR open
- **Typical workflow**: `/issue` → `/design` → `/implement` → `/review` → **`/pr`**

ARGUMENTS:
$ARGUMENTS
