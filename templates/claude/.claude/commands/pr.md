# Claude Command: PR (Pull Request)

This command helps you create Pull Requests to merge your feature branch, with automatic change history gathering, issue linking, and verification.

## Usage

To create a Pull Request:

```
/pr
```

Or specify a target branch:

```
/pr main
```

## What This Command Does

1. **Gather PR information** - Determine source and target branches (defaults to current branch → main/develop)
2. **Analyze changes** - Review current branch changes and staged content
3. **Run code quality checks** - Execute linters and formatters on changed files
4. **Run test suite** - Execute all applicable tests
5. **Commit improvements** - Commit any improvements with descriptive message
6. **Push changes** - Push all commits to remote branch
7. **Create Pull Request** - Submit PR with comprehensive description and **English title**
8. **Verify CI status** - Check GitHub Actions status if configured
9. **Report completion** - Notify user of successful PR creation

## Workflow Steps

### 1. Branch Information Gathering

- Identify current branch using `git branch --show-current`
- Default target: `main` or `develop` branch
- Verify branches are appropriate for PR
- If current branch is the default branch, ask user for clarification

### 2. Change History Collection

- Use `git log` to get all commits since branching
- Run `git diff` to summarize changes
- Organize commits by type (feature, fix, refactor, etc.)
- Calculate statistics (files changed, additions, deletions)

### 3. Issue Linking

- Extract issue number from branch name (format: `#{number}`)
- Add "Closes #XXX" to ensure automatic issue closure
- Link related issues mentioned in commits

### 4. PR Creation

Use `gh pr create` with:

- **Title in English** derived from branch name or main feature
- Comprehensive description
- Issue closing keywords

## Pull Request Title Format (English)

The PR title should follow conventional commit format in English:

```
{type}: {description in English}
```

Examples:

- `feat: add user settings management`
- `fix: resolve login authentication error`
- `refactor: optimize database query performance`
- `docs: update README with installation guide`

## Pull Request Description Format

The PR description will include:

```markdown
## Summary

Brief description of what this PR accomplishes

## Changes

### New Features
- List of new features implemented

### Bug Fixes
- List of bugs fixed

### Refactoring
- List of refactoring changes

### Documentation
- Documentation updates

## Testing

- [ ] Tests pass
- [ ] Code quality checks pass
- [ ] Manual testing completed (if applicable)

## Related Issue

Closes #XXX
```

## Automatic Issue Closing

The PR will include keywords to automatically close related issues:

- `Closes #123` - Closes issue when PR is merged
- `Fixes #456` - Alternative keyword for bug fixes
- `Resolves #789` - Alternative keyword for resolved issues

## Branch Naming Convention

Expected branch format for automatic issue detection:

```
{type}/{assignee}/#{issue_number}/{description}
```

Examples:

- `feature/alice/#123/add-user-settings` → Links to issue #123
- `bugfix/bob/#456/fix-login-error` → Links to issue #456

## Error Handling

The command will handle these scenarios:

1. **No changes to commit**: Remind user to commit changes first
2. **On default branch**: Ask which feature branch to create PR from
3. **Conflicts detected**: Notify user and provide merge instructions
4. **No issue number**: Proceed without issue linking
5. **PR already exists**: Show existing PR URL

## Command Output

Successful completion will show:

```
Pull Request Created

PR: #XXX - [Title in English]
URL: https://github.com/owner/repo/pull/XXX

Target Branch: main
Source Branch: feature/user/#123/add-feature

Related Issue: #123 (will be closed on merge)

Change Summary:
- X files changed
- Y lines added
- Z lines deleted

Ready for review.
```

## Best Practices

- **English Title**: Always use English for PR titles following conventional commit format
- **Comprehensive Description**: Include all context needed for review
- **Clear Change Summary**: Organize changes by type
- **Test Evidence**: Document testing approach and results
- **Issue Linking**: Always link related issues for traceability
- **Review Ready**: Ensure all checks pass before creating PR

## Integration with Other Commands

This command works with:

- `/issue` - Create issues that will be linked
- `/implement` - Implement features that will be merged

ARGUMENTS:
