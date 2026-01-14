#!/bin/bash
# =============================================================================
# Devcontainer Boilerplate Setup Script
# =============================================================================
# This script creates a new Devcontainer environment for your project.
#
# Usage:
#   ./setup.sh                    # Interactive mode
#   ./setup.sh --help             # Show help
#   ./setup.sh --dry-run          # Preview without creating files
#   ./setup.sh my-project         # Non-interactive mode with project name
#   ./setup.sh --lang node,python # Select specific languages
#   ./setup.sh --playwright       # Include Playwright E2E testing
#
# =============================================================================

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Source common library
source "${SCRIPT_DIR}/scripts/lib/common.sh"

# Plugin tracking
declare -a LOADED_PLUGINS=()
declare -a PLUGIN_NAMES=()

# Language selection
declare -a SELECTED_LANGUAGES=()
declare -a AVAILABLE_LANGUAGES=()
declare -A LANGUAGE_DISPLAY_NAMES=(
    ["node"]="Node.js 22.x (LTS)"
    ["python"]="Python 3.x"
    ["rust"]="Rust"
    ["deno"]="Deno"
)
PLAYWRIGHT_ENABLED=false

DOCKER_ENABLED=false

# Core plugins that are always loaded
declare -a CORE_PLUGINS=("core" "claude")

# =============================================================================
# Help Function
# =============================================================================

