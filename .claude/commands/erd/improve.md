# /erd:improve - Code Improvement

Apply systematic improvements to code quality, performance, and maintainability.

## Usage

```
/erd:improve [target path or component]
```

## MCP Tools

- **serena**: `find_symbol`, `get_symbols_overview`, `replace_symbol_body`, `find_referencing_symbols` -- for understanding code structure and safely applying changes
- **sequential-thinking**: `sequentialthinking` -- for planning complex multi-step improvements
- **context7**: `resolve-library-id`, `query-docs` -- for framework-specific best practices

## Behavioral Flow

1. **Analyze**: Examine code for improvement opportunities
2. **Plan**: Prioritize improvements by impact and safety
3. **Execute**: Apply improvements systematically
4. **Validate**: Verify improvements preserve functionality
5. **Report**: Summarize changes made

## Improvement Categories

### Auto-fix (applies without confirmation)
- Unused import removal
- Dead variable cleanup
- Style/formatting fixes
- Simple type annotation additions
- Import organization

### Approval Required (confirms with user first)
- Logic refactoring
- Function signature changes
- Architectural changes
- Removing code used by public APIs
- Changes affecting multiple files

## Improvement Patterns

### Quality
- Extract duplicated logic into shared functions
- Reduce function complexity (split long functions)
- Improve naming for clarity
- Add missing error handling
- Standardize patterns across similar code

### Performance
- Replace inefficient algorithms
- Eliminate unnecessary allocations
- Add caching where beneficial
- Optimize hot paths

### Maintainability
- Reduce coupling between modules
- Improve separation of concerns
- Simplify complex conditionals
- Make implicit behavior explicit

### Type Safety
- Add missing type annotations
- Replace `any` types with specific types
- Add validation at system boundaries
- Use enums instead of magic strings

## Output

```markdown
## Improvement Report: [target]

### Changes Applied
1. [file:line] {description of change} -- {category}
2. ...

### Changes Requiring Approval
1. [file:line] {description} -- {reason for approval}
   - **Impact**: {what changes}
   - **Risk**: {low/medium/high}

### Skipped (out of scope)
- {items that need separate work}

### Verification
- Build: {pass/fail}
- Tests: {pass/fail}
```

## CRITICAL BOUNDARIES

**IMPROVEMENT ONLY -- NO FEATURE CHANGES**

This command improves existing code quality without changing behavior.

**Will NOT**:
- Add new features or functionality
- Change external behavior or API contracts
- Make architectural decisions without user confirmation
- Remove functionality

**Next Step**: Run build and tests to verify improvements. Use `/erd:cleanup` for dead code removal.
