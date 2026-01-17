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
# Remote Execution:
#   curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash
#   curl -fsSL ... | bash -s -- [OPTIONS] [PROJECT_NAME]
#
# =============================================================================

# =============================================================================
# Remote Execution Bootstrap
# =============================================================================
# Detect if running via pipe (curl | bash) and bootstrap if necessary

REMOTE_REPO_URL="${DEVCONTAINER_REPO_URL:-https://github.com/TE-ToshiakiTanaka2/tarnished.git}"
REMOTE_BRANCH="${DEVCONTAINER_BRANCH:-develop}"

# Check if running from pipe (curl | bash)
# BASH_SOURCE[0] is empty, "-", or doesn't exist as a file when piped
if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    echo "================================================"
    echo "  Devcontainer Boilerplate - Remote Execution"
    echo "================================================"
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
    # Using exec to replace current shell, ensuring proper exit code
    exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"
fi

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
POSTGRESQL_ENABLED=false
NEO4J_ENABLED=false
REDIS_ENABLED=false
GITHUB_ACTIONS_ENABLED=false

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
    --lang <languages>  Select language template(s), comma-separated
                        (e.g., --lang node or --lang node,python)
    --playwright        Include Playwright for E2E testing
    --docker            Include Docker-in-Docker (DinD) support
    --postgresql        Include PostgreSQL database support
    --neo4j             Include Neo4j graph database support
    --redis             Include Redis cache/session support
    --github-actions    Include GitHub Actions templates (auto-tag, etc.)

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
    ./setup.sh --lang node --postgresql          # Node.js with PostgreSQL
    ./setup.sh --lang python --neo4j             # Python with Neo4j for GraphRAG
    ./setup.sh --lang node --redis               # Node.js with Redis
    ./setup.sh --lang node --github-actions      # Node.js with GitHub Actions
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
    - PostgreSQL (optional) for database development
    - GitHub Actions (optional) for CI/CD automation

GitHub Integration:
    This script automatically:
    - Authenticates with GitHub CLI (prompts if not authenticated)
    - Creates/checks out 'develop' branch
    - Sets 'develop' as the default branch on GitHub (if permissions allow)
    - Auto-commits setup changes to the develop branch

Remote Execution:
    Run directly from GitHub without cloning first:

    curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash

    With options:
    curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/develop/setup.sh | bash -s -- --lang node --docker

    With project name:
    curl -fsSL ... | bash -s -- my-project --lang python

    Requirements: git, curl

EOF
}

# =============================================================================
# GitHub Operations Functions
# =============================================================================

# Check GitHub CLI authentication status
# Returns 0 if authenticated, 1 if not
check_gh_auth() {
    print_info "Checking GitHub CLI authentication..."

    # Check if gh command exists
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed"
        print_info "Please install: https://cli.github.com/"
        return 1
    fi

    # Check authentication status
    if ! gh auth status &>/dev/null; then
        print_warning "GitHub CLI is not authenticated"
        print_info "Starting authentication flow..."
        if ! gh auth login; then
            print_error "GitHub authentication failed"
            return 1
        fi
    fi

    print_success "GitHub CLI authenticated"
    return 0
}

