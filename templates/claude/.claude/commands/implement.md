# Claude Command: Implement

This command helps you implement GitHub Issues by reviewing requirements, creating branches, implementing features, running tests, and ensuring code quality.

## Usage

To implement a GitHub Issue:

```
/implement <issue_number>
```

Example:

```
/implement 1
```

## What This Command Does

1. **Review GitHub Issue** - Use `gh issue view` to check and understand the issue content
2. **Create feature branch** - Checkout a new branch with the naming convention:
   - Format: `{label}/{assignee}/#{issue_number}/{title}`
   - Example: `feature/john/#42/add-user-settings`
3. **Plan implementation** - Break down the issue into implementable tasks
4. **Implement features** - Execute the implementation following the plan
5. **Commit progressively** - Create commits as each task or subtask is completed
6. **Run tests** - Execute test suite based on the project's test configuration
7. **Code quality checks** - Run linters and formatters as configured
8. **Final commit** - Commit all remaining modifications
9. **Present results** - Show the final branch name and issue number to the user

## Branch Naming Convention

Branches are created following this pattern:

```
{label}/{assignee}/#{issue_number}/{title}
```

Where:

- `{label}` - Issue label (feature, bugfix, patch, refactor, documentation)
- `{assignee}` - GitHub username of the assignee
- `{issue_number}` - The issue number (with # prefix)
- `{title}` - Kebab-case title derived from the issue

Examples:

- `feature/alice/#123/add-user-settings`
- `bugfix/bob/#456/fix-login-error`
- `refactor/charlie/#789/optimize-database-queries`

## Implementation Workflow

### 1. Issue Analysis

- Read and understand all requirements
- Identify main tasks and subtasks
- Note acceptance criteria
- Check for dependencies

### 2. Development Process

- Implement features incrementally
- Follow existing code patterns and conventions
- Write clean, maintainable code
- Add appropriate comments and documentation

### 3. Commit Strategy

- Make atomic commits for each logical change
- Use conventional commit format with emojis:
  - `feat:` for new features
  - `fix:` for bug fixes
  - `refactor:` for refactoring
  - `test:` for test additions
  - `docs:` for documentation

### 4. Testing Requirements

- Run existing tests to ensure no regressions
- Add new tests for new functionality when appropriate
- Verify all tests pass before completing

### 5. Code Quality

- Run configured linters
- Apply formatters as needed
- Fix all issues before proceeding

## Error Handling

If unable to complete implementation:

- Clearly communicate blockers to the user
- Ask for guidance on unresolved issues
- Document any assumptions made

## Output Format

Upon successful completion, the command will present:

```
Implementation Complete

Branch: feature/username/#123/feature-title
Issue: #123

Summary:
- All tasks implemented
- All tests passing

Ready for review.
```

## Best Practices

- **Incremental Development**: Build features step by step
- **Test-Driven Development**: Consider writing tests first when appropriate
- **Code Review Ready**: Ensure code is clean and well-documented
- **Communication**: Keep the user informed of progress and any issues

## Integration with Other Commands

This command works with:

- `/issue` - Create issues to implement
- `/pr` - Create pull request after implementation

ARGUMENTS:
