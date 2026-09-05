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

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and stage ownership; where the two disagree with `.tarnished/workflows/review.md`, the skills are authoritative.

The review itself is the `external-reviewer`'s. Independence is the point: the reviewer must not have seen the reasoning that produced the diff. The **orchestrator** triages the findings, and the **executor** applies the fixes — triage is a judgment about what matters, application is work with an objective success condition.

Where the primary agent has no subagent mechanism, the orchestrator applies the fixes inline; record in the report that delegation was unavailable.

## MCP Tools

Use the following MCP tools for code understanding during review:

- **serena**: `find_symbol`, `get_symbols_overview`, `search_for_pattern` — for tracing code paths and understanding symbol relationships in the reviewed changes

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search and file reading tools — do not stop or ask for installation.

## What This Skill Does

### Phase 1: Collect Context

Read `references/completion.md` relative to this skill for review evidence and reuse rules. Apply all nine criteria at every change size; size changes inspection depth, not which requirements are checked.

1. **Identify branches** — Parse reviewer flags separately from the optional target branch (default `develop`); reject unknown or conflicting flags. For example, `/review --codex` uses `develop`, not `--codex`, as its target. Resolve the issue worktree as `ISSUE_WORKTREE` and the requested target as `TARGET_BRANCH`; fetch its remote ref and bind `BASE_COMMIT` to that fetched commit, `REVIEWED_HEAD` to the issue branch's full commit SHA, and `MERGE_BASE` to `git -C "$ISSUE_WORKTREE" merge-base "$BASE_COMMIT" "$REVIEWED_HEAD"`. These are the inputs used in Phase 3. Record the target commit and reviewed head. Inspect index/working-tree changes and state explicitly what the committed diff excludes; do not silently include unrelated edits or call excluded work reviewed.
2. **Determine issue number** — Extract from branch name (e.g., `feature/user/#123/desc` → `123`)
3. **Load both ground truths** — the design and the issue:
   - `docs/design/#<issue_number>/design.md` and `api-spec.md` if available: architecture decisions, constraints, expected behavior
   - The issue's Requirements section via `gh issue view <issue_number>`. Without it the reviewer treats the design as ground truth, so a requirement dropped upstream of the design passes every check: the code matches the design, and the design matches the reduced issue
4. **Determine review scope** — Based on change size:
   - **Small** (< 100 lines changed): Focused review — all nine criteria, tracing the affected paths
   - **Medium** (100–500 lines): Standard review — all criteria
   - **Large** (500+ lines): Deep review — all criteria + architecture adherence to design

### Phase 2: Resolve the Reviewer

Resolve in priority order (stop at the first match):

1. **Explicit flag** — `--codex` / `--builtin` selects Codex CLI (fail with install instructions if `command -v codex` is empty); `--claude` selects the Claude-native subagent.
2. **Configured review agent** — Read `.tarnished/agent-profile.json`. Prefer `roles.external-reviewer.agent` (resolving `"review"` through `review_agent`); fall back to `review_agent` when the `roles` key is absent. If it names an installed external agent (e.g. `codex`) distinct from the primary agent, use it. Skip if the file is missing, contains unrendered `{{...}}` placeholders, or names an unavailable tool.
3. **Codex CLI** — If `command -v codex` succeeds, use Codex (Phase 3A).
4. **Claude-native fallback** — Use the `code-reviewer` subagent (Phase 3C). Mark the artifact as a fallback review.

Then **resolve the reviewer's model and reasoning effort** so they can be recorded in Phase 4. Resolve reviewer configuration and any project-relative profile from `ISSUE_WORKTREE`. For Codex, read `model` and `model_reasoning_effort` from that worktree's `.codex/config.toml` — the reviewer CLI's own config is the single source for both. Record `default` for any value that is unset or unreadable. A config change must be visible in the artifact rather than silently changing review quality.

`roles.external-reviewer` carries no `model` or `reasoning_effort`: the reviewer is executed by another vendor's tool that already owns a config file, and a second declaration site could only drift. `roles.external-reviewer.agent` still selects *which* agent reviews.

### Phase 3A: Review via `codex exec` (Codex default)

1. **Collect implementation changes**:
   - `git -C "$ISSUE_WORKTREE" log --oneline "$MERGE_BASE..$REVIEWED_HEAD"` — commits
   - `git -C "$ISSUE_WORKTREE" diff "$MERGE_BASE" "$REVIEWED_HEAD"` — full diff
2. **Construct review prompt** — Use the Review Prompt Template below with diff, commit history, design constraints, and scope-scaled criteria. Inline the criteria; do not replace them with a path reference, since the reviewer runs in a read-only sandbox against a piped prompt.
3. **Execute**, passing the model and effort resolved in Phase 2 explicitly so the artifact attributes the review to settings that were actually used:
   ```bash
   echo "${REVIEW_PROMPT}" | codex exec - -C "$ISSUE_WORKTREE" --sandbox read-only \
     -c model="${REVIEW_MODEL}" -c model_reasoning_effort="${REVIEW_EFFORT}"
   ```
   Omit a `-c` flag whose value resolved to `default`, letting `.codex/config.toml` supply it, and record what the config holds. Use `--strict-config` to catch unknown configuration fields. Verify model and reasoning-effort support with a minimal runtime check as well; schema validation alone does not establish backend availability.
