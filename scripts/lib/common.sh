#!/bin/bash
# =============================================================================
# Common Library for Devcontainer Setup
# =============================================================================
# This library provides shared utility functions used by setup.sh and all
# template plugins.
#
# Usage:
#   source "${SCRIPT_DIR}/scripts/lib/common.sh"
#
# =============================================================================

# Guard against multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return
_COMMON_SH_LOADED=1

# =============================================================================
# Color Constants
# =============================================================================

export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[1;33m'
export COLOR_BLUE='\033[0;34m'
export COLOR_NC='\033[0m' # No Color

# =============================================================================
# Output Helper Functions
# =============================================================================

print_header() {
    echo -e "${COLOR_BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║         Devcontainer Boilerplate Setup Script                     ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_NC}"
}

print_success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_NC}"
}

print_warning() {
    echo -e "${COLOR_YELLOW}⚠ $1${COLOR_NC}"
}

print_error() {
    echo -e "${COLOR_RED}✗ $1${COLOR_NC}"
}

print_info() {
    echo -e "${COLOR_BLUE}ℹ $1${COLOR_NC}"
}

# =============================================================================
# JSON Utility Functions
# =============================================================================

# Merge two JSON files with deep merge strategy
# Usage: merge_json_files <base_file> <overlay_file> <output_file>
merge_json_files() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"

    if [[ ! -f "$base_file" ]]; then
        print_error "Base file not found: $base_file"
        return 1
    fi

    if [[ ! -f "$overlay_file" ]]; then
        print_error "Overlay file not found: $overlay_file"
        return 1
    fi

    # Deep merge using jq
    if ! jq -s '.[0] * .[1]' "$base_file" "$overlay_file" > "$output_file"; then
        print_error "Failed to merge JSON files"
        return 1
    fi
}

# Merge devcontainer.json files with special handling for features and extensions
# Usage: merge_devcontainer_json <base_file> <overlay_file> <output_file>
merge_devcontainer_json() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"

    if [[ ! -f "$base_file" ]]; then
        print_error "Base file not found: $base_file"
        return 1
    fi

    if [[ ! -f "$overlay_file" ]]; then
        print_error "Overlay file not found: $overlay_file"
        return 1
    fi

    # Merge preserving all base fields and merging features/customizations
    if ! jq -s '
        .[0] as $core | .[1] as $lang |
        $core + {
            features: (($core.features // {}) + ($lang.features // {})),
            customizations: {
                vscode: {
                    extensions: (($core.customizations.vscode.extensions // []) + ($lang.customizations.vscode.extensions // []) | unique),
                    settings: (($core.customizations.vscode.settings // {}) + ($lang.customizations.vscode.settings // {}))
                }
            }
        }
    ' "$base_file" "$overlay_file" > "$output_file"; then
        print_error "Failed to merge devcontainer JSON files"
        return 1
    fi
}

# Merge Claude settings.json files with special handling for permissions and hooks
# Usage: merge_claude_settings <base_file> <overlay_file> <output_file>
merge_claude_settings() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"

    if [[ ! -f "$base_file" ]]; then
        print_error "Base file not found: $base_file"
        return 1
    fi

    if [[ ! -f "$overlay_file" ]]; then
        # If overlay doesn't exist, just use base
        cp "$base_file" "$output_file"
        return 0
    fi

    # Merge with special handling for permissions and hooks
    if ! jq -s '
        .[0] as $base | .[1] as $overlay |
        {
            permissions: {
                allow: (($base.permissions.allow // []) + ($overlay.permissions.allow // []) | unique),
                deny: (($base.permissions.deny // []) + ($overlay.permissions.deny // []) | unique)
            },
            hooks: (($base.hooks // {}) * ($overlay.hooks // {}))
        }
    ' "$base_file" "$overlay_file" > "$output_file"; then
        print_error "Failed to merge Claude settings files"
        return 1
    fi
}

# Merge Claude settings.json with hook array concatenation
# Usage: merge_claude_settings_hooks <base_file> <overlay_file> <output_file>
merge_claude_settings_hooks() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"

    if [[ ! -f "$base_file" ]]; then
        print_error "Base file not found: $base_file"
        return 1
    fi

    if [[ ! -f "$overlay_file" ]]; then
        return 0
    fi

    # Merge settings with hook array concatenation
    if ! jq -s '
        .[0] as $base | .[1] as $lang |
        $base * {
            hooks: {
                PreToolUse: (($base.hooks.PreToolUse // []) + ($lang.hooks.PreToolUse // [])),
                PostToolUse: (($base.hooks.PostToolUse // []) + ($lang.hooks.PostToolUse // []))
            }
        }
    ' "$base_file" "$overlay_file" > "$output_file"; then
        print_error "Failed to merge Claude settings hooks"
        return 1
    fi
}

# =============================================================================
# File Utility Functions
# =============================================================================

# Copy a directory recursively with error handling
# Usage: copy_template_dir <source_dir> <target_dir>
copy_template_dir() {
    local source_dir="$1"
    local target_dir="$2"

    if [[ ! -d "$source_dir" ]]; then
        print_error "Source directory not found: $source_dir"
        return 1
    fi

    cp -r "$source_dir" "$target_dir"
}

# Make all shell scripts in a directory executable
# Usage: make_scripts_executable <directory>
make_scripts_executable() {
    local directory="$1"

    if [[ -d "$directory" ]]; then
        find "$directory" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    fi
}

# =============================================================================
# Placeholder Utility Functions
# =============================================================================

# Replace placeholders in files
# Usage: replace_placeholders <target_dir> <project_name>
replace_placeholders() {
    local target_dir="$1"
    local project_name="$2"

    print_info "Replacing placeholders with project name: ${project_name}"

    # Files to process
    local files=(
        "${target_dir}/.devcontainer/devcontainer.json"
        "${target_dir}/docker-compose.yml"
        "${target_dir}/CLAUDE.md"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            # Use sed to replace placeholder (using | delimiter for safety)
            if [[ "$(uname)" == "Darwin" ]]; then
                # macOS
                sed -i '' "s|{{PROJECT_NAME}}|${project_name}|g" "$file"
            else
                # Linux
                sed -i "s|{{PROJECT_NAME}}|${project_name}|g" "$file"
            fi
        fi
    done

    print_success "Placeholders replaced"
}

# =============================================================================
# Gitignore Utility Functions
# =============================================================================

# Update .gitignore with common entries
# Usage: update_gitignore <target_dir>
update_gitignore() {
    local target_dir="$1"
    local gitignore_file="${target_dir}/.gitignore"

    print_info "Updating .gitignore..."

    # Create .gitignore if it doesn't exist
    if [[ ! -f "$gitignore_file" ]]; then
        touch "$gitignore_file"
    fi

    # Add Claude Code settings.local.json if not already present
    if ! grep -q "^\.claude/settings\.local\.json$" "$gitignore_file" 2>/dev/null; then
        echo "" >> "$gitignore_file"
        echo "# Claude Code local settings (personal preferences)" >> "$gitignore_file"
        echo ".claude/settings.local.json" >> "$gitignore_file"
    fi

    print_success ".gitignore updated"
}
