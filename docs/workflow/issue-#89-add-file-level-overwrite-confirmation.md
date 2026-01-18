# Implementation Workflow: File-level Overwrite Confirmation

**Issue**: #89 - Add file-level overwrite confirmation to setup.sh
**Date**: 2026-01-18

## Phase 1: Core Infrastructure

### Step 1.1: Add Global Variable
- File: `setup.sh`
- Add `OVERWRITE_ALL=false` after other global flags (line ~103)

### Step 1.2: Add Argument Parsing
- File: `setup.sh`
- Add `--overwrite)` case in main() argument parsing

### Step 1.3: Implement Utility Functions
- File: `setup.sh`
- Add `copy_with_confirm()` function
- Add `copy_dir_with_confirm()` function
- Place after other utility functions, before plugin loading

### Step 1.4: Update Help Message
- File: `setup.sh`
- Add `--overwrite` option to `show_help()`

### Step 1.5: Remove Bulk Overwrite Logic
- File: `setup.sh`
- Remove or comment out the existing bulk overwrite confirmation in `main()`

**Commit**: `feat(setup): add file-level overwrite confirmation infrastructure`

## Phase 2: Core Plugin Updates

### Step 2.1: Update core/plugin.sh
- Replace `cp -r "${PLUGIN_DIR}/.devcontainer"` with `copy_dir_with_confirm`
- Replace `cp -r "${PLUGIN_DIR}/docker"` with `copy_dir_with_confirm`
- Replace `cp -r "${PLUGIN_DIR}/.claude"` with `copy_dir_with_confirm`
- Replace `cp "${PLUGIN_DIR}/docker-compose.yml"` with `copy_with_confirm`

### Step 2.2: Update claude/plugin.sh
- Replace `cp -r "${PLUGIN_DIR}/.claude/commands"` with `copy_dir_with_confirm`
- Replace `cp -r "${PLUGIN_DIR}/.claude/scripts"` with `copy_dir_with_confirm`
- Replace `cp "${PLUGIN_DIR}/CLAUDE.md"` with `copy_with_confirm`
- Replace `cp "$plugin_settings"` with `copy_with_confirm`

**Commit**: `feat(plugin): update core and claude plugins to use copy_with_confirm`

## Phase 3: Language Plugin Updates

### Step 3.1: Update node/plugin.sh
- Replace config file copy with `copy_with_confirm`
- Replace workflow file copy with `copy_with_confirm`
- Replace tests directory copy with `copy_dir_with_confirm`

### Step 3.2: Update python/plugin.sh
- Replace config file copy with `copy_with_confirm`
- Replace workflow file copy with `copy_with_confirm`
- Replace tests directory copy with `copy_dir_with_confirm`

### Step 3.3: Update rust/plugin.sh
- Replace config file copy with `copy_with_confirm`

**Commit**: `feat(plugin): update language plugins to use copy_with_confirm`

## Phase 4: Service Plugin Updates

### Step 4.1: Update playwright/plugin.sh
- Replace config file copy with `copy_with_confirm`

### Step 4.2: Update github-actions/plugin.sh
- Replace action.yml copy with `copy_with_confirm`
- Replace dist directory copy with `copy_dir_with_confirm`
- Replace workflow file copy with `copy_with_confirm`
- Replace version.yml copy with `copy_with_confirm`

### Step 4.3: Update database plugins
- postgresql/plugin.sh: Update env and init copies
- neo4j/plugin.sh: Update env and init copies
- redis/plugin.sh: Update env and init copies

**Commit**: `feat(plugin): update service plugins to use copy_with_confirm`

## Phase 5: Testing & Quality

### Step 5.1: Run shellcheck
```bash
shellcheck setup.sh templates/*/plugin.sh
```

### Step 5.2: Test dry-run mode
```bash
./setup.sh --dry-run --lang node
```

### Step 5.3: Test help message
```bash
./setup.sh --help | grep -A1 overwrite
```

### Step 5.4: Test overwrite scenarios
```bash
# Create test environment
mkdir -p /tmp/test-overwrite && cd /tmp/test-overwrite
git init && git remote add origin https://github.com/test/test.git

# Test 1: Interactive mode (manual)
# Test 2: -y mode (should skip)
# Test 3: --overwrite mode (should overwrite)
```

**Commit**: `test: verify file-level overwrite confirmation`

## Phase 6: Final Review

### Step 6.1: Code Review
- Ensure all `cp` and `cp -r` commands are replaced
- Verify error handling
- Check log messages consistency

### Step 6.2: Documentation
- Design doc committed
- Workflow doc committed

**Final Commit**: `docs: add design and workflow documents for #89`

## Dependencies

```
Phase 1 (Core) ──► Phase 2 (Core Plugins) ──► Phase 3 (Language Plugins)
                                          └──► Phase 4 (Service Plugins)
                                                         │
                                                         ▼
                                               Phase 5 (Testing)
                                                         │
                                                         ▼
                                               Phase 6 (Final)
```

## Rollback Plan

If issues arise:
1. Revert to bulk overwrite behavior by restoring original `cp -r` calls
2. Remove `copy_with_confirm()` and `copy_dir_with_confirm()` functions
3. Remove `--overwrite` argument parsing
4. Restore bulk overwrite confirmation in `main()`

## Estimated Changes

| File | Lines Added | Lines Modified | Lines Removed |
|------|-------------|----------------|---------------|
| setup.sh | ~60 | ~5 | ~15 |
| templates/core/plugin.sh | 0 | ~4 | 0 |
| templates/claude/plugin.sh | 0 | ~4 | 0 |
| templates/node/plugin.sh | 0 | ~3 | 0 |
| templates/python/plugin.sh | 0 | ~3 | 0 |
| templates/rust/plugin.sh | 0 | ~1 | 0 |
| templates/playwright/plugin.sh | 0 | ~1 | 0 |
| templates/github-actions/plugin.sh | 0 | ~4 | 0 |
| templates/postgresql/plugin.sh | 0 | ~3 | 0 |
| templates/neo4j/plugin.sh | 0 | ~3 | 0 |
| templates/redis/plugin.sh | 0 | ~3 | 0 |
