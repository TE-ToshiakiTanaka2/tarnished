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

# =============================================================================
# Help Function
# =============================================================================

show_help() {
    cat << 'EOF'
Devcontainer Boilerplate Setup Script

Usage:
    ./setup.sh [OPTIONS] [PROJECT_NAME]

Options:
    -h, --help      Show this help message
    -d, --dry-run   Preview files without creating them
    -y, --yes       Skip confirmation prompts

Arguments:
    PROJECT_NAME    Name for your project (optional, will prompt if not provided)

Examples:
    ./setup.sh                      # Interactive mode
    ./setup.sh my-project           # Create project named 'my-project'
    ./setup.sh --dry-run my-app     # Preview what would be created

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
    - Node.js 22.x (LTS)
    - VS Code extensions for development

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

# Load all discovered plugins
load_all_plugins() {
    local plugins=()
    # Use mapfile to safely handle paths with spaces
    mapfile -t plugins < <(for p in "${TEMPLATES_DIR}"/*/plugin.sh; do [[ -f "$p" ]] && echo "$p"; done)

    if [[ ${#plugins[@]} -eq 0 ]]; then
        print_error "No plugins found in ${TEMPLATES_DIR}"
        return 1
    fi

    for plugin_path in "${plugins[@]}"; do
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

    # Discover and load plugins
    print_info "Discovering plugins..."
    if ! load_all_plugins; then
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