show_help() {
    cat << 'EOF'
Devcontainer Boilerplate Setup Script

Usage:
    ./setup.sh [OPTIONS] [PROJECT_NAME]

Options:
    -h, --help          Show this help message
    -d, --dry-run       Preview files without creating them
    -y, --yes           Skip confirmation prompts
    --lang <languages>  Select language template(s), comma-separated
                        (e.g., --lang node or --lang node,python)
    --playwright        Include Playwright for E2E testing
    --docker            Include Docker-in-Docker (DinD) support

Arguments:
    PROJECT_NAME        Name for your project (optional, will prompt if not provided)

Available Languages:
    node                Node.js 22.x (LTS) [default]
    python              Python 3.x
    rust                Rust
    deno                Deno

Examples:
    ./setup.sh                              # Interactive mode
    ./setup.sh my-project                   # Create project named 'my-project'
    ./setup.sh --dry-run my-app             # Preview what would be created
    ./setup.sh --lang node                  # Node.js only
    ./setup.sh --lang node,python           # Node.js and Python
    ./setup.sh --lang node --playwright     # Node.js with Playwright
    ./setup.sh --lang node --docker         # Node.js with Docker-in-Docker
    ./setup.sh --lang node --docker --playwright  # Node.js with both
    ./setup.sh my-project --lang node -y    # Non-interactive mode

Generated Files:
    .devcontainer/
        devcontainer.json           # VS Code Devcontainer configuration
        scripts/
            post.sh                 # Post-creation setup script
    docker/
        Dockerfile.dev              # Development Docker image
    docker-compose.yml              # Docker Compose configuration
    .claude/
        settings.json               # Claude Code settings
        commands/                   # Custom slash commands
            issue.md                # Issue creation command
            implement.md            # Implementation command
            pr.md                   # Pull request command
        scripts/
            deny-check.sh           # Command deny check script
    CLAUDE.md                       # Claude Code project context

Features Included:
    - Git and GitHub CLI
    - Claude Code CLI with custom commands
    - Selected language runtime(s)
    - VS Code extensions for development
    - Playwright (optional) for E2E testing
    - Docker-in-Docker (optional) for container development

EOF
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_project_name() {
    local name="$1"

    # Check if empty
    if [[ -z "$name" ]]; then
        print_error "Project name cannot be empty"
        return 1
    fi

    # Check for valid characters (alphanumeric, dash, underscore)
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        print_error "Project name must start with a letter and contain only letters, numbers, dashes, and underscores"
        return 1
    fi

    # Check length
    if [[ ${#name} -gt 50 ]]; then
        print_error "Project name must be 50 characters or less"
        return 1
    fi

    return 0
}

check_dependencies() {
    local missing_deps=()

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install the missing dependencies:"
        print_info "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        print_info "  macOS:         brew install ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# Language Selection Functions
# =============================================================================

# Discover available language plugins
discover_available_languages() {
    AVAILABLE_LANGUAGES=()

    for plugin_dir in "${TEMPLATES_DIR}"/*/; do
        local plugin_name
        plugin_name=$(basename "$plugin_dir")

        # Skip core plugins
        if [[ " ${CORE_PLUGINS[*]} " =~ " ${plugin_name} " ]]; then
            continue
        fi

        # Skip optional feature plugins (handled separately)
        if [[ "$plugin_name" == "playwright" ]] || [[ "$plugin_name" == "docker" ]]; then
            continue
        fi

        # Check if plugin.sh exists
        if [[ -f "${plugin_dir}plugin.sh" ]]; then
            AVAILABLE_LANGUAGES+=("$plugin_name")
        fi
    done
}

# Validate user-provided languages
validate_languages() {
    local languages=("$@")
    local invalid=()

    for lang in "${languages[@]}"; do
        local found=false
        for available in "${AVAILABLE_LANGUAGES[@]}"; do
            if [[ "$lang" == "$available" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == false ]]; then
            invalid+=("$lang")
        fi
    done

    if [[ ${#invalid[@]} -gt 0 ]]; then
        print_error "Unknown language(s): ${invalid[*]}"
        print_info "Available languages: ${AVAILABLE_LANGUAGES[*]}"
        return 1
    fi

    return 0
}

# Parse comma-separated language list
parse_language_list() {
    local lang_string="$1"
    local -a result=()

    # Split by comma
    IFS=',' read -ra result <<< "$lang_string"

    # Trim whitespace from each element
    for i in "${!result[@]}"; do
        result[$i]=$(echo "${result[$i]}" | tr -d '[:space:]')
    done

    echo "${result[@]}"
}

# Get display name for a language
get_language_display_name() {
    local lang="$1"

    if [[ -n "${LANGUAGE_DISPLAY_NAMES[$lang]}" ]]; then
        echo "${LANGUAGE_DISPLAY_NAMES[$lang]}"
    else
        echo "$lang"
    fi
}

# Interactive language selection prompt
prompt_language_selection() {
    local -a languages=("${AVAILABLE_LANGUAGES[@]}")
    local -a selected=()
    local current=0
    local num_languages=${#languages[@]}

    # Initialize with node selected by default if available
    for i in "${!languages[@]}"; do
        if [[ "${languages[$i]}" == "node" ]]; then
            selected[$i]=1
        else
            selected[$i]=0
        fi
    done

    echo ""
    print_info "Select language template(s) [multiple selection allowed]:"
    echo "  (Use arrow keys to navigate, Space to toggle, Enter to confirm)"
    echo ""

    # Hide cursor
    tput civis 2>/dev/null || true

    # Trap to restore cursor on exit
    trap 'tput cnorm 2>/dev/null || true' EXIT

    while true; do
        # Move cursor up to redraw
        if [[ $current -gt 0 ]] || [[ ${selected[*]} != "" ]]; then
            for ((i=0; i<num_languages; i++)); do
                tput cuu1 2>/dev/null || echo -en "\033[1A"
            done
        fi

        # Draw options
        for i in "${!languages[@]}"; do
            local lang="${languages[$i]}"
            local display_name
            display_name=$(get_language_display_name "$lang")
            local marker="[ ]"
            local default_marker=""

            if [[ "${selected[$i]}" -eq 1 ]]; then
                marker="[x]"
            fi

            if [[ "$lang" == "node" ]]; then
                default_marker=" [default]"
            fi

            if [[ $i -eq $current ]]; then
                echo -e "  > ${marker} ${display_name}${default_marker}    "
            else
                echo -e "    ${marker} ${display_name}${default_marker}    "
            fi
        done

        # Read single keypress
        read -rsn1 key

        # Handle arrow keys (escape sequences)
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.1 key
            case "$key" in
                '[A') # Up arrow
                    ((current--)) || true
                    if [[ $current -lt 0 ]]; then
                        current=$((num_languages - 1))
                    fi
                    ;;
                '[B') # Down arrow
                    ((current++)) || true
                    if [[ $current -ge $num_languages ]]; then
                        current=0
                    fi
                    ;;
            esac
        elif [[ "$key" == ' ' ]]; then
            # Toggle selection
            if [[ "${selected[$current]}" -eq 1 ]]; then
                selected[$current]=0
            else
                selected[$current]=1
            fi
        elif [[ "$key" == '' ]]; then
            # Enter pressed - confirm selection
            break
        fi
    done

    # Restore cursor
    tput cnorm 2>/dev/null || true
    trap - EXIT

    # Build selected languages array
    SELECTED_LANGUAGES=()
    for i in "${!languages[@]}"; do
        if [[ "${selected[$i]}" -eq 1 ]]; then
            SELECTED_LANGUAGES+=("${languages[$i]}")
        fi
    done

    # Default to node if nothing selected
    if [[ ${#SELECTED_LANGUAGES[@]} -eq 0 ]]; then
        SELECTED_LANGUAGES=("node")
        print_warning "No language selected, defaulting to Node.js"
    fi

    echo ""
    print_success "Selected: ${SELECTED_LANGUAGES[*]}"
}

# Interactive Playwright selection prompt
prompt_playwright() {
    echo ""
    echo -n "Include Playwright for E2E testing? [y/N]: "
    read -r response

    if [[ "$response" =~ ^[Yy] ]]; then
        PLAYWRIGHT_ENABLED=true
        print_success "Playwright enabled"
    else
        PLAYWRIGHT_ENABLED=false
    fi
}

# =============================================================================
# Plugin Functions
# =============================================================================

# Load a single plugin and verify it has required functions
load_plugin() {
    local plugin_path="$1"

    # Source the plugin
    if ! source "$plugin_path"; then
        print_error "Failed to load plugin: $plugin_path"
        return 1
    fi

    # Verify required functions exist
    if ! declare -f plugin_name > /dev/null; then
        print_error "Plugin missing required function 'plugin_name': $plugin_path"
        return 1
    fi

    if ! declare -f plugin_description > /dev/null; then
        print_error "Plugin missing required function 'plugin_description': $plugin_path"
        return 1
    fi

    return 0
}

# Load selected plugins in correct order
load_selected_plugins() {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()

    # Define load order: core -> selected languages -> claude -> playwright
    local -a load_order=()

    # 1. Core plugin first
    if [[ -f "${TEMPLATES_DIR}/core/plugin.sh" ]]; then
        load_order+=("${TEMPLATES_DIR}/core/plugin.sh")
    fi

    # 2. Selected language plugins
    for lang in "${SELECTED_LANGUAGES[@]}"; do
        local plugin_path="${TEMPLATES_DIR}/${lang}/plugin.sh"
        if [[ -f "$plugin_path" ]]; then
            load_order+=("$plugin_path")
        fi
    done

    # 3. Claude plugin
    if [[ -f "${TEMPLATES_DIR}/claude/plugin.sh" ]]; then
        load_order+=("${TEMPLATES_DIR}/claude/plugin.sh")
    fi

    # 4. Docker plugin (if enabled)
    if [[ "$DOCKER_ENABLED" == true ]]; then
        local docker_path="${TEMPLATES_DIR}/docker/plugin.sh"
        if [[ -f "$docker_path" ]]; then
            load_order+=("$docker_path")
        else
            print_warning "Docker plugin not found, skipping"
        fi
    fi

    # 5. Playwright plugin (if enabled)
    if [[ "$PLAYWRIGHT_ENABLED" == true ]]; then
        local playwright_path="${TEMPLATES_DIR}/playwright/plugin.sh"
        if [[ -f "$playwright_path" ]]; then
            load_order+=("$playwright_path")
        else
            print_warning "Playwright plugin not found, skipping"
        fi
    fi

    # Load plugins
    for plugin_path in "${load_order[@]}"; do
        if load_plugin "$plugin_path"; then
            LOADED_PLUGINS+=("$plugin_path")
            PLUGIN_NAMES+=("$(plugin_name)")
        fi
    done

    if [[ ${#LOADED_PLUGINS[@]} -eq 0 ]]; then
        print_error "No valid plugins loaded"
        return 1
    fi

    return 0
}

# Execute a specific hook for all loaded plugins
execute_plugins_hook() {
    local hook_name="$1"
    local target_dir="$2"

    for plugin_path in "${LOADED_PLUGINS[@]}"; do
        # Unset previous hook functions to prevent carryover
        unset -f plugin_pre_copy plugin_copy plugin_post_copy plugin_validate 2>/dev/null || true

        # Source plugin to get its functions
        source "$plugin_path"
        local name
        name=$(plugin_name)

        # Execute the hook if it exists
        if declare -f "$hook_name" > /dev/null; then
            if ! "$hook_name" "$target_dir"; then
                print_error "Plugin '${name}' failed during ${hook_name}"
                return 1
            fi
        fi
    done

    return 0
}

# =============================================================================
# Main Functions
# =============================================================================

prompt_project_name() {
    local project_name=""

    while true; do
        echo -n "Enter project name: "
        read -r project_name

        if validate_project_name "$project_name"; then
            echo "$project_name"
            return 0
        fi

        echo ""
    done
}

show_preview() {
    local project_name="$1"

    echo ""
    print_info "Preview of files to be created:"
    echo ""
    echo "  ${project_name}/"
    echo "  ├── .devcontainer/"
    echo "  │   ├── devcontainer.json"
    echo "  │   └── scripts/"
    echo "  │       └── post.sh"
    echo "  ├── docker/"
    echo "  │   └── Dockerfile.dev"
    echo "  ├── docker-compose.yml"
    echo "  ├── .claude/"
    echo "  │   ├── settings.json"
    echo "  │   ├── commands/"
    echo "  │   │   ├── issue.md"
    echo "  │   │   ├── implement.md"
    echo "  │   │   └── pr.md"
    echo "  │   └── scripts/"
    echo "  │       └── deny-check.sh"
    echo "  └── CLAUDE.md"
    echo ""

    # Show selected languages
    print_info "Selected languages: ${SELECTED_LANGUAGES[*]}"

    # Show optional feature status
    if [[ "$DOCKER_ENABLED" == true ]]; then
        print_info "Docker-in-Docker: enabled"
    fi
    if [[ "$PLAYWRIGHT_ENABLED" == true ]]; then
        print_info "Playwright: enabled"
    fi
    echo ""

    # Show loaded plugins
    print_info "Plugins to be applied:"
    for plugin_path in "${LOADED_PLUGINS[@]}"; do
        source "$plugin_path"
        echo "  - $(plugin_name): $(plugin_description)"
    done
    echo ""
}

show_completion() {
    local project_name="$1"

    echo ""
    echo -e "${COLOR_GREEN}╔═══════════════════════════════════════════════════════════════════╗${COLOR_NC}"
    echo -e "${COLOR_GREEN}║                    Setup Complete!                                ║${COLOR_NC}"
    echo -e "${COLOR_GREEN}╚═══════════════════════════════════════════════════════════════════╝${COLOR_NC}"
    echo ""
    print_success "Devcontainer environment created successfully!"
    echo ""
    echo "Configuration:"
    echo "  Languages:   ${SELECTED_LANGUAGES[*]}"
    if [[ "$DOCKER_ENABLED" == true ]]; then
        echo "  Docker:      enabled"
    fi
    if [[ "$PLAYWRIGHT_ENABLED" == true ]]; then
        echo "  Playwright:  enabled"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Open the project in VS Code"
    echo "  2. Click 'Reopen in Container' when prompted"
    echo "     Or use Command Palette: 'Dev Containers: Reopen in Container'"
    echo ""
    echo "Claude Code commands available:"
    echo "  /issue      - Create a GitHub Issue"
    echo "  /implement  - Implement a GitHub Issue"
    echo "  /pr         - Create a Pull Request"
    echo ""
    echo "Project location: $(pwd)"
    echo ""
}

main() {
    local project_name=""
    local dry_run=false
    local skip_confirm=false
    local lang_arg=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -y|--yes)
                skip_confirm=true
                shift
                ;;
            --lang)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    print_error "--lang requires a language argument"
                    exit 1
                fi
                lang_arg="$2"
                shift 2
                ;;
            --playwright)
                PLAYWRIGHT_ENABLED=true
                shift
                ;;
            --docker)
                DOCKER_ENABLED=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                project_name="$1"
                shift
                ;;
        esac
    done

    print_header

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Discover available languages
    discover_available_languages

    if [[ ${#AVAILABLE_LANGUAGES[@]} -eq 0 ]]; then
        print_warning "No language plugins found, using core plugins only"
    fi

    # Handle language selection
    if [[ -n "$lang_arg" ]]; then
        # Parse and validate provided languages
        read -ra SELECTED_LANGUAGES <<< "$(parse_language_list "$lang_arg")"
        if ! validate_languages "${SELECTED_LANGUAGES[@]}"; then
            exit 1
        fi
        print_success "Using languages: ${SELECTED_LANGUAGES[*]}"
    elif [[ "$skip_confirm" == true ]]; then
        # Non-interactive mode: default to node
        SELECTED_LANGUAGES=("node")
        print_info "Using default language: node"
    else
        # Interactive language selection
        if [[ ${#AVAILABLE_LANGUAGES[@]} -gt 0 ]]; then
            prompt_language_selection
        fi
    fi

    # Handle Playwright selection (only prompt in interactive mode without --lang)
    if [[ "$PLAYWRIGHT_ENABLED" == true ]]; then
        print_info "Playwright enabled via --playwright flag"
    elif [[ "$skip_confirm" != true ]] && [[ -z "$lang_arg" ]] && [[ -f "${TEMPLATES_DIR}/playwright/plugin.sh" ]]; then
        prompt_playwright
    fi

    # Load selected plugins
    print_info "Loading plugins..."
    if ! load_selected_plugins; then
        exit 1
    fi
    print_success "Loaded ${#LOADED_PLUGINS[@]} plugin(s): ${PLUGIN_NAMES[*]}"

    # Get project name if not provided
    if [[ -z "$project_name" ]]; then
        project_name=$(prompt_project_name)
    else
        if ! validate_project_name "$project_name"; then
            exit 1
        fi
    fi

    # Show preview
    show_preview "$project_name"

    # Dry run mode
    if [[ "$dry_run" == true ]]; then
        print_warning "Dry run mode - no files will be created"
        exit 0
    fi

    # Confirm unless --yes flag
    if [[ "$skip_confirm" != true ]]; then
        echo -n "Proceed with setup? [Y/n]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            print_warning "Setup cancelled"
            exit 0
        fi
    fi

    echo ""

    # Create target directory (current directory)
    local target_dir="."

    # Check if files already exist
    if [[ -d ".devcontainer" ]] || [[ -f "docker-compose.yml" ]]; then
        print_warning "Some files already exist in the current directory"
        echo -n "Overwrite existing files? [y/N]: "
        read -r overwrite
        if [[ ! "$overwrite" =~ ^[Yy] ]]; then
            print_warning "Setup cancelled"
            exit 0
        fi
    fi

    # Execute plugin hooks in order
    print_info "Executing plugin pre-copy hooks..."
    execute_plugins_hook "plugin_pre_copy" "$target_dir"

    print_info "Executing plugin copy hooks..."
    execute_plugins_hook "plugin_copy" "$target_dir"

    print_info "Executing plugin post-copy hooks..."
    execute_plugins_hook "plugin_post_copy" "$target_dir"

    # Finalization
    replace_placeholders "$target_dir" "$project_name"
    update_gitignore "$target_dir"

    # Execute validation hooks
    print_info "Executing plugin validation hooks..."
    execute_plugins_hook "plugin_validate" "$target_dir"

    show_completion "$project_name"
}

# Run main function
main "$@"
