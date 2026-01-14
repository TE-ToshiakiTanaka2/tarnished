# Workflow Document: Python Language Template

**Issue**: #25 - Add Python language template with uv, Ruff, mypy, and pytest
**Milestone**: python
**Created**: 2026-01-14

## Implementation Phases

### Phase 1: Basic Structure
**Goal**: Create the plugin directory and entry point

**Tasks**:
1. Create `templates/python/` directory structure
2. Create `templates/python/plugin.sh` with required functions
3. Verify plugin is discoverable by setup.sh

**Dependencies**: None

**Verification**:
```bash
# Check plugin functions
source templates/python/plugin.sh
plugin_name  # Should return "python"
plugin_description  # Should return description
```

---

### Phase 2: Devcontainer Configuration
**Goal**: Configure Python development environment features

**Tasks**:
1. Create `templates/python/.devcontainer/devcontainer.json`
2. Add Python 3.12 feature
3. Add uv package manager feature
4. Add VS Code extensions

**Dependencies**: Phase 1

**Verification**:
```bash
# Validate JSON syntax
jq . templates/python/.devcontainer/devcontainer.json
```

---

### Phase 3: Tool Configuration Files
**Goal**: Create configuration files for Python development tools

**Tasks**:
1. Create `templates/python/ruff.toml`
2. Create `templates/python/mypy.ini`
3. Create `templates/python/pytest.ini`

**Dependencies**: None (can run parallel with Phase 2)

**Verification**:
```bash
# Check file existence and syntax
cat templates/python/ruff.toml
cat templates/python/mypy.ini
cat templates/python/pytest.ini
```

---

### Phase 4: Claude Code Hooks
**Goal**: Configure automatic code quality hooks

**Tasks**:
1. Create `templates/python/.claude/settings.json`
2. Configure PostToolUse hook for Ruff

**Dependencies**: Phase 1

**Verification**:
```bash
# Validate JSON syntax
jq . templates/python/.claude/settings.json
```

---

### Phase 5: Plugin Post-Copy Implementation
**Goal**: Implement file copy and merge logic

**Tasks**:
1. Update `plugin_post_copy()` in plugin.sh
2. Add devcontainer.json merge logic
3. Add Claude settings merge logic
4. Add tool config file copy logic

**Dependencies**: Phase 2, 3, 4

**Verification**:
```bash
# Run setup.sh with Python template and verify outputs
```

---

### Phase 6: E2E Tests
**Goal**: Add comprehensive tests for Python template

**Tasks**:
1. Create `tests/e2e/python_template.bats`
2. Test plugin discovery
3. Test file generation
4. Test JSON merge operations

**Dependencies**: Phase 5

**Verification**:
```bash
# Run E2E tests
bats tests/e2e/python_template.bats
```

---

### Phase 7: Quality Assurance
**Goal**: Ensure code quality and documentation

**Tasks**:
1. Run shellcheck on plugin.sh
2. Run actionlint on workflows
3. Verify all tests pass
4. Update README if needed

**Dependencies**: Phase 6

**Verification**:
```bash
shellcheck templates/python/plugin.sh
bats tests/
```

---

## Task Breakdown

### Detailed Task List

| # | Task | Phase | Priority | Estimate |
|---|------|-------|----------|----------|
| 1 | Create directory structure | 1 | High | - |
| 2 | Implement plugin.sh | 1 | High | - |
| 3 | Create devcontainer.json | 2 | High | - |
| 4 | Create ruff.toml | 3 | Medium | - |
| 5 | Create mypy.ini | 3 | Medium | - |
| 6 | Create pytest.ini | 3 | Medium | - |
| 7 | Create Claude settings.json | 4 | High | - |
| 8 | Implement plugin_post_copy() | 5 | High | - |
| 9 | Create E2E tests | 6 | High | - |
| 10 | Run quality checks | 7 | Medium | - |

### Critical Path

```
Phase 1 (plugin.sh)
    │
    ├──► Phase 2 (devcontainer.json)
    │         │
    ├──► Phase 3 (tool configs) ───┐
    │                              │
    └──► Phase 4 (Claude hooks)    │
              │                    │
              ▼                    ▼
         Phase 5 (post_copy implementation)
              │
              ▼
         Phase 6 (E2E tests)
              │
              ▼
         Phase 7 (QA)
```

---

## Rollback Considerations

### If Plugin Fails
- Remove `templates/python/` directory
- Revert any changes to setup.sh

### If Tests Fail
- Check JSON syntax in generated files
- Verify feature URLs are correct
- Check merge function behavior

---

## Commit Strategy

| Phase | Commit Message |
|-------|----------------|
| 1-2 | `feat(python): add basic plugin structure and devcontainer config` |
| 3 | `feat(python): add tool configuration files (ruff, mypy, pytest)` |
| 4-5 | `feat(python): add Claude Code hooks and post-copy implementation` |
| 6 | `test(python): add E2E tests for Python template` |
| 7 | `chore(python): fix linting issues and finalize` |

---

## Success Criteria

- [ ] `templates/python/plugin.sh` returns correct plugin metadata
- [ ] Devcontainer features include Python 3.12 and uv
- [ ] VS Code extensions are correctly configured
- [ ] Claude Code hooks trigger Ruff on .py file changes
- [ ] All tool configuration files are valid
- [ ] E2E tests pass
- [ ] shellcheck passes on plugin.sh
