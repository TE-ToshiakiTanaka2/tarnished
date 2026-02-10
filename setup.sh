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
#   ./setup.sh --lang rust        # Select specific language
#   ./setup.sh --github-actions   # Include GitHub Project integration
#
# Remote Execution:
#   curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
#   curl -fsSL ... | bash -s -- [OPTIONS] [PROJECT_NAME]
#
# =============================================================================

# =============================================================================
# Remote Execution Bootstrap
# =============================================================================

REMOTE_REPO_URL="${DEVCONTAINER_REPO_URL:-https://github.com/TE-ToshiakiTanaka2/tarnished.git}"
REMOTE_BRANCH="${DEVCONTAINER_BRANCH:-develop}"

# Check if running from pipe (curl | bash)
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    echo "============================================================="
    echo "  Devcontainer Boilerplate - Remote Execution"
    echo "============================================================="
    echo ""

    # Check for git
    if ! command -v git &> /dev/null; then
        echo "Error: git is required for remote execution"
        echo "Please install git and try again:"
        echo "  Ubuntu/Debian: sudo apt-get install git"
        echo "  macOS:         brew install git"
        exit 1
    fi

    # Create temporary directory
    BOOTSTRAP_TEMP_DIR=$(mktemp -d)

    # Cleanup function
    cleanup_bootstrap() {
        if [[ -n "${BOOTSTRAP_TEMP_DIR:-}" ]] && [[ -d "$BOOTSTRAP_TEMP_DIR" ]]; then
            rm -rf "$BOOTSTRAP_TEMP_DIR"
        fi
    }

    # Register cleanup trap
    trap cleanup_bootstrap EXIT

    # Clone repository
    echo "Downloading setup files..."
    if ! git clone --depth 1 --branch "$REMOTE_BRANCH" --quiet "$REMOTE_REPO_URL" "$BOOTSTRAP_TEMP_DIR"; then
        echo "Error: Failed to download setup files"
        echo "Please check your network connection and try again"
        exit 1
    fi

    echo "Starting setup..."
    echo ""

    # Execute local setup.sh with all arguments
    exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"
fi

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# Source common library
source "${SCRIPT_DIR}/scripts/lib/common.sh"

# =============================================================================
# Global Variables
# =============================================================================

# Plugin tracking
declare -a LOADED_PLUGINS=()
declare -a PLUGIN_NAMES=()

# Language selection
declare -a SELECTED_LANGUAGES=()
declare -a AVAILABLE_LANGUAGES=("rust" "python" "node" "deno")
declare -A LANGUAGE_DISPLAY_NAMES=(
    ["rust"]="Rust"
    ["python"]="Python"
    ["node"]="Node.js/TypeScript"
    ["deno"]="Deno"
)

# Service selection
declare -a SELECTED_SERVICES=()
declare -a AVAILABLE_SERVICES=("postgresql")
declare -A SERVICE_DISPLAY_NAMES=(
    ["postgresql"]="PostgreSQL 16"
)

# Feature flags
GITHUB_ACTIONS_ENABLED=false
AUTO_TAG_ENABLED=false
CODEX_ENABLED=false
POSTGRESQL_ENABLED=false
DRY_RUN=false
SKIP_CONFIRM=false

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

Prerequisites:
    - Git repository cloned (e.g., via ghq)
    - 'origin' remote configured
    - GitHub CLI (gh) installed

Options:
    -h, --help          Show this help message
    -d, --dry-run       Preview files without creating them
    -y, --yes           Skip confirmation prompts
    --lang <language>   Select language template (can be specified multiple times)
    --codex             Include OpenAI Codex CLI integration (code review)
    --postgresql        Include PostgreSQL database service
    --github-actions    Include GitHub Project integration (requires erd CLI)
    --overwrite         Overwrite existing files without confirmation

Arguments:
    PROJECT_NAME        Name for your project (optional, will prompt if not provided)

Available Languages:
    rust                Rust
    python              Python (uv, ruff, mypy, pytest)
    node                Node.js/TypeScript (pnpm, Biome, Vitest)
    deno                Deno (built-in fmt, lint, test)

Available Services:
    postgresql          PostgreSQL 16 database with psql client

