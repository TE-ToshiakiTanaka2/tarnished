#!/bin/sh
# =============================================================================
# DevContainer Setup Script
# =============================================================================
# Dotfiles-style setup script for initializing DevContainer environments
# with Claude Code and SuperClaude support.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/develop/setup.sh | bash
#   ./setup.sh
#
# POSIX sh compatible for maximum portability
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop"

# -----------------------------------------------------------------------------
# Color Definitions (with fallback for non-TTY)
# -----------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

header() {
    printf "\n${BOLD}${CYAN}=== %s ===${NC}\n\n" "$1"
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# Check if running interactively
is_interactive() {
    [ -t 0 ]
}

# Prompt for yes/no confirmation
# Returns 0 for yes, 1 for no
confirm() {
    prompt="$1"
    default="${2:-n}"

    if ! is_interactive; then
        [ "$default" = "y" ]
        return $?
    fi

    if [ "$default" = "y" ]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    printf "%s %s: " "$prompt" "$prompt_suffix"
    read -r response

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        [nN]|[nN][oO]) return 1 ;;
        "") [ "$default" = "y" ] && return 0 || return 1 ;;
        *) return 1 ;;
    esac
}

# Prompt for text input
# Usage: result=$(prompt_input "Enter value" "default")
prompt_input() {
    prompt="$1"
    default="$2"

    if ! is_interactive; then
        printf "%s" "$default"
        return 0
    fi

    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi
    read -r response

    if [ -z "$response" ]; then
        printf "%s" "$default"
    else
        printf "%s" "$response"
    fi
}

# Convert string to lowercase
to_lower() {
    printf "%s" "$1" | tr '[:upper:]' '[:lower:]'
}

# Convert string to kebab-case
to_kebab() {
    printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-'
}

