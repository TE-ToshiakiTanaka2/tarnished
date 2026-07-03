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

## erd Command Invocation

All erd commands in this skill MUST be loaded via the **Read tool** and followed inline:

```
Read(".claude/commands/erd/<command>.md") → follow instructions inline
```

Do NOT use the Skill tool to invoke erd commands. Loading via Read keeps the entire workflow in a single turn, preventing flow interruption between phases.

## What This Skill Does

### Phase 1: Preparation

1. **Review Issue** - Use `gh issue view` to understand Issue content
2. **Detect or create branch** - Follow `_shared/branch` procedure (Issue mode) with the issue number. Branch naming and existing-branch detection are defined in `_shared/branch/SKILL.md`. If `/design` already created a branch for this issue, it is detected and reused — do not create a duplicate.
3. **Load design artifacts** - Read both layers of the design corpus:
   - **Shared layer**: `docs/design/shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md`, and any `shared/research/*.md` (skip files that do not exist — `shared/` may be empty for the very first issue)
   - **Per-issue layer**: `docs/design/#{issue_number}/design.md`, `api-spec.md`, `workflow.md`, `flowchart.md`, `research.md` (skip files that do not exist)
   - The shared layer is the cumulative project truth maintained by `/design`. The per-issue layer is the self-contained delta for this issue.
4. **Load `/erd:index-repo` and follow inline** - `Read(".claude/commands/erd/index-repo.md")`:
   - Map relevant modules, identify files that need modification, understand existing patterns

### Phase 2: Implementation

5. **Load `/erd:implement` and follow inline** - `Read(".claude/commands/erd/implement.md")`:
   - Follow design artifacts from `/design` (if available), language best practices, proper error handling, type safety
6. **Progressive commits** - Commit per logical unit of work (see "Commit Strategy" below)

### Phase 3: Build and Test

7. **Load `/erd:build` and follow inline** - `Read(".claude/commands/erd/build.md")`:
   - Run linters, formatters, and type checkers; fix build errors iteratively
8. **Load `/erd:test` and follow inline** - `Read(".claude/commands/erd/test.md")`:
   - Run the test suite, analyze coverage, and author missing tests for changed code paths

### Phase 4: Quality Assurance

9. **Load `/erd:analyze` and follow inline** - `Read(".claude/commands/erd/analyze.md")`:
   - Quality, security, performance, and architecture findings
10. **Load `/erd:improve` and follow inline** - `Read(".claude/commands/erd/improve.md")`:
    - Apply behavior-preserving improvements addressing the analysis findings
11. **Re-load `/erd:build`** and **`/erd:test`** and follow inline - Verify improvements don't break anything

The QA feedback cycle is: `erd:analyze findings → erd:improve fixes → erd:build verify → erd:test verify`.

### Phase 5: Error Recovery (if needed)

12. **Load `/erd:troubleshoot` and follow inline** (conditional) - `Read(".claude/commands/erd/troubleshoot.md")`:
    - When build or test failures persist after direct fixes, or failures stem from configuration/dependencies rather than code

### Phase 6: Final Commit and Report

13. **Final commit** - Commit all remaining changes
14. **Report results** - Present branch name, quality metrics, and test results using the "Output Format" below

## MCP Tools

Use the following MCP tools during implementation:

- **serena**: `find_symbol`, `get_symbols_overview`, `find_file`, `search_for_pattern`, `list_dir`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol` — for codebase navigation, understanding existing patterns, and semantic code editing
- **context7**: `resolve-library-id`, `get-library-docs` — for looking up library documentation when implementing with external dependencies

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search, file reading, and web search tools — do not stop or ask for installation.

## erd Commands Used

| Command | Purpose | Phase |
| --- | --- | --- |
| `/erd:index-repo` | Repository indexing for efficient codebase understanding | Phase 1 |
| `/erd:implement` | Feature implementation following design artifacts | Phase 2 |
| `/erd:build` | Build verification with iterative error fixing | Phase 3 |
| `/erd:test` | Test execution, coverage analysis, and authoring missing tests | Phase 3 |
| `/erd:analyze` | Code analysis (quality, security, performance, architecture) | Phase 4 |
| `/erd:improve` | Behavior-preserving quality improvements | Phase 4 |
| `/erd:troubleshoot` | Diagnose persistent build/test failures (conditional) | Phase 5 |

## Commit Strategy

Conventional commit format with progressive commits:

```
feat: add config type definitions
feat: implement config file loader
test: add unit tests for config module
fix: resolve edge case in config parsing
refactor: extract validation logic (erd:improve)
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
