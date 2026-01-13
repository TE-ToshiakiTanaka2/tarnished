# Implementation Workflow: MVP setup.sh Script

**Issue**: #3 - Add MVP setup.sh script for Devcontainer environment creation
**Milestone**: core
**Date**: 2026-01-13

## Phase 1: Core Template Creation

### Task 1.1: Create Directory Structure
- [ ] Create `templates/core/.devcontainer/scripts/`
- [ ] Create `templates/core/docker/`
- [ ] Create `templates/core/.claude/`

### Task 1.2: Create Core devcontainer.json
- [ ] Create `templates/core/.devcontainer/devcontainer.json`
- [ ] Include common features (git, github-cli, claude-code)
- [ ] Use `{{PROJECT_NAME}}` placeholder

### Task 1.3: Create post.sh
- [ ] Create `templates/core/.devcontainer/scripts/post.sh`
- [ ] Include basic setup (git config, Claude Code setup)

### Task 1.4: Create Dockerfile.dev
- [ ] Create `templates/core/docker/Dockerfile.dev`
- [ ] Use mcr.microsoft.com/vscode/devcontainers/base:bookworm
- [ ] Install basic packages

### Task 1.5: Create docker-compose.yml
- [ ] Create `templates/core/docker-compose.yml`
- [ ] Configure volume mounts
- [ ] Use `{{PROJECT_NAME}}` placeholder

### Task 1.6: Create Claude Code settings
- [ ] Create `templates/core/.claude/settings.json`
- [ ] Include basic settings

**Checkpoint**: Core template files complete

---

## Phase 2: Node.js Template Creation

### Task 2.1: Create Directory Structure
- [ ] Create `templates/node/.devcontainer/`

### Task 2.2: Create Node.js devcontainer.json
- [ ] Create `templates/node/.devcontainer/devcontainer.json`
- [ ] Include only Node.js feature (node:22)

**Checkpoint**: Node.js template complete

---

## Phase 3: Setup Script Creation

### Task 3.1: Create setup.sh Base
- [ ] Create `setup.sh` at repository root
- [ ] Add shebang and error handling (`set -e`)
- [ ] Add script header/description

### Task 3.2: Implement Interactive Prompt
- [ ] Add `prompt_project_name()` function
- [ ] Add `validate_project_name()` function
- [ ] Handle empty input and invalid characters

### Task 3.3: Implement Template Copy
- [ ] Add `copy_core_template()` function
- [ ] Copy all files from templates/core/

### Task 3.4: Implement JSON Merge
- [ ] Add `merge_language_features()` function
- [ ] Use jq to merge devcontainer.json files
- [ ] Combine features from core and node templates

### Task 3.5: Implement Placeholder Replacement
- [ ] Add `replace_placeholders()` function
- [ ] Replace `{{PROJECT_NAME}}` in all files
- [ ] Handle files: devcontainer.json, docker-compose.yml

### Task 3.6: Implement Completion Message
- [ ] Add `show_completion()` function
- [ ] Display created files
- [ ] Show next steps for user

### Task 3.7: Add Main Execution Flow
- [ ] Combine all functions in main()
- [ ] Add argument parsing (--help, --dry-run)
- [ ] Execute main function

**Checkpoint**: setup.sh complete and functional

---

## Phase 4: Testing

### Task 4.1: Shell Script Validation
- [ ] Run shellcheck on setup.sh
- [ ] Run shellcheck on post.sh
- [ ] Fix any issues

### Task 4.2: Functional Testing
- [ ] Test setup.sh with sample project name
- [ ] Verify all files are generated correctly
- [ ] Verify placeholder replacement works
- [ ] Verify JSON merge is correct

### Task 4.3: Edge Case Testing
- [ ] Test with special characters in project name
- [ ] Test with empty input
- [ ] Test in existing directory

**Checkpoint**: All tests passing

---

## Phase 5: Documentation

### Task 5.1: Update README
- [ ] Add usage section for setup.sh
- [ ] Include curl/wget example command
- [ ] Document generated file structure

**Checkpoint**: Documentation complete

---

## Commit Strategy

| Phase | Commit Message |
|-------|----------------|
| 1 | `feat: add core template files for Devcontainer setup` |
| 2 | `feat: add Node.js template for Devcontainer features` |
| 3 | `feat: add setup.sh script for Devcontainer environment creation` |
| 4 | `fix: address shellcheck warnings and test issues` |
| 5 | `docs: update README with setup.sh usage instructions` |

---

## Dependencies

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4 ──► Phase 5
```

All phases are sequential - each depends on the previous phase being complete.

---

## Rollback Considerations

If issues are found:
1. Revert to previous commit
2. Fix issues in isolation
3. Re-test before proceeding

All changes are in new files, so rollback is straightforward (delete new files).