# Check if file exists and prompt for overwrite
# Returns 0 if should write, 1 if should skip
check_overwrite() {
    filepath="$1"

    if [ -f "$filepath" ]; then
        warn "File already exists: $filepath"
        if confirm "Overwrite?" "n"; then
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Download file from remote repository
download_template() {
    template_path="$1"
    output_path="$2"

    url="${REPO_URL}/${template_path}"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output_path"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output_path"
    else
        error "Neither curl nor wget found. Please install one of them."
        return 1
    fi
}

# Get local template path (for local execution)
get_local_template() {
    template_path="$1"
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    printf "%s/%s" "$script_dir" "$template_path"
}

# Read template from local or remote
read_template() {
    template_path="$1"

    # Check if running locally with templates available
    local_path=$(get_local_template "$template_path")
    if [ -f "$local_path" ]; then
        cat "$local_path"
        return 0
    fi

    # Download from remote
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${REPO_URL}/${template_path}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "${REPO_URL}/${template_path}"
    else
        error "Neither curl nor wget found."
        return 1
    fi
}

# Process template by replacing placeholders
process_template() {
    template="$1"
    # Uses global variables: PROJECT_NAME, PROJECT_NAME_LOWER

    printf "%s" "$template" | \
        sed "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" | \
        sed "s/{{PROJECT_NAME_LOWER}}/${PROJECT_NAME_LOWER}/g"
}

# -----------------------------------------------------------------------------
# Plugin System
# -----------------------------------------------------------------------------

# Plugin categories
PLUGIN_CATEGORIES="languages tools github-actions"

# Selected plugins (space-separated list of category/name)
SELECTED_PLUGINS=""

# Check if jq is available
has_jq() {
    command -v jq >/dev/null 2>&1
}

# Get script directory (for local plugin paths)
get_script_dir() {
    cd "$(dirname "$0")" && pwd
}

# Get plugin directory path
# Usage: get_plugin_path "languages/rust"
get_plugin_path() {
    plugin="$1"
    script_dir=$(get_script_dir)
    printf "%s/plugins/%s" "$script_dir" "$plugin"
}

# Parse JSON value using jq or fallback
# Usage: json_get "file.json" ".key" or json_get "file.json" ".key.subkey"
json_get() {
    json_file="$1"
    json_path="$2"

    if has_jq; then
        jq -r "$json_path // empty" "$json_file" 2>/dev/null
    else
        # Simple fallback for basic paths like ".name", ".version"
        key=$(printf "%s" "$json_path" | sed 's/^\.//')
        grep "\"$key\"" "$json_file" 2>/dev/null | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/'
    fi
}

# Parse JSON array using jq or fallback
# Usage: json_get_array "file.json" ".dependencies.features"
json_get_array() {
    json_file="$1"
    json_path="$2"

    if has_jq; then
        jq -r "$json_path // [] | .[]" "$json_file" 2>/dev/null
    else
        # Fallback: very limited, only works for simple arrays
        :
    fi
}

# Check if plugin exists and has required files
# Usage: validate_plugin "languages/rust"
# Returns: 0 if valid, 1 if invalid
validate_plugin() {
    plugin="$1"
    plugin_path=$(get_plugin_path "$plugin")

    # Check plugin directory exists
    if [ ! -d "$plugin_path" ]; then
        return 1
    fi

    # Check required files
    if [ ! -f "$plugin_path/plugin.json" ]; then
        error "Plugin '$plugin' missing plugin.json"
        return 1
    fi

    if [ ! -f "$plugin_path/plugin.sh" ]; then
        error "Plugin '$plugin' missing plugin.sh"
        return 1
    fi

    # Validate plugin.json has required fields
    name=$(json_get "$plugin_path/plugin.json" ".name")
    version=$(json_get "$plugin_path/plugin.json" ".version")
    description=$(json_get "$plugin_path/plugin.json" ".description")

    if [ -z "$name" ] || [ -z "$version" ] || [ -z "$description" ]; then
        error "Plugin '$plugin' has invalid plugin.json (missing required fields)"
        return 1
    fi

    return 0
}

# Discover all available plugins
# Output: list of "category/name" (one per line)
discover_plugins() {
    script_dir=$(get_script_dir)

    for category in $PLUGIN_CATEGORIES; do
        category_dir="$script_dir/plugins/$category"
        if [ -d "$category_dir" ]; then
            for plugin_dir in "$category_dir"/*/; do
                if [ -d "$plugin_dir" ]; then
                    plugin_name=$(basename "$plugin_dir")
                    plugin_id="$category/$plugin_name"
                    if validate_plugin "$plugin_id" 2>/dev/null; then
                        printf "%s\n" "$plugin_id"
                    fi
                fi
            done
        fi
    done
}

# Get plugin metadata
# Usage: get_plugin_info "languages/rust" "description"
get_plugin_info() {
    plugin="$1"
    field="$2"
    plugin_path=$(get_plugin_path "$plugin")
    json_get "$plugin_path/plugin.json" ".$field"
}

# Get plugin feature dependencies
# Usage: get_plugin_feature_deps "languages/rust"
get_plugin_feature_deps() {
    plugin="$1"
    plugin_path=$(get_plugin_path "$plugin")
    json_get_array "$plugin_path/plugin.json" ".dependencies.features"
}

# Get plugin dependencies (other plugins)
# Usage: get_plugin_deps "languages/rust"
get_plugin_deps() {
    plugin="$1"
    plugin_path=$(get_plugin_path "$plugin")
    json_get_array "$plugin_path/plugin.json" ".dependencies.plugins"
}

# Check if a plugin is in the selected list
# Usage: is_plugin_selected "languages/rust"
is_plugin_selected() {
    plugin="$1"
    case " $SELECTED_PLUGINS " in
        *" $plugin "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Add a plugin to selected list (if not already present)
# Usage: add_selected_plugin "languages/rust"
add_selected_plugin() {
    plugin="$1"
    if ! is_plugin_selected "$plugin"; then
        SELECTED_PLUGINS="$SELECTED_PLUGINS $plugin"
        SELECTED_PLUGINS=$(printf "%s" "$SELECTED_PLUGINS" | sed 's/^ *//')
    fi
}

# Resolve plugin dependencies recursively
# Adds dependent plugins to SELECTED_PLUGINS
# Usage: resolve_plugin_dependencies "languages/rust"
resolve_plugin_dependencies() {
    plugin="$1"
    visited="$2"

    # Check for circular dependency
    case " $visited " in
        *" $plugin "*)
            error "Circular dependency detected: $plugin"
            return 1
            ;;
    esac

    visited="$visited $plugin"

    # Get plugin dependencies
    deps=$(get_plugin_deps "$plugin")

    for dep in $deps; do
        if [ -n "$dep" ]; then
            if validate_plugin "$dep" 2>/dev/null; then
                # Recursively resolve dependencies
                resolve_plugin_dependencies "$dep" "$visited" || return 1
                # Add dependency to selected plugins
                if ! is_plugin_selected "$dep"; then
                    info "Auto-selecting dependency: $dep"
                    add_selected_plugin "$dep"
                fi
            else
                warn "Plugin dependency '$dep' not found, skipping"
            fi
        fi
    done

    return 0
}

