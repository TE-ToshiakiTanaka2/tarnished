---
name: pr
description: Create a Pull Request with code analysis, quality checks, CI monitoring, and validation. Uses erd commands (erd:analyze, erd:improve, erd:cleanup, erd:reflect). Supports --merge for auto-merge after CI passes.
argument-hint: "[target_branch] [--merge]"
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

## Roles

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and the routing table. Phase 1 mixes judgment (which findings matter, which refactor preserves behavior) with mechanics (formatters, linters, dead-code removal); route within it per unit of work rather than delegating the phase as a block. CI log collection is mechanical; interpreting a CI failure is judgment.

## erd Command Invocation

Invoke each erd command by the first available route:

1. `Skill(erd:<command>)` — loads the instructions into the current turn
2. `Read(".claude/commands.local/erd/<command>.md")` — the project's overlay, when one exists
3. `Read(".claude/commands/erd/<command>.md")` — the base copy

Check for the overlay before falling back to the base copy: a project that customizes an erd command does so in `commands.local/`, and reading the base copy directly would silently ignore it.

## MCP Tools

Use the following MCP tools for code analysis:

- **serena**: `find_symbol`, `get_symbols_overview` — for understanding code structure during analysis and improvement phases

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search and file reading tools — do not stop or ask for installation.

## What This Skill Does

### Phase 1: Code Analysis and Improvement

1. **Load `/erd:analyze`**:
   - Quality, security, performance, and architecture findings
2. **Load `/erd:improve`**:
   - Apply behavior-preserving improvements addressing the findings
3. **Load `/erd:cleanup`**:
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

11. **Monitor GitHub Actions** - Wait for CI completion with `gh run watch <run_id> --exit-status` in the background, or with the harness's condition-waiting affordance where one is available. Background completion re-invokes the agent, so no manual re-check step is needed. Never `sleep`-poll — the runtime blocks it.

    Set an explicit timeout on the wait — 15 minutes unless the project's CI is known to run longer. The timeout is what owns the "CI status unknown" rule below: nothing else in this procedure measures elapsed time, so a rule without a wait deadline has no actor that can execute it.
12. **Validate CI results** - Load `/erd:reflect`:
    - Interpret CI pass/fail, assess coverage adequacy, verify the implementation matches the issue requirements, identify remaining risks
13. **Fix loop on CI failure**:
    - Analyze error content from CI logs (`gh run view <run_id> --log-failed`)
    - Implement fix, commit & push, re-check CI
    - If the repository has a first-pass CI review workflow configured and it left a review comment, address its Critical and Major findings before merging. This workflow is opt-in and is not installed by scaffolding, so treat its absence as normal
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

Do not include the Issue number `(#XXX)` in the PR title. GitHub's squash merge automatically appends the PR number `(#N)` to the commit message. If the Issue number is also in the title, the commit message becomes `feat: ... (#issue) (#pr)`, which breaks auto-tag workflows.

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

- **CI timeout**: When the wait deadline passes without a conclusive result, report CI status as unknown and stop. Do not merge on unknown CI
- **Fix loop limit**: Report to user if still failing after 3 fix attempts
- **Merge conflict**: Notify user and provide resolution instructions
- **Merge failure** (with `--merge`): Report the error (e.g., branch protection, required reviews). Do NOT retry merge automatically

## Reporting

Report, in whatever shape fits the run:

- PR number, title, and URL
- Source and target branches
- Analysis findings and the improvements and cleanup applied
- CI status, and the number of fix iterations if any were needed
- What each fix iteration changed
- Validation outcome from `/erd:reflect`: CI, coverage adequacy, requirement coverage, remaining risks
- Change summary — files changed, lines added and deleted
- Linked issue, and that it closes on merge
- Merge result when `--merge` was given: merge method, target branch, and whether the source branch was deleted

Report only what actually happened. A checklist item that was not run is not a passing checklist item.

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
- **CI Workflow**: Integrates with the repository's GitHub Actions workflows. A first-pass CI review, where a project has configured one, uses the criteria and severity taxonomy in `.claude/skills/review/SKILL.md`
- **Typical workflow**: `/issue` → `/design` → `/implement` → `/review` → **`/pr`**

ARGUMENTS:
$ARGUMENTS
