# Implementation Workflow: GitHub Repository Operations for setup.sh

## Issue Reference
- **Issue**: #47
- **Title**: Add GitHub repository operations to setup.sh for develop branch workflow

## Implementation Phases

### Phase 1: GitHub Operations Functions

**Goal**: Implement core GitHub operation functions in setup.sh

#### Task 1.1: Add check_gh_auth function
- [ ] Add `check_gh_auth()` function after the validation functions section
- [ ] Check if `gh` command exists
- [ ] Check `gh auth status`
- [ ] Run `gh auth login` if not authenticated
- [ ] Return appropriate error codes

#### Task 1.2: Add setup_develop_branch function
- [ ] Add `setup_develop_branch()` function
- [ ] Check if current directory is a git repository
- [ ] Check if develop branch exists locally
- [ ] Check if develop branch exists on remote
- [ ] Create or checkout develop branch accordingly

#### Task 1.3: Add set_default_branch function
- [ ] Add `set_default_branch()` function
- [ ] Try `gh repo edit --default-branch develop`
- [ ] Handle permission errors gracefully
- [ ] Push develop branch as fallback
- [ ] Show manual instruction message

#### Task 1.4: Add auto_commit function
- [ ] Add `auto_commit()` function
- [ ] Check if there are changes to commit
- [ ] Stage all changes with `git add -A`
- [ ] Commit with provided message
- [ ] Handle "nothing to commit" case

### Phase 2: Setup Flow Integration

**Goal**: Integrate GitHub operations into the existing setup flow

#### Task 2.1: Add setup_github_repository function
- [ ] Create wrapper function that orchestrates GitHub operations
- [ ] Call check_gh_auth
- [ ] Call setup_develop_branch
- [ ] Call set_default_branch
- [ ] Handle errors and provide appropriate feedback

#### Task 2.2: Modify main function
- [ ] Add call to `setup_github_repository()` at the beginning of main
- [ ] Place it after `print_header` and before `check_dependencies`
- [ ] Ensure early exit if GitHub setup fails

#### Task 2.3: Add auto commits after each major step
- [ ] Add auto_commit after plugin_copy hooks
- [ ] Add auto_commit after plugin_post_copy hooks
- [ ] Add auto_commit after plugin_validate hooks
- [ ] Use appropriate commit messages

### Phase 3: Error Handling Enhancement

**Goal**: Robust error handling for all edge cases

#### Task 3.1: Validate git repository state
- [ ] Check for `.git` directory
- [ ] Check for `origin` remote
- [ ] Provide clear error messages

#### Task 3.2: Handle network errors
- [ ] Wrap git push in error handling
- [ ] Allow setup to continue even if push fails
- [ ] Log warnings for network-related issues

### Phase 4: Update show_completion

**Goal**: Update completion message to include GitHub-related information

#### Task 4.1: Add branch information to completion
- [ ] Show current branch name
- [ ] Show if default branch was set
- [ ] Show commit count

### Phase 5: Testing and Validation

**Goal**: Ensure all functionality works correctly

#### Task 5.1: Manual testing
- [ ] Test with authenticated gh
- [ ] Test with unauthenticated gh
- [ ] Test in non-git directory
- [ ] Test with existing develop branch
- [ ] Test without existing develop branch

#### Task 5.2: Dry-run mode verification
- [ ] Verify dry-run doesn't make git changes
- [ ] Verify preview shows correct information

## Implementation Order

```
Phase 1.1 (check_gh_auth)
    ↓
Phase 1.2 (setup_develop_branch)
    ↓
Phase 1.3 (set_default_branch)
    ↓
Phase 1.4 (auto_commit)
    ↓
Phase 2.1 (setup_github_repository wrapper)
    ↓
Phase 2.2 (main function integration)
    ↓
Phase 2.3 (auto commits integration)
    ↓
Phase 3 (error handling)
    ↓
Phase 4 (show_completion update)
    ↓
Phase 5 (testing)
```

## Commit Strategy

| Phase | Commit Message |
|-------|----------------|
| 1.1 | `feat(setup): add GitHub CLI authentication check` |
| 1.2 | `feat(setup): add develop branch setup functionality` |
| 1.3 | `feat(setup): add default branch configuration` |
| 1.4 | `feat(setup): add auto commit functionality` |
| 2.1-2.3 | `feat(setup): integrate GitHub operations into setup flow` |
| 3 | `feat(setup): enhance error handling for GitHub operations` |
| 4 | `feat(setup): update completion message with branch info` |

## Rollback Considerations

If issues are found:
1. GitHub operations are isolated functions - can be disabled by commenting out `setup_github_repository()` call
2. Auto commits can be disabled individually
3. Each function has independent error handling

## Critical Path

1. **check_gh_auth** - Must work correctly to proceed
2. **setup_develop_branch** - Core functionality
3. **main integration** - Ties everything together

## Dependencies Between Tasks

```
check_gh_auth ─────────────────────────────┐
                                           │
setup_develop_branch ──────────────────────┼──► setup_github_repository
                                           │
set_default_branch ────────────────────────┘

auto_commit (independent, used by main)

main integration (depends on all above)
```

## Success Criteria

- [ ] `gh auth` check works correctly
- [ ] develop branch is created/checked out
- [ ] default branch change is attempted (with graceful fallback)
- [ ] Auto commits are created at appropriate points
- [ ] Existing functionality is not broken
- [ ] Dry-run mode works correctly
- [ ] Error messages are clear and helpful