# Enable features required by a plugin
# Usage: enable_plugin_features "languages/rust"
enable_plugin_features() {
    plugin="$1"
    deps=$(get_plugin_feature_deps "$plugin")

    for dep in $deps; do
        case "$dep" in
            git)
                if [ "$FEATURE_GIT" != "y" ]; then
                    info "Auto-enabling feature: git (required by $plugin)"
                    FEATURE_GIT="y"
                fi
                ;;
            github-cli)
                if [ "$FEATURE_GITHUB_CLI" != "y" ]; then
                    info "Auto-enabling feature: github-cli (required by $plugin)"
                    FEATURE_GITHUB_CLI="y"
                fi
                ;;
            uv)
                if [ "$FEATURE_UV" != "y" ]; then
                    info "Auto-enabling feature: uv (required by $plugin)"
                    FEATURE_UV="y"
                fi
                ;;
            claude-code)
                if [ "$FEATURE_CLAUDE_CODE" != "y" ]; then
                    info "Auto-enabling feature: claude-code (required by $plugin)"
                    FEATURE_CLAUDE_CODE="y"
                fi
                ;;
        esac
    done
}

# Source a plugin's plugin.sh
# Usage: source_plugin "languages/rust"
source_plugin() {
    plugin="$1"
    plugin_path=$(get_plugin_path "$plugin")

    if [ -f "$plugin_path/plugin.sh" ]; then
        # shellcheck disable=SC1090
        . "$plugin_path/plugin.sh"
        return 0
    fi
    return 1
}

# Collect all plugin features JSON
# Output: JSON fragment for devcontainer.json features
collect_plugin_features() {
    result=""
    for plugin in $SELECTED_PLUGINS; do
        if source_plugin "$plugin"; then
            if command -v get_features >/dev/null 2>&1; then
                output=$(get_features)
                if [ -n "$output" ]; then
                    if [ -n "$result" ]; then
                        result="${result}\n${output}"
                    else
                        result="$output"
                    fi
                fi
                unset -f get_features 2>/dev/null || true
            fi
        fi
    done
    printf "%s" "$result"
}

# Collect all plugin extensions JSON
# Output: JSON fragment for devcontainer.json extensions
collect_plugin_extensions() {
    result=""
    for plugin in $SELECTED_PLUGINS; do
        if source_plugin "$plugin"; then
            if command -v get_extensions >/dev/null 2>&1; then
                output=$(get_extensions)
                if [ -n "$output" ]; then
                    if [ -n "$result" ]; then
                        result="${result},\n${output}"
                    else
                        result="$output"
                    fi
                fi
                unset -f get_extensions 2>/dev/null || true
            fi
        fi
    done
    printf "%s" "$result"
}

# Collect all plugin Dockerfile extras
# Output: Dockerfile RUN commands
collect_plugin_dockerfile_extras() {
    result=""
    for plugin in $SELECTED_PLUGINS; do
        if source_plugin "$plugin"; then
            if command -v get_dockerfile_extras >/dev/null 2>&1; then
                output=$(get_dockerfile_extras)
                if [ -n "$output" ]; then
                    if [ -n "$result" ]; then
                        result="${result}\n\n${output}"
                    else
                        result="$output"
                    fi
                fi
                unset -f get_dockerfile_extras 2>/dev/null || true
            fi
        fi
    done
    printf "%s" "$result"
}

# Collect all plugin post-setup scripts
# Output: Bash script fragment
collect_plugin_post_setup() {
    result=""
    for plugin in $SELECTED_PLUGINS; do
        if source_plugin "$plugin"; then
            if command -v get_post_setup >/dev/null 2>&1; then
                output=$(get_post_setup)
                if [ -n "$output" ]; then
                    if [ -n "$result" ]; then
                        result="${result}\n\n${output}"
                    else
                        result="$output"
                    fi
                fi
                unset -f get_post_setup 2>/dev/null || true
            fi
        fi
    done
    printf "%s" "$result"
}

# Collect all plugin hooks JSON
# Output: JSON fragment for .claude/settings.json hooks
collect_plugin_hooks() {
    result=""
    for plugin in $SELECTED_PLUGINS; do
        if source_plugin "$plugin"; then
            if command -v get_hooks >/dev/null 2>&1; then
                output=$(get_hooks)
                if [ -n "$output" ]; then
                    if [ -n "$result" ]; then
                        result="${result},\n${output}"
                    else
                        result="$output"
                    fi
                fi
                unset -f get_hooks 2>/dev/null || true
            fi
        fi
    done
    printf "%s" "$result"
}

# -----------------------------------------------------------------------------
# Plugin Variable Configuration
# -----------------------------------------------------------------------------

# Prompt for single selection from options
# Usage: result=$(prompt_select "Select version" "stable nightly 1.75.0" "stable")
prompt_select() {
    prompt_text="$1"
    options="$2"
    default="$3"

    if ! is_interactive; then
        printf "%s" "$default"
        return 0
    fi

    echo "$prompt_text:"
    i=1
    default_num=1
    for opt in $options; do
        if [ "$opt" = "$default" ]; then
            printf "  %d) %s (default)\n" "$i" "$opt"
            default_num=$i
        else
            printf "  %d) %s\n" "$i" "$opt"
        fi
        i=$((i + 1))
    done

    printf "Enter number [%d]: " "$default_num"
    read -r response

    if [ -z "$response" ]; then
        printf "%s" "$default"
        return 0
    fi

    # Get selected option by number
    i=1
    for opt in $options; do
        if [ "$i" = "$response" ]; then
            printf "%s" "$opt"
            return 0
        fi
        i=$((i + 1))
    done

    # Invalid input, return default
    printf "%s" "$default"
}

