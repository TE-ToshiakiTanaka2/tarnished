# /erd:reflect - Task Reflection and Validation

Validate task completion, CI results, and overall quality before finalizing work.

## Usage

```
/erd:reflect [target: PR number, task description, or CI run]
```

## Behavioral Flow

1. **Gather**: Collect CI results, test output, coverage data, and change diff
2. **Validate**: Assess whether the implementation meets requirements
3. **Evaluate**: Check quality gates and identify remaining concerns
4. **Report**: Present validation summary with clear pass/fail and action items

## Validation Checklist

### CI Results
- All checks passed or identified as flaky
- No new warnings introduced
- Build artifacts generated successfully

### Test Coverage
- New code has adequate test coverage
- No existing tests broken by changes
- Edge cases covered

### Requirement Matching
- Implementation satisfies issue requirements
- No scope creep beyond what was asked
- Acceptance criteria met

### Risk Assessment
- No security concerns introduced
- No performance regressions
- No breaking changes to public APIs

## Output

```markdown
## Validation Report

### CI Status
- Checks: [N/N passed]
- Failures: [list any failures with analysis]
- Flaky: [identified flaky tests, if any]

### Coverage
- Assessment: [adequate/needs improvement]
- New code coverage: [estimate]

### Requirements
- Status: [fully met / partially met / not met]
- Gaps: [any unmet requirements]

### Risks
- [identified risks or "None identified"]

### Verdict
- [PASS: Ready for merge / FAIL: Action required]
- Action items: [if any]
```

## CRITICAL BOUNDARIES

**VALIDATION ONLY**

This command validates and reports -- it does NOT fix issues.

**Will NOT**:
- Apply code changes or fixes
- Modify CI configuration
- Merge or close PRs
- Make architectural decisions

**Next Step**: If issues found, use `/erd:troubleshoot` to diagnose or `/erd:improve` to fix. If passed, proceed with merge.
