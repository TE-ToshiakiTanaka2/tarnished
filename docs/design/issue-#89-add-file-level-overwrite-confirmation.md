# Design Document: File-level Overwrite Confirmation

**Issue**: #89 - Add file-level overwrite confirmation to setup.sh
**Author**: Claude
**Date**: 2026-01-18

## Overview

Add file-level overwrite confirmation to setup.sh that prompts users before overwriting existing files during project setup.

## Architecture

### Current Flow

```
setup.sh main()
    └── Check if .devcontainer or docker-compose.yml exists
        └── Single "Overwrite existing files?" prompt (all or nothing)
            └── execute_plugins_hook "plugin_copy"
                └── Each plugin uses cp/cp -r directly
```

### New Flow

```
setup.sh main()
    └── Remove bulk overwrite check
    └── execute_plugins_hook "plugin_copy"
        └── Each plugin uses copy_with_confirm() / copy_dir_with_confirm()
            └── Per-file: "Overwrite? [y/N]" or auto-skip/overwrite based on flags
```

## Components

### 1. Global Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `OVERWRITE_ALL` | boolean | `false` | Set by `--overwrite` flag |
| `skip_confirm` | boolean | `false` | Existing `-y` flag (reused) |

### 2. Utility Functions (in setup.sh)

#### `copy_with_confirm()`

Copies a single file with overwrite confirmation.

```bash
copy_with_confirm() {
    local src="$1"
    local dest="$2"

    # If destination doesn't exist, copy directly
    if [[ ! -e "$dest" ]]; then
        cp "$src" "$dest"
        return 0
    fi

    # Handle existing file based on flags
    if [[ "$OVERWRITE_ALL" == true ]]; then
        cp "$src" "$dest"
        return 0
    fi

    if [[ "$skip_confirm" == true ]]; then
        print_warning "Skipped: $dest (already exists)"
        return 0
    fi

    # Interactive confirmation
    echo -n "File exists: $dest - Overwrite? [y/N]: "
    local response
    IFS='' read -r response < /dev/tty
    if [[ "$response" =~ ^[Yy] ]]; then
        cp "$src" "$dest"
    else
        print_warning "Skipped: $dest (already exists)"
    fi
}
```

#### `copy_dir_with_confirm()`

Recursively copies a directory, applying `copy_with_confirm()` to each file.

```bash
copy_dir_with_confirm() {
    local src="$1"
    local dest="$2"

    # Create destination directory if needed
    mkdir -p "$dest"

    # Iterate through source files
    find "$src" -type f | while read -r file; do
        local rel_path="${file#$src/}"
        local dest_file="$dest/$rel_path"
        local dest_dir="$(dirname "$dest_file")"

        mkdir -p "$dest_dir"
        copy_with_confirm "$file" "$dest_file"
    done
}
```

### 3. Argument Parsing

Add to `main()` argument parsing:

```bash
--overwrite)
    OVERWRITE_ALL=true
    shift
    ;;
```

### 4. Help Message Update

Add to `show_help()`:

```
    --overwrite         Overwrite existing files without confirmation
```

## Behavior Matrix

| Mode | `skip_confirm` | `OVERWRITE_ALL` | Behavior |
|------|----------------|-----------------|----------|
| Interactive | false | false | Prompt `Overwrite? [y/N]` for each file |
| `-y` | true | false | Auto-skip, log "Skipped: ..." |
| `--overwrite` | false | true | Auto-overwrite all |
| `-y --overwrite` | true | true | Auto-overwrite all |

## Files to Modify

### setup.sh
- Add `OVERWRITE_ALL=false` global variable
- Add `--overwrite` argument parsing
- Add `copy_with_confirm()` function
- Add `copy_dir_with_confirm()` function
- Update `show_help()` with `--overwrite` option
- Remove existing bulk overwrite confirmation logic (lines ~1098-1111)

### templates/core/plugin.sh
Replace `cp -r` calls with `copy_dir_with_confirm()` and `cp` with `copy_with_confirm()`.

### templates/claude/plugin.sh
Replace `cp -r` calls with `copy_dir_with_confirm()` and `cp` with `copy_with_confirm()`.

### templates/node/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

### templates/python/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

### templates/rust/plugin.sh
Replace `cp` calls with `copy_with_confirm()`.

### templates/playwright/plugin.sh
Replace `cp` calls with `copy_with_confirm()`.

### templates/github-actions/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

### templates/postgresql/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

### templates/neo4j/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

### templates/redis/plugin.sh
Replace `cp` and `cp -r` calls with new functions.

## Test Strategy

### Unit Tests
1. `copy_with_confirm()` with non-existing file → copies
2. `copy_with_confirm()` with existing file + `--overwrite` → overwrites
3. `copy_with_confirm()` with existing file + `-y` → skips with log
4. `copy_dir_with_confirm()` with mixed existing/new files

### Integration Tests
1. `setup.sh --dry-run` → no changes
2. `setup.sh -y` → skips existing files
3. `setup.sh --overwrite` → overwrites all
4. `setup.sh -y --overwrite` → overwrites all

## Backward Compatibility

- Existing `-y` behavior preserved (now auto-skips files instead of prompting)
- New `--overwrite` flag required for explicit overwrite behavior
- Interactive mode now prompts per-file instead of all-or-nothing
