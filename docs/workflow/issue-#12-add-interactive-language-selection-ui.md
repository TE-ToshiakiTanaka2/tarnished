# Workflow Document: Interactive Language Selection UI

## Issue Reference
- **Issue**: #12 - Add interactive language selection UI to setup.sh
- **Milestone**: core
- **Label**: feature

## Implementation Phases

### Phase 1: Argument Parsing Enhancement
**Files**: `setup.sh`

1. Add new global variables for language selection and Playwright
2. Extend argument parsing in `main()` to handle:
   - `--lang <languages>` option
   - `--playwright` flag
3. Implement `parse_language_list()` function

**Commit**: `feat: add --lang and --playwright argument parsing`

### Phase 2: Language Discovery
**Files**: `setup.sh`

1. Implement `discover_available_languages()` function
   - Scan templates/ for valid language plugins
   - Build available languages list
2. Implement `validate_languages()` function
   - Validate user-provided languages against available list

**Commit**: `feat: add language discovery and validation`

### Phase 3: Interactive UI Implementation
**Files**: `setup.sh`, `scripts/lib/common.sh`

1. Implement `prompt_language_selection()` in setup.sh
   - Display available languages with toggle selection
   - Support space to toggle, enter to confirm
   - Default to Node.js if nothing selected
2. Implement `prompt_playwright()` in setup.sh
   - Simple y/N prompt
   - Skip if `--playwright` flag or `-y` flag provided

**Commit**: `feat: add interactive language and Playwright selection UI`

### Phase 4: Plugin Filtering
**Files**: `setup.sh`

1. Modify `load_all_plugins()` to filter by selection
2. Ensure load order: core -> selected languages -> claude -> playwright
3. Handle empty selection (default to node)

**Commit**: `feat: filter plugins based on language selection`

### Phase 5: Playwright Plugin Creation
**Files**: `templates/playwright/plugin.sh`, `templates/playwright/.devcontainer/devcontainer.json`

1. Create Playwright plugin directory structure
2. Implement plugin.sh with required functions
3. Create devcontainer.json with Playwright features
4. Add Playwright VS Code extension

**Commit**: `feat: add Playwright plugin template`

### Phase 6: Help and Preview Update
**Files**: `setup.sh`

1. Update `show_help()` with new options
2. Update `show_preview()` to show selected languages and options

**Commit**: `feat: update help message and preview with new options`

### Phase 7: Testing and Refinement
1. Run shellcheck on all modified files
2. Test all argument combinations
3. Test interactive mode
4. Fix any issues found

**Commit**: `fix: address issues found during testing` (if needed)

## Task Breakdown

### Task 1: Argument Parsing (Phase 1)
- [ ] Add `SELECTED_LANGUAGES` and `PLAYWRIGHT_ENABLED` variables
- [ ] Add `--lang` case in argument parsing
- [ ] Add `--playwright` case in argument parsing
- [ ] Implement `parse_language_list()` helper function

### Task 2: Language Discovery (Phase 2)
- [ ] Implement `discover_available_languages()`
- [ ] Implement `validate_languages()`
- [ ] Map plugin names to display names

### Task 3: Interactive Language Selection (Phase 3a)
- [ ] Implement cursor-based selection UI
- [ ] Handle keyboard input (arrows, space, enter)
- [ ] Apply default selection (Node.js)
- [ ] Return selected languages

### Task 4: Interactive Playwright Selection (Phase 3b)
- [ ] Implement simple y/N prompt
- [ ] Honor `-y` flag for auto-skip
- [ ] Set `PLAYWRIGHT_ENABLED` variable

### Task 5: Plugin Filtering (Phase 4)
- [ ] Modify `load_all_plugins()` with filtering logic
- [ ] Maintain correct load order
- [ ] Handle Playwright plugin conditional loading

### Task 6: Playwright Plugin (Phase 5)
- [ ] Create `templates/playwright/` directory
- [ ] Implement `plugin.sh` with required functions
- [ ] Create devcontainer.json with Playwright features
- [ ] Add merge logic in plugin_post_copy

### Task 7: Help Update (Phase 6)
- [ ] Add `--lang` description and examples
- [ ] Add `--playwright` description
- [ ] Update preview output

## Critical Path

```
Phase 1 (Parsing) → Phase 2 (Discovery) → Phase 3 (UI) → Phase 4 (Filtering)
                                                              ↓
                                          Phase 5 (Playwright) →  Phase 6 (Help)
```

Phases 1-4 are sequential dependencies. Phase 5 can be done in parallel with Phase 4.

## Rollback Considerations

If issues arise:
1. Language selection can default to loading all plugins (current behavior)
2. Playwright option can be disabled without affecting core functionality
3. Interactive prompts can be bypassed with existing `-y` flag

## Test Cases

| Test | Command | Expected Behavior |
|------|---------|-------------------|
| Default | `./setup.sh -y my-app` | Node.js selected, no Playwright |
| Node only | `./setup.sh --lang node -y my-app` | Node.js only |
| Multiple | `./setup.sh --lang node,python -y my-app` | Both loaded |
| Playwright | `./setup.sh --lang node --playwright -y my-app` | Node + Playwright |
| Invalid | `./setup.sh --lang invalid -y my-app` | Error with valid options list |
| Dry run | `./setup.sh --lang node --playwright --dry-run` | Preview shows selections |
| Help | `./setup.sh --help` | Shows new options |

## Estimated Complexity

| Phase | Complexity | Files Changed |
|-------|------------|---------------|
| 1 | Low | 1 |
| 2 | Low | 1 |
| 3 | Medium | 2 |
| 4 | Medium | 1 |
| 5 | Low | 3 (new) |
| 6 | Low | 1 |
