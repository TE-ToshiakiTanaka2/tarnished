# Workflow: #228 versioning.yml template schema does not match erd's expected format

## Implementation Steps

### Step 1: Add legacy format types to `tag_config.rs`

Add `LegacyBranchRule` struct with serde `Deserialize` and the optional legacy fields to `Config`.

**Files**: `src/tag_config.rs`

### Step 2: Implement `BranchPrefixes::is_empty()` and `BranchPrefixes::from_legacy()`

- `is_empty()`: Returns `true` when all four prefix vectors are empty
- `from_legacy()`: Iterates `Vec<LegacyBranchRule>` and populates the appropriate vector based on the `bump` field value (`"major"`, `"minor"`, `"patch"`, `"release"`)

**Files**: `src/tag_config.rs`

### Step 3: Implement `Config::normalize()`

Post-deserialization method that converts legacy format to canonical when needed. Update `load_from_file` and `load_from_default` to call `normalize()`.

**Files**: `src/tag_config.rs`

### Step 4: Add unit tests for legacy format support

- Test parsing legacy format YAML → correct `BranchPrefixes`
- Test that canonical format still works (regression)
- Test that canonical takes precedence when both are present
- Test legacy format with unknown bump types (ignored gracefully)
- Test `BranchPrefixes::is_empty()`
- Test end-to-end: legacy config → `match_branch()` returns correct bump types

**Files**: `src/tag_config.rs`

### Step 5: Fix the template in `plugin.sh`

Replace the heredoc in `plugin_post_copy()` with the correct `versioning.branch_prefixes` format.

**Files**: `templates/github-actions/auto-tag/plugin.sh`

### Step 6: Fix the workflow comment in `auto-tag.yml`

Update the example YAML in the comment header to show the correct format.

**Files**: `templates/github-actions/auto-tag/.github/workflows/auto-tag.yml`

### Step 7: Run full test suite

Run `cargo test` to verify all existing and new tests pass. Run `cargo clippy` for lint checks.

## Task Dependencies

```
Step 1 (types) ← Step 2 (helpers) ← Step 3 (normalize) ← Step 4 (tests)
Step 5 (template fix) — independent
Step 6 (comment fix) — independent
Step 7 (full test suite) ← depends on all above
```

- Steps 1 → 2 → 3 → 4 are sequential (each builds on the prior)
- Steps 5 and 6 are independent of Steps 1-4 and can be done in parallel
- Step 7 depends on all prior steps

## Test Strategy

### Unit Tests

- **`test_parse_legacy_config`**: Parse template-format YAML, verify `BranchPrefixes` is populated correctly
- **`test_legacy_match_branch`**: End-to-end legacy config → `match_branch()` returns expected bump types
- **`test_canonical_takes_precedence`**: When both formats are present, canonical wins
- **`test_legacy_unknown_bump_ignored`**: Unknown `bump` values in legacy format are skipped
- **`test_branch_prefixes_is_empty`**: Verify `is_empty()` on default vs populated prefixes
- **`test_existing_tests_still_pass`**: All existing tests remain green (regression)

### Integration Tests

- Verify `Config::load_from_file` works with a legacy-format file on disk
- Verify `Config::load_from_file` works with canonical-format file on disk

### Edge Cases

- Empty `branches` array in legacy format → defaults to RC (same as empty config)
- Mixed case in bump field (e.g., `"Major"` vs `"major"`) — decide: case-insensitive or strict
- Legacy format with `release` bump type
- Legacy format with `default_bump` set to something other than `rc`
