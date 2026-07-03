---
name: review
description: Independent code review of the current branch before PR creation. Resolves a reviewer in priority order — configured review agent, Codex CLI, Claude-native fresh-context subagent — then saves the review artifact and applies fixes.
argument-hint: "[target_branch] [--codex|--claude|--builtin]"
disable-model-invocation: true
---

# Skill: Review

Independent review of the current branch's implementation before PR creation. Review scope scales with development size. The reviewer is resolved through a fallback ladder, so the skill works with or without an external review agent installed.

This skill is the Claude Code projection of `.tarnished/workflows/review.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

## Usage

```
/review                    # auto-resolve reviewer, diff against develop
/review main               # diff against main instead
/review --codex            # force Codex CLI reviewer
/review --claude           # force Claude-native subagent reviewer
/review --builtin          # force Codex built-in `codex review`
```

## MCP Tools

Use the following MCP tools for code understanding during review:

- **serena**: `find_symbol`, `get_symbols_overview`, `search_for_pattern` — for tracing code paths and understanding symbol relationships in the reviewed changes

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search and file reading tools — do not stop or ask for installation.

## What This Skill Does

### Phase 1: Collect Context

1. **Identify branches** — Detect current branch and merge base with the target branch (first non-flag argument, default `develop`):
   ```bash
   TARGET_BRANCH=${1:-develop}
   CURRENT_BRANCH=$(git branch --show-current)
   MERGE_BASE=$(git merge-base "$TARGET_BRANCH" HEAD)
   ```
2. **Determine issue number** — Extract from branch name (e.g., `feature/user/#123/desc` → `123`)
3. **Load design artifacts** — Read `docs/design/#<issue_number>/design.md` and `api-spec.md` if available: architecture decisions, constraints, expected behavior
4. **Determine review scope** — Based on change size:
   - **Small** (< 100 lines changed): Quick review — bugs, security, correctness
   - **Medium** (100–500 lines): Standard review — all criteria
   - **Large** (500+ lines): Deep review — all criteria + architecture adherence to design

### Phase 2: Resolve the Reviewer

Resolve in priority order (stop at the first match):

1. **Explicit flag** — `--codex` / `--builtin` selects Codex CLI (fail with install instructions if `command -v codex` is empty); `--claude` selects the Claude-native subagent.
2. **Configured review agent** — Read `.tarnished/agent-profile.json` → `review_agent`. If it names an installed external agent (e.g. `codex`) distinct from the primary agent, use it. Skip if the file is missing, contains unrendered `{{...}}` placeholders, or names an unavailable tool.
3. **Codex CLI** — If `command -v codex` succeeds, use Codex (Phase 3A).
4. **Claude-native fallback** — Use the `code-reviewer` subagent (Phase 3C). Mark the artifact `Reviewer: Claude (code-reviewer subagent, fallback)`.

### Phase 3A: Review via `codex exec` (Codex default)

5. **Collect implementation changes**:
   - `git log --oneline ${MERGE_BASE}...HEAD` — commits
   - `git diff ${MERGE_BASE}...HEAD` — full diff
6. **Construct review prompt** — Use the Review Prompt Template below with diff, commit history, design constraints, and scope-scaled criteria
7. **Execute**:
   ```bash
   echo "${REVIEW_PROMPT}" | codex exec - --sandbox read-only
   ```
8. **Capture output**

### Phase 3B: Review via `codex review` (with `--builtin`)

5. **Run** `codex review --base "$TARGET_BRANCH"` and capture output.

### Phase 3C: Review via Claude subagent (fallback or `--claude`)

5. **Launch the `code-reviewer` subagent** (defined in `.claude/agents/code-reviewer.md`) with the Review Prompt Template below as its task. The subagent runs read-only in a fresh context — do not paste your own analysis of the changes into the prompt; let it judge the diff independently.
   - If `.claude/agents/code-reviewer.md` does not exist (e.g. a project scaffolded before it shipped), launch a general-purpose subagent instead with the Review Prompt Template as its task, instructing it to work read-only. The review still runs in a fresh context.
6. **Capture its final message** as the review output.

### Phase 4: Save & Apply Fixes

