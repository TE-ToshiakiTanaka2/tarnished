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
# File Copy Utility Functions
# =============================================================================

# Global variables for file copy behavior (can be overridden by setup.sh)
OVERWRITE_ALL="${OVERWRITE_ALL:-false}"
skip_confirm="${skip_confirm:-false}"

# Copy a single file with overwrite confirmation
# Usage: copy_with_confirm <source> <destination>
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

# Copy a directory recursively with overwrite confirmation for each file
# Usage: copy_dir_with_confirm <source_dir> <destination_dir>
copy_dir_with_confirm() {
    local src="$1"
    local dest="$2"

    # Create destination directory if needed
    mkdir -p "$dest"

    # Iterate through source files
    while IFS= read -r -d '' file; do
        local rel_path="${file#$src/}"
        local dest_file="$dest/$rel_path"
        local dest_dir
        dest_dir="$(dirname "$dest_file")"

        mkdir -p "$dest_dir"
        copy_with_confirm "$file" "$dest_file"
    done < <(find "$src" -type f -print0)
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
# Docker Compose Utility Functions
# =============================================================================

# Merge docker-compose.yml files (add services and volumes from overlay)
# Usage: merge_docker_compose_services <base_file> <overlay_file> <output_file>
merge_docker_compose_services() {
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

    # Check if yq is available for direct YAML processing
    if command -v yq &> /dev/null; then
        # Use yq for YAML merge
        if ! yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$base_file" "$overlay_file" > "$output_file"; then
            print_error "Failed to merge docker-compose files with yq"
            return 1
        fi
    else
        # Fallback: Convert YAML to JSON, merge with jq, convert back
        # This requires yq for the final conversion, so we use a simpler approach
        # Append the overlay content with proper YAML structure

        # Read base file
        local base_content
        base_content=$(cat "$base_file")

        # Read overlay file and extract services and volumes sections
        local overlay_services
        local overlay_volumes

        # Extract services from overlay (skip the 'services:' header line)
        overlay_services=$(sed -n '/^services:/,/^volumes:/{ /^services:/d; /^volumes:/d; p; }' "$overlay_file")

        # Extract volumes from overlay (skip the 'volumes:' header line)
        overlay_volumes=$(sed -n '/^volumes:/,/^[a-z]/{ /^volumes:/d; /^[a-z]/d; p; }' "$overlay_file")
        # Handle case where volumes is at the end of file
        if [[ -z "$overlay_volumes" ]]; then
            overlay_volumes=$(sed -n '/^volumes:/,$ { /^volumes:/d; p; }' "$overlay_file")
        fi

        # Check if base already has volumes section
        if grep -q "^volumes:" "$base_file"; then
            # Insert services before volumes section, add volumes at the end
            {
                sed '/^volumes:/,$d' "$base_file"
                echo "$overlay_services"
                echo ""
                echo "volumes:"
                sed -n '/^volumes:/,$ { /^volumes:/d; p; }' "$base_file"
                echo "$overlay_volumes"
            } > "$output_file"
        else
            # Append services and volumes sections
            {
                cat "$base_file"
                echo ""
                echo "$overlay_services"
                echo ""
                echo "volumes:"
                echo "$overlay_volumes"
            } > "$output_file"
        fi
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

# =============================================================================
# TTY Utility Functions
# =============================================================================

# Check if /dev/tty is available for interactive input
# This is essential for curl | bash execution where stdin is piped
# Returns 0 if available, 1 if not
check_tty_available() {
    # Check if /dev/tty exists and is a character device
    if [[ ! -c /dev/tty ]]; then
        return 1
    fi

    # Try to open /dev/tty for reading
    if ! exec 3< /dev/tty 2>/dev/null; then
        return 1
    fi

    # Close the test file descriptor
    exec 3<&-
    return 0
}

# Show error message when interactive mode is not available
# Provides helpful guidance for non-interactive execution
show_interactive_mode_error() {
    print_error "Interactive mode is not available"
    echo ""
    echo "This appears to be a non-interactive environment (e.g., piped input, CI/CD)."
    echo ""
    echo "To run in non-interactive mode, specify all required options:"
    echo ""
    echo "  curl -fsSL <url>/setup.sh | bash -s -- --lang node my-project -y"
    echo "  curl -fsSL <url>/setup.sh | bash -s -- --lang python --docker my-app -y"
    echo ""
    echo "Available options:"
    echo "  --lang <languages>    Select language(s): node, python, rust, deno"
    echo "  --playwright          Include Playwright E2E testing"
    echo "  --docker              Include Docker-in-Docker support"
    echo "  --postgresql          Include PostgreSQL database support"
    echo "  --neo4j               Include Neo4j graph database support"
    echo "  --redis               Include Redis cache/session support"
    echo "  --github-actions      Include GitHub Actions templates"
    echo "  -y, --yes             Skip confirmation prompts (required for non-interactive)"
    echo ""
    echo "For full options, see: ./setup.sh --help"
}
