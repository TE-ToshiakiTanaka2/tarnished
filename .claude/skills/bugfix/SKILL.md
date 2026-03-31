---
name: bugfix
description: Bug investigation and fix workflow. Uses SuperClaude sc:analyze for root cause analysis. Investigates bugs, implements fix with regression tests, and verifies the solution.
argument-hint: "[issue_number]"
disable-model-invocation: true
---

# Bugfix Skill

Bug investigation and fix workflow. Analyzes a bug Issue, investigates root cause, implements a targeted fix with regression tests, and verifies the solution.

## Issue Context

!`gh issue view $ARGUMENTS --json title,body,labels,assignees 2>/dev/null || echo "Issue not found or no arguments provided"`

## What This Skill Does

### Phase 1: Preparation

1. **Review bug report** - Understand the bug from the Issue context above:
   - Expected behavior vs actual behavior
   - Reproduction steps
   - Environment details
2. **Create branch** - Create branch following naming convention:
   ```
   bugfix/{assignee}/#{issue_number}/{description}
   ```
3. **Reproduce the bug** - If possible, write a failing test first

### Phase 2: Investigation

4. **Execute `/sc:analyze`** - Investigate the bug with comprehensive analysis:
   - Trace the code path
   - Identify the faulty logic
   - Check git blame for recent changes that may have caused it
   - Search for related issues or patterns
5. **Determine fix scope** - Assess impact:
   - Is this an isolated issue or systemic?
   - What other code paths are affected?
   - Are there similar bugs elsewhere?

### Phase 3: Fix Implementation

6. **Write regression test** - Create a test that fails with the current code:
   - Test the exact scenario from the bug report
   - Test edge cases around the bug
7. **Implement fix** - Apply the minimal fix:
   - Fix the root cause, not symptoms
   - Keep changes focused and small
   - Avoid unrelated refactoring
8. **Verify fix** - Confirm the regression test passes

### Phase 4: Quality Assurance

9. **Run full test suite** - Ensure no regressions
10. **Run static analysis** - Language-specific linters and formatters
11. **Commit changes** - Using conventional commit format:
    ```
    fix: <description of what was fixed>

    Root cause: <brief explanation>
    Fixes #<issue_number>
    ```
12. **Report results**

## MCP Tools

Use the following MCP tools for bug investigation:

- **serena**: `find_symbol`, `get_symbols_overview`, `find_file`, `search_for_pattern`, `find_referencing_symbols` — for tracing code paths, finding references to buggy symbols, and understanding call chains
- **context7**: `resolve-library-id`, `query-docs` — for checking library behavior when the bug may relate to external dependency usage
- **sequential-thinking**: `sequentialthinking` — for structured root cause analysis: form hypotheses, verify against code evidence, revise and narrow down until the root cause is identified

## SuperClaude Skills Used

| Skill | Purpose |
| --- | --- |
| `/sc:analyze` | Root cause analysis and code path investigation |

## Investigation Techniques

| Technique              | When to Use                              |
| ---------------------- | ---------------------------------------- |
| Code path tracing      | Logic errors, unexpected behavior        |
| `git blame` / `git log`| Recent regressions                       |
| Search for patterns    | Systemic issues across codebase          |
| Input boundary analysis| Edge cases, off-by-one errors            |
| Error message tracing  | Runtime errors, panics, exceptions       |

## Output Format

```
Bugfix Complete

Branch: bugfix/username/#456/fix-argument-parsing
Issue: #456

Root Cause:
  Off-by-one error in argument index calculation
  when optional flags precede positional arguments.

Fix Applied:
  src/cli/parser.rs:142 — Adjusted index offset
  to account for consumed flag arguments.

Tests:
- New regression test: test_parse_args_with_flags
- All existing tests: 42/42 passed

Quality Checks:
- Formatting: Passed
- Linting: Passed

Commits:
- test: add regression test for #456
- fix: correct argument index calculation with flags

Ready for /review or /pr
```

## Best Practices

- **Reproduce first**: Always try to write a failing test before fixing
- **Fix root cause**: Don't patch symptoms
- **Minimal changes**: Keep the fix focused; avoid scope creep
- **Regression tests**: Every bug fix needs a test that would have caught it
- **Check for siblings**: Look for the same bug pattern elsewhere

## Integration

- **Prerequisite**: Bug Issue exists
- **Next step**: Review with `/review` or create PR with `/pr`
- **Typical workflow**: `/issue` → **`/bugfix`** → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