# Prompt for multiple selection from options
# Usage: result=$(prompt_multiselect "Select components" "clippy rustfmt rust-src" "clippy rustfmt")
prompt_multiselect() {
    prompt_text="$1"
    options="$2"
    defaults="$3"

    if ! is_interactive; then
        printf "%s" "$defaults"
        return 0
    fi

    echo "$prompt_text (comma-separated numbers):"
    i=1
    for opt in $options; do
        marker=" "
        case " $defaults " in
            *" $opt "*) marker="*" ;;
        esac
        printf "  %d) [%s] %s\n" "$i" "$marker" "$opt"
        i=$((i + 1))
    done

    printf "Enter numbers (e.g., 1,2,3) or press Enter for defaults: "
    read -r response

    if [ -z "$response" ]; then
        printf "%s" "$defaults"
        return 0
    fi

    # Parse comma-separated numbers
    result=""
    IFS=','
    for num in $response; do
        num=$(printf "%s" "$num" | tr -d ' ')
        i=1
        for opt in $options; do
            if [ "$i" = "$num" ]; then
                if [ -n "$result" ]; then
                    result="$result $opt"
                else
                    result="$opt"
                fi
                break
            fi
            i=$((i + 1))
        done
    done
    unset IFS

    printf "%s" "$result"
}

# Get variable configuration from plugin.json
# Usage: get_plugin_variables "languages/rust"
get_plugin_variables() {
    plugin="$1"
    plugin_path=$(get_plugin_path "$plugin")

    if has_jq; then
        jq -r '.variables // {} | keys[]' "$plugin_path/plugin.json" 2>/dev/null
    fi
}

# Get variable metadata from plugin.json
# Usage: get_variable_info "languages/rust" "RUST_VERSION" "type"
get_variable_info() {
    plugin="$1"
    var_name="$2"
    field="$3"
    plugin_path=$(get_plugin_path "$plugin")

    if has_jq; then
        jq -r ".variables.${var_name}.${field} // empty" "$plugin_path/plugin.json" 2>/dev/null
    fi
}

# Get variable options as space-separated list
# Usage: get_variable_options "languages/rust" "RUST_VERSION"
get_variable_options() {
    plugin="$1"
    var_name="$2"
    plugin_path=$(get_plugin_path "$plugin")

    if has_jq; then
        jq -r ".variables.${var_name}.options // [] | .[]" "$plugin_path/plugin.json" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
    fi
}

# Get variable default value
# Usage: get_variable_default "languages/rust" "RUST_VERSION"
get_variable_default() {
    plugin="$1"
    var_name="$2"
    plugin_path=$(get_plugin_path "$plugin")

    if has_jq; then
        default=$(jq -r ".variables.${var_name}.default" "$plugin_path/plugin.json" 2>/dev/null)
        # Handle array defaults for multiselect
        if printf "%s" "$default" | grep -q '^\['; then
            jq -r ".variables.${var_name}.default | .[]" "$plugin_path/plugin.json" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
        else
            printf "%s" "$default"
        fi
    fi
}

# Configure all variables for a plugin
# Sets environment variables PLUGIN_VAR_<NAME>
# Usage: configure_plugin_variables "languages/rust"
configure_plugin_variables() {
    plugin="$1"
    plugin_name=$(get_plugin_info "$plugin" "name")

    variables=$(get_plugin_variables "$plugin")
    if [ -z "$variables" ]; then
        return 0
    fi

    echo ""
    info "Configuring $plugin_name variables:"

    for var in $variables; do
        var_type=$(get_variable_info "$plugin" "$var" "type")
        var_desc=$(get_variable_info "$plugin" "$var" "description")
        var_default=$(get_variable_default "$plugin" "$var")
        var_options=$(get_variable_options "$plugin" "$var")

        case "$var_type" in
            select)
                value=$(prompt_select "  $var_desc" "$var_options" "$var_default")
                ;;
            multiselect)
                value=$(prompt_multiselect "  $var_desc" "$var_options" "$var_default")
                ;;
            boolean)
                if [ "$var_default" = "true" ]; then
                    def="y"
                else
                    def="n"
                fi
                if confirm "  $var_desc" "$def"; then
                    value="true"
                else
                    value="false"
                fi
                ;;
            *)
                value=$(prompt_input "  $var_desc" "$var_default")
                ;;
        esac

        # Export as environment variable
        eval "export PLUGIN_VAR_${var}=\"$value\""
        success "  $var = $value"
    done
}