4. **Capture output**

### Phase 3B: Review via `codex review` (with `--builtin`)

1. **Run** `codex review --base "$BASE_COMMIT"` from `ISSUE_WORKTREE`, passing the same resolved `-c model` / `-c model_reasoning_effort` overrides, and capture output. Confirm that worktree's `HEAD` is still `REVIEWED_HEAD` before running; the fetched commit pins the target even when the local `TARGET_BRANCH` has diverged.

This path takes no custom prompt, so it receives **neither** ground truth and applies the reviewer's own built-in criteria rather than the list below — no design reference, and no requirement-adherence check. Record that limitation in the artifact so the review is not read as having covered criteria 8 and 9. It is opt-in via `--builtin` and is never selected automatically for this reason.

### Phase 3C: Review via Claude subagent (fallback or `--claude`)

1. **Launch the `code-reviewer` subagent** (defined in `.claude/agents/code-reviewer.md`) with the Review Prompt Template below as its task. The subagent runs read-only in a fresh context — do not paste your own analysis of the changes into the prompt; let it judge the diff independently.
   - If `.claude/agents/code-reviewer.md` does not exist (e.g. a project scaffolded before it shipped), launch a general-purpose subagent instead with the Review Prompt Template as its task, instructing it to work read-only. The review still runs in a fresh context.
2. **Capture its final message** as the review output.

### Phase 4: Save & Apply Fixes

A review-only request saves and reports findings without applying fixes. Apply fixes when requested or when review is part of `/flow`. Record completion using `references/completion.md`: a clean review can complete with `None required`; unresolved required fixes or missing review inputs leave it `report-only`.

1. **Save review results** to `docs/review/#{issue_number}/review.md`. The metadata header includes the evidence fields in `references/completion.md` (initially `pending`), branch, base and merge base, review scope with changed-line count, ISO 8601 timestamp, and the reviewer — **including the resolved model and reasoning effort**, using `Codex CLI (model: <resolved model>, reasoning effort: <resolved effort>)`. Mark a Claude-native review as a fallback. The full review output follows the header verbatim.
2. **Present review results** to the user.
3. **Triage** — the orchestrator classifies each finding per the severity policy below and decides what must be fixed.
4. **Apply fixes** — dispatch the `executor` (`.claude/agents/executor.md`) with the triaged must-fix list. It commits as `fix: address review feedback for #<issue_number>`. A blocked-result comes back to the orchestrator, which answers it or escalates.
5. **Verify the fixes** — the orchestrator reads the fix commits against the findings they claim to resolve, before anything is recorded as fixed. A fix that is incomplete, that addresses a different problem, or that regresses something else goes back to the executor and is re-reviewed; at most 2 returns, then escalate. A delegated artifact that is recorded as complete without being reviewed defeats the point of delegating it, and a Critical finding marked fixed on an incomplete patch is the worst version of that.

### Phase 5: Report

1. **Update review record** — After verification, record each finding's disposition and the fix commit hashes, or `None required`. Set `verified_head` and `review_status` according to `references/completion.md`. Complete reviews must remain tied to the reviewed code, target commit, and issue body. Saving a `Fixes Applied` heading alone never marks a run complete. Recheck freshness after later code, design, target, or requirement changes.
2. **Summarize** — Issues found and resolved, deferrals with rationale, remaining minor findings and suggestions.

## Severity taxonomy and fix policy

One taxonomy is used repository-wide — by this skill, the `code-reviewer` subagent, the Codex root prompt in `AGENTS.md`, and CI first-pass review where configured. Because it is shared, triage needs no per-reviewer translation.

| Severity | Meaning | Policy |
| --- | --- | --- |
| **Critical** | Breaks correctness, security, or a documented invariant | Must fix before the PR. Not deferrable — no rationale clears it |
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

## Requirement Reference
{The issue's Requirements section, from `gh issue view <issue_number>`.
Otherwise: "No issue requirements available."}

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
9. **Requirement Adherence** — Does the branch carry every requirement in the issue?
   Criterion 8 compares the implementation against the design; this one compares
   the branch against the issue. Only this one catches a requirement that was
   dropped before the design was written.

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

Keep every severity category and state explicitly when it has no findings.
Provide a final verdict: APPROVE, REQUEST_CHANGES, or COMMENT.
```

## Reporting

Report to the user, in whatever shape fits the review:

- Branch, issue number, target branch
- Resolved reviewer, how it was resolved, and its model and reasoning effort
- Review scope and changed-line count
- The review output
- Where the artifact was saved
- Fixes applied, with the fix commit, and whether the executor applied them or they were applied inline
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