# Setup develop branch (create if not exists, checkout if exists)
setup_develop_branch() {
    print_info "Setting up develop branch..."

    # Check if we're in a git repository
    if ! git rev-parse --git-dir &>/dev/null; then
        print_error "Not a git repository"
        return 1
    fi

    # Check if origin remote exists
    if ! git remote get-url origin &>/dev/null; then
        print_error "No 'origin' remote configured"
        return 1
    fi

    # Fetch latest from remote
    print_info "Fetching latest from remote..."
    git fetch origin 2>/dev/null || true

    # Check if develop branch exists locally
    if git show-ref --verify --quiet refs/heads/develop; then
        print_info "Develop branch exists locally, checking out..."
        git checkout develop
    # Check if develop branch exists on remote
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

# Set develop as default branch on GitHub
set_default_branch() {
    print_info "Setting develop as default branch on GitHub..."

    # Try to set default branch
    if gh repo edit --default-branch develop 2>/dev/null; then
        print_success "Default branch set to develop"
    else
        print_warning "Could not set default branch (insufficient permissions or not a GitHub repo)"
        print_info "Pushing develop branch to remote..."
        if git push -u origin develop 2>/dev/null; then
            print_success "Develop branch pushed to remote"
        else
            print_warning "Could not push to remote (network issue or permissions)"
        fi
        print_info "Please manually set develop as default branch in repository settings"
    fi

    return 0
}

# Auto commit changes with given message
# Usage: auto_commit "commit message"
auto_commit() {
    local message="$1"

    # Check if there are changes to commit
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

# Main GitHub repository setup function
# Orchestrates all GitHub-related operations
setup_github_repository() {
    print_info "Setting up GitHub repository..."
    echo ""

    # Step 1: Check GitHub CLI authentication
    if ! check_gh_auth; then
        print_error "GitHub setup failed: authentication required"
        return 1
    fi

    # Step 2: Setup develop branch
    if ! setup_develop_branch; then
        print_error "GitHub setup failed: could not setup develop branch"
        return 1
    fi

    # Step 3: Set default branch (non-fatal if fails)
    set_default_branch

    echo ""
    print_success "GitHub repository setup complete"
    return 0
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
# TTY Helper Functions
# =============================================================================

# Get default project name from current directory
# Returns directory name if valid, empty string otherwise
get_default_project_name() {
    local dir_name
    dir_name=$(basename "$(pwd)")

    # Validate directory name as project name
    if validate_project_name "$dir_name" 2>/dev/null; then
        echo "$dir_name"
    else
        echo ""
    fi
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
        if [[ "$plugin_name" == "playwright" ]] || [[ "$plugin_name" == "docker" ]] || [[ "$plugin_name" == "postgresql" ]]; then
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
    local first_draw=true

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
        # Move cursor up to redraw (skip on first draw to prevent display corruption)
        if [[ "$first_draw" != true ]]; then
            for ((i=0; i<num_languages; i++)); do
                tput cuu1 2>/dev/null || echo -en "\033[1A"
            done
        fi
        first_draw=false

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

        # Read single keypress from /dev/tty (supports curl | bash)
        # IFS='' prevents SPACE from being treated as a field separator
        IFS='' read -rsn1 key < /dev/tty

        # Handle arrow keys (escape sequences)
        if [[ "$key" == $'\x1b' ]]; then
            IFS='' read -rsn2 -t 0.1 key < /dev/tty
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
    IFS='' read -r response < /dev/tty

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

    # 5. PostgreSQL plugin (if enabled)
    if [[ "$POSTGRESQL_ENABLED" == true ]]; then
        local postgresql_path="${TEMPLATES_DIR}/postgresql/plugin.sh"
        if [[ -f "$postgresql_path" ]]; then
            load_order+=("$postgresql_path")
        else
            print_warning "PostgreSQL plugin not found, skipping"
        fi
    fi

    # 6. Neo4j plugin (if enabled)
    if [[ "$NEO4J_ENABLED" == true ]]; then
        local neo4j_path="${TEMPLATES_DIR}/neo4j/plugin.sh"
        if [[ -f "$neo4j_path" ]]; then
            load_order+=("$neo4j_path")
        else
            print_warning "Neo4j plugin not found, skipping"
        fi
    fi

    # 7. Redis plugin (if enabled)
    if [[ "$REDIS_ENABLED" == true ]]; then
        local redis_path="${TEMPLATES_DIR}/redis/plugin.sh"
        if [[ -f "$redis_path" ]]; then
            load_order+=("$redis_path")
        else
            print_warning "Redis plugin not found, skipping"
        fi
    fi

    # 8. GitHub Actions plugin (if enabled)
    if [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
        local github_actions_path="${TEMPLATES_DIR}/github-actions/plugin.sh"
        if [[ -f "$github_actions_path" ]]; then
            load_order+=("$github_actions_path")
        else
            print_warning "GitHub Actions plugin not found, skipping"
        fi
    fi

    # 9. Playwright plugin (if enabled)
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
        # Output prompt to /dev/tty to avoid capture by command substitution
        echo -n "Enter project name: " > /dev/tty
        IFS='' read -r project_name < /dev/tty

        if validate_project_name "$project_name"; then
            echo "$project_name"
            return 0
        fi

        echo "" > /dev/tty
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
    if [[ "$POSTGRESQL_ENABLED" == true ]]; then
        print_info "PostgreSQL: enabled"
    fi
    if [[ "$NEO4J_ENABLED" == true ]]; then
        print_info "Neo4j: enabled"
    fi
    if [[ "$REDIS_ENABLED" == true ]]; then
        print_info "Redis: enabled"
    fi
    if [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
        print_info "GitHub Actions: enabled"
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
    if [[ "$POSTGRESQL_ENABLED" == true ]]; then
        echo "  PostgreSQL:  enabled"
    fi
    if [[ "$NEO4J_ENABLED" == true ]]; then
        echo "  Neo4j:       enabled"
    fi
    if [[ "$REDIS_ENABLED" == true ]]; then
        echo "  Redis:       enabled"
    fi
    if [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
        echo "  GitHub Actions: enabled"
    fi
    if [[ "$PLAYWRIGHT_ENABLED" == true ]]; then
        echo "  Playwright:  enabled"
    fi
    echo ""

    # Show git/GitHub information
    echo "Git Status:"
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "  Branch:      ${current_branch}"
    local commit_count
    commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    echo "  Commits:     ${commit_count}"
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
            --postgresql)
                POSTGRESQL_ENABLED=true
                shift
                ;;
            --neo4j)
                NEO4J_ENABLED=true
                shift
                ;;
            --redis)
                REDIS_ENABLED=true
                shift
                ;;
            --github-actions)
                GITHUB_ACTIONS_ENABLED=true
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

    # Setup GitHub repository (authentication, develop branch, default branch)
    # Skip in dry-run mode since we don't need git operations for preview
    if [[ "$dry_run" != true ]]; then
        if ! setup_github_repository; then
            exit 1
        fi
    fi

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Discover available languages
    discover_available_languages

    if [[ ${#AVAILABLE_LANGUAGES[@]} -eq 0 ]]; then
        print_warning "No language plugins found, using core plugins only"
    fi

    # Check if interactive mode is needed and TTY is available
    local needs_interactive=false
    if [[ -z "$lang_arg" ]] && [[ "$skip_confirm" != true ]]; then
        needs_interactive=true
    fi
    if [[ -z "$project_name" ]] && [[ "$skip_confirm" != true ]]; then
        needs_interactive=true
    fi

    # If interactive mode is needed, verify TTY is available
    if [[ "$needs_interactive" == true ]]; then
        if ! check_tty_available; then
            show_interactive_mode_error
            exit 1
        fi
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
        # In non-interactive mode with skip_confirm, try to use directory name
        if [[ "$skip_confirm" == true ]]; then
            project_name=$(get_default_project_name)
            if [[ -z "$project_name" ]]; then
                print_error "Project name is required in non-interactive mode"
                print_info "Please provide a project name as an argument or use a valid directory name"
                exit 1
            fi
            print_info "Using directory name as project name: $project_name"
        else
            project_name=$(prompt_project_name)
        fi
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
        IFS='' read -r confirm < /dev/tty
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
        if [[ "$skip_confirm" != true ]]; then
            echo -n "Overwrite existing files? [y/N]: "
            IFS='' read -r overwrite < /dev/tty
            if [[ ! "$overwrite" =~ ^[Yy] ]]; then
                print_warning "Setup cancelled"
                exit 0
            fi
        else
            print_info "Proceeding with overwrite (--yes flag specified)"
        fi
    fi

    # Execute plugin hooks in order
    print_info "Executing plugin pre-copy hooks..."
    execute_plugins_hook "plugin_pre_copy" "$target_dir"

    print_info "Executing plugin copy hooks..."
    execute_plugins_hook "plugin_copy" "$target_dir"

    # Auto commit after core setup
    auto_commit "feat: initialize devcontainer environment"

    print_info "Executing plugin post-copy hooks..."
    execute_plugins_hook "plugin_post_copy" "$target_dir"

    # Execute interactive setup hooks for plugins (e.g., github-actions)
    if [[ "$skip_confirm" != true ]]; then
        print_info "Executing plugin interactive setup hooks..."
        execute_plugins_hook "plugin_interactive_setup" "$target_dir"
    else
        # Non-interactive mode: generate minimal config files
        print_info "Executing plugin minimal setup hooks..."
        execute_plugins_hook "plugin_minimal_setup" "$target_dir"
    fi

    # Auto commit after language/tool configuration
    local lang_list="${SELECTED_LANGUAGES[*]}"
    auto_commit "feat: configure ${lang_list} development environment"

    # Finalization
    replace_placeholders "$target_dir" "$project_name"
    update_gitignore "$target_dir"

    # Execute validation hooks
    print_info "Executing plugin validation hooks..."
    execute_plugins_hook "plugin_validate" "$target_dir"

    # Auto commit final configuration
    auto_commit "chore: finalize project configuration"

    show_completion "$project_name"
}

# Run main function
main "$@"
