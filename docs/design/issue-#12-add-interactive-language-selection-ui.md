# Design Document: Interactive Language Selection UI

## Issue Reference
- **Issue**: #12 - Add interactive language selection UI to setup.sh
- **Milestone**: core
- **Label**: feature

## Overview

Add an interactive language selection UI to `setup.sh` that allows users to select multiple language templates and optionally include Playwright for E2E testing.

## Requirements Summary

### Language Selection
| Item | Specification |
|------|---------------|
| Default language | Node.js |
| Multiple selection | Allowed (e.g., node + python) |
| Skip with argument | `--lang node,python` skips interactive prompt |

### Playwright Option
| Item | Specification |
|------|---------------|
| Enable method | `--playwright` flag or interactive selection |
| Target | Add Playwright configuration to selected language templates |

## Architecture Design

### Component Overview

```
setup.sh
├── Argument Parsing (--lang, --playwright)
├── Language Selection UI (interactive)
├── Playwright Selection UI (interactive)
├── Plugin Filtering (based on selections)
└── Plugin Execution (existing hook system)
```

### Data Flow

```
User Input (--lang node,python --playwright)
    ↓
Argument Parsing
    ↓
Language Selection (skip if --lang provided)
    ↓
Playwright Selection (skip if --playwright or -y provided)
    ↓
Filter Plugins (only load selected languages)
    ↓
Execute Plugin Hooks
    ↓
Generate Output
```

## Detailed Design

### 1. New Global Variables

```bash
# Language selection
declare -a SELECTED_LANGUAGES=()   # User-selected language templates
PLAYWRIGHT_ENABLED=false            # Whether to include Playwright

# Available language templates (auto-discovered)
declare -A AVAILABLE_LANGUAGES=(
    ["node"]="Node.js 22.x (LTS)"
    ["python"]="Python 3.x"
    ["rust"]="Rust"
    ["deno"]="Deno"
)
```

### 2. New Command-Line Arguments

| Argument | Description |
|----------|-------------|
| `--lang <list>` | Comma-separated list of languages (e.g., `node,python`) |
| `--playwright` | Enable Playwright E2E testing support |

### 3. Interactive UI Functions

#### Language Selection Prompt
```bash
prompt_language_selection() {
    # Display multi-select menu
    # Allow toggling with space, confirm with enter
    # Return selected languages in SELECTED_LANGUAGES array
}
```

**UI Design**:
```
? Select language template(s) [multiple selection allowed]:
  > [x] Node.js 22.x (LTS) [default]
    [ ] Python 3.x
    [ ] Rust
    [ ] Deno

(Use arrow keys, Space to toggle, Enter to confirm)
```

#### Playwright Selection Prompt
```bash
prompt_playwright() {
    # Simple y/n prompt
    # Set PLAYWRIGHT_ENABLED based on response
}
```

**UI Design**:
```
? Include Playwright for E2E testing? [y/N]:
```

### 4. Plugin Discovery Enhancement

Modify `load_all_plugins()` to:
1. Discover all available language plugins
2. Filter based on `SELECTED_LANGUAGES`
3. Always include `core` and `claude` plugins

```bash
# Plugin loading order:
# 1. core (always first)
# 2. Selected language plugins (node, python, etc.)
# 3. claude (always included)
# 4. playwright (if enabled)
```

### 5. Playwright Plugin Design

Create a new `templates/playwright/plugin.sh`:
- Add Playwright dependencies to devcontainer features
- Merge Playwright VS Code extensions
- Add Playwright-specific Claude Code hooks (if any)

### 6. File Structure Changes

```
templates/
├── core/           # Existing - always included
├── node/           # Existing - optional
├── claude/         # Existing - always included
└── playwright/     # NEW - optional
    ├── plugin.sh
    └── .devcontainer/
        └── devcontainer.json  # Playwright features/extensions
```

## Implementation Approach

### Phase 1: Argument Parsing
1. Add `--lang` option parsing with comma-separated support
2. Add `--playwright` flag parsing
3. Validate language names against available templates

### Phase 2: Interactive UI
1. Implement `prompt_language_selection()` function
2. Implement `prompt_playwright()` function
3. Handle non-interactive mode (`-y` flag)

### Phase 3: Plugin Filtering
1. Modify `load_all_plugins()` to respect selection
2. Ensure `core` and `claude` are always loaded
3. Add Playwright plugin loading logic

### Phase 4: Playwright Plugin
1. Create `templates/playwright/plugin.sh`
2. Add Playwright devcontainer features
3. Test integration with language templates

### Phase 5: Help Update
1. Update `show_help()` with new options
2. Add examples for new usage patterns

## Compatibility Considerations

### Backward Compatibility
- Existing `--dry-run` and `--yes` options continue to work
- Default behavior (no arguments) uses Node.js as default
- `--yes` flag auto-selects Node.js without prompts

### Future Extensibility
- Adding new languages only requires adding a plugin directory
- Playwright can be extended to support language-specific configurations

## Test Strategy

### Unit Tests
1. Argument parsing: `--lang node`, `--lang node,python`, `--playwright`
2. Language validation: reject invalid language names
3. Default behavior: Node.js selected when no `--lang`

### Integration Tests
1. `./setup.sh --lang node --playwright --dry-run`
2. `./setup.sh --lang node,python -y`
3. Interactive mode testing (manual)

### Edge Cases
1. Empty language selection (should default to Node.js)
2. Invalid language name (should error with list of valid options)
3. Playwright without language (should work with any selection)

## Error Handling

| Error | Message | Action |
|-------|---------|--------|
| Invalid language | "Unknown language: {name}. Available: node, python, rust, deno" | Exit with error |
| No plugins found | "No language plugins found in templates/" | Exit with error |
| Conflicting options | N/A (none expected) | - |

## Security Considerations

- No additional security concerns introduced
- Language names are validated against known list
- No user input is executed directly

## Dependencies

- No new external dependencies
- Uses existing jq for JSON operations
- Pure bash for interactive prompts
