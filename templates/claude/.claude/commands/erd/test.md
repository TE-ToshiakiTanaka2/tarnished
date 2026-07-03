---
description: Run the project's test suite with coverage analysis, fix clear failures, and author missing tests for changed or uncovered code paths. Use after a build passes or when asked to run tests, check coverage, or add missing tests.
argument-hint: "[target path or component]"
---

# /erd:test - Test Execution and Coverage

Execute tests with coverage analysis and quality reporting.

## Usage

```
/erd:test [target path or component]
```

## MCP Tools

- **playwright**: for e2e browser testing when the project includes UI components
- **context7**: `resolve-library-id`, `get-library-docs` -- for looking up test framework documentation and assertion patterns

If a listed MCP server is unavailable in the current environment, fall back to the agent's built-in code search, file reading, and web search tools -- do not stop or ask for installation.

## Behavioral Flow

1. **Discover**: Detect test framework and categorize available tests
2. **Execute**: Run test suite with coverage collection
3. **Analyze**: Parse results, identify failures, assess coverage
4. **Author**: Write missing tests for changed or uncovered code paths identified during coverage analysis
5. **Fix**: Fix failing tests if the cause is clear (implementation bug or test bug)
6. **Report**: Present results with actionable recommendations

## Test Framework Detection

| Indicator | Framework | Commands |
| --- | --- | --- |
| `Cargo.toml` | Rust/cargo test | `cargo test`, `cargo test -- --nocapture` |
| `package.json` (jest) | Jest | `npm test`, `npx jest --coverage` |
| `pyproject.toml` (pytest) | pytest | `pytest`, `pytest --cov` |
| `go.mod` | Go test | `go test ./...`, `go test -cover ./...` |

## Test Categories

- **Unit tests**: Test individual functions/modules in isolation
- **Integration tests**: Test module interactions and data flow
- **E2E tests**: Test full user workflows (use playwright for browser-based)

## Failure Analysis

When tests fail:
1. **Read the assertion error** -- what was expected vs actual?
2. **Determine if the test or implementation is wrong**
3. **Check for recent changes** that could have caused regression
4. **Fix the root cause**, not the symptom

## Output

```markdown
## Test Report

- Framework: [detected framework]
- Status: [all passed / N failures]

### Results
- Unit tests: [N/N passed]
- Integration tests: [N/N passed]
- E2E tests: [N/N passed] (if applicable)

### Coverage
- Overall: [percentage]
- New code: [assessment]

### Failures (if any)
- [test name]: [failure reason] -- [fix applied or action needed]

### Recommendations
- [missing test coverage areas]
```

## CRITICAL BOUNDARIES

**TEST EXECUTION AND COVERAGE ONLY**

This command runs tests, authors missing tests for uncovered changes, and reports results.

**Will NOT**:
- Rewrite existing passing tests without cause
- Modify test framework configuration
- Skip tests to make the suite pass

**Next Step**: After tests pass, use `/erd:analyze` for code quality or proceed to the PR stage of the lifecycle workflow.