Examples:
    ./setup.sh                              # Interactive mode
    ./setup.sh my-project                   # Create project named 'my-project'
    ./setup.sh --dry-run my-app             # Preview what would be created
    ./setup.sh --lang rust                  # Rust only
    ./setup.sh --lang python                # Python only
    ./setup.sh --lang rust --lang python    # Rust + Python
    ./setup.sh --lang rust --codex          # Rust with Codex CLI code review
    ./setup.sh --lang rust --postgresql     # Rust with PostgreSQL
    ./setup.sh --lang rust --github-actions # Rust with GitHub Project integration
    ./setup.sh my-project --lang rust -y    # Non-interactive mode
    ./setup.sh --overwrite                  # Overwrite existing files

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
        scripts/                    # Helper scripts
    CLAUDE.md                       # Claude Code project context

Remote Execution:
    Run directly from GitHub without cloning first:

    curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash

    With options:
    curl -fsSL ... | bash -s -- --lang rust --github-actions

    Requirements: git, curl, jq

EOF
}

# =============================================================================
# GitHub Operations Functions
# =============================================================================

check_gh_auth() {
    print_info "Checking GitHub CLI authentication..."

    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Please install: https://cli.github.com/"
        return 1
    fi

    if ! gh auth status </dev/null &>/dev/null; then
        print_warning "GitHub CLI is not authenticated"
        print_info "Starting authentication flow..."
        if ! gh auth login </dev/tty; then
            print_error "GitHub authentication failed"
            return 1
        fi
    fi

    print_success "GitHub CLI authenticated"
    return 0
}

setup_develop_branch() {
    print_info "Setting up develop branch..."

    if ! git rev-parse --git-dir &>/dev/null; then
        print_error "Not a git repository"
        return 1
    fi

    if ! git remote get-url origin &>/dev/null; then
        print_error "No 'origin' remote configured"
        return 1
    fi

    print_info "Fetching latest from remote..."
    git fetch origin 2>/dev/null || true

    if git show-ref --verify --quiet refs/heads/develop; then
        print_info "Develop branch exists locally, checking out..."
        git checkout develop
    elif git show-ref --verify --quiet refs/remotes/origin/develop; then
        print_info "Develop branch exists on remote, checking out..."
        git checkout -b develop origin/develop
    else
        print_info "Creating new develop branch..."
        git checkout -b develop
    fi

    print_success "Now on develop branch"
    return 0
}

set_default_branch() {
    print_info "Setting develop as default branch on GitHub..."

    if gh repo edit --default-branch develop </dev/null 2>/dev/null; then
        print_success "Default branch set to develop"
    else
        print_warning "Could not set default branch (insufficient permissions or not a GitHub repo)"
        if git push -u origin develop 2>/dev/null; then
            print_success "Develop branch pushed to remote"
        else
            print_warning "Could not push to remote"
        fi
    fi

    return 0
}

setup_github_labels() {
    print_info "Setting up GitHub labels..."

    local -a labels=(
        "feature|0E8A16|New feature"
        "bugfix|D73A4A|Bug fix"
        "patch|FBCA04|Small changes"
        "refactor|1D76DB|Code refactoring"
        "documentation|0075CA|Documentation"
    )

    local created=0
    local skipped=0

    for label_def in "${labels[@]}"; do
        IFS='|' read -r name color description <<< "$label_def"

        if gh label create "$name" --color "$color" --description "$description" </dev/null 2>/dev/null; then
            print_success "  Created label: $name"
            ((created++)) || true
        else
            ((skipped++)) || true
        fi
    done

    if [[ $created -gt 0 ]]; then
        print_success "Created $created label(s), skipped $skipped existing"
    else
        print_info "All labels already exist ($skipped skipped)"
    fi

    return 0
}

auto_commit() {
    local message="$1"

    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        print_info "No changes to commit"
        return 0
    fi

    git add -A
    if git commit -m "$message" 2>/dev/null; then
        print_success "Committed: $message"
    else
        print_info "Nothing to commit"
    fi

    return 0
}

setup_github_repository() {
    print_section "GitHub Repository Setup"

    if ! check_gh_auth; then
        print_error "GitHub setup failed: authentication required"
        return 1
    fi

    if ! setup_develop_branch; then
        print_error "GitHub setup failed: could not setup develop branch"
        return 1
    fi

    set_default_branch
    setup_github_labels

    print_success "GitHub repository setup complete"
    return 0
}

# =============================================================================
# Validation Functions
# =============================================================================

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

