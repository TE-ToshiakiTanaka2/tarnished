---
name: review
description: Independent code review of the current branch before PR creation. Resolves a reviewer in priority order — configured review agent, Codex CLI, Claude-native fresh-context subagent — then saves the review artifact and applies fixes.
argument-hint: "[target_branch] [--codex|--claude|--builtin]"
disable-model-invocation: true
---

# Skill: Review

Independent review of the current branch's implementation before PR creation. Review scope scales with development size. The reviewer is resolved through a fallback ladder, so the skill works with or without an external review agent installed.

This skill is the Claude Code projection of `.tarnished/workflows/review.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

**This file is the canonical source for the review criteria and the severity taxonomy.** They live inline in the Review Prompt Template below, at the point where the reviewer's prompt is constructed, because every reviewer receives them inline: `codex exec` gets a piped prompt inside a read-only sandbox, and the CI reviewer gets them embedded in workflow YAML. Other documents reference this file rather than restating it.

## Usage

```
/review                    # auto-resolve reviewer, diff against develop
/review main               # diff against main instead
/review --codex            # force Codex CLI reviewer
/review --claude           # force Claude-native subagent reviewer
/review --builtin          # force Codex built-in `codex review`
```

## Roles

This skill fills the `external-reviewer` role. Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and binding. Independence is the point: the reviewer must not have seen the reasoning that produced the diff.

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
2. **Configured review agent** — Read `.tarnished/agent-profile.json`. Prefer `roles.external-reviewer.agent` (resolving `"review"` through `review_agent`); fall back to `review_agent` when the `roles` key is absent. If it names an installed external agent (e.g. `codex`) distinct from the primary agent, use it. Skip if the file is missing, contains unrendered `{{...}}` placeholders, or names an unavailable tool.
3. **Codex CLI** — If `command -v codex` succeeds, use Codex (Phase 3A).
4. **Claude-native fallback** — Use the `code-reviewer` subagent (Phase 3C). Mark the artifact as a fallback review.

Then **resolve the reviewer's model and reasoning effort** so they can be recorded in Phase 4. For Codex, read `model` and `model_reasoning_effort` from `.codex/config.toml`, preferring `roles.external-reviewer.model` / `.reasoning_effort` from `agent-profile.json` when set. Record `default` for any value that is unset or unreadable. A config change must be visible in the artifact rather than silently changing review quality.

### Phase 3A: Review via `codex exec` (Codex default)

1. **Collect implementation changes**:
   - `git log --oneline ${MERGE_BASE}...HEAD` — commits
   - `git diff ${MERGE_BASE}...HEAD` — full diff
2. **Construct review prompt** — Use the Review Prompt Template below with diff, commit history, design constraints, and scope-scaled criteria. Inline the criteria; do not replace them with a path reference, since the reviewer runs in a read-only sandbox against a piped prompt.
3. **Execute**:
   ```bash
   echo "${REVIEW_PROMPT}" | codex exec - --sandbox read-only
   ```
4. **Capture output**

### Phase 3B: Review via `codex review` (with `--builtin`)

1. **Run** `codex review --base "$TARGET_BRANCH"` and capture output.

### Phase 3C: Review via Claude subagent (fallback or `--claude`)

1. **Launch the `code-reviewer` subagent** (defined in `.claude/agents/code-reviewer.md`) with the Review Prompt Template below as its task. The subagent runs read-only in a fresh context — do not paste your own analysis of the changes into the prompt; let it judge the diff independently.
   - If `.claude/agents/code-reviewer.md` does not exist (e.g. a project scaffolded before it shipped), launch a general-purpose subagent instead with the Review Prompt Template as its task, instructing it to work read-only. The review still runs in a fresh context.
2. **Capture its final message** as the review output.

### Phase 4: Save & Apply Fixes

1. **Save review results** to `docs/review/#{issue_number}/review.md`. The metadata header records branch, base and merge base, review scope with changed-line count, ISO 8601 timestamp, and the reviewer — **including the resolved model and reasoning effort**, e.g. `Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra)`. Mark a Claude-native review as a fallback. The full review output follows the header verbatim.
2. **Present review results** to the user.
3. **Implement fixes** per the severity policy below.
4. **Commit fixes**: `fix: address review feedback for #<issue_number>`

### Phase 5: Report

1. **Update review record** — Append a "Fixes Applied" section to `docs/review/#{issue_number}/review.md` listing the fixes and the fix commit hash. For any Critical or Major finding deliberately left unfixed, record the rationale next to it.
2. **Summarize** — Issues found and resolved, deferrals with rationale, remaining minor findings and suggestions.

## Severity taxonomy and fix policy

One taxonomy is used repository-wide — by this skill, the `code-reviewer` subagent, the Codex root prompt in `AGENTS.md`, and CI first-pass review where configured. Because it is shared, triage needs no per-reviewer translation.

| Severity | Meaning | Policy |
| --- | --- | --- |
| **Critical** | Breaks correctness, security, or a documented invariant | Must fix before the PR |
| **Major** | Materially wrong or materially harms maintainability | Must fix before the PR, unless deferred with a recorded rationale |
| **Minor** | Real but small; localized cost | Fix when cheap, otherwise record |
| **Suggestions** | Optional improvement | Discuss; no obligation |

## Review Prompt Template

Used for both `codex exec` (Phase 3A) and the `code-reviewer` subagent (Phase 3C). The "Review Criteria" and "Output Format" sections below are the canonical lists.

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

### Major (must fix before PR)
- [file:line] Description

### Minor (fix when cheap)
- [file:line] Description

### Suggestions (nice to have)
- [file:line] Description

### Positive
- Note any well-written code or good patterns

If there are no issues in a category, omit that section.
Provide a final verdict: APPROVE, REQUEST_CHANGES, or COMMENT.
```

## Reporting

Report to the user, in whatever shape fits the review:

- Branch, issue number, target branch
- Resolved reviewer, how it was resolved, and its model and reasoning effort
- Review scope and changed-line count
- The review output
- Where the artifact was saved
- Fixes applied, with the fix commit
- Any Critical or Major finding left unfixed, with its rationale
- Readiness for `/pr`

## Error Handling

- **`--codex`/`--builtin` given but Codex missing**: Stop and show `npm install -g @openai/codex` install instructions
- **Codex not authenticated**: Prompt user to run `codex login`, or fall through to the Claude-native reviewer with user consent
- **Configured model or effort rejected by the reviewer CLI**: Report the rejection rather than silently falling back — a demoted review is worse than a failed one, because it looks like it succeeded
- **No changes on branch**: Inform user that the branch has no implementation changes vs the target branch
- **Diff too large**: Split review by directory and combine results
- **External reviewer execution fails**: Show error output, then offer the Claude-native fallback

## Integration

- **Prerequisite**: Implementation completed with `/implement <issue_number>`
- **Next step**: Create Pull Request with `/pr`
- **CI counterpart**: when a first-pass CI review workflow is configured for the repository, it uses these same criteria and taxonomy. It is opt-in and is not installed by scaffolding
- **Typical workflow**: `/issue` → `/design` → `/implement` → **`/review`** → `/pr`

ARGUMENTS:
$ARGUMENTS
