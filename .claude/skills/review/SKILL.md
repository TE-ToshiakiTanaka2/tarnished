---
name: review
description: Code review via Codex CLI. Delegates review of the current branch to OpenAI Codex for an independent second opinion, then applies fixes. Requires codex CLI to be installed.
argument-hint: [--builtin]
disable-model-invocation: true
---

# Code Review Skill (via Codex)

Code review skill that delegates review of the current branch's implementation to OpenAI Codex CLI for an independent second opinion. Review scope scales with development size.

## Prerequisites Check

!`command -v codex >/dev/null 2>&1 && echo "CODEX_AVAILABLE=true" || echo "CODEX_AVAILABLE=false"`

**IMPORTANT**: If `CODEX_AVAILABLE=false` above, you MUST stop immediately and show this message:

```
Codex CLI is required for /review but was not found.

Install with:
  npm install -g @openai/codex

After installation, run /review again.
```

Do NOT proceed with any review steps if Codex CLI is not available.

## Usage

Review the current feature branch's implementation (default):

```
/review
```

Use Codex built-in review:

```
/review --builtin
```

## What This Skill Does

### Phase 1: Collect Context

1. **Identify branches** - Detect current branch and merge base with `develop`:
   ```bash
   CURRENT_BRANCH=$(git branch --show-current)
   MERGE_BASE=$(git merge-base develop HEAD)
   ```
2. **Determine issue number** - Extract from branch name (e.g., `feature/user/#123/desc` → `123`)
3. **Load design artifacts** - Read `docs/issues/<issue_number>/design.md` if available:
   - Architecture decisions and constraints
   - API specifications
   - Expected behavior
4. **Determine review scope** - Based on change size:
   - **Small** (< 100 lines changed): Quick review — bugs, security, correctness
   - **Medium** (100-500 lines): Standard review — all criteria
   - **Large** (500+ lines): Deep review — all criteria + architecture adherence to design

### Phase 2A: Custom Review via `codex exec` (Default)

5. **Collect implementation changes**:
   - `git log --oneline ${MERGE_BASE}...HEAD` — commits
   - `git diff ${MERGE_BASE}...HEAD` — full diff
6. **Construct review prompt** - Build a structured prompt with:
   - The diff and commit history
   - Project context from codebase analysis
   - Design constraints (from design.md if available)
   - Review criteria scaled to scope (see Review Prompt Template)
7. **Execute `codex exec`**:
   ```bash
   echo "${REVIEW_PROMPT}" | codex exec - --sandbox read-only
   ```
8. **Capture output**

### Phase 2B: Built-in Review via `codex review` (with `--builtin`)

5. **Run `codex review`** directly:
   ```bash
   codex review --base develop
   ```
6. **Capture output**

### Phase 3: Save & Apply Fixes

9. **Save review results** - Save Codex output to `docs/review/#{issue_number}/`:
    ```bash
    mkdir -p docs/review/#{issue_number}
    ```
    - Save the raw review output as `docs/review/#{issue_number}/review.md` with metadata header:
      ```markdown
      # Code Review: #{issue_number}

      - **Branch**: {current branch name}
      - **Base**: develop (merge base: {merge base SHA short})
      - **Review scope**: {Small/Medium/Large} ({N} lines changed)
      - **Reviewed at**: {ISO 8601 timestamp}
      - **Reviewer**: Codex CLI

      ---

      {Full Codex review output}
      ```
10. **Present review results** - Display Codex output to user
11. **Implement fixes** - Address issues found:
    - Critical issues: Must fix
    - Warnings: Should fix
    - Suggestions: Discuss with user
12. **Commit fixes**:
    ```
    fix: address review feedback for #<issue_number>
    ```

### Phase 4: Report

13. **Update review record** - Append fix summary to `docs/review/#{issue_number}/review.md`:
    ```markdown

    ---

    ## Fixes Applied

    - {list of fixes applied}
    - Commit: {fix commit hash}
    ```
14. **Summarize** - Present final status:
    - Issues found and resolved
    - Remaining suggestions (if any)

## Review Prompt Template

When using `codex exec` (default mode), construct the prompt as follows:

```
You are a senior code reviewer. Review the implementation on this feature branch.

## Project Context
- Repository: {repo name from git remote}
- Technology stack: {detected from project files — e.g., Cargo.toml → Rust, package.json → Node.js, etc.}

## Branch
- Current branch: {current branch name}
- Base: develop (merge base: {merge base SHA short})

## Design Reference
{Contents of docs/issues/<issue_number>/design.md, if available.
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
Code Review (via Codex)

Branch: feature/alice/#123/add-user-authentication
Issue: #123
Review scope: Medium (247 lines changed)

--- Codex Review Output ---
(Full review output from codex)
--- End of Review ---

Review saved to: docs/review/#123/review.md

Fixes Applied:
- fix: address review feedback for #123
  - Fixed null check in auth middleware
  - Added input validation for email field

Review complete. Ready for /pr.
```

## Error Handling

- **Codex not installed**: Stop immediately, show install instructions (see Prerequisites Check)
- **Codex not authenticated**: Prompt user to run `codex login`
- **No changes on branch**: Inform user that the branch has no implementation changes
- **Diff too large**: Split review by directory and combine results
- **Codex execution fails**: Show error output and suggest checking API key / network

## Integration

- **Prerequisite**: Implementation completed with `/implement <issue_number>`
- **Next step**: Create Pull Request with `/pr`
- **Typical workflow**: `/issue` → `/design` → `/implement` → **`/review`** → `/pr`

ARGUMENTS:
$ARGUMENTS