get_default_project_name() {
    local dir_name
    dir_name=$(basename "$(pwd)")

    if validate_project_name "$dir_name" 2>/dev/null; then
        echo "$dir_name"
    else
        echo ""
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

    local -a load_order=()

    # 1. Core plugin first
    if [[ -f "${TEMPLATES_DIR}/core/plugin.sh" ]]; then
        load_order+=("${TEMPLATES_DIR}/core/plugin.sh")
    fi

    # 2. Selected language plugins
    for lang in "${SELECTED_LANGUAGES[@]}"; do
        local plugin_path="${TEMPLATES_DIR}/languages/${lang}/plugin.sh"
        if [[ -f "$plugin_path" ]]; then
            load_order+=("$plugin_path")
        fi
    done

    # 3. Selected service plugins
    for svc in "${SELECTED_SERVICES[@]}"; do
        local plugin_path="${TEMPLATES_DIR}/services/${svc}/plugin.sh"
        if [[ -f "$plugin_path" ]]; then
            load_order+=("$plugin_path")
        fi
    done

    # 4. Claude plugin
    if [[ -f "${TEMPLATES_DIR}/claude/plugin.sh" ]]; then
        load_order+=("${TEMPLATES_DIR}/claude/plugin.sh")
    fi

    # 5. Codex plugin (if enabled)
    if [[ "$CODEX_ENABLED" == true ]]; then
        local codex_path="${TEMPLATES_DIR}/codex/plugin.sh"
        if [[ -f "$codex_path" ]]; then
            load_order+=("$codex_path")
        else
            print_warning "Codex plugin not found, skipping"
        fi
    fi

    # 6. GitHub Actions plugins (if enabled)
    if [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
        local github_actions_path="${TEMPLATES_DIR}/github-actions/project-integration/plugin.sh"
        if [[ -f "$github_actions_path" ]]; then
            load_order+=("$github_actions_path")
        else
            print_warning "GitHub Actions project-integration plugin not found, skipping"
        fi
    fi

    # 7. Auto-tag plugin (independent from project-integration)
    if [[ "$AUTO_TAG_ENABLED" == true ]]; then
        local auto_tag_path="${TEMPLATES_DIR}/github-actions/auto-tag/plugin.sh"
        if [[ -f "$auto_tag_path" ]]; then
            load_order+=("$auto_tag_path")
        else
            print_warning "Auto-tag plugin not found, skipping"
        fi
    fi

    # Load plugins
    for plugin_path in "${load_order[@]}"; do
        if load_plugin "$plugin_path"; then
            local name
            name=$(plugin_name)
            LOADED_PLUGINS+=("$plugin_path")
            PLUGIN_NAMES+=("$name")
            print_success "Loaded plugin: $name - $(plugin_description)"
        else
            print_error "Failed to load: $plugin_path"
        fi
    done
}

# Unset plugin functions to prevent carryover between plugins
unset_plugin_functions() {
    unset -f plugin_name plugin_description plugin_copy plugin_post_copy plugin_interactive_setup plugin_dockerfile 2>/dev/null || true
}

# Execute plugin_copy for all loaded plugins
execute_plugin_copies() {
    local target_dir="$1"

    for plugin_path in "${LOADED_PLUGINS[@]}"; do
        # Unset previous plugin functions
        unset_plugin_functions

        # Source plugin
        source "$plugin_path"

        # Execute plugin_copy if it exists
        if declare -f plugin_copy > /dev/null; then
            plugin_copy "$target_dir"
        fi
    done

    unset_plugin_functions
}

# Execute plugin_dockerfile for all loaded plugins
# Appends language-specific ENV/RUN directives to Dockerfile.dev
execute_plugin_dockerfiles() {
    local target_dir="$1"
    local dockerfile="${target_dir}/docker/Dockerfile.dev"

    if [[ ! -f "$dockerfile" ]]; then
        print_warning "Dockerfile.dev not found, skipping plugin_dockerfile hooks"
        return
    fi

    for plugin_path in "${LOADED_PLUGINS[@]}"; do
        # Unset previous plugin functions
        unset_plugin_functions

        # Source plugin
        source "$plugin_path"

        # Execute plugin_dockerfile if it exists
        if declare -f plugin_dockerfile > /dev/null; then
            plugin_dockerfile "$target_dir"
        fi
    done

    unset_plugin_functions
}

# Execute plugin_post_copy for all loaded plugins
execute_plugin_post_copies() {
    local target_dir="$1"

    for plugin_path in "${LOADED_PLUGINS[@]}"; do
        # Unset previous plugin functions
        unset_plugin_functions

        # Source plugin
        source "$plugin_path"

        # Execute plugin_interactive_setup FIRST if it exists and we're in interactive mode
        # This ensures variables are set before plugin_post_copy runs
        if declare -f plugin_interactive_setup > /dev/null && check_tty_available; then
            plugin_interactive_setup
        fi

        # Execute plugin_post_copy if it exists (after interactive setup)
        if declare -f plugin_post_copy > /dev/null; then
            plugin_post_copy "$target_dir"
        fi
    done

    unset_plugin_functions
}

# =============================================================================
# Language Selection
# =============================================================================

prompt_language_selection() {
    if ! check_tty_available; then
        print_warning "Non-interactive mode: skipping language plugins"
        SELECTED_LANGUAGES=()
        return
    fi

    local lang_count=${#AVAILABLE_LANGUAGES[@]}

    echo "" > /dev/tty
    print_info "Select language templates (comma-separated numbers, or 'all'/'none'):"

    local i=1
    for lang in "${AVAILABLE_LANGUAGES[@]}"; do
        local display_name="${LANGUAGE_DISPLAY_NAMES[$lang]:-$lang}"
        echo "  $i. $display_name" > /dev/tty
        ((i++))
    done

    echo "" > /dev/tty
    echo -n "Enter selection [none]: " > /dev/tty
    local response
    IFS='' read -r response < /dev/tty

    # Build SELECTED_LANGUAGES from input
    SELECTED_LANGUAGES=()

    if [[ -z "$response" ]] || [[ "$response" == "none" ]]; then
        # Empty or 'none' = no languages
        :
    elif [[ "$response" == "all" ]]; then
        SELECTED_LANGUAGES=("${AVAILABLE_LANGUAGES[@]}")
    else
        # Parse comma-separated numbers
        IFS=',' read -ra nums <<< "$response"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$lang_count" ]]; then
                SELECTED_LANGUAGES+=("${AVAILABLE_LANGUAGES[$((num-1))]}")
            else
                print_warning "Invalid selection: $num"
            fi
        done
    fi

    if [[ ${#SELECTED_LANGUAGES[@]} -eq 0 ]]; then
        print_success "Selected: none (skipping language plugins)"
    else
        print_success "Selected: ${SELECTED_LANGUAGES[*]}"
    fi
}

# =============================================================================
# Service Selection
# =============================================================================

prompt_service_selection() {
    if ! check_tty_available; then
        print_warning "Non-interactive mode: skipping service plugins"
        SELECTED_SERVICES=()
        return
    fi

    local svc_count=${#AVAILABLE_SERVICES[@]}

    echo "" > /dev/tty
    print_info "Select service plugins (comma-separated numbers, or 'all'/'none'):"

    local i=1
    for svc in "${AVAILABLE_SERVICES[@]}"; do
        local display_name="${SERVICE_DISPLAY_NAMES[$svc]:-$svc}"
        echo "  $i. $display_name" > /dev/tty
        ((i++))
    done

    echo "" > /dev/tty
    echo -n "Enter selection [none]: " > /dev/tty
    local response
    IFS='' read -r response < /dev/tty

    # Build SELECTED_SERVICES from input
    SELECTED_SERVICES=()

    if [[ -z "$response" ]] || [[ "$response" == "none" ]]; then
        :
    elif [[ "$response" == "all" ]]; then
        SELECTED_SERVICES=("${AVAILABLE_SERVICES[@]}")
    else
        IFS=',' read -ra nums <<< "$response"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$svc_count" ]]; then
                SELECTED_SERVICES+=("${AVAILABLE_SERVICES[$((num-1))]}")
            else
                print_warning "Invalid selection: $num"
            fi
        done
    fi

    # Set feature flags based on selection
    for svc in "${SELECTED_SERVICES[@]}"; do
        case "$svc" in
            postgresql) POSTGRESQL_ENABLED=true ;;
        esac
    done

    if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
        print_success "Selected: none (skipping service plugins)"
    else
        print_success "Selected: ${SELECTED_SERVICES[*]}"
    fi
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_arguments() {
    PROJECT_NAME=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                skip_confirm=true
                shift
                ;;
            --lang)
                if [[ -n "$2" ]]; then
                    SELECTED_LANGUAGES+=("$2")
                    shift 2
                else
                    print_error "--lang requires a value"
                    exit 1
                fi
                ;;
            --codex)
                CODEX_ENABLED=true
                shift
                ;;
            --postgresql)
                POSTGRESQL_ENABLED=true
                SELECTED_SERVICES+=("postgresql")
                shift
                ;;
            --github-actions)
                GITHUB_ACTIONS_ENABLED=true
                shift
                ;;
            --overwrite)
                OVERWRITE_ALL=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                if [[ -z "$PROJECT_NAME" ]]; then
                    PROJECT_NAME="$1"
                else
                    print_error "Unexpected argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# =============================================================================
# Main Setup Flow
# =============================================================================

main() {
    print_header

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Parse arguments
    parse_arguments "$@"

    # Get project name
    if [[ -z "$PROJECT_NAME" ]]; then
        local default_name
        default_name=$(get_default_project_name)

        if check_tty_available; then
            PROJECT_NAME=$(prompt_input "Enter project name" "$default_name")
        else
            if [[ -n "$default_name" ]]; then
                PROJECT_NAME="$default_name"
            else
                print_error "Project name required in non-interactive mode"
                exit 1
            fi
        fi
    fi

    # Validate project name
    if ! validate_project_name "$PROJECT_NAME"; then
        exit 1
    fi

    print_info "Project name: $PROJECT_NAME"

    # Select language if not specified
    if [[ ${#SELECTED_LANGUAGES[@]} -eq 0 ]]; then
        prompt_language_selection
    fi

    # Select services if not specified
    if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
        prompt_service_selection
    fi

    # Prompt for optional features if in interactive mode
    if check_tty_available; then
        # Ask about Codex CLI integration
        if [[ "$CODEX_ENABLED" != true ]]; then
            echo "" > /dev/tty
            echo -n "Enable OpenAI Codex CLI integration (code review)? (y/n) [n]: " > /dev/tty
            local codex_response
            read -r codex_response < /dev/tty
            if [[ "$codex_response" == "y" || "$codex_response" == "Y" ]]; then
                CODEX_ENABLED=true
            fi
        fi

        # Ask about project-integration
        if [[ "$GITHUB_ACTIONS_ENABLED" != true ]]; then
            echo "" > /dev/tty
            echo -n "Enable GitHub Project integration workflows? (y/n) [n]: " > /dev/tty
            local github_response
            read -r github_response < /dev/tty
            if [[ "$github_response" == "y" || "$github_response" == "Y" ]]; then
                GITHUB_ACTIONS_ENABLED=true
            fi
        fi

        # Ask about auto-tag (independent from project-integration)
        if [[ "$AUTO_TAG_ENABLED" != true ]]; then
            echo "" > /dev/tty
            echo -n "Enable auto-tag workflow? (y/n) [n]: " > /dev/tty
            local autotag_response
            read -r autotag_response < /dev/tty
            if [[ "$autotag_response" == "y" || "$autotag_response" == "Y" ]]; then
                AUTO_TAG_ENABLED=true
            fi
        fi
    fi

    # Confirm settings
    print_section "Setup Configuration"
    echo "Project name:         $PROJECT_NAME"
    echo "Language:             ${SELECTED_LANGUAGES[*]:-none}"
    echo "Services:             ${SELECTED_SERVICES[*]:-none}"
    echo "Codex CLI:            $CODEX_ENABLED"
    echo "Project Integration:  $GITHUB_ACTIONS_ENABLED"
    echo "Auto-Tag:             $AUTO_TAG_ENABLED"
    echo "Overwrite:            $OVERWRITE_ALL"
    echo ""

    if [[ "$SKIP_CONFIRM" != true ]] && check_tty_available; then
        if ! confirm "Proceed with setup?" "y"; then
            print_info "Setup cancelled"
            exit 0
        fi
    fi

    # Dry run mode
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "Dry run mode - no files will be created"
        exit 0
    fi

    # Target directory is current directory
    TARGET_DIR="$(pwd)"

    # Load plugins
    print_section "Loading Plugins"
    load_selected_plugins

    # Execute plugin copies
    print_section "Copying Template Files"
    execute_plugin_copies "$TARGET_DIR"

    # Execute Dockerfile customizations
    execute_plugin_dockerfiles "$TARGET_DIR"

    # Execute post-copy processing
    print_section "Post-Processing"
    execute_plugin_post_copies "$TARGET_DIR"

    # Replace placeholders
    replace_placeholders "$TARGET_DIR" "$PROJECT_NAME"

    # Update .gitignore
    update_gitignore "$TARGET_DIR"

    # Setup GitHub repository
    print_section "GitHub Repository Setup"
    if check_tty_available; then
        if confirm "Setup GitHub repository (develop branch, labels)?" "y"; then
            setup_github_repository
            auto_commit "feat: add devcontainer configuration"
        fi
    fi

    # Completion message
    print_section "Setup Complete"
    print_success "Devcontainer environment created for: $PROJECT_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. Open in VS Code: code ."
    echo "  2. Reopen in Container: F1 > Dev Containers: Reopen in Container"
    echo ""
    echo "Available Claude Code commands:"
    echo "  /issue     - Create a GitHub Issue"
    echo "  /implement - Implement a GitHub Issue"
    echo "  /pr        - Create a Pull Request"
}

# Run main function
main "$@"
