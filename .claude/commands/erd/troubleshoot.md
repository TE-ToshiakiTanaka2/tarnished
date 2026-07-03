---
description: Diagnose issues in code, builds, tests, or performance, identify the root cause with evidence, and propose ranked solutions without applying fixes by default. Use when something is broken, failing, or behaving unexpectedly and the root cause is unknown.
argument-hint: "[issue description]"
---

# /erd:troubleshoot - Issue Diagnosis and Resolution

Diagnose and resolve issues in code, builds, deployments, and system behavior.

## Usage

```
/erd:troubleshoot [issue description]
```

## MCP Tools

- **context7**: `resolve-library-id`, `get-library-docs` -- for looking up library-specific error patterns and known issues when troubleshooting dependency-related problems

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search, file reading, and web search tools -- do not stop or ask for installation.

## Behavioral Flow

1. **Gather**: Collect error messages, logs, stack traces, and system state
2. **Hypothesize**: Form hypotheses about root causes
3. **Investigate**: Test each hypothesis systematically with targeted analysis
4. **Diagnose**: Identify the root cause with supporting evidence
5. **Propose**: Present solution options ranked by safety and effectiveness

## Diagnostic Approach

### For code bugs:
1. Read the error message and stack trace
2. Find the failing code path with Grep/Read
3. Identify the triggering condition
4. Trace data flow to find where it diverges from expectations
5. Propose targeted fix

### For build failures:
1. Read build output/logs
2. Identify the failing step (compile, lint, type-check, link)
3. Check dependency versions and configuration
4. Trace the error to its source
5. Propose fix (dependency update, config change, code fix)

### For test failures:
1. Read test output and identify failing assertions
2. Compare expected vs actual values
3. Check if the test or the implementation is wrong
4. Look for recent changes that could have caused the regression
5. Propose fix for either test or implementation

### For performance issues:
1. Identify the slow operation (profiling, logs, metrics)
2. Analyze the algorithm/data structure used
3. Check for common bottlenecks (N+1, missing index, blocking I/O)
4. Propose optimization with expected impact

## Output

```markdown
## Diagnostic Report: [issue]

### Symptoms
- {observed behavior}

### Root Cause
{explanation of what is causing the issue}

### Evidence
- {supporting evidence from investigation}

### Proposed Solutions
1. **[Recommended]** {solution} -- Risk: Low
   - {implementation steps}
2. {alternative} -- Risk: Medium
   - {implementation steps}

### Prevention
- {how to prevent recurrence}
```

## CRITICAL BOUNDARIES

**DIAGNOSIS FIRST**

By default, this command diagnoses but does NOT apply fixes.

**Default behavior**:
- Diagnose the issue
- Identify root cause
- Propose solutions with risk assessment
- **STOP and present findings to user**

**Will NOT** (by default):
- Apply any code changes
- Modify any files
- Execute fixes automatically

The user decides whether to apply the proposed fix manually or ask for it to be applied.

**Next Step**: User reviews diagnosis, then applies fix or uses `/erd:improve` for broader refactoring.
