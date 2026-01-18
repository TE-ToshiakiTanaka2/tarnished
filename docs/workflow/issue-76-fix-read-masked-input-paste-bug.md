# Workflow: Fix read_masked_input Paste Handling Bug

Issue: #76

## Implementation Phases

### Phase 1: Fix read_masked_input Function

1. Add bracket paste mode disable at function start
2. Add escape sequence detection and skip logic
3. Add bracket paste mode re-enable at function end
4. Add input sanitization before return

### Phase 2: Update Unit Tests

1. Update test for escape sequence handling
2. Add test for sanitization

### Phase 3: Verification

1. Run shellcheck
2. Run existing unit tests
3. Manual verification (if possible)

## Task Breakdown

- [x] Read current implementation
- [ ] Modify `read_masked_input` function
- [ ] Update unit tests
- [ ] Run shellcheck
- [ ] Run bats tests
- [ ] Commit changes

## Files to Modify

1. `templates/github-actions/plugin.sh` - Main fix
2. `tests/unit/test_read_masked_input.bats` - Test updates
