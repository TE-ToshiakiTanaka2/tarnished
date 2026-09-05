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

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and stage ownership; where the two disagree with `.tarnished/workflows/pr.md`, the skills are authoritative.

This stage splits at the irreversible operation.

| Work | Owner |
| --- | --- |
| Quality pass, PR body **drafting**, `git push`, CI monitoring, failed-log collection, fix commits | `executor` |
| Checking the drafted body, then running `gh pr create` | `orchestrator` |
| Interpreting a CI failure | `orchestrator` |
| The merge decision, including under `--merge` | `orchestrator` |

Creation is the orchestrator's command, not merely its approval. "The executor creates it but the orchestrator checks first" has no executable boundary — by the time the orchestrator sees anything, the pull request exists. The executor therefore **returns the drafted body** and stops; the orchestrator reads it, revises or re-dispatches if it is wrong, and then creates the PR itself.

A pull request is outward-facing and a merge is irreversible, so neither is delegated to the stage's writing agent. The executor never runs `gh pr merge`.

When the executor returns a **blocked-result** — a CI failure whose cause is a design or requirement question rather than a fixable defect, for instance — the orchestrator answers it and re-dispatches, or escalates to the user when the answer is the user's to give. See `_shared/delegation/SKILL.md`.

Where the primary agent has no subagent mechanism, the orchestrator runs the whole stage inline; record in the report that delegation was unavailable.

## erd Command Invocation

Invoke each erd command by the first available route:

1. `Read(".claude/commands.local/erd/<command>.md")` — the project's overlay, when one exists
2. `Skill(erd:<command>)` — loads the base instructions into the current turn
3. `Read(".claude/commands/erd/<command>.md")` — the base copy, when the Skill route is unavailable

The overlay is checked first because it is the only route guaranteed to honor a project's customization. `commands.local/` is where a project overrides an erd command, and taking the Skill route without looking would silently run the base version instead.

## MCP Tools

Use the following MCP tools for code analysis:

- **serena**: `find_symbol`, `get_symbols_overview` — for understanding code structure during analysis and improvement phases

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search and file reading tools — do not stop or ask for installation.

## What This Skill Does

Before preparation, resolve the repository, source branch, target, and existing PRs with `gh pr list --head <branch> --state all`. Match the intended base and repository as well. Reuse a unique open PR; report a merged PR as complete. Stop for an ambiguous match, a conflicting base, or a closed unmerged PR rather than silently creating or retargeting one. After an uncertain create result, query again before retrying so a timeout cannot create a duplicate.

Check review evidence using `.claude/skills/review/references/completion.md`. Under `/flow`, complete missing or stale review before proceeding. Standalone `/pr` preserves its optional-review contract: if no review was requested or required, disclose that it was not performed; if an existing review has unresolved required findings, or review is required by the repository, resolve it before creation or merge. Do not treat a stale artifact as approval.

### Phase 1: Code Analysis and Improvement

Reuse existing review findings and successful checks for unchanged code. Limit improvements and cleanup to the issue; load the following commands only for missing analysis or actionable findings. After changes, rerun affected checks and all repository-required checks. Do not repeat broad verification solely because a new stage began.

1. **Load `/erd:analyze`**:
   - Quality, security, performance, and architecture findings
2. **Load `/erd:improve`**:
   - Apply behavior-preserving improvements addressing the findings
3. **Load `/erd:cleanup`**:
   - Remove dead code, unused imports, and commented-out code
4. **Commit improvements** - Commit all improvement and cleanup changes

### Phase 2: Quality Checks

5. **Static analysis** - Run language-specific linters and formatters
6. **Run tests** - Required suites and tests affected by changes since the last successful verification; report reused results and unavailable checks
7. **Fix and re-commit** - If any checks fail, fix and commit

### Phase 3: Pull Request Creation

8. **Collect change history** - Analyze commit history and diff against target branch
9. **Push to remote** - `git push -u origin <branch>` (executor)
10. **Draft the PR body** - The executor writes the body per the "Pull Request Format" below and **returns it without creating anything**
11. **Check and create or reuse** - The orchestrator reads the drafted body and creates the PR only if the lookup found none. Use a structured body argument or a UTF-8 file with `gh pr create --body-file <path>` so Markdown and shell metacharacters survive unchanged. For an existing open PR, retain its number and URL; update its description only if the authorized changes require it, preserving user-authored content.

### Phase 4: CI Monitoring and Validation

12. **Monitor CI** - Wait on the pull request's **aggregate** check state, not on a single workflow run: `gh pr checks <pr_number> --watch --fail-fast` in the background, or the harness's condition-waiting affordance where one is available. Background completion re-invokes the agent, so no manual re-check step is needed. Never `sleep`-poll — the runtime blocks it.

    Watching one `gh run watch <run_id>` is not sufficient. A repository can have several workflows and check suites on the same PR, so a single green run says nothing about the others, and merging on it can merge over a pending or failing check.

    Set an explicit timeout on the wait — 15 minutes unless the project's CI is known to run longer. The timeout is what owns the "CI status unknown" rule below: nothing else in this procedure measures elapsed time, so a rule without a wait deadline has no actor that can execute it.
13. **Validate CI results** - Load `/erd:reflect`:
    - Interpret CI pass/fail, assess coverage adequacy, verify the implementation matches the issue requirements, identify remaining risks
14. **Fix loop on CI failure**:
    - Analyze error content from CI logs (`gh run view <run_id> --log-failed`)
    - Implement fix, commit & push, re-check CI. Refresh affected review evidence after each code/design change; green CI alone does not revalidate the review.
    - If the repository has a first-pass CI review workflow configured and it left a review comment, address its Critical and Major findings before merging. This workflow is opt-in and is not installed by scaffolding, so treat its absence as normal
15. **Report completion** - Present PR URL and validation summary

### Phase 5: Auto-Merge (if `--merge` flag is specified)

16. **Merge PR** — the orchestrator's decision and the orchestrator's command; the executor never runs it. Record the PR's current `headRefOid` as `VALIDATED_HEAD` and verify that it is the head covered by review and CI. Squash merge via `gh pr merge <pr_number> --squash --delete-branch --match-head-commit "$VALIDATED_HEAD"`:
    - Re-read aggregate checks and the PR head immediately before merging. Require applicable checks to pass, with no pending, failed, or cancelled required checks. A skipped non-applicable job is not a failure; an empty or unreadable check result is not proof of success. If the head changed, revalidate it before retrying the merge.
    - Only proceeds if CI has passed and validation is successful
    - If merge fails (e.g., merge conflict, branch protection), report the error to user
17. **Confirm merge and update** - Read the PR state after the command. A queued or auto-merge request is still pending; continue monitoring within the CI deadline and do not report it merged or switch branches until GitHub confirms `MERGED`. After a confirmed merge, update the local target with `git pull --ff-only origin <target_branch>` using the shared branch worktree rules. Preserve unrelated edits and report separately if the remote merge succeeded but local synchronization could not.
18. **Report merge result** - Present merge status and final commit

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
- Whether the mechanical work was delegated to the executor or run inline because no subagent mechanism was available
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
