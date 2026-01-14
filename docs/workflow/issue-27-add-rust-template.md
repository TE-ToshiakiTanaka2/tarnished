# Workflow Document: Add Rust Language Template

**Issue**: #27 - Add Rust language template with Cargo, rustfmt, and clippy
**Date**: 2025-01-14

## Implementation Phases

### Phase 1: Directory Structure (5 min)

**Tasks**:
1. Create `templates/rust/` directory
2. Create `templates/rust/.devcontainer/` directory
3. Create `templates/rust/.claude/` directory

**Verification**:
```bash
ls -la templates/rust/
ls -la templates/rust/.devcontainer/
ls -la templates/rust/.claude/
```

**Commit**: None (directories only)

---

### Phase 2: Plugin Entry Point (10 min)

**Tasks**:
1. Create `templates/rust/plugin.sh`
   - Implement `plugin_name()`
   - Implement `plugin_description()`
   - Implement `plugin_post_copy()`

**Dependencies**:
- Reference: `templates/python/plugin.sh`
- Reference: `templates/node/plugin.sh`

**Verification**:
```bash
# Syntax check
bash -n templates/rust/plugin.sh

# Shellcheck
shellcheck templates/rust/plugin.sh
```

**Commit**: `✨ feat(rust): add plugin.sh entry point`

---

### Phase 3: Devcontainer Configuration (10 min)

**Tasks**:
1. Create `templates/rust/.devcontainer/devcontainer.json`
   - Add Rust feature
   - Add VS Code extensions
   - Add postCreateCommand

**Verification**:
```bash
# JSON syntax check
python3 -m json.tool templates/rust/.devcontainer/devcontainer.json > /dev/null
```

**Commit**: `✨ feat(rust): add devcontainer configuration`

---

### Phase 4: Claude Code Integration (10 min)

**Tasks**:
1. Create `templates/rust/.claude/settings.json`
   - Add PostToolUse hooks for `.rs` files
   - Configure cargo fmt and clippy commands

**Verification**:
```bash
# JSON syntax check
python3 -m json.tool templates/rust/.claude/settings.json > /dev/null
```

**Commit**: `✨ feat(rust): add Claude Code hooks`

---

### Phase 5: Configuration Files (10 min)

**Tasks**:
1. Create `templates/rust/rustfmt.toml`
   - Edition 2021
   - Max width 100
   - Tab spaces 4

2. Create `templates/rust/clippy.toml`
   - Cognitive complexity threshold
   - Too many arguments threshold

**Verification**:
```bash
# TOML syntax check (if tomlq available)
cat templates/rust/rustfmt.toml
cat templates/rust/clippy.toml
```

**Commit**: `✨ feat(rust): add rustfmt and clippy configuration`

---

### Phase 6: E2E Tests (15 min)

**Tasks**:
1. Create `tests/e2e/rust-template.bats`
   - Test plugin discovery
   - Test file copy/merge operations
   - Test configuration syntax

**Dependencies**:
- Reference: `tests/e2e/python-template.bats` (if exists)
- BATS testing framework

**Verification**:
```bash
bats tests/e2e/rust-template.bats
```

**Commit**: `✅ test(rust): add E2E tests for Rust template`

---

### Phase 7: Final Verification (10 min)

**Tasks**:
1. Run all shellcheck validations
2. Run setup.sh dry-run with rust template
3. Verify all JSON/TOML files are valid
4. Run E2E tests

**Commands**:
```bash
# Shellcheck all shell scripts
shellcheck templates/rust/plugin.sh

# JSON validation
python3 -m json.tool templates/rust/.devcontainer/devcontainer.json > /dev/null
python3 -m json.tool templates/rust/.claude/settings.json > /dev/null

# Dry run (if supported)
./setup.sh --dry-run --lang rust
```

---

## Task Checklist

| # | Task | Phase | Status |
|---|------|-------|--------|
| 1 | Create directory structure | 1 | [ ] |
| 2 | Create plugin.sh | 2 | [ ] |
| 3 | Create devcontainer.json | 3 | [ ] |
| 4 | Create settings.json | 4 | [ ] |
| 5 | Create rustfmt.toml | 5 | [ ] |
| 6 | Create clippy.toml | 5 | [ ] |
| 7 | Create E2E tests | 6 | [ ] |
| 8 | Run final verification | 7 | [ ] |

## Critical Path

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7
   │         │         │         │         │         │         │
   │         │         │         │         │         │         └─ Final verification
   │         │         │         │         │         └─ E2E tests
   │         │         │         │         └─ Config files (rustfmt, clippy)
   │         │         │         └─ Claude hooks
   │         │         └─ Devcontainer features
   │         └─ Plugin entry point (depends on directories)
   └─ Directory structure (no dependencies)
```

All phases are sequential - each phase depends on the previous one being complete.

## Rollback Plan

If issues are discovered:

1. **Plugin issues**: Revert plugin.sh changes
2. **Devcontainer issues**: Revert devcontainer.json
3. **Hook issues**: Revert settings.json
4. **Config issues**: Revert TOML files

Individual file reverts are safe as they don't affect other templates.

## Testing Strategy Per Phase

| Phase | Test Type | Command |
|-------|-----------|---------|
| 2 | Syntax | `bash -n plugin.sh && shellcheck plugin.sh` |
| 3 | JSON | `python3 -m json.tool devcontainer.json` |
| 4 | JSON | `python3 -m json.tool settings.json` |
| 5 | TOML | Manual review or `tomlq` |
| 6 | E2E | `bats tests/e2e/rust-template.bats` |
| 7 | Full | All of the above |
