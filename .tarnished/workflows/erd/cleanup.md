# /erd:cleanup - Code and Project Cleanup

Systematically clean up code, remove dead code, and optimize project structure.

## Usage

```
/erd:cleanup [target path or component]
```

## MCP Tools

- **serena**: `find_symbol`, `find_referencing_symbols` -- for safely identifying unused code; confirm zero references with `find_referencing_symbols` before removing code via the standard edit tools
- **context7**: `resolve-library-id`, `get-library-docs` -- for checking whether seemingly unused imports are required by framework conventions

## Behavioral Flow

1. **Analyze**: Scan for cleanup opportunities (dead code, unused imports, empty blocks)
2. **Classify**: Categorize each finding as auto-fix or approval-required
3. **Execute**: Apply safe cleanups automatically, prompt for others
4. **Validate**: Verify no functionality was lost (build + tests)
5. **Report**: Summarize what was cleaned up

## Cleanup Categories

### Auto-fix (applies automatically)
- Unused imports removal
- Dead code with zero references
- Empty blocks removal
- Redundant type annotations
- Trailing whitespace and formatting

### Approval Required (prompts user first)
- Code with indirect references (reflection, dynamic dispatch)
- Exports potentially used by external consumers
- Test fixtures and utilities
- Configuration values
- Comments and documentation

## Safety Rules

- If code has ANY usage path: prompt user
- If code affects public API: prompt user
- If unsure about usage: prompt user
- Use `find_referencing_symbols` to verify zero references before deletion

## Cleanup Checklist

1. **Unused imports**: Scan all files for imports with no references
2. **Dead functions/methods**: Find functions with zero callers
3. **Unused variables**: Local variables assigned but never read
4. **Empty blocks**: try/catch, if/else blocks with no content
5. **Commented-out code**: Old code left in comments
6. **Duplicate code**: Nearly identical blocks across files
7. **Stale TODOs**: TODO/FIXME comments that reference completed work

## Output

```markdown
## Cleanup Report: [target]

### Auto-fixed
- Removed N unused imports across M files
- Removed N dead functions
- Cleaned N empty blocks

### User-approved Removals
- [file:line] {description} -- approved by user

### Skipped (needs review)
- [file:line] {description} -- {reason for skip}

### Verification
- Build: {pass/fail}
- Tests: {pass/fail}
```

## CRITICAL BOUNDARIES

**CLEANUP ONLY -- NO BEHAVIOR CHANGES**

This command removes dead/unused code without changing behavior.

**Will NOT**:
- Remove code without thorough reference analysis
- Change logic or control flow
- Modify public APIs
- Delete files without user confirmation

**Next Step**: Run build and tests to verify cleanup. Use `/erd:improve` for quality improvements beyond cleanup.
