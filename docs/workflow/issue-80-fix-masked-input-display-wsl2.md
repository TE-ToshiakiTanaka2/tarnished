# Workflow: Fix Masked Input Display on WSL2 + Windows Terminal

**Issue**: #80
**Branch**: `bugfix/TE-ToshiakiTanaka2/#80/fix-masked-input-display`
**Status**: In Progress

## Phase 1: Implementation

### Task 1.1: Update read_masked_input Function

**File**: `templates/github-actions/plugin.sh`

**Changes**:
1. Add small delay after bracket paste mode disable
2. Increase escape sequence timeout from 0.01s to 0.1s
3. Add break on letter terminators for escape sequences
4. Add safety limit for escape buffer
5. Add explicit printable character check

**Verification**:
- [ ] Function compiles without syntax errors
- [ ] shellcheck passes

### Task 1.2: Update Unit Tests

**File**: `tests/unit/test_read_masked_input.bats`

**Changes**:
1. Add test for printable character filtering
2. Add test for increased escape sequence timeout
3. Verify existing tests still pass

**Verification**:
- [ ] All unit tests pass

## Phase 2: Testing

### Task 2.1: Run Automated Tests

```bash
# Shellcheck
shellcheck templates/github-actions/plugin.sh

# Unit tests
bats tests/unit/test_read_masked_input.bats
```

### Task 2.2: Manual Verification (User Required)

| Test | Environment | Expected |
|------|-------------|----------|
| Ctrl+V paste | WSL2 + Windows Terminal | 40 asterisks, no token leak |
| Ctrl+V paste | VS Code Terminal | 40 asterisks |
| Type manually | Any terminal | Asterisks per character |
| Backspace | Any terminal | Asterisks removed |

## Phase 3: Commit and Finalize

### Task 3.1: Final Commits

1. Commit implementation changes
2. Commit test updates
3. Verify all commits are atomic and well-documented

### Task 3.2: Summary

- Branch ready for PR
- All automated tests passing
- Manual testing guidance provided

## Dependencies

```
Phase 1 ─┬─► Task 1.1 (Implementation)
         │
         └─► Task 1.2 (Tests)
              │
              ▼
Phase 2 ────► Task 2.1 (Automated Tests)
              │
              ▼
Phase 3 ────► Task 3.1 (Commits)
```

## Checklist

- [ ] Design document created and committed
- [ ] Workflow document created and committed
- [ ] read_masked_input function updated
- [ ] Unit tests updated
- [ ] shellcheck passes
- [ ] bats tests pass
- [ ] Final commit created
