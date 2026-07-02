---
name: implement
description: Implement a GitHub Issue with codebase understanding, build verification, testing, and quality assurance. Uses erd commands (erd:index-repo, erd:implement, erd:build, erd:test, erd:analyze, erd:improve, erd:troubleshoot).
argument-hint: "[issue_number]"
disable-model-invocation: true
---

# Skill: Implement

Implementation skill for projects. Handles codebase understanding, feature implementation, build verification, testing, code analysis, and quality improvement.

This skill is the Claude Code projection of `.tarnished/workflows/implement.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

## Usage

```
/implement <issue_number>
```

Example:

```
/implement 42
```

## erd Command Invocation

All erd commands in this skill MUST be loaded via the **Read tool** and followed inline:

```
Read(".claude/commands/erd/<command>.md") → follow instructions inline
```

Do NOT use the Skill tool to invoke erd commands. Loading via Read keeps the entire workflow in a single turn, preventing flow interruption between phases.

## What This Skill Does

### Phase 1: Preparation

1. **Review Issue** - Use `gh issue view` to understand Issue content
2. **Detect or create branch** - Follow `_shared/branch` procedure (Issue mode) with the issue number
   - This handles existing branch detection, checkout, and new branch creation
   - See `_shared/branch/SKILL.md` for full procedure
3. **Load design artifacts** - Read both layers of the design corpus:
   - **Shared layer**: `docs/design/shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md`, and any `shared/research/*.md` (skip files that do not exist — `shared/` may be empty for the very first issue)
   - **Per-issue layer**: `docs/design/#{issue_number}/design.md`, `api-spec.md`, `workflow.md`, `flowchart.md`, `research.md` (skip files that do not exist)
   - The shared layer is the cumulative project truth maintained by `/design`. The per-issue layer is the self-contained delta for this issue.
4. **Load `/erd:index-repo` and follow inline** - `Read(".claude/commands/erd/index-repo.md")`:
   - Map relevant modules and their relationships
   - Identify files that need modification
   - Understand existing patterns and conventions

### Phase 2: Implementation

5. **Load `/erd:implement` and follow inline** - `Read(".claude/commands/erd/implement.md")`:
   - Follow design artifacts from `/design` (if available)
   - Follow language best practices
   - Proper error handling
   - Type safety
6. **Progressive commits** - Commit per logical unit of work

### Phase 3: Build and Test

7. **Load `/erd:build` and follow inline** - `Read(".claude/commands/erd/build.md")`:
   - Run language-specific linters and formatters
   - Run type checkers
   - Fix build errors iteratively
8. **Load `/erd:test` and follow inline** - `Read(".claude/commands/erd/test.md")`:
   - Unit tests
   - Integration tests (if applicable)
   - E2E tests (if applicable)
   - Analyze coverage and add missing tests

### Phase 4: Quality Assurance

9. **Load `/erd:analyze` and follow inline** - `Read(".claude/commands/erd/analyze.md")`:
   - Code quality: readability, maintainability, DRY
   - Security: input validation, injection risks, auth checks
   - Performance: inefficient patterns, unnecessary allocations
   - Architecture: module design, layer separation
10. **Load `/erd:improve` and follow inline** - `Read(".claude/commands/erd/improve.md")`:
    - Code quality improvements
    - Pattern standardization
    - Type safety enhancements
    - Error handling improvements
11. **Re-load `/erd:build`** and **`/erd:test`** and follow inline - Verify improvements don't break anything

### Phase 5: Error Recovery (if needed)

12. **Load `/erd:troubleshoot` and follow inline** (conditional) - `Read(".claude/commands/erd/troubleshoot.md")`:
    - Diagnose root cause of failures
    - Identify dependency issues
    - Resolve configuration problems
    - Apply targeted fixes

### Phase 6: Final Commit and Report

13. **Final commit** - Commit all remaining changes
14. **Report results** - Present branch name, quality metrics, and test results

## Branch Naming Convention

```
{label}/{assignee}/#{issue_number}/{title}
```

- `{label}`: Issue label (feature, bugfix, refactor, docs)
- `{assignee}`: GitHub username
- `{issue_number}`: Issue number (with # prefix)
- `{title}`: kebab-case title

Examples:

- `feature/alice/#123/add-config-loader`
- `bugfix/bob/#456/fix-argument-parsing`

**Important**: If `/design` has already created a branch, reuse it. Do not create a duplicate.

## MCP Tools

Use the following MCP tools during implementation:

- **serena**: `find_symbol`, `get_symbols_overview`, `find_file`, `search_for_pattern`, `list_dir`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol` — for codebase navigation, understanding existing patterns, and semantic code editing
- **context7**: `resolve-library-id`, `get-library-docs` — for looking up library documentation when implementing with external dependencies
## erd Skills Used

| Skill | Purpose | Phase |
| --- | --- | --- |
| `/erd:index-repo` | Repository indexing for efficient codebase understanding | Phase 1 |
| `/erd:implement` | Feature implementation with persona activation | Phase 2 |
| `/erd:build` | Build verification with intelligent error handling | Phase 3 |
| `/erd:test` | Test execution with coverage analysis and quality reporting | Phase 3 |
| `/erd:analyze` | Comprehensive code analysis (quality, security, performance, architecture) | Phase 4 |
| `/erd:improve` | Systematic code quality improvements | Phase 4 |
| `/erd:troubleshoot` | Diagnose and resolve persistent build/test failures (conditional) | Phase 5 |

## Leveraging erd:index-repo

Use `/erd:index-repo` for efficient codebase understanding:

- Significant token reduction compared to reading full files
- Map module relationships and dependencies
- Identify patterns and conventions already in use
- Focus on files relevant to the current issue

## Leveraging erd:implement

Use `/erd:implement` for the actual coding work:

- Follow design artifacts from `/design` phase (if available)
- Activate appropriate persona for the language/framework
- Implement with proper type annotations and error handling
- Create progressive commits per logical unit

## Leveraging erd:build

Use `/erd:build` to verify the build:

- Run language-specific linters and formatters
- Run type checkers (mypy, tsc, cargo check, etc.)
- Fix errors iteratively until build passes
- Language detection is automatic based on project files

## Leveraging erd:test

Use `/erd:test` to run and analyze tests:

- Execute the project's test suite
- Analyze test coverage
- Identify and add missing test cases
- Run integration/E2E tests if applicable

## Leveraging erd:analyze and erd:improve

Use `/erd:analyze` then `/erd:improve` as a feedback loop:

```
erd:analyze findings → erd:improve fixes → erd:build verify → erd:test verify
```

Analysis domains:
- **Quality**: Code readability, maintainability, DRY principle
- **Security**: Input validation, permission checks, injection risks
- **Performance**: Inefficient patterns, unnecessary allocations
- **Architecture**: Module design, layer separation, API contracts

## Commit Strategy

Conventional commit format with progressive commits:

```
feat: add config type definitions
feat: implement config file loader
test: add unit tests for config module
fix: resolve edge case in config parsing
refactor: extract validation logic (erd:improve)
```

## Implementation Workflow

```mermaid
graph TD
    A[Review Issue] --> B{Design branch exists?}
    B -->|Yes| C[Switch to branch]
    B -->|No| C2[Create branch]
    C --> D[Load design artifacts]
    C2 --> D
    D --> E[Execute erd:index-repo]
    E --> F[Execute erd:implement]
    F --> G[Progressive commits]
    G --> H[Execute erd:build]
    H --> I{Build OK?}
    I -->|No| J[Fix build errors]
    J --> H
    I -->|Yes| K[Execute erd:test]
    K --> L{Tests pass?}
    L -->|No| M{Persistent failure?}
    M -->|Yes| N[Execute erd:troubleshoot]
    N --> F
    M -->|No| O[Fix tests]
    O --> K
    L -->|Yes| P[Execute erd:analyze]
    P --> Q[Execute erd:improve]
    Q --> R[Re-run erd:build + erd:test]
    R --> S{All pass?}
    S -->|No| T[Fix issues]
    T --> R
    S -->|Yes| U[Final commit]
    U --> V[Report completion]
```

## Error Handling

- **Build errors**: Attempt auto-fix with linters/formatters, retry build
- **Test failures**: Analyze cause, fix implementation, re-run tests
- **Persistent failures**: Escalate to `/erd:troubleshoot` for root cause analysis
- **Blockers**: Report to user, request guidance

## Output Format

```
Implementation Complete

Branch: feature/username/#123/add-config-loader
Issue: #123

Codebase Analysis (erd:index-repo):
  - Indexed N modules, identified M relevant files

Quality Checks (erd:build):
  - Linting: Passed
  - Formatting: Passed
  - Type Check: Passed

Tests (erd:test):
  - Unit tests: 15/15 passed
  - Integration tests: 3/3 passed

Code Analysis (erd:analyze):
  - Quality: No issues
  - Security: No issues
  - Performance: No issues

Improvements Applied (erd:improve):
  - Standardized error handling pattern
  - Enhanced type safety in 2 modules

Commits:
- feat: add Config type definitions
- feat: implement config loader
- test: add config loader tests
- refactor: improve error handling (erd:improve)

Ready for /review or /pr
```

## Best Practices

- **Design First**: Load and follow design artifacts from `/design` if available
- **Codebase Understanding**: Use `/erd:index-repo` before jumping into implementation
- **Incremental Implementation**: Implement and commit in small logical units
- **Type Safety**: Maximize use of type systems where available
- **Test Coverage**: Always add tests for new features
- **Quality Loop**: analyze → improve → build → test as a feedback cycle

## Integration

- **Prerequisite**: Issue created with `/issue`, optionally designed with `/design`
- **Next step**: Review with `/review` or create Pull Request with `/pr`
- **Typical workflow**: `/issue` → `/design` → **`/implement`** → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