# -----------------------------------------------------------------------------
# Plugin Selection UI
# -----------------------------------------------------------------------------

# Display plugin selection menu for a category
# Usage: select_plugins_from_category "languages"
select_plugins_from_category() {
    category="$1"
    script_dir=$(get_script_dir)
    category_dir="$script_dir/plugins/$category"

    if [ ! -d "$category_dir" ]; then
        return 0
    fi

    # Collect available plugins in this category
    available=""
    for plugin_dir in "$category_dir"/*/; do
        if [ -d "$plugin_dir" ]; then
            plugin_name=$(basename "$plugin_dir")
            plugin_id="$category/$plugin_name"
            if validate_plugin "$plugin_id" 2>/dev/null; then
                available="$available $plugin_id"
            fi
        fi
    done
    available=$(printf "%s" "$available" | sed 's/^ *//')

    if [ -z "$available" ]; then
        info "No plugins available in $category"
        return 0
    fi

    echo ""
    echo "Available $category plugins:"
    i=1
    for plugin in $available; do
        desc=$(get_plugin_info "$plugin" "description")
        name=$(get_plugin_info "$plugin" "name")
        printf "  %d) %s - %s\n" "$i" "$name" "$desc"
        i=$((i + 1))
    done

    printf "Select plugins (comma-separated numbers, or Enter to skip): "
    read -r response

    if [ -z "$response" ]; then
        return 0
    fi

    # Parse selection
    IFS=','
    for num in $response; do
        num=$(printf "%s" "$num" | tr -d ' ')
        i=1
        for plugin in $available; do
            if [ "$i" = "$num" ]; then
                add_selected_plugin "$plugin"
                success "Selected: $plugin"
                break
            fi
            i=$((i + 1))
        done
    done
    unset IFS
}