9. **Save review results** to `docs/review/#{issue_number}/review.md` with metadata header:
   ```markdown
   # Code Review: #{issue_number}

   - **Branch**: {current branch name}
   - **Base**: {target branch} (merge base: {merge base SHA short})
   - **Review scope**: {Small/Medium/Large} ({N} lines changed)
   - **Reviewed at**: {ISO 8601 timestamp}
   - **Reviewer**: {Codex CLI | Claude (code-reviewer subagent, fallback) | configured agent name}

   ---

   {Full review output}
   ```
10. **Present review results** to the user
11. **Implement fixes** — Critical issues: must fix. Warnings: should fix. Suggestions: discuss with user.
12. **Commit fixes**: `fix: address review feedback for #<issue_number>`

### Phase 5: Report

13. **Update review record** — Append to `docs/review/#{issue_number}/review.md`:
    ```markdown

    ---

    ## Fixes Applied

    - {list of fixes applied}
    - Commit: {fix commit hash}
    ```
14. **Summarize** — Issues found and resolved, remaining suggestions

## Review Prompt Template

Used verbatim for both `codex exec` (Phase 3A) and the `code-reviewer` subagent (Phase 3C). The same criteria drive the CI first-pass review (`.github/workflows/claude-code-review.yml`), so local and CI review stay aligned.

```
You are a senior code reviewer. Review the implementation on this feature branch.

## Project Context
- Repository: {repo name from git remote}
- Technology stack: {detected from project files — e.g., Cargo.toml → Rust, package.json → Node.js, etc.}

## Branch
- Current branch: {current branch name}
- Base: {target branch} (merge base: {merge base SHA short})

## Design Reference
{Contents of docs/design/#<issue_number>/design.md, if available.
Otherwise: "No design document available."}

## Review Criteria
Please review for:
1. **Bugs & Logic Errors** — Incorrect behavior, off-by-one, null/undefined issues
2. **Security** — Injection, auth issues, secrets exposure, input validation
3. **Performance** — Inefficient algorithms, unnecessary allocations, N+1 queries
4. **Code Quality** — Readability, naming, DRY violations, overly complex logic
5. **Type Safety** — Missing types, unsafe casts, improper use of type system
6. **Error Handling** — Unhandled exceptions, missing edge cases
7. **Test Coverage** — Are new features/changes adequately tested?
8. **Design Adherence** — Does the implementation match the design document?

Report gaps and defects, not stylistic nitpicks — code-quality findings must
materially affect maintainability or violate a documented project rule
(.claude/rules/*). Verify claims by reading the code before asserting them.

## Implementation Commits
{git log --oneline output}

## Implementation Diff
{git diff output}

## Output Format
Organize your review as:

### Critical (must fix)
- [file:line] Description

### Warnings (should fix)
- [file:line] Description

### Suggestions (nice to have)
- [file:line] Description

### Positive
- Note any well-written code or good patterns

If there are no issues in a category, omit that section.
Provide a final verdict: APPROVE, REQUEST_CHANGES, or COMMENT.
```

## Output Format

```
Code Review

Branch: feature/alice/#123/add-user-authentication
Issue: #123
Target: develop
Reviewer: Codex CLI (resolved via: codex available)
Review scope: Medium (247 lines changed)

--- Review Output ---
(Full review output)
--- End of Review ---

Review saved to: docs/review/#123/review.md

Fixes Applied:
- fix: address review feedback for #123
  - Fixed null check in auth middleware
  - Added input validation for email field

Review complete. Ready for /pr.
```

## Error Handling

- **`--codex`/`--builtin` given but Codex missing**: Stop and show `npm install -g @openai/codex` install instructions
- **Codex not authenticated**: Prompt user to run `codex login`, or fall through to the Claude-native reviewer with user consent
- **No changes on branch**: Inform user that the branch has no implementation changes vs the target branch
- **Diff too large**: Split review by directory and combine results
- **External reviewer execution fails**: Show error output, then offer the Claude-native fallback

## Integration

- **Prerequisite**: Implementation completed with `/implement <issue_number>`
- **Next step**: Create Pull Request with `/pr`
- **CI counterpart**: `claude-code-review.yml` posts a first-pass review on PR open using the same criteria (when configured)
- **Typical workflow**: `/issue` → `/design` → `/implement` → **`/review`** → `/pr`

ARGUMENTS:
$ARGUMENTS
