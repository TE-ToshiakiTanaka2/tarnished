# Workflow Document: Fix sudo npm/node command not found

**Issue**: #91
**Type**: bugfix
**Milestone**: core

## Implementation Phases

### Phase 1: Add sudoers configuration function to post.sh

**Objective**: Add a function to configure sudoers secure_path with nvm bin path

**Tasks**:
1. Add `setup_sudo_path()` function to post.sh
2. Place it early in the script (before any `sudo npm` commands)
3. Make the function idempotent (check if already configured)

**Dependencies**: None

**Verification**:
- Function creates `/etc/sudoers.d/nvm-path` correctly
- File has proper permissions (0440)
- `sudo visudo -c` passes validation

### Phase 2: Update design document (if needed)

**Objective**: Align design document with actual implementation

**Tasks**:
1. Update design document to reflect post.sh modification approach
2. Remove reference to separate script file

### Phase 3: Testing

**Objective**: Verify the fix works correctly

**Tasks**:
1. Run shellcheck on post.sh
2. Test script logic manually
3. Verify `sudo npm -v` works after running the function

**Verification**:
- shellcheck passes without errors
- `sudo npm -v` returns version
- `sudo node -v` returns version
- Existing `setup_devcontainer_cli` function works

### Phase 4: Commit and Finalize

**Objective**: Create atomic commits and finalize

**Tasks**:
1. Commit design document
2. Commit workflow document
3. Commit implementation changes

## Critical Path

```
Phase 1 (Implementation) → Phase 2 (Docs) → Phase 3 (Testing) → Phase 4 (Commit)
```

## Rollback Plan

If issues occur:
1. Remove the sudoers.d file: `sudo rm /etc/sudoers.d/nvm-path`
2. Revert post.sh changes

## Task Breakdown

| Task | File | Priority | Status |
|------|------|----------|--------|
| Add setup_sudo_path function | post.sh | High | Pending |
| Update design doc | design/issue-91-*.md | Medium | Pending |
| Run shellcheck | - | High | Pending |
| Test sudo npm/node | - | High | Pending |
| Commit changes | - | High | Pending |