# Main plugin selection flow
collect_plugin_selection() {
    header "Plugin Selection"

    # Check if any plugins exist
    available_plugins=$(discover_plugins)
    if [ -z "$available_plugins" ]; then
        info "No plugins available"
        return 0
    fi

    echo "Select plugins to include in your DevContainer:"

    # Select from each category
    for category in $PLUGIN_CATEGORIES; do
        select_plugins_from_category "$category"
    done

    # Resolve dependencies
    if [ -n "$SELECTED_PLUGINS" ]; then
        echo ""
        info "Resolving plugin dependencies..."
        for plugin in $SELECTED_PLUGINS; do
            resolve_plugin_dependencies "$plugin" "" || true
            enable_plugin_features "$plugin"
        done

        # Configure variables for each selected plugin
        if has_jq; then
            for plugin in $SELECTED_PLUGINS; do
                configure_plugin_variables "$plugin"
            done
        else
            warn "jq not available, skipping plugin variable configuration"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Feature Configuration
# -----------------------------------------------------------------------------

# Build devcontainer features JSON
build_features_json() {
    features=""

    if [ "$FEATURE_GIT" = "y" ]; then
        features="${features}    \"ghcr.io/devcontainers/features/git:1\": {},\n"
    fi

    if [ "$FEATURE_GITHUB_CLI" = "y" ]; then
        features="${features}    \"ghcr.io/devcontainers/features/github-cli:1\": {\n      \"installDirectlyFromGitHubRelease\": true\n    },\n"
    fi

    if [ "$FEATURE_UV" = "y" ]; then
        features="${features}    \"ghcr.io/devcontainer-community/devcontainer-features/astral.sh-uv:1\": {\n      \"version\": \"latest\"\n    },\n"
    fi

    if [ "$FEATURE_CLAUDE_CODE" = "y" ]; then
        features="${features}    \"ghcr.io/anthropics/devcontainer-features/claude-code:1.0\": {},\n"
    fi

    # Add plugin features
    plugin_features=$(collect_plugin_features)
    if [ -n "$plugin_features" ]; then
        features="${features}${plugin_features}\n"
    fi

    # Remove trailing comma and newline from last feature
    features=$(printf "%s" "$features" | sed '$ s/,$//')

    printf "%s" "$features"
}

# Build VSCode extensions JSON
build_extensions_json() {
    extensions=""

    if [ "$FEATURE_GITHUB_CLI" = "y" ]; then
        extensions="${extensions}        \"mhutchie.git-graph\",\n"
        extensions="${extensions}        \"eamodio.gitlens\",\n"
    fi

    extensions="${extensions}        \"ms-azuretools.vscode-docker\""

    if [ "$FEATURE_CLAUDE_CODE" = "y" ]; then
        extensions="${extensions},\n        \"anthropic.claude-code\""
    fi

    # Add plugin extensions
    plugin_extensions=$(collect_plugin_extensions)
    if [ -n "$plugin_extensions" ]; then
        extensions="${extensions},\n${plugin_extensions}"
    fi

    printf "%s" "$extensions"
}

# -----------------------------------------------------------------------------
# File Generation
# -----------------------------------------------------------------------------

generate_devcontainer_json() {
    header "Generating .devcontainer/devcontainer.json"

    mkdir -p .devcontainer/scripts

    if ! check_overwrite ".devcontainer/devcontainer.json"; then
        warn "Skipped: .devcontainer/devcontainer.json"
        return 0
    fi

    template=$(read_template "plugins/base/devcontainer.json")
    features=$(build_features_json)
    extensions=$(build_extensions_json)

    processed=$(printf "%s" "$template" | \
        sed "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" | \
        sed "s/{{PROJECT_NAME_LOWER}}/${PROJECT_NAME_LOWER}/g")

    # Replace features placeholder
    processed=$(printf "%s" "$processed" | awk -v features="$features" '
        /{{FEATURES}}/ { print features; next }
        { print }
    ')

    # Replace extensions placeholder
    processed=$(printf "%s" "$processed" | awk -v extensions="$extensions" '
        /{{EXTENSIONS}}/ { print extensions; next }
        { print }
    ')

    printf "%s" "$processed" > .devcontainer/devcontainer.json
    success "Created: .devcontainer/devcontainer.json"
}

generate_post_sh() {
    header "Generating .devcontainer/scripts/post.sh"

    mkdir -p .devcontainer/scripts

    if ! check_overwrite ".devcontainer/scripts/post.sh"; then
        warn "Skipped: .devcontainer/scripts/post.sh"
        return 0
    fi

    template=$(read_template "plugins/base/post.sh")

    # Collect plugin post-setup scripts
    plugin_setup=$(collect_plugin_post_setup)

    # Replace language setup placeholder with plugin setup
    if [ -n "$plugin_setup" ]; then
        processed=$(printf "%s" "$template" | awk -v setup="$plugin_setup" '
            /{{LANGUAGE_SETUP}}/ { print setup; next }
            { print }
        ')
    else
        processed=$(printf "%s" "$template" | sed '/{{LANGUAGE_SETUP}}/d')
    fi

    printf "%s" "$processed" > .devcontainer/scripts/post.sh
    chmod +x .devcontainer/scripts/post.sh
    success "Created: .devcontainer/scripts/post.sh"
}

generate_docker_compose() {
    header "Generating docker-compose.yml"

    if ! check_overwrite "docker-compose.yml"; then
        warn "Skipped: docker-compose.yml"
        return 0
    fi

    template=$(read_template "plugins/base/docker-compose.yml")
    processed=$(process_template "$template")

    printf "%s" "$processed" > docker-compose.yml
    success "Created: docker-compose.yml"
}

generate_dockerfile() {
    header "Generating docker/Dockerfile.dev"

    mkdir -p docker

    if ! check_overwrite "docker/Dockerfile.dev"; then
        warn "Skipped: docker/Dockerfile.dev"
        return 0
    fi

    template=$(read_template "plugins/base/Dockerfile.dev")

    # Collect plugin dockerfile extras
    plugin_extras=$(collect_plugin_dockerfile_extras)

    # Replace extras placeholder with plugin extras
    if [ -n "$plugin_extras" ]; then
        processed=$(printf "%s" "$template" | awk -v extras="$plugin_extras" '
            /{{DOCKERFILE_EXTRAS}}/ { print extras; next }
            { print }
        ')
    else
        processed=$(printf "%s" "$template" | sed '/{{DOCKERFILE_EXTRAS}}/d')
    fi

    printf "%s" "$processed" > docker/Dockerfile.dev
    success "Created: docker/Dockerfile.dev"
}

generate_claude_settings() {
    header "Generating .claude/settings.json"

    mkdir -p .claude/scripts
    mkdir -p .claude/commands

    if ! check_overwrite ".claude/settings.json"; then
        warn "Skipped: .claude/settings.json"
        return 0
    fi

    template=$(read_template "plugins/claude/settings.json")

    # Collect plugin hooks
    plugin_hooks=$(collect_plugin_hooks)

    # Replace hooks placeholder with plugin hooks
    if [ -n "$plugin_hooks" ]; then
        processed=$(printf "%s" "$template" | awk -v hooks="$plugin_hooks" '
            /{{HOOKS}}/ { print hooks; next }
            { print }
        ')
    else
        processed=$(printf "%s" "$template" | sed 's/{{HOOKS}}//')
    fi

    printf "%s" "$processed" > .claude/settings.json
    success "Created: .claude/settings.json"
}

generate_deny_check_sh() {
    header "Generating .claude/scripts/deny-check.sh"

    mkdir -p .claude/scripts

    if ! check_overwrite ".claude/scripts/deny-check.sh"; then
        warn "Skipped: .claude/scripts/deny-check.sh"
        return 0
    fi

    template=$(read_template "plugins/claude/deny-check.sh")
    printf "%s" "$template" > .claude/scripts/deny-check.sh
    chmod +x .claude/scripts/deny-check.sh
    success "Created: .claude/scripts/deny-check.sh"
}

generate_claude_commands() {
    header "Generating .claude/commands/*.md"

    mkdir -p .claude/commands

    commands="implement issue pr"
    for cmd in $commands; do
        if ! check_overwrite ".claude/commands/${cmd}.md"; then
            warn "Skipped: .claude/commands/${cmd}.md"
            continue
        fi

        template=$(read_template "plugins/claude/commands/${cmd}.md")
        printf "%s" "$template" > ".claude/commands/${cmd}.md"
        success "Created: .claude/commands/${cmd}.md"
    done
}

generate_github_workflows() {
    header "Generating GitHub Workflows"

    mkdir -p .github/workflows

    # project-integration.yml
    if ! check_overwrite ".github/workflows/project-integration.yml"; then
        warn "Skipped: .github/workflows/project-integration.yml"
    else
        template=$(read_template "plugins/github/project-integration.yml.template")
        printf "%s" "$template" > .github/workflows/project-integration.yml
        success "Created: .github/workflows/project-integration.yml"
    fi

    # pr-project-status.yml
    if ! check_overwrite ".github/workflows/pr-project-status.yml"; then
        warn "Skipped: .github/workflows/pr-project-status.yml"
    else
        template=$(read_template "plugins/github/pr-project-status.yml.template")
        printf "%s" "$template" > .github/workflows/pr-project-status.yml
        success "Created: .github/workflows/pr-project-status.yml"
    fi

    info "Note: Configure PROJECT_TOKEN secret and .github/project.yml for workflows to function"
}

# Generate workflow files from plugins
generate_plugin_workflows() {
    header "Generating Plugin Workflows"

    has_workflows=false

    for plugin in $SELECTED_PLUGINS; do
        plugin_path=$(get_plugin_path "$plugin")
        templates_dir="$plugin_path/templates"

        if [ -d "$templates_dir" ]; then
            for template_file in "$templates_dir"/*.template; do
                if [ -f "$template_file" ]; then
                    has_workflows=true
                    filename=$(basename "$template_file" .template)
                    output_path=".github/workflows/$filename"

                    mkdir -p .github/workflows

                    if ! check_overwrite "$output_path"; then
                        warn "Skipped: $output_path"
                        continue
                    fi

                    # Read and process template
                    template=$(cat "$template_file")
                    processed=$(printf "%s" "$template" | \
                        sed "s/{{PROJECT_NAME}}/${PROJECT_NAME}/g" | \
                        sed "s/{{PROJECT_NAME_LOWER}}/${PROJECT_NAME_LOWER}/g")

                    printf "%s" "$processed" > "$output_path"
                    success "Created: $output_path (from $plugin)"
                fi
            done
        fi
    done

    if [ "$has_workflows" = false ]; then
        info "No plugin workflows to generate"
    fi
}

# -----------------------------------------------------------------------------
# Main Setup Flow
# -----------------------------------------------------------------------------

show_banner() {
    printf "${BOLD}${CYAN}"
    cat << 'EOF'
    ____              ______            __        _
   / __ \___ _   __  / ____/___  ____  / /_____ _(_)___  ___  _____
  / / / / _ \ | / / / /   / __ \/ __ \/ __/ __ `/ / __ \/ _ \/ ___/
 / /_/ /  __/ |/ / / /___/ /_/ / / / / /_/ /_/ / / / / /  __/ /
/_____/\___/|___/  \____/\____/_/ /_/\__/\__,_/_/_/ /_/\___/_/
                                                    Setup v
EOF
    printf "%s${NC}\n" "$SCRIPT_VERSION"
    echo ""
    echo "DevContainer + Claude Code + SuperClaude setup script"
    echo ""
}

check_prerequisites() {
    header "Checking Prerequisites"

    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        success "curl is available"
    elif command -v wget >/dev/null 2>&1; then
        success "wget is available"
    else
        warn "Neither curl nor wget found. Remote templates may not work."
    fi

    # Check for Docker (optional)
    if command -v docker >/dev/null 2>&1; then
        success "Docker is available"
    else
        warn "Docker not found. DevContainer requires Docker."
    fi

    # Check for git
    if command -v git >/dev/null 2>&1; then
        success "git is available"
    else
        warn "git not found. Version control will not work."
    fi
}

collect_project_info() {
    header "Project Configuration"

    # Get project name
    default_name=$(basename "$(pwd)")
    PROJECT_NAME=$(prompt_input "Enter project name" "$default_name")
    PROJECT_NAME_LOWER=$(to_kebab "$PROJECT_NAME")

    echo ""
    info "Project name: $PROJECT_NAME"
    info "Service name: $PROJECT_NAME_LOWER"
}

collect_feature_selection() {
    header "Feature Selection"

    echo "Select DevContainer features to include:"
    echo ""

    # Git feature
    if confirm "Include git feature?" "y"; then
        FEATURE_GIT="y"
        success "git: enabled"
    else
        FEATURE_GIT="n"
        info "git: disabled"
    fi

    # GitHub CLI feature
    if confirm "Include GitHub CLI feature?" "y"; then
        FEATURE_GITHUB_CLI="y"
        success "github-cli: enabled"
    else
        FEATURE_GITHUB_CLI="n"
        info "github-cli: disabled"
    fi

    # Claude Code feature
    if confirm "Include Claude Code feature?" "y"; then
        FEATURE_CLAUDE_CODE="y"
        success "claude-code: enabled"
    else
        FEATURE_CLAUDE_CODE="n"
        info "claude-code: disabled"
    fi

    # uv feature (required for SuperClaude)
    if confirm "Include uv feature? (required for SuperClaude)" "y"; then
        FEATURE_UV="y"
        success "uv: enabled"
    else
        FEATURE_UV="n"
        info "uv: disabled"
        warn "SuperClaude will not be available without uv"
    fi

    echo ""
    echo "Select additional features:"
    echo ""

    # GitHub Project workflows
    if confirm "Include GitHub Project workflows? (requires erd)" "n"; then
        FEATURE_GITHUB_WORKFLOWS="y"
        success "github-workflows: enabled"
    else
        FEATURE_GITHUB_WORKFLOWS="n"
        info "github-workflows: disabled"
    fi
}

generate_files() {
    header "Generating Files"

    generate_devcontainer_json
    generate_post_sh
    generate_docker_compose
    generate_dockerfile
    generate_claude_settings
    generate_deny_check_sh
    generate_claude_commands

    # Optional: GitHub workflows (legacy)
    if [ "$FEATURE_GITHUB_WORKFLOWS" = "y" ]; then
        generate_github_workflows
    fi

    # Generate plugin workflows (new plugin system)
    if [ -n "$SELECTED_PLUGINS" ]; then
        generate_plugin_workflows
    fi
}

show_summary() {
    header "Setup Complete!"

    echo "Generated files:"
    echo "  - .devcontainer/devcontainer.json"
    echo "  - .devcontainer/scripts/post.sh"
    echo "  - docker-compose.yml"
    echo "  - docker/Dockerfile.dev"
    echo "  - .claude/settings.json"
    echo "  - .claude/scripts/deny-check.sh"
    echo "  - .claude/commands/implement.md"
    echo "  - .claude/commands/issue.md"
    echo "  - .claude/commands/pr.md"
    if [ "$FEATURE_GITHUB_WORKFLOWS" = "y" ]; then
        echo "  - .github/workflows/project-integration.yml"
        echo "  - .github/workflows/pr-project-status.yml"
    fi
    echo ""
    echo "Features enabled:"
    [ "$FEATURE_GIT" = "y" ] && echo "  - git"
    [ "$FEATURE_GITHUB_CLI" = "y" ] && echo "  - github-cli"
    [ "$FEATURE_CLAUDE_CODE" = "y" ] && echo "  - claude-code"
    [ "$FEATURE_UV" = "y" ] && echo "  - uv (for SuperClaude)"
    [ "$FEATURE_GITHUB_WORKFLOWS" = "y" ] && echo "  - github-workflows (erd integration)"

    # Show selected plugins
    if [ -n "$SELECTED_PLUGINS" ]; then
        echo ""
        echo "Plugins installed:"
        for plugin in $SELECTED_PLUGINS; do
            plugin_desc=$(get_plugin_info "$plugin" "description")
            echo "  - $plugin: $plugin_desc"
        done
    fi

    echo ""
    echo "Next steps:"
    echo "  1. Open this folder in VS Code"
    echo "  2. Click 'Reopen in Container' when prompted"
    echo "  3. Wait for the container to build and start"
    echo "  4. Run 'claude' to start using Claude Code"
    if [ "$FEATURE_GITHUB_WORKFLOWS" = "y" ]; then
        echo ""
        echo "GitHub Workflows setup:"
        echo "  5. Create PROJECT_TOKEN secret in repository settings"
        echo "  6. Create .github/project.yml with project configuration"
    fi
    echo ""
}

main() {
    show_banner
    check_prerequisites
    collect_project_info
    collect_feature_selection
    collect_plugin_selection
    generate_files
    show_summary
}

main "$@"
