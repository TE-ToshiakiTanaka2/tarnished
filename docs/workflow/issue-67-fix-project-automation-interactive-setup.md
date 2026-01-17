# Workflow Document: Fix project-automation Interactive Setup Bugs

**Issue**: #67
**Type**: Bugfix
**Milestone**: github-actions

## Implementation Phases

### Phase 1: Fix Hook Carryover Issue

**Priority**: High (blocks other fixes from being testable)
**Estimated Complexity**: Low

#### Tasks

- [ ] **1.1** Modify `execute_plugins_hook` function in `setup.sh`
  - Location: `setup.sh:803`
  - Add `plugin_interactive_setup` to unset list
  - Add `plugin_minimal_setup` to unset list

#### Verification
- Run setup.sh with multiple plugins selected
- Confirm `plugin_interactive_setup` is called only once

---

### Phase 2: Add /dev/tty to All Read Commands

**Priority**: High (core fix for pipe execution)
**Estimated Complexity**: Low

#### Tasks

- [ ] **2.1** Update overwrite confirmation read
  - Location: `templates/github-actions/plugin.sh:186`
  - Add `< /dev/tty`

- [ ] **2.2** Update PAT token read
  - Location: `templates/github-actions/plugin.sh:196`
  - Add `< /dev/tty`

- [ ] **2.3** Update project type choice read
  - Location: `templates/github-actions/plugin.sh:207`
  - Add `< /dev/tty`

- [ ] **2.4** Update owner name read
  - Location: `templates/github-actions/plugin.sh:220`
  - Add `< /dev/tty`

- [ ] **2.5** Update project number read
  - Location: `templates/github-actions/plugin.sh:226`
  - Add `< /dev/tty`

- [ ] **2.6** Update status default read
  - Location: `templates/github-actions/plugin.sh:261`
  - Add `< /dev/tty`

- [ ] **2.7** Update priority default read
  - Location: `templates/github-actions/plugin.sh:270`
  - Add `< /dev/tty`

#### Verification
- Test each read command individually
- Confirm all prompts wait for user input during pipe execution

---

### Phase 3: Add Skip Confirmation Logic

**Priority**: Medium (UX improvement)
**Estimated Complexity**: Medium

#### Tasks

- [ ] **3.1** Replace simple empty token check with retry loop
  - Location: `templates/github-actions/plugin.sh:198-202`
  - Implement while loop for token input
  - Add skip confirmation prompt
  - Allow retry on "don't skip" choice

#### Verification
- Test empty token input → skip confirmation appears
- Test "Y" response → setup is skipped
- Test "n" response → re-prompt for token
- Test valid token input → proceeds normally

---

### Phase 4: Testing

**Priority**: High
**Estimated Complexity**: Medium

#### Tasks

- [ ] **4.1** Run shellcheck on modified files
  ```bash
  shellcheck setup.sh templates/github-actions/plugin.sh
  ```

- [ ] **4.2** Run setup.sh help test
  ```bash
  bash setup.sh --help
  ```

- [ ] **4.3** Run actionlint on workflows
  ```bash
  actionlint .github/workflows/*.yml
  ```

- [ ] **4.4** Manual integration test (if possible)
  - Test with pipe execution
  - Test with direct execution

---

### Phase 5: Commit and Documentation

**Priority**: Medium
**Estimated Complexity**: Low

#### Tasks

- [ ] **5.1** Commit Phase 1 changes
  - Message: `🐛 fix(setup): add plugin_interactive_setup to hook unset list`

- [ ] **5.2** Commit Phase 2 & 3 changes
  - Message: `🐛 fix(github-actions): add /dev/tty support for pipe execution`

- [ ] **5.3** Commit documentation
  - Message: `📝 docs: add design and workflow for issue #67`

---

## Dependency Graph

```
Phase 1 (Hook Fix)
    │
    ▼
Phase 2 (/dev/tty) ──► Phase 3 (Skip Confirm)
    │                      │
    └──────────┬───────────┘
               ▼
          Phase 4 (Testing)
               │
               ▼
          Phase 5 (Commit)
```

## Critical Path

1. **Phase 1** must be completed first to prevent multiple hook calls
2. **Phase 2** is the core fix for pipe execution
3. **Phase 3** depends on Phase 2 (uses the same `/dev/tty` pattern)
4. **Phase 4** validates all changes
5. **Phase 5** commits and documents

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `/dev/tty` not available in some environments | Medium | Add fallback to stdin if tty unavailable |
| Loop logic causes infinite loop | Low | Add maximum retry count |
| Unset breaks other plugins | Low | Test with all plugin combinations |

## Rollback Considerations

Each phase can be rolled back independently:
- Phase 1: Remove hooks from unset list
- Phase 2: Remove `< /dev/tty` from read commands
- Phase 3: Revert to simple empty check

## Success Criteria

- [ ] `plugin_interactive_setup` called exactly once regardless of plugin count
- [ ] All `read` commands work correctly in pipe execution
- [ ] Skip confirmation appears on empty token
- [ ] All shellcheck warnings resolved
- [ ] No regressions in normal (non-pipe) execution
