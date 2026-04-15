# /erd:analyze - Code Analysis and Quality Assessment

Comprehensive code analysis across quality, security, performance, and architecture domains.

## Usage

```
/erd:analyze [target path or component]
```

## MCP Tools

- **serena**: `find_symbol`, `get_symbols_overview`, `find_referencing_symbols` -- for understanding code structure, symbol relationships, and usage patterns
- **sequential-thinking**: `sequentialthinking` -- for structured multi-domain analysis and prioritizing findings

## Behavioral Flow

1. **Discover**: Identify target files using Glob and categorize by language/purpose
2. **Scan**: Apply domain-specific analysis across all four domains
3. **Evaluate**: Generate prioritized findings with severity ratings
4. **Recommend**: Create actionable recommendations
5. **Report**: Present structured analysis

## Analysis Domains

### Quality
- Code readability and naming conventions
- DRY violations and duplicated logic
- Function/method complexity (long functions, deep nesting)
- Error handling completeness
- Type safety and annotation coverage

### Security
- Input validation gaps
- Injection risks (SQL, command, path traversal)
- Authentication/authorization checks
- Sensitive data exposure (hardcoded secrets, logging PII)
- Dependency vulnerabilities (known CVEs)

### Performance
- Inefficient algorithms or data structures
- Unnecessary allocations or copies
- N+1 query patterns
- Missing caching opportunities
- Blocking operations in async contexts

### Architecture
- Module coupling and cohesion
- Layer boundary violations
- API contract consistency
- Separation of concerns
- Dependency direction (no circular deps)

## Severity Levels

| Level | Description | Action |
| --- | --- | --- |
| **Critical** | Security vulnerability or data loss risk | Fix immediately |
| **High** | Bug-prone pattern or significant tech debt | Fix before merge |
| **Medium** | Code smell or maintainability concern | Fix when touching the file |
| **Low** | Style or minor improvement opportunity | Nice to have |

## Output

```markdown
## Analysis Report: [target]

### Summary
- Critical: N | High: N | Medium: N | Low: N

### Critical Findings
- [C-1] [domain] {description} -- {file:line}
  - **Impact**: {what could go wrong}
  - **Fix**: {recommended action}

### High Findings
- [H-1] ...

### Medium Findings
- [M-1] ...

### Recommendations
1. {prioritized action items}
```

## CRITICAL BOUNDARIES

**ANALYSIS ONLY**

This command produces an ANALYSIS REPORT ONLY.

**Will NOT**:
- Modify source code or apply fixes
- Execute code or run tests
- Make architectural decisions

**Next Step**: After review, use `/erd:improve` to apply fixes or `/erd:cleanup` for dead code removal.
