# Workflow Document: Issue #5 - Improve post.sh Interactive Setup

## Implementation Phases

### Phase 1: Implement .gitconfig.local Interactive Setup

**Estimated Tasks**: 3

#### Task 1.1: Create setup_gitconfig_local function

- Add function skeleton to post.sh
- Implement file existence check
- Add early return for idempotency

#### Task 1.2: Implement git config detection

- Check existing `user.name` with `git config --global`
- Check existing `user.email` with `git config --global`
- Store results in variables

#### Task 1.3: Implement interactive prompts

- Add `read -p` for user.name (if not set)
- Add `read -p` for user.email (if not set)
- Write .gitconfig.local with provided values
- Handle empty input as skip

---

### Phase 2: Implement host_config Conditional Setup

**Estimated Tasks**: 3

#### Task 2.1: Create setup_ssh_host_config function

- Add function skeleton to post.sh
- Implement file existence check
- Add early return for idempotency

#### Task 2.2: Implement SSH connectivity check

- Run `ssh -T -o ConnectTimeout=10 git@github.com`
- Capture exit code and output
- Classify result (success/auth_fail/network_error)

#### Task 2.3: Implement conditional creation

- If success (exit 1): no action needed
- If auth fail: prompt user for creation
- If network error: warning message only
- Create minimal host_config template if confirmed

---

### Phase 3: Update Template and Cleanup

**Estimated Tasks**: 2

#### Task 3.1: Apply changes to template

- Copy updated logic to `templates/core/.devcontainer/scripts/post.sh`
- Ensure consistency between files

#### Task 3.2: Remove old implementation

- Remove old .gitconfig.local creation code
- Remove old host_config creation code
- Clean up any obsolete comments

---

## Task Dependencies

```
Phase 1 ─────────────────────────────────────────────┐
  Task 1.1 ──► Task 1.2 ──► Task 1.3                 │
                                                     │
Phase 2 ─────────────────────────────────────────────┤
  Task 2.1 ──► Task 2.2 ──► Task 2.3                 │
                                                     │
Phase 3 ◄────────────────────────────────────────────┘
  (depends on Phase 1 & 2 completion)
  Task 3.1 ──► Task 3.2
```

## Critical Path

1. Phase 1 and Phase 2 can be implemented in parallel
2. Phase 3 must wait for both Phase 1 and Phase 2
3. Testing should occur after each phase

## Testing Strategy Per Phase

### Phase 1 Tests
- Verify function exists and is callable
- Test with existing .gitconfig.local (should skip)
- Test with existing git config (should skip prompts)
- Test fresh setup (should prompt)

### Phase 2 Tests
- Verify function exists and is callable
- Test with existing host_config (should skip)
- Test with working ssh-agent (should not prompt)
- Test without ssh-agent (should prompt)

### Phase 3 Tests
- Verify template matches main script
- Run shellcheck on both files
- Full integration test in container

## Commit Strategy

| Phase | Commit Message |
|-------|----------------|
| Phase 1 | `✨ feat: add interactive .gitconfig.local setup` |
| Phase 2 | `✨ feat: add conditional host_config creation` |
| Phase 3 | `♻️ refactor: apply changes to template, cleanup old code` |

## Rollback Considerations

- Keep backup of original post.sh before modifications
- Each phase is independently functional
- Can revert individual commits if issues found
