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
export COLOR_CYAN='\033[0;36m'
export COLOR_BOLD='\033[1m'
export COLOR_NC='\033[0m' # No Color

# =============================================================================
# Output Helper Functions
# =============================================================================

print_header() {
    echo -e "${COLOR_BLUE}"
    echo "============================================================="
    echo "         Devcontainer Boilerplate Setup Script               "
    echo "============================================================="
    echo -e "${COLOR_NC}"
}

print_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_NC} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $1"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $1" >&2
}

print_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $1"
}

print_section() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}=== $1 ===${COLOR_NC}"
    echo ""
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

    # Check if TTY is available for interactive confirmation
    if [[ ! -e /dev/tty ]] || ! : < /dev/tty 2>/dev/null; then
        # Non-interactive environment: skip by default
        print_warning "Skipped: $dest (already exists, non-interactive)"
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
    # First merge all fields from base, then selectively merge features, extensions, and settings
    if ! jq -s '
        .[0] as $base | .[1] as $overlay |
        ($base | del(.features, .customizations)) *
        ($overlay | del(.features, .customizations)) *
        {
            features: (($base.features // {}) * ($overlay.features // {})),
            customizations: {
                vscode: {
                    extensions: (($base.customizations.vscode.extensions // []) + ($overlay.customizations.vscode.extensions // []) | unique),
                    settings: (($base.customizations.vscode.settings // {}) * ($overlay.customizations.vscode.settings // {}))
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

    # Merge with special handling for permissions and hooks (arrays are concatenated)
    if ! jq -s '
        .[0] as $base | .[1] as $overlay |
        {
            permissions: {
                allow: (($base.permissions.allow // []) + ($overlay.permissions.allow // []) | unique),
                deny: (($base.permissions.deny // []) + ($overlay.permissions.deny // []) | unique)
            },
            hooks: {
                PreToolUse: (($base.hooks.PreToolUse // []) + ($overlay.hooks.PreToolUse // [])),
                PostToolUse: (($base.hooks.PostToolUse // []) + ($overlay.hooks.PostToolUse // []))
            }
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
        # Fallback: Extract and merge services/volumes sections

        # Read base file
        local base_content
        base_content=$(cat "$base_file")

        # Extract services from overlay (skip the 'services:' header line)
        local overlay_services
        overlay_services=$(sed -n '/^services:/,/^volumes:/{ /^services:/d; /^volumes:/d; p; }' "$overlay_file")

        # Extract volumes from overlay (skip the 'volumes:' header line)
        local overlay_volumes
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
        "${target_dir}/.devcontainer/scripts/post.sh"
        "${target_dir}/docker/Dockerfile.dev"
        "${target_dir}/docker-compose.yml"
        "${target_dir}/docker-compose.postgresql.yml"
        "${target_dir}/docker-compose.redis.yml"
        "${target_dir}/docker-compose.celery.yml"
        "${target_dir}/CLAUDE.md"
        "${target_dir}/AGENTS.md"
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

    # Normalize trailing newline so block separators land on their own line
    if [[ -s "$gitignore_file" ]] && [[ -n "$(tail -c1 "$gitignore_file")" ]]; then
        echo "" >> "$gitignore_file"
    fi

    # Block 1: Claude Code whitelist — ignore .claude/* and allow project-tracked subdirs/files
    if ! grep -q "^# Claude Code (track project configs only)$" "$gitignore_file" 2>/dev/null; then
        {
            echo ""
            echo "# Claude Code (track project configs only)"
            echo ".claude/*"
            echo "!.claude/commands/"
            echo "!.claude/skills/"
            echo "!.claude/scripts/"
            echo "!.claude/agents/"
            echo "!.claude/rules/"
            echo "!.claude/hooks/"
            echo "!.claude/settings.json"
        } >> "$gitignore_file"
    fi

    # Block 2: Serena MCP working files
    if ! grep -q "^# Serena MCP working files$" "$gitignore_file" 2>/dev/null; then
        {
            echo ""
            echo "# Serena MCP working files"
            echo ".serena/"
        } >> "$gitignore_file"
    fi

    # Block 3: Local screenshots (manual UI testing)
    if ! grep -q "^# Local screenshots (manual UI testing)$" "$gitignore_file" 2>/dev/null; then
        {
            echo ""
            echo "# Local screenshots (manual UI testing)"
            echo "screenshots/"
        } >> "$gitignore_file"
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

# =============================================================================
# Validation Utility Functions
# =============================================================================

# Validate project name (alphanumeric, hyphens, underscores)
# Usage: validate_project_name <name>
validate_project_name() {
    local name="$1"

    # Check if empty
    if [[ -z "$name" ]]; then
        print_error "Project name cannot be empty"
        return 1
    fi

    # Check for valid characters (alphanumeric, hyphens, underscores)
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        print_error "Project name must start with a letter and contain only letters, numbers, hyphens, and underscores"
        return 1
    fi

    # Check length
    if [[ ${#name} -gt 64 ]]; then
        print_error "Project name must be 64 characters or less"
        return 1
    fi

    return 0
}

# =============================================================================
# Interactive Prompt Utility Functions
# =============================================================================

# Prompt for input with default value
# Usage: prompt_input "Enter value" "default"
prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [[ -n "$default" ]]; then
        echo -n "$prompt [$default]: " > /dev/tty
    else
        echo -n "$prompt: " > /dev/tty
    fi

    IFS='' read -r result < /dev/tty
    if [[ -z "$result" ]]; then
        result="$default"
    fi

    echo "$result"
}

# Prompt for yes/no confirmation
# Usage: confirm "Continue?" "y"
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        echo -n "$prompt [Y/n]: " > /dev/tty
    else
        echo -n "$prompt [y/N]: " > /dev/tty
    fi

    IFS='' read -r response < /dev/tty

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        [nN]|[nN][oO]) return 1 ;;
        "") [[ "$default" == "y" ]] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

# Prompt for selection from options
# Usage: prompt_select "Select option" "option1 option2 option3" "option1"
prompt_select() {
    local prompt="$1"
    local options_str="$2"
    local default="$3"

    # Convert space-separated string to array
    local -a options=($options_str)
    local count=${#options[@]}

    echo "$prompt:" > /dev/tty
    for i in "${!options[@]}"; do
        local marker=""
        if [[ "${options[$i]}" == "$default" ]]; then
            marker=" (default)"
        fi
        echo "  $((i+1)). ${options[$i]}${marker}" > /dev/tty
    done

    while true; do
        echo -n "Enter number [1-$count]: " > /dev/tty
        local response
        IFS='' read -r response < /dev/tty

        if [[ -z "$response" && -n "$default" ]]; then
            echo "$default"
            return 0
        fi

        if [[ "$response" =~ ^[0-9]+$ ]] && [[ "$response" -ge 1 ]] && [[ "$response" -le "$count" ]]; then
            echo "${options[$((response-1))]}"
            return 0
        fi

        echo "Invalid selection. Please enter a number between 1 and $count." > /dev/tty
    done
}

# Prompt for multi-selection from options
# Usage: result=$(prompt_multiselect "Select options" "option1 option2 option3" "option1 option2")
prompt_multiselect() {
    local prompt="$1"
    local options_str="$2"
    local defaults_str="$3"

    # Convert space-separated string to array
    local -a options=($options_str)
    local -a defaults=($defaults_str)
    local count=${#options[@]}

    # Create associative array for defaults
    declare -A default_map
    for d in "${defaults[@]}"; do
        default_map["$d"]=1
    done

    echo "$prompt (comma-separated numbers, or 'all'/'none'):" > /dev/tty
    for i in "${!options[@]}"; do
        local marker=""
        if [[ -n "${default_map[${options[$i]}]:-}" ]]; then
            marker=" *"
        fi
        echo "  $((i+1)). ${options[$i]}${marker}" > /dev/tty
    done

    echo -n "Enter selection: " > /dev/tty
    local response
    IFS='' read -r response < /dev/tty

    # Handle special cases
    if [[ -z "$response" ]]; then
        echo "$defaults_str"
        return 0
    fi

    if [[ "$response" == "all" ]]; then
        echo "$options_str"
        return 0
    fi

    if [[ "$response" == "none" ]]; then
        echo ""
        return 0
    fi

    # Parse comma-separated numbers
    local -a selected=()
    IFS=',' read -ra nums <<< "$response"
    for num in "${nums[@]}"; do
        num=$(echo "$num" | tr -d ' ')
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$count" ]]; then
            selected+=("${options[$((num-1))]}")
        fi
    done

    echo "${selected[*]}"
}

# =============================================================================
# Monorepo Utility Functions (#263)
# =============================================================================
#
# Helpers for the monorepo / add-module flows in setup.sh. The schema and
# function contracts are documented in
# docs/design/shared/api-spec.md :: "scripts/lib/common.sh — monorepo helpers"
# and docs/design/shared/data-model.md :: "modules.json schema".
#
# All helpers below assume `jq` is installed (already a hard dependency of
# setup.sh — checked in check_dependencies).

# Maximum modules.json schema version this version of setup.sh understands.
# Bump when introducing breaking changes to the schema.
readonly MODULES_JSON_SUPPORTED_VERSION=1

# Detect whether the given directory is an existing monorepo target
# (i.e., contains a modules.json registry).
# Usage: detect_existing_monorepo <target_dir>
# Returns: 0 if modules.json is present, 1 otherwise.
detect_existing_monorepo() {
    local target_dir="$1"
    [[ -f "${target_dir}/modules.json" ]]
}

# Validate a module name. Same character set as project names, but with
# stricter constraints (lowercase only, length 50, no leading digit) to
# keep paths and compose service names predictable.
# Usage: validate_module_name <name>
# Returns: 0 if valid, 1 otherwise. Emits an error on stderr on failure.
validate_module_name() {
    local name="$1"

    if [[ -z "$name" ]]; then
        print_error "Module name cannot be empty"
        return 1
    fi

    if [[ ${#name} -gt 50 ]]; then
        print_error "Module name '$name' exceeds 50 characters"
        return 1
    fi

    if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "Module name '$name' must match ^[a-z][a-z0-9_-]*$ (lowercase, alnum/-/_, no leading digit)"
        return 1
    fi

    return 0
}

# Read modules.json and stream the parsed top-level object to stdout via jq.
# Rejects unknown major schema versions with a clear error.
# Usage: read_modules_json <target_dir>
# Returns: 0 on success (object to stdout), 1 on parse / version error.
read_modules_json() {
    local target_dir="$1"
    local file="${target_dir}/modules.json"

    if [[ ! -f "$file" ]]; then
        print_error "modules.json not found at: $file"
        return 1
    fi

    local version
    if ! version=$(jq -r '.version // 0' "$file" 2>/dev/null); then
        print_error "modules.json parse failed (invalid JSON): $file"
        return 1
    fi

    if ! [[ "$version" =~ ^[0-9]+$ ]] || [[ "$version" -lt 1 ]]; then
        print_error "modules.json missing required 'version' field"
        return 1
    fi

    if [[ "$version" -gt "$MODULES_JSON_SUPPORTED_VERSION" ]]; then
        print_error "Unsupported modules.json version: $version (max supported: $MODULES_JSON_SUPPORTED_VERSION). Upgrade setup.sh."
        return 1
    fi

    cat "$file"
}

# Atomically rewrite modules.json by passing the current contents through a
# jq filter and replacing the file. Uses tmp + mv so a SIGINT mid-write
# leaves the original intact. Extra arguments (e.g. `--arg`, `--argjson`)
# are forwarded to jq for safe value injection (Suggestion #7 from #263
# review).
# Usage: write_modules_json <target_dir> <jq_filter> [<extra_jq_args>...]
write_modules_json() {
    local target_dir="$1"
    local jq_filter="$2"
    shift 2
    local file="${target_dir}/modules.json"
    local tmp="${file}.tmp"

    if ! jq "$@" "$jq_filter" "$file" > "$tmp"; then
        print_error "Failed to apply jq filter to modules.json"
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$file"
}

# Look up a module by name. Pure read (no mutation).
# Usage: find_module_by_name <target_dir> <name>
# Returns: 0 if a module with that name exists, 1 otherwise.
find_module_by_name() {
    local target_dir="$1"
    local name="$2"
    local file="${target_dir}/modules.json"

    [[ -f "$file" ]] || return 1
    jq -e --arg n "$name" '.modules[] | select(.name == $n)' "$file" >/dev/null 2>&1
}

# Stream module names to stdout, one per line.
# Usage: list_module_names <target_dir>
list_module_names() {
    local target_dir="$1"
    local file="${target_dir}/modules.json"

    [[ -f "$file" ]] || return 0
    jq -r '.modules[].name' "$file" 2>/dev/null
}

# Recover the canonical project name from an existing target's
# docker-compose.yml. Used by add-module so that the new module's
# generated content (CLAUDE.md placeholders, service compose
# substitution, etc.) uses the same name as the original `--monorepo`
# init even if the user typed a different value or the directory was
# renamed (Warning #4 from #263 review).
#
# The dev container service (always written first by templates/core/
# docker-compose.yml) has its name unprefixed, so we take the first
# top-level service key.
derive_project_name_from_compose() {
    local target_dir="$1"
    local file="${target_dir}/docker-compose.yml"

    [[ -f "$file" ]] || return 1

    local first
    first=$(list_existing_compose_services "$target_dir" | head -1)
    if [[ -z "$first" ]]; then
        return 1
    fi
    printf '%s' "$first"
}

# Append a module entry to modules.json. Refuses to overwrite an existing
# entry — caller must call find_module_by_name + handle the overwrite
# prompt before invoking this with a colliding name.
# Usage: add_module_entry <target_dir> <name> <lang> [<services_csv>]
# Returns: 0 on success, 2 on duplicate name, 1 on other error.
add_module_entry() {
    local target_dir="$1"
    local name="$2"
    local lang="$3"
    local services_csv="${4:-}"

    if find_module_by_name "$target_dir" "$name"; then
        return 2
    fi

    # Build the services array from a comma-separated list (may be empty).
    local services_json='[]'
    if [[ -n "$services_csv" ]]; then
        services_json=$(printf '%s' "$services_csv" | jq -R 'split(",") | map(select(length > 0))')
    fi

    write_modules_json "$target_dir" \
        '.modules += [{name: $name, path: $name, language: $lang, services: $svcs}]' \
        --arg name "$name" --arg lang "$lang" --argjson svcs "$services_json"
}

# Replace an existing module entry in-place. Updates only the known fields
# (`path`, `language`, `services`) so any forward-compatible per-module
# keys the user may have added (e.g. `commands`, `version_file`) are
# preserved across the rewrite (Warning #6 from #263 review).
# Usage: replace_module_entry <target_dir> <name> <lang> [<services_csv>]
# Returns: 0 on success, 1 on error.
replace_module_entry() {
    local target_dir="$1"
    local name="$2"
    local lang="$3"
    local services_csv="${4:-}"

    local services_json='[]'
    if [[ -n "$services_csv" ]]; then
        services_json=$(printf '%s' "$services_csv" | jq -R 'split(",") | map(select(length > 0))')
    fi

    # `. + {…}` merges the right-hand object onto the existing entry,
    # overwriting only the listed keys. Unknown keys in `.` are kept.
    write_modules_json "$target_dir" \
        '.modules |= map(if .name == $name then . + {path: $name, language: $lang, services: $svcs} else . end)' \
        --arg name "$name" --arg lang "$lang" --argjson svcs "$services_json"
}

# List the docker-compose service ids currently defined in the target's
# docker-compose.yml. Used by add-module to offer only un-added services.
# Usage: list_existing_compose_services <target_dir>
list_existing_compose_services() {
    local target_dir="$1"
    local file="${target_dir}/docker-compose.yml"

    [[ -f "$file" ]] || return 0

    # Compose service keys are 4-space-indented under a top-level `services:`.
    # This light grep keeps us free of yq as a hard dep.
    awk '
        /^services:[[:space:]]*$/ { in_services = 1; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_services = 0 }
        in_services && /^  [a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
            sub(/^  /, ""); sub(/:[[:space:]]*$/, ""); print
        }
    ' "$file"
}

# Prompt the user (interactive only) whether they want monorepo mode.
# Echoes "true" or "false" on stdout.
# Usage: result=$(prompt_monorepo_mode)
prompt_monorepo_mode() {
    echo "" > /dev/tty
    echo -n "Monorepo configuration? (y/n) [n]: " > /dev/tty
    local response
    IFS='' read -r response < /dev/tty

    if [[ "$response" =~ ^[Yy] ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Interactive module dialogue loop. Mutates the global MODULES array,
# appending each accepted "name:lang" entry. Empty name terminates.
# At least one module is required (re-prompts if user terminates with 0
# entries).
# Usage: prompt_module_loop  (operates on global MODULES)
# Globals required: AVAILABLE_LANGUAGES (set by setup.sh)
prompt_module_loop() {
    echo "" > /dev/tty
    print_info "Define monorepo modules. Enter an empty module name to finish."
    print_info "Available languages: ${AVAILABLE_LANGUAGES[*]}"

    local idx=$((${#MODULES[@]} + 1))
    while true; do
        echo "" > /dev/tty
        echo -n "Module $idx name (empty to finish): " > /dev/tty
        local name
        IFS='' read -r name < /dev/tty

        if [[ -z "$name" ]]; then
            if [[ ${#MODULES[@]} -eq 0 ]]; then
                print_warning "At least one module is required"
                continue
            fi
            break
        fi

        if ! validate_module_name "$name"; then
            continue
        fi

        # Reject duplicates within this batch.
        local dup=false
        local existing
        for existing in "${MODULES[@]}"; do
            if [[ "${existing%%:*}" == "$name" ]]; then
                print_warning "Module '$name' already declared in this run"
                dup=true
                break
            fi
        done
        if [[ "$dup" == true ]]; then
            continue
        fi

        echo -n "Module $idx language (${AVAILABLE_LANGUAGES[*]}): " > /dev/tty
        local lang
        IFS='' read -r lang < /dev/tty

        local valid=false
        local available
        for available in "${AVAILABLE_LANGUAGES[@]}"; do
            if [[ "$available" == "$lang" ]]; then
                valid=true
                break
            fi
        done
        if [[ "$valid" != true ]]; then
            print_warning "Unknown language '$lang' (available: ${AVAILABLE_LANGUAGES[*]})"
            continue
        fi

        MODULES+=("$name:$lang")
        print_success "Added module: $name ($lang)"
        idx=$((idx + 1))
    done
}

# Single-shot prompt for one module name + language (used by add-module).
# Echoes "name:lang" on stdout.
# Globals required: AVAILABLE_LANGUAGES
prompt_add_module() {
    local name lang

    while true; do
        echo "" > /dev/tty
        echo -n "Module name: " > /dev/tty
        IFS='' read -r name < /dev/tty
        if validate_module_name "$name"; then
            break
        fi
    done

    while true; do
        echo -n "Module language (${AVAILABLE_LANGUAGES[*]}): " > /dev/tty
        IFS='' read -r lang < /dev/tty
        local available
        for available in "${AVAILABLE_LANGUAGES[@]}"; do
            if [[ "$available" == "$lang" ]]; then
                echo "${name}:${lang}"
                return 0
            fi
        done
        print_warning "Unknown language '$lang' (available: ${AVAILABLE_LANGUAGES[*]})"
    done
}
