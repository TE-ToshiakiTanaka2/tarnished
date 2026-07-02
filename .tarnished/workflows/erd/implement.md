# /erd:implement - Feature Implementation

Implement features and code changes following design artifacts and codebase conventions.

## Usage

```
/erd:implement [feature description or issue reference]
```

## MCP Tools

- **serena**: `find_symbol`, `get_symbols_overview`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol` -- for codebase navigation, understanding existing patterns, and semantic code editing
- **context7**: `resolve-library-id`, `get-library-docs` -- for looking up library documentation and framework-specific patterns during implementation

## Behavioral Flow

1. **Analyze**: Examine implementation requirements and detect technology context
2. **Plan**: Determine implementation approach based on design artifacts (if available)
3. **Implement**: Write code following existing patterns and conventions
4. **Validate**: Ensure code compiles, basic functionality works
5. **Commit**: Create progressive commits per logical unit of work

## Implementation Principles

- **Follow design artifacts**: If `/erd:design` output exists, follow it
- **Match existing patterns**: Use the same conventions already in the codebase
- **Type safety**: Maximize use of the type system
- **Error handling**: Handle errors explicitly, don't swallow them
- **Progressive commits**: Commit per logical unit (types, core logic, tests, etc.)

## Commit Convention

```
feat: add config type definitions
feat: implement config file loader
test: add unit tests for config module
fix: resolve edge case in config parsing
```

## Completion Criteria

Implementation is DONE when:
- Feature code is written and compiles
- Basic functionality verified
- Files saved and committed

## CRITICAL BOUNDARIES

**IMPLEMENTATION ONLY**

This command writes code for the specified feature.

**Will NOT**:
- Make architectural decisions not covered by design artifacts
- Skip compilation verification
- Implement beyond the specified scope

**Next Step**: After implementation, use `/erd:build` to verify build, then `/erd:test` to run tests.
