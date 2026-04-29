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
declare -a AVAILABLE_LANGUAGES=("rust" "python" "node" "deno" "latex")
declare -A LANGUAGE_DISPLAY_NAMES=(
    ["rust"]="Rust"
    ["python"]="Python"
    ["node"]="Node.js/TypeScript"
    ["deno"]="Deno"
    ["latex"]="LaTeX"
)

# Service selection
declare -a SELECTED_SERVICES=()
declare -a AVAILABLE_SERVICES=("postgresql" "mysql" "redis" "celery")
declare -A SERVICE_DISPLAY_NAMES=(
    ["postgresql"]="PostgreSQL 16"
    ["mysql"]="MySQL 8.0"
    ["redis"]="Redis 7"
    ["celery"]="Celery Worker + Beat (requires Python + Redis)"
)

# Feature flags
GITHUB_ACTIONS_ENABLED=false
AUTO_TAG_ENABLED=false
CODEX_ENABLED=false
POSTGRESQL_ENABLED=false
MYSQL_ENABLED=false
REDIS_ENABLED=false
CELERY_ENABLED=false
DRY_RUN=false
SKIP_CONFIRM=false

# Monorepo mode (#263)
MONOREPO_MODE=false
IS_ADD_MODULE_MODE=false
ADD_MODULE_NAME=""
ADD_MODULE_LANG=""
declare -a MODULES=()

# Manifest modes (#265). Mutually exclusive with each other and with the
# scaffold modes (single / monorepo init / add-module).
CREATE_MANIFEST_MODE=false
UPGRADE_MODE=false
FROM_VERSION=""
TARGET_VERSION=""
FORCE=false
PRUNE_ENABLED=false
SHARED_ONLY=false
declare -a UPGRADE_MODULES=()

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
    --lang <language>   Select language template (can be specified multiple times in
                        single mode; in monorepo mode use --module instead)
    --monorepo          Enable monorepo mode for fresh init (#263)
    --module <name>:<lang>
                        Define a monorepo module. Repeatable. Implies --monorepo. (#263)
    --add-module <name> Add a single module to an existing monorepo. Pair with --lang.
                        Auto-detected when CWD already contains modules.json. (#263)
    --codex             Include OpenAI Codex CLI integration (code review)
    --postgresql        Include PostgreSQL database service
    --mysql             Include MySQL database service
    --redis             Include Redis cache/broker service
    --celery            Include Celery task queue (auto-enables Redis, requires Python)
    --github-actions    Include GitHub Project integration (requires erd CLI)
    --overwrite         Overwrite existing files without confirmation
    --create-manifest   Bootstrap a .tarnished-manifest.json from the current
                        state of files in this directory. Required as a one-shot
                        for legacy projects before their first --upgrade. (#265)
    --from-version <ref>
                        Recorded as `tarnished_version` in the new manifest
                        (defaults to "unknown"). Use this to pin the originating
                        tarnished version for projects scaffolded before the
                        manifest format existed. Only valid with --create-manifest. (#265)
    --upgrade           Refresh tracked files of an existing scaffolded project
                        to the latest (or --target-version-pinned) tarnished
                        version. User-edited files are skipped automatically. (#265)
    --target-version <ref>
                        Target git ref (tag, branch, or commit) of upstream
                        tarnished for --upgrade. Defaults to ${REMOTE_BRANCH}
                        HEAD (currently develop). (#265)
    --shared-only       Restrict --upgrade to the root-level (shared) manifest.
                        Has no effect on single-mode targets. (#265)
    --prune             Delete tracked files removed upstream and unedited
                        locally. Without this flag, such files are left in
                        place and reported as a warning. (#265)
    --force             Bypass --upgrade's clean-tree precondition. Use with
                        care — uncommitted edits to unedited files may be
                        overwritten. (#265)

Arguments:
    PROJECT_NAME        Name for your project (optional, will prompt if not provided)

Available Languages:
    rust                Rust
    python              Python (uv, ruff, mypy, pytest)
    node                Node.js/TypeScript (pnpm, Biome, Vitest)
    deno                Deno (built-in fmt, lint, test)

Available Services:
    postgresql          PostgreSQL 16 database with psql client
    mysql               MySQL 8.0 database with mysql client
    redis               Redis 7 cache/broker with redis-cli client
    celery              Celery Worker + Beat task queue (requires Python + Redis)

Examples:
    # Single-project mode (default)
    ./setup.sh                              # Interactive mode
    ./setup.sh my-project                   # Create project named 'my-project'
    ./setup.sh --dry-run my-app             # Preview what would be created
    ./setup.sh --lang rust                  # Rust only
    ./setup.sh --lang rust --lang python    # Rust + Python
    ./setup.sh --lang rust --postgresql     # Rust with PostgreSQL
    ./setup.sh --lang python --celery       # Python with Celery + Redis (auto-enabled)
    ./setup.sh --lang rust --github-actions # Rust with GitHub Project integration
    ./setup.sh my-project --lang rust -y    # Non-interactive mode

    # Monorepo mode (#263)
    ./setup.sh --monorepo                   # Interactive: define modules in a loop
    ./setup.sh --monorepo --module jing:python --module kir:node
                                            # Two-module init (Python + Node)
    ./setup.sh --monorepo --module foo:python --postgresql --redis -y
                                            # Init with shared services

    # Add module to an existing monorepo (#263)
    ./setup.sh --add-module anisette --lang python -y
    ./setup.sh                              # Auto-detected if CWD has modules.json

    # Bootstrap a manifest for an existing project (#265)
    ./setup.sh --create-manifest --from-version v0.0.74 -y
    ./setup.sh --create-manifest -y         # tarnished_version recorded as "unknown"

    # Upgrade an existing scaffolded project (#265)
    ./setup.sh --upgrade -y                 # Latest develop
    ./setup.sh --upgrade --target-version v0.0.76 -y
    ./setup.sh --upgrade --dry-run          # Preview without writes
    ./setup.sh --upgrade --shared-only -y   # Monorepo: only shared assets
    ./setup.sh --upgrade --module backend -y
    ./setup.sh --upgrade --prune -y         # Also delete files removed upstream
    ./setup.sh --upgrade --force -y         # Bypass clean-tree check

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

# Load selected plugins in correct order. In add-module mode (#263) we skip
# the plugins that own the shared root assets (core, claude, codex,
# github-actions) — those were already installed during the original
# `setup.sh --monorepo` run, and re-running their plugin_copy hooks would
# overwrite user customizations and language-toolchain marker blocks.
load_selected_plugins() {
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()

    local -a load_order=()
    local skip_root_plugins=false
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        skip_root_plugins=true
    fi

    # 1. Core plugin first (skipped in add-module mode)
    if [[ "$skip_root_plugins" != true ]] && [[ -f "${TEMPLATES_DIR}/core/plugin.sh" ]]; then
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

    # 4. Claude plugin (skipped in add-module mode)
    if [[ "$skip_root_plugins" != true ]] && [[ -f "${TEMPLATES_DIR}/claude/plugin.sh" ]]; then
        load_order+=("${TEMPLATES_DIR}/claude/plugin.sh")
    fi

    # 5. Codex plugin (if enabled — skipped in add-module mode)
    if [[ "$skip_root_plugins" != true ]] && [[ "$CODEX_ENABLED" == true ]]; then
        local codex_path="${TEMPLATES_DIR}/codex/plugin.sh"
        if [[ -f "$codex_path" ]]; then
            load_order+=("$codex_path")
        else
            print_warning "Codex plugin not found, skipping"
        fi
    fi

    # 6. GitHub Actions plugins (skipped in add-module mode)
    if [[ "$skip_root_plugins" != true ]] && [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
        local github_actions_path="${TEMPLATES_DIR}/github-actions/project-integration/plugin.sh"
        if [[ -f "$github_actions_path" ]]; then
            load_order+=("$github_actions_path")
        else
            print_warning "GitHub Actions project-integration plugin not found, skipping"
        fi
    fi

    # 7. Auto-tag plugin (independent from project-integration; skipped in add-module mode)
    if [[ "$skip_root_plugins" != true ]] && [[ "$AUTO_TAG_ENABLED" == true ]]; then
        local auto_tag_path="${TEMPLATES_DIR}/github-actions/auto-tag/plugin.sh"
        if [[ -f "$auto_tag_path" ]]; then
            load_order+=("$auto_tag_path")
        else
            print_warning "Auto-tag plugin not found, skipping"
        fi
    fi

    if [[ "$skip_root_plugins" == true ]]; then
        print_info "add-module mode: skipping core/claude/codex/github-actions (already installed)"
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
    unset -f plugin_name plugin_description plugin_copy plugin_post_copy plugin_interactive_setup plugin_dockerfile plugin_post_copy_shared plugin_post_copy_module 2>/dev/null || true
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

# Execute plugin_post_copy for all loaded plugins.
#
# Dispatch (#263):
#   - Single mode (MONOREPO_MODE=false): call plugin_post_copy(root) for every
#     plugin. Identical to pre-#263 behavior.
#   - Monorepo / add-module mode (MONOREPO_MODE=true || IS_ADD_MODULE_MODE=true):
#     for language plugins (path under templates/languages/) that expose
#     plugin_post_copy_module, call plugin_post_copy_shared(root) once and
#     plugin_post_copy_module(root/<module>, <module>) for each module whose
#     language matches this plugin. Non-language plugins (and language plugins
#     missing the new hook) fall back to plugin_post_copy(root).
execute_plugin_post_copies() {
    local target_dir="$1"
    local monorepo_dispatch=false
    if [[ "$MONOREPO_MODE" == true ]] || [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        monorepo_dispatch=true
    fi

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

        local is_lang=false
        if [[ "$plugin_path" == */templates/languages/* ]]; then
            is_lang=true
        fi

        if [[ "$monorepo_dispatch" == true ]] && [[ "$is_lang" == true ]] \
            && declare -f plugin_post_copy_module > /dev/null; then

            # Determine this plugin's language id from its parent directory.
            local plugin_lang
            plugin_lang="$(basename "$(dirname "$plugin_path")")"

            # Run shared edits once.
            if declare -f plugin_post_copy_shared > /dev/null; then
                plugin_post_copy_shared "$target_dir"
            fi

            # Run per-module edits for every module that uses this language.
            local entry module_name module_lang
            for entry in "${MODULES[@]}"; do
                module_name="${entry%%:*}"
                module_lang="${entry#*:}"
                if [[ "$module_lang" != "$plugin_lang" ]]; then
                    continue
                fi
                local module_dir="${target_dir}/${module_name}"
                mkdir -p "$module_dir"
                plugin_post_copy_module "$module_dir" "$module_name"
            done
        elif declare -f plugin_post_copy > /dev/null; then
            # Single mode (and non-language / legacy plugins in monorepo mode).
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
            mysql) MYSQL_ENABLED=true ;;
            redis) REDIS_ENABLED=true ;;
            celery) CELERY_ENABLED=true ;;
        esac
    done

    # Celery requires Python
    if [[ "$CELERY_ENABLED" == true ]]; then
        local python_selected=false
        for lang in "${SELECTED_LANGUAGES[@]}"; do
            if [[ "$lang" == "python" ]]; then
                python_selected=true
                break
            fi
        done

        if [[ "$python_selected" != true ]]; then
            print_warning "Celery requires Python language plugin. Adding Python automatically."
            SELECTED_LANGUAGES+=("python")
        fi

        # Auto-enable Redis if not already selected
        if [[ "$REDIS_ENABLED" != true ]]; then
            print_info "Celery requires Redis. Adding Redis automatically."
            REDIS_ENABLED=true
            SELECTED_SERVICES+=("redis")
        fi
    fi

    # Ensure Redis is loaded before Celery (Celery depends on Redis at setup time)
    if [[ "$CELERY_ENABLED" == true ]] && [[ "$REDIS_ENABLED" == true ]]; then
        local -a reordered=()
        for svc in "${SELECTED_SERVICES[@]}"; do
            [[ "$svc" == "redis" || "$svc" == "celery" ]] && continue
            reordered+=("$svc")
        done
        reordered+=("redis")
        reordered+=("celery")
        SELECTED_SERVICES=("${reordered[@]}")
    fi

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
            --monorepo)
                MONOREPO_MODE=true
                shift
                ;;
            --module)
                if [[ -z "${2:-}" ]]; then
                    print_error "--module requires a value (format: <name>:<lang> or <name>)"
                    exit 1
                fi
                # Disambiguate the two valid forms (#263 monorepo init takes
                # <name>:<lang>; #265 --upgrade scope filter takes <name>).
                # Both are routed to MODULES here; validate_argument_combinations
                # checks that the form matches the mode.
                if [[ "$2" == *:* ]]; then
                    MODULES+=("$2")
                    MONOREPO_MODE=true
                else
                    UPGRADE_MODULES+=("$2")
                fi
                shift 2
                ;;
            --add-module)
                if [[ -z "${2:-}" ]]; then
                    print_error "--add-module requires a value (module name)"
                    exit 1
                fi
                IS_ADD_MODULE_MODE=true
                ADD_MODULE_NAME="$2"
                shift 2
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
            --mysql)
                MYSQL_ENABLED=true
                SELECTED_SERVICES+=("mysql")
                shift
                ;;
            --redis)
                REDIS_ENABLED=true
                SELECTED_SERVICES+=("redis")
                shift
                ;;
            --celery)
                CELERY_ENABLED=true
                # Auto-enable Redis as Celery dependency (Redis must load before Celery)
                if [[ "$REDIS_ENABLED" != true ]]; then
                    REDIS_ENABLED=true
                    SELECTED_SERVICES+=("redis")
                fi
                SELECTED_SERVICES+=("celery")
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
            --create-manifest)
                CREATE_MANIFEST_MODE=true
                shift
                ;;
            --from-version)
                if [[ -z "${2:-}" ]]; then
                    print_error "--from-version requires a value (e.g., v0.0.74 or 'unknown')"
                    exit 1
                fi
                FROM_VERSION="$2"
                shift 2
                ;;
            --upgrade)
                UPGRADE_MODE=true
                shift
                ;;
            --target-version)
                if [[ -z "${2:-}" ]]; then
                    print_error "--target-version requires a value (tag, branch, or commit)"
                    exit 1
                fi
                TARGET_VERSION="$2"
                shift 2
                ;;
            --shared-only)
                SHARED_ONLY=true
                shift
                ;;
            --prune)
                PRUNE_ENABLED=true
                shift
                ;;
            --force)
                FORCE=true
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

    validate_argument_combinations
}

# Reject mutually-exclusive flag combinations and other invalid mixes
# (#263, #265). Documented in docs/design/shared/api-spec.md ::
# Setup / Plugin Surface.
validate_argument_combinations() {
    # Manifest modes (#265) are mutually exclusive with each other.
    if [[ "$CREATE_MANIFEST_MODE" == true ]] && [[ "$UPGRADE_MODE" == true ]]; then
        print_error "--create-manifest and --upgrade are mutually exclusive"
        exit 1
    fi

    # --create-manifest is exclusive with every scaffold/upgrade flag (#265).
    if [[ "$CREATE_MANIFEST_MODE" == true ]]; then
        if [[ "$MONOREPO_MODE" == true ]]; then
            print_error "--create-manifest is mutually exclusive with --monorepo / --module"
            exit 1
        fi
        if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
            print_error "--create-manifest is mutually exclusive with --add-module"
            exit 1
        fi
        if [[ ${#UPGRADE_MODULES[@]} -gt 0 ]]; then
            print_error "--create-manifest is mutually exclusive with --module <name>"
            exit 1
        fi
        if [[ ${#SELECTED_LANGUAGES[@]} -gt 0 ]]; then
            print_error "--create-manifest does not accept --lang (no scaffold work is done)"
            exit 1
        fi
        if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
            print_error "--create-manifest does not accept service flags (--postgresql, --mysql, --redis, --celery)"
            exit 1
        fi
        if [[ "$CODEX_ENABLED" == true ]] || [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
            print_error "--create-manifest does not accept feature flags (--codex, --github-actions)"
            exit 1
        fi
        if [[ "$SHARED_ONLY" == true ]] || [[ "$PRUNE_ENABLED" == true ]] || [[ "$FORCE" == true ]] || [[ -n "$TARGET_VERSION" ]]; then
            print_error "--shared-only / --prune / --force / --target-version are upgrade-only flags"
            exit 1
        fi
        return 0
    fi

    # --upgrade is exclusive with the scaffold modes (#265).
    if [[ "$UPGRADE_MODE" == true ]]; then
        # Order matters: check --module <n>:<l> before the generic
        # --monorepo check, because the parser sets MONOREPO_MODE=true
        # whenever --module foo:bar is seen.
        if [[ ${#MODULES[@]} -gt 0 ]]; then
            print_error "--upgrade does not accept --module <name>:<lang>; use --module <name> instead"
            exit 1
        fi
        if [[ "$MONOREPO_MODE" == true ]]; then
            print_error "--upgrade is mutually exclusive with --monorepo"
            exit 1
        fi
        if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
            print_error "--upgrade is mutually exclusive with --add-module"
            exit 1
        fi
        if [[ ${#SELECTED_LANGUAGES[@]} -gt 0 ]]; then
            print_error "--upgrade does not accept --lang (the manifest records languages)"
            exit 1
        fi
        if [[ ${#SELECTED_SERVICES[@]} -gt 0 ]]; then
            print_error "--upgrade does not accept service flags"
            exit 1
        fi
        if [[ "$CODEX_ENABLED" == true ]] || [[ "$GITHUB_ACTIONS_ENABLED" == true ]] || [[ "$AUTO_TAG_ENABLED" == true ]]; then
            print_error "--upgrade does not accept feature flags (--codex, --github-actions, --auto-tag)"
            exit 1
        fi
        if [[ -n "$FROM_VERSION" ]]; then
            print_error "--from-version is only valid with --create-manifest"
            exit 1
        fi
        return 0
    fi

    # --from-version is only meaningful with --create-manifest.
    if [[ -n "$FROM_VERSION" ]]; then
        print_error "--from-version is only valid with --create-manifest"
        exit 1
    fi

    # --target-version / --shared-only / --prune / --force / --module <name>
    # are upgrade-only.
    if [[ -n "$TARGET_VERSION" ]] || [[ "$SHARED_ONLY" == true ]] || [[ "$PRUNE_ENABLED" == true ]] || [[ "$FORCE" == true ]]; then
        print_error "--target-version / --shared-only / --prune / --force are only valid with --upgrade"
        exit 1
    fi
    if [[ ${#UPGRADE_MODULES[@]} -gt 0 ]]; then
        print_error "--module <name> (no :lang) is only valid with --upgrade; use --module <name>:<lang> for monorepo init"
        exit 1
    fi

    # --add-module is exclusive with monorepo init flags
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        if [[ "$MONOREPO_MODE" == true ]] && [[ ${#MODULES[@]} -gt 0 ]]; then
            print_error "--module cannot be combined with --add-module (--module is init-only)"
            exit 1
        fi
        if [[ ${#MODULES[@]} -gt 0 ]]; then
            print_error "--module cannot be combined with --add-module"
            exit 1
        fi
        # --add-module via CLI requires --lang to specify the new module's language
        if [[ ${#SELECTED_LANGUAGES[@]} -gt 0 ]]; then
            ADD_MODULE_LANG="${SELECTED_LANGUAGES[0]}"
            if [[ ${#SELECTED_LANGUAGES[@]} -gt 1 ]]; then
                print_error "--add-module accepts a single --lang (got ${#SELECTED_LANGUAGES[@]})"
                exit 1
            fi
            if ! validate_language "$ADD_MODULE_LANG"; then
                exit 1
            fi
        fi
        # --monorepo + --add-module (without --module) is also rejected as a redundant
        # signal — --add-module already implies "operate on an existing monorepo".
        if [[ "$MONOREPO_MODE" == true ]]; then
            print_error "--monorepo and --add-module are mutually exclusive"
            exit 1
        fi
        return 0
    fi

    # In monorepo init mode, --lang at the root level is invalid; languages
    # come from --module entries.
    if [[ "$MONOREPO_MODE" == true ]] && [[ ${#SELECTED_LANGUAGES[@]} -gt 0 ]]; then
        print_error "--lang is not allowed in monorepo mode; use --module <name>:<lang> instead"
        exit 1
    fi

    # Validate languages embedded in --module entries.
    local entry name lang
    for entry in "${MODULES[@]}"; do
        name="${entry%%:*}"
        lang="${entry#*:}"
        if ! validate_module_name "$name"; then
            exit 1
        fi
        if ! validate_language "$lang"; then
            exit 1
        fi
    done
}

# Verify a language id is one of AVAILABLE_LANGUAGES.
# Usage: validate_language <lang>
validate_language() {
    local lang="$1"
    local available
    for available in "${AVAILABLE_LANGUAGES[@]}"; do
        if [[ "$available" == "$lang" ]]; then
            return 0
        fi
    done
    print_error "Unknown language '$lang' (available: ${AVAILABLE_LANGUAGES[*]})"
    return 1
}

# =============================================================================
# Mode Resolution (#263)
# =============================================================================

# Resolve the operating mode based on flags, the pre-existing state of the
# CWD, and (when interactive) user choice. After this returns, exactly one
# of three states holds:
#
#   1. Single mode:    MONOREPO_MODE=false, IS_ADD_MODULE_MODE=false
#   2. Monorepo init:  MONOREPO_MODE=true,  IS_ADD_MODULE_MODE=false, MODULES non-empty
#   3. Add-module:     IS_ADD_MODULE_MODE=true, MODULES has exactly 1 entry
#
# In modes 2 and 3, SELECTED_LANGUAGES is populated from MODULES so the
# downstream language-selection prompt is skipped.
resolve_setup_mode() {
    local target_dir
    target_dir="$(pwd)"

    # --- Add-module path ------------------------------------------------------
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        if ! detect_existing_monorepo "$target_dir"; then
            print_error "No modules.json found in $target_dir. Run with --monorepo first."
            exit 1
        fi

        # Validate the registry NOW, before any plugin writes — fail fast
        # on malformed JSON or unsupported `version` (Critical #2 from
        # the #263 review).
        if ! read_modules_json "$target_dir" >/dev/null; then
            exit 1
        fi

        # Anchor PROJECT_NAME to the existing monorepo so the new module's
        # generated content (CLAUDE.md, service compose substitution, etc.)
        # matches what was written by the original --monorepo init — even
        # if the user typed a different name or renamed the directory
        # (Warning #4 from #263 review).
        local canonical
        if canonical=$(derive_project_name_from_compose "$target_dir"); then
            if [[ "$PROJECT_NAME" != "$canonical" ]]; then
                print_info "Using existing project name '$canonical' (overrides '$PROJECT_NAME')"
                PROJECT_NAME="$canonical"
            fi
        fi

        # Module name validated already; need the language too.
        if [[ -z "$ADD_MODULE_LANG" ]]; then
            if check_tty_available; then
                # Interactive completion of a partial CLI invocation.
                local lang
                while true; do
                    echo -n "Module language for '$ADD_MODULE_NAME' (${AVAILABLE_LANGUAGES[*]}): " > /dev/tty
                    IFS='' read -r lang < /dev/tty
                    if validate_language "$lang"; then
                        ADD_MODULE_LANG="$lang"
                        break
                    fi
                done
            else
                print_error "--add-module requires --lang in non-interactive mode"
                exit 1
            fi
        fi

        if ! validate_module_name "$ADD_MODULE_NAME"; then
            exit 1
        fi

        MODULES=("${ADD_MODULE_NAME}:${ADD_MODULE_LANG}")
        SELECTED_LANGUAGES=("$ADD_MODULE_LANG")
        print_info "Add-module mode: ${ADD_MODULE_NAME} (${ADD_MODULE_LANG})"
        return 0
    fi

    # --- Auto-detect existing monorepo (no explicit flag) ---------------------
    # If the user just ran `./setup.sh` in a directory that already contains
    # modules.json, offer to add a module rather than re-init from scratch.
    if [[ "$MONOREPO_MODE" != true ]] && detect_existing_monorepo "$target_dir"; then
        # Validate before offering anything (Critical #2 from #263 review).
        if ! read_modules_json "$target_dir" >/dev/null; then
            exit 1
        fi
        if check_tty_available; then
            echo "" > /dev/tty
            print_info "Existing monorepo detected (modules.json present)."
            if confirm "Add a new module?" "y"; then
                IS_ADD_MODULE_MODE=true
                local entry name lang
                entry=$(prompt_add_module)
                name="${entry%%:*}"
                lang="${entry#*:}"
                ADD_MODULE_NAME="$name"
                ADD_MODULE_LANG="$lang"
                MODULES=("$entry")
                SELECTED_LANGUAGES=("$lang")
                print_info "Add-module mode: ${name} (${lang})"
                return 0
            fi
            # User declined; nothing to do.
            print_info "Nothing to do."
            exit 0
        else
            # Non-interactive run inside an existing monorepo with no flags
            # is a no-op (avoid accidental re-init in CI).
            print_info "Existing monorepo detected; no flags given. Use --add-module to add."
            exit 0
        fi
    fi

    # --- Monorepo init path ---------------------------------------------------
    if [[ "$MONOREPO_MODE" == true ]]; then
        if [[ ${#MODULES[@]} -eq 0 ]]; then
            if check_tty_available; then
                prompt_module_loop
            else
                print_error "--monorepo requires --module entries in non-interactive mode"
                exit 1
            fi
        fi
        derive_selected_languages_from_modules
        return 0
    fi

    # --- Default: ask whether to enable monorepo (interactive only) ----------
    if check_tty_available; then
        local answer
        answer=$(prompt_monorepo_mode)
        if [[ "$answer" == "true" ]]; then
            MONOREPO_MODE=true
            prompt_module_loop
            derive_selected_languages_from_modules
            return 0
        fi
    fi

    # Fall through: single mode (no change).
}

# Populate SELECTED_LANGUAGES from MODULES (deduplicated, order-preserving).
derive_selected_languages_from_modules() {
    local seen entry lang
    declare -A seen=()
    SELECTED_LANGUAGES=()
    for entry in "${MODULES[@]}"; do
        lang="${entry#*:}"
        if [[ -z "${seen[$lang]:-}" ]]; then
            SELECTED_LANGUAGES+=("$lang")
            seen[$lang]=1
        fi
    done
}

# In add-module mode, fail fast (or prompt) when the requested module name
# already exists in modules.json. Honors --overwrite (-y also bypasses the
# prompt). Exits 0 on a clean decline.
check_add_module_conflict() {
    local target_dir entry name
    target_dir="$(pwd)"

    for entry in "${MODULES[@]}"; do
        name="${entry%%:*}"
        if ! find_module_by_name "$target_dir" "$name"; then
            continue
        fi

        if [[ "$OVERWRITE_ALL" == true ]]; then
            print_warning "Module '$name' exists; will overwrite (--overwrite)"
            continue
        fi

        if check_tty_available; then
            if confirm "Module '$name' already exists. Overwrite?" "n"; then
                OVERWRITE_ALL=true
                print_info "Overwriting module '$name' on user confirmation"
            else
                print_info "Skipped: $name"
                exit 0
            fi
        else
            print_error "Module '$name' exists. Re-run with --overwrite to replace."
            exit 1
        fi
    done
}

# Reduce both the interactive AVAILABLE_SERVICES list and the CLI-flag-set
# SELECTED_SERVICES list to only those services that would NOT collide with
# something already defined in the existing docker-compose.yml (FR-10,
# Critical #3 from #263 review).
#
# We compute "would collide" by reading the candidate overlay's own service
# keys and substituting {{PROJECT_NAME}}, then checking against the target's
# current top-level service list. This is more accurate than hardcoded
# suffix tables — postgresql and mysql both produce `<project>-db`, celery
# produces both `-celery-worker` and `-celery-beat`, etc.
filter_available_services_for_add_module() {
    local target_dir svc_id
    target_dir="$(pwd)"

    if [[ ! -f "${target_dir}/docker-compose.yml" ]]; then
        return 0
    fi

    # Filter interactive offer list.
    local -a remaining=()
    for svc_id in "${AVAILABLE_SERVICES[@]}"; do
        if service_overlay_collides_with_target "$svc_id" "$target_dir"; then
            print_info "Service '$svc_id' would collide with existing compose service; will not offer."
        else
            remaining+=("$svc_id")
        fi
    done
    AVAILABLE_SERVICES=("${remaining[@]}")

    # Scrub the CLI-flag-populated SELECTED_SERVICES list too — without this,
    # `--add-module foo --lang python --postgresql` against a project that
    # already has postgres would re-run the postgres plugin and append
    # duplicate compose services / depends_on / env vars.
    local -a selected_remaining=()
    for svc_id in "${SELECTED_SERVICES[@]}"; do
        if service_overlay_collides_with_target "$svc_id" "$target_dir"; then
            print_warning "Service '$svc_id' (from CLI flag) would collide with existing compose service; skipping."
        else
            selected_remaining+=("$svc_id")
        fi
    done
    SELECTED_SERVICES=("${selected_remaining[@]}")
}

# Check whether the candidate service plugin's compose overlay would
# introduce a service key that already exists in the target compose file.
# Returns 0 (collision) / 1 (no collision).
service_overlay_collides_with_target() {
    local svc_id="$1"
    local target_dir="$2"
    local overlay="${TEMPLATES_DIR}/services/${svc_id}/docker-compose.${svc_id}.yml"

    [[ -f "$overlay" ]] || return 1

    local existing_services overlay_services
    existing_services=$(list_existing_compose_services "$target_dir")

    # Substitute {{PROJECT_NAME}} FIRST so the resulting service keys match
    # the same `^  [a-zA-Z]...` shape as list_existing_compose_services
    # (raw overlay keys start with `{`, so awk needs the substituted form).
    overlay_services=$(sed "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" "$overlay" | awk '
        /^services:[[:space:]]*$/ { in_services = 1; next }
        /^[a-zA-Z]/ && !/^[[:space:]]/ { in_services = 0 }
        in_services && /^  [a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
            sub(/^  /, ""); sub(/:[[:space:]]*$/, ""); print
        }
    ')

    local svc existing
    for svc in $overlay_services; do
        for existing in $existing_services; do
            if [[ "$svc" == "$existing" ]]; then
                return 0
            fi
        done
    done
    return 1
}

# =============================================================================
# Manifest Modes (#265)
# =============================================================================

# Infer the scaffold_options object as a JSON string from filesystem evidence
# in <target_dir>. Used by --create-manifest to fill the manifest's
# scaffold_options field for legacy projects that have no recorded scaffold
# parameters.
#
# Usage: infer_scaffold_options <target_dir> <monorepo_bool> [<single_lang>]
#   <single_lang> overrides languages[] when set (used by per-module
#   manifests where the module's language is known from modules.json).
infer_scaffold_options() {
    local target_dir="$1"
    local monorepo_flag="$2"
    local single_lang="${3:-}"

    local languages_json='[]'
    if [[ -n "$single_lang" ]]; then
        languages_json=$(printf '%s' "$single_lang" | jq -Rs 'split("\n") | map(select(length>0))')
    elif [[ "$monorepo_flag" == true ]] && [[ -f "$target_dir/modules.json" ]]; then
        languages_json=$(jq '[.modules[].language] | unique' "$target_dir/modules.json" 2>/dev/null || echo '[]')
    else
        # Single mode: probe for the per-language marker files emitted by
        # each language plugin's plugin_post_copy.
        local langs=()
        [[ -f "$target_dir/Cargo.toml" ]] && langs+=(rust)
        [[ -f "$target_dir/pyproject.toml" ]] && langs+=(python)
        [[ -f "$target_dir/package.json" ]] && langs+=(node)
        [[ -f "$target_dir/deno.json" || -f "$target_dir/deno.jsonc" ]] && langs+=(deno)
        # LaTeX has no canonical root manifest; the build-pdf workflow is
        # the cleanest indicator.
        [[ -f "$target_dir/.github/workflows/build-pdf.yml" ]] && langs+=(latex)
        if [[ ${#langs[@]} -eq 0 ]]; then
            languages_json='[]'
        else
            languages_json=$(printf '%s\n' "${langs[@]}" | jq -Rs 'split("\n") | map(select(length>0))')
        fi
    fi

    # Services: scan docker-compose.yml for top-level service ids that match
    # the well-known plugin names. Per-module manifests do not carry services
    # (services are project-wide).
    local services_json='[]'
    if [[ -z "$single_lang" ]] && [[ -f "$target_dir/docker-compose.yml" ]]; then
        local svcs=()
        # Service names use the {{PROJECT_NAME}}-<svc> convention; check for
        # the `<...>-db|redis|celery-worker` shapes.
        local compose="$target_dir/docker-compose.yml"
        grep -qE '^  [a-z][a-z0-9_-]*-db:[[:space:]]*$' "$compose" 2>/dev/null && {
            # disambiguate db type by the image
            if grep -q "image: postgres" "$compose"; then svcs+=(postgresql); fi
            if grep -q "image: mysql" "$compose"; then svcs+=(mysql); fi
        }
        grep -qE '^  [a-z][a-z0-9_-]*-redis:[[:space:]]*$' "$compose" 2>/dev/null && svcs+=(redis)
        grep -qE '^  [a-z][a-z0-9_-]*-celery-worker:[[:space:]]*$' "$compose" 2>/dev/null && svcs+=(celery)
        if [[ ${#svcs[@]} -gt 0 ]]; then
            services_json=$(printf '%s\n' "${svcs[@]}" | jq -Rs 'split("\n") | map(select(length>0))')
        fi
    fi

    local gha=false ata=false codex=false
    [[ -f "$target_dir/.github/workflows/project-integration.yml" ]] && gha=true
    [[ -f "$target_dir/.github/workflows/auto-tag.yml" ]] && ata=true
    [[ -f "$target_dir/.codex/config.toml" ]] && codex=true

    jq -n \
        --argjson languages "$languages_json" \
        --argjson services "$services_json" \
        --argjson gha "$gha" \
        --argjson ata "$ata" \
        --argjson codex "$codex" \
        --argjson monorepo "$monorepo_flag" \
        '{
            languages: $languages,
            services: $services,
            github_actions_enabled: $gha,
            auto_tag_enabled: $ata,
            codex_enabled: $codex,
            monorepo: $monorepo
        }'
}

# Walk a directory and load its current contents into MANIFEST_TRACKED so
# manifest_write can persist them. Used by --create-manifest.
#
# Usage: load_manifest_from_walk <root> [<additional_skip_prefix>...]
load_manifest_from_walk() {
    local root="$1"
    shift
    manifest_recording_start "$root"
    local rel hash
    while IFS=$'\t' read -r rel hash; do
        [[ -z "$rel" ]] && continue
        MANIFEST_TRACKED["$rel"]="$hash"
    done < <(manifest_walk_directory "$root" "$@")
    manifest_recording_stop
}

# Bootstrap a manifest for an existing project. Detects single vs monorepo
# by the presence of modules.json. In monorepo mode, writes a root manifest
# (covering shared assets) and one manifest per registered module.
#
# Usage: run_create_manifest <target_dir>
# Returns: 0 on success.
run_create_manifest() {
    local target_dir="$1"

    if [[ ! -d "$target_dir" ]]; then
        print_error "create-manifest: target directory not found: $target_dir"
        return 1
    fi

    local from_version="${FROM_VERSION:-unknown}"
    local commit=""

    print_section "Creating Manifest"
    print_info "target: $target_dir"
    print_info "tarnished_version: $from_version"

    if [[ "$DRY_RUN" == true ]]; then
        print_info "(dry-run: no manifest will be written)"
    fi

    if detect_existing_monorepo "$target_dir"; then
        print_info "monorepo target detected (modules.json present)"

        # Collect module names so we can both skip them in the root walk and
        # iterate them for per-module manifests.
        local modules=()
        local m
        while IFS= read -r m; do
            [[ -n "$m" ]] && modules+=("$m")
        done < <(list_module_names "$target_dir")

        # Root manifest: walk root, skipping every module subtree.
        local opts
        opts="$(infer_scaffold_options "$target_dir" true)"
        load_manifest_from_walk "$target_dir" "${modules[@]}"
        if [[ "$DRY_RUN" != true ]]; then
            manifest_write "$target_dir" "$from_version" "$commit" "$opts"
            print_success "wrote $(manifest_path "$target_dir")"
        else
            print_info "would write root manifest with ${#MANIFEST_TRACKED[@]} file entries"
        fi

        # Per-module manifests.
        local module
        for module in "${modules[@]}"; do
            local module_dir="$target_dir/$module"
            if [[ ! -d "$module_dir" ]]; then
                print_warning "module '$module' has no directory at $module_dir; skipping"
                continue
            fi
            local lang
            lang=$(jq -r --arg n "$module" '.modules[] | select(.name == $n) | .language' "$target_dir/modules.json" 2>/dev/null)
            local module_opts
            module_opts="$(infer_scaffold_options "$module_dir" false "$lang")"
            load_manifest_from_walk "$module_dir"
            if [[ "$DRY_RUN" != true ]]; then
                manifest_write "$module_dir" "$from_version" "$commit" "$module_opts"
                print_success "wrote $(manifest_path "$module_dir")"
            else
                print_info "would write $module manifest with ${#MANIFEST_TRACKED[@]} file entries"
            fi
        done
    else
        print_info "single-mode target detected"
        local opts
        opts="$(infer_scaffold_options "$target_dir" false)"
        load_manifest_from_walk "$target_dir"
        if [[ "$DRY_RUN" != true ]]; then
            manifest_write "$target_dir" "$from_version" "$commit" "$opts"
            print_success "wrote $(manifest_path "$target_dir")"
        else
            print_info "would write manifest with ${#MANIFEST_TRACKED[@]} file entries"
        fi
    fi

    return 0
}

# =============================================================================
# Upgrade Mode (#265 Phase 3)
# =============================================================================

# FR-9: refuse to run --upgrade against a dirty git tree (without --force).
# A non-git target is treated as clean (with a warning) — manifest tracking
# does not require git, but the safety net of "you can `git checkout` if
# something goes wrong" is missing.
#
# Usage: check_git_clean <target_dir>
# Returns: 0 if safe to proceed, 1 if dirty without --force.
check_git_clean() {
    local target_dir="$1"

    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    if ! git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null; then
        print_warning "Target is not a git repository — proceeding without clean-tree check"
        return 0
    fi

    if git -C "$target_dir" diff-index --quiet HEAD -- 2>/dev/null; then
        return 0
    fi

    print_error "Target git tree has uncommitted changes."
    print_error "Commit or stash your changes, or pass --force to override."
    return 1
}

# Resolve the upstream tarnished source for --upgrade. When --target-version
# is empty, use SCRIPT_DIR (the in-process tarnished checkout) directly to
# avoid a redundant clone. When set, clone tarnished@<ref> into a fresh
# temp dir.
#
# Sets UPSTREAM_DIR, UPSTREAM_VERSION, UPSTREAM_COMMIT.
# Caller is responsible for cleaning UPSTREAM_DIR if it differs from
# SCRIPT_DIR.
#
# Usage: resolve_target_version
# Returns: 0 on success, 1 on clone failure.
resolve_target_version() {
    if [[ -z "$TARGET_VERSION" ]]; then
        UPSTREAM_DIR="$SCRIPT_DIR"
        UPSTREAM_VERSION=$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || echo "${REMOTE_BRANCH:-develop}")
        UPSTREAM_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "")
        return 0
    fi

    UPSTREAM_DIR=$(mktemp -d)/upstream
    print_info "Cloning upstream tarnished@${TARGET_VERSION}..."
    if ! git clone --depth 1 --branch "$TARGET_VERSION" --quiet "$REMOTE_REPO_URL" "$UPSTREAM_DIR" 2>/dev/null; then
        # Branch / tag not found; try as a commit by cloning then checking out.
        rm -rf "$UPSTREAM_DIR" 2>/dev/null
        if ! git clone --quiet "$REMOTE_REPO_URL" "$UPSTREAM_DIR" 2>/dev/null; then
            print_error "Failed to clone upstream tarnished from $REMOTE_REPO_URL"
            return 1
        fi
        if ! git -C "$UPSTREAM_DIR" checkout --quiet "$TARGET_VERSION" 2>/dev/null; then
            print_error "Failed to resolve --target-version: $TARGET_VERSION"
            return 1
        fi
    fi

    UPSTREAM_VERSION="$TARGET_VERSION"
    UPSTREAM_COMMIT=$(git -C "$UPSTREAM_DIR" rev-parse HEAD 2>/dev/null || echo "")
    return 0
}

# Cleanup helper for resolve_target_version's tmp clone.
cleanup_upstream_dir() {
    if [[ -n "${UPSTREAM_DIR:-}" ]] && [[ "$UPSTREAM_DIR" != "$SCRIPT_DIR" ]] && [[ -d "$UPSTREAM_DIR" ]]; then
        case "$UPSTREAM_DIR" in
            /tmp/*) rm -rf "$(dirname "$UPSTREAM_DIR")" 2>/dev/null || true ;;
        esac
    fi
}

# Run the loaded plugin pipeline (copies + dockerfile + post-copy) against a
# scratch staging directory. The recording wrapper in copy_with_confirm
# populates MANIFEST_TRACKED with each emitted file. When this returns,
# MANIFEST_TRACKED holds the new-version hashes for the active scope.
#
# Usage: stage_plugin_run <upstream_dir> <staging_dir>
stage_plugin_run() {
    local upstream_dir="$1"
    local staging_dir="$2"

    # Pre-seed the staging tree so plugins can append to expected files
    # (Dockerfile.dev / post.sh / devcontainer.json).
    mkdir -p "$staging_dir/.devcontainer/scripts"
    mkdir -p "$staging_dir/.claude"
    mkdir -p "$staging_dir/.github/workflows"
    mkdir -p "$staging_dir/docker"

    manifest_recording_start "$staging_dir"
    # The execute_plugin_* helpers source plugins from LOADED_PLUGINS and
    # call plugin_copy / plugin_dockerfile / plugin_post_copy. We need to
    # temporarily point LOADED_PLUGINS at the upstream's templates so
    # SOURCE files are read from there.
    #
    # The plugins themselves discover their own files via PLUGIN_DIR (set
    # at the top of each plugin.sh from BASH_SOURCE), so re-sourcing them
    # from upstream recomputes PLUGIN_DIR correctly.
    local saved_templates="$TEMPLATES_DIR"
    TEMPLATES_DIR="${upstream_dir}/templates"
    load_selected_plugins
    execute_plugin_copies "$staging_dir"
    execute_plugin_dockerfiles "$staging_dir"
    execute_plugin_post_copies "$staging_dir"
    TEMPLATES_DIR="$saved_templates"
    manifest_recording_stop
}

# Re-run plugin_post_copy hooks against the user's real target tree (not
# the staging area). FR-5: merge logic is idempotent and reapplying it
# absorbs any new whitelist blocks / merge entries from the upgraded
# templates. Verbatim files have already been resolved by the lifecycle
# loop; this pass only mutates merge/append targets.
#
# Usage: rerun_post_copy_on_target <upstream_dir> <target_dir>
rerun_post_copy_on_target() {
    local upstream_dir="$1"
    local target_dir="$2"

    local saved_templates="$TEMPLATES_DIR"
    TEMPLATES_DIR="${upstream_dir}/templates"
    # Reload plugin functions from upstream so PLUGIN_DIR is correct.
    load_selected_plugins
    # Recording is OFF here — we don't want plugin_post_copy's mutations
    # entering the manifest.
    execute_plugin_post_copies "$target_dir"
    TEMPLATES_DIR="$saved_templates"
}

# Drive a single upgrade scope. Reads the existing manifest, stages plugins
# at the upstream, dispatches the FR-4 lifecycle per file, and writes the
# new manifest.
#
# Usage: apply_decisions_for_scope <scope_root> <staging_dir> <scope_label>
# Returns: 0 on success.
apply_decisions_for_scope() {
    local scope_root="$1"
    local staging_dir="$2"
    local scope_label="$3"

    if ! manifest_exists "$scope_root"; then
        print_error "no manifest at $scope_root — run 'setup.sh --create-manifest' first"
        return 1
    fi

    local old_json
    if ! old_json=$(manifest_read "$scope_root"); then
        return 1
    fi

    # Snapshot old hashes into a local map.
    declare -A OLD_HASHES=()
    while IFS=$'\t' read -r path hash; do
        [[ -z "$path" ]] && continue
        OLD_HASHES["$path"]="$hash"
    done < <(echo "$old_json" | jq -r '.files | to_entries[] | "\(.key)\t\(.value)"')

    # Snapshot new hashes from the staged run that just populated
    # MANIFEST_TRACKED. Copy now because subsequent operations may clear
    # the global.
    declare -A NEW_HASHES=()
    local k
    for k in "${!MANIFEST_TRACKED[@]}"; do
        NEW_HASHES["$k"]="${MANIFEST_TRACKED[$k]}"
    done

    # Reset tallies for this scope.
    manifest_tally_reset

    # Build the union of paths to consider.
    declare -A ALL_PATHS=()
    for k in "${!OLD_HASHES[@]}"; do
        ALL_PATHS["$k"]=1
    done
    for k in "${!NEW_HASHES[@]}"; do
        ALL_PATHS["$k"]=1
    done

    local rel old current new staging_path target_path decision
    for rel in "${!ALL_PATHS[@]}"; do
        old="${OLD_HASHES[$rel]:-}"
        new="${NEW_HASHES[$rel]:-}"
        target_path="${scope_root}/${rel}"
        staging_path="${staging_dir}/${rel}"
        if [[ -f "$target_path" ]]; then
            current=$(sha256_file "$target_path")
        else
            current=""
        fi
        decision=$(manifest_decide "$old" "$current" "$new")
        manifest_apply "$decision" "$rel" "$staging_path" "$target_path" || true
    done

    # Re-run plugin_post_copy on the real target so merge logic / new
    # whitelist blocks land (FR-5). Recording is OFF.
    if [[ "${DRY_RUN:-false}" != true ]]; then
        rerun_post_copy_on_target "$UPSTREAM_DIR" "$scope_root"
    fi

    # Write the new manifest. MANIFEST_TRACKED already holds the new
    # hashes from the staged run; transfer to the scope-local map and
    # write.
    if [[ "${DRY_RUN:-false}" != true ]]; then
        # Reset MANIFEST_TRACKED to the new-hashes set (drop NEW_HASHES
        # entries that the user has rejected with SKIP_NEW_CONFLICT —
        # they belong to the user, not the manifest).
        unset MANIFEST_TRACKED
        declare -gA MANIFEST_TRACKED
        for k in "${!NEW_HASHES[@]}"; do
            local skipped=false
            local sk
            for sk in "${SKIPPED_NEW_CONFLICT_FILES[@]}"; do
                if [[ "$sk" == "$k" ]]; then
                    skipped=true
                    break
                fi
            done
            [[ "$skipped" == true ]] && continue
            MANIFEST_TRACKED["$k"]="${NEW_HASHES[$k]}"
        done

        local opts
        opts="$(infer_scaffold_options "$scope_root" "$(echo "$old_json" | jq -r '.scaffold_options.monorepo // false')")"
        manifest_write "$scope_root" "$UPSTREAM_VERSION" "$UPSTREAM_COMMIT" "$opts"
    fi

    manifest_summary_print "$(echo "$old_json" | jq -r .tarnished_version)" "$UPSTREAM_VERSION" "$scope_label"
}

# Top-level orchestrator for `setup.sh --upgrade`. Computes the set of
# scopes to process based on --shared-only / --module / target's monorepo
# state, then drives each scope through apply_decisions_for_scope.
#
# Usage: run_upgrade <target_dir>
# Returns: 0 on success.
run_upgrade() {
    local target_dir="$1"

    if [[ ! -d "$target_dir" ]]; then
        print_error "upgrade: target directory not found: $target_dir"
        return 1
    fi

    if ! manifest_exists "$target_dir"; then
        print_error "no .tarnished-manifest.json at $target_dir"
        print_error "Run 'setup.sh --create-manifest' first to bootstrap the manifest."
        return 1
    fi

    if ! check_git_clean "$target_dir"; then
        return 1
    fi

    if ! resolve_target_version; then
        return 1
    fi
    trap cleanup_upstream_dir EXIT

    local is_monorepo=false
    if detect_existing_monorepo "$target_dir"; then
        is_monorepo=true
    fi

    if [[ "$SHARED_ONLY" == true ]] && [[ "$is_monorepo" != true ]]; then
        print_warning "--shared-only has no effect on single-mode targets; ignoring"
        SHARED_ONLY=false
    fi

    if [[ ${#UPGRADE_MODULES[@]} -gt 0 ]] && [[ "$is_monorepo" != true ]]; then
        print_error "--module is monorepo-only; this target has no modules.json"
        return 1
    fi

    print_section "Upgrade"
    print_info "target: $target_dir"
    print_info "tarnished_version → ${UPSTREAM_VERSION}"
    if [[ "$DRY_RUN" == true ]]; then
        print_info "(dry-run: no files will be modified)"
    fi

    local old_root_json old_version
    old_root_json=$(manifest_read "$target_dir") || return 1
    old_version=$(echo "$old_root_json" | jq -r '.tarnished_version')

    # Print the top-of-summary header once for the entire run; per-scope
    # sections are appended via manifest_summary_print(scope_label).
    {
        printf '\n'
        printf 'Tarnished upgrade summary (%s → %s)\n' "$old_version" "$UPSTREAM_VERSION"
        printf '─────────────────────────────────────────────\n'
    } >&2

    # Drive scopes.
    if [[ "$is_monorepo" == true ]]; then
        # Determine which modules to touch.
        local modules=()
        local m
        while IFS= read -r m; do
            [[ -n "$m" ]] && modules+=("$m")
        done < <(list_module_names "$target_dir")

        if [[ ${#UPGRADE_MODULES[@]} -gt 0 ]]; then
            # Validate each requested module exists.
            local req
            for req in "${UPGRADE_MODULES[@]}"; do
                local found=false
                for m in "${modules[@]}"; do
                    [[ "$m" == "$req" ]] && { found=true; break; }
                done
                if [[ "$found" != true ]]; then
                    print_error "module '$req' not found in modules.json"
                    return 1
                fi
            done
            # Limit modules to the requested set (and disable shared
            # processing implicitly unless --shared-only is also given).
            modules=("${UPGRADE_MODULES[@]}")
        fi

        # --- Shared (root) scope --------------------------------------
        local process_shared=true
        if [[ ${#UPGRADE_MODULES[@]} -gt 0 ]] && [[ "$SHARED_ONLY" != true ]]; then
            # Default behavior when only --module foo is given: skip
            # shared (per workflow.md compute_upgrade_scopes spec).
            process_shared=false
        fi

        if [[ "$process_shared" == true ]]; then
            # Set up plugin selection from the old manifest's
            # scaffold_options so the staged run reproduces the original
            # scaffold flavor.
            populate_setup_state_from_manifest "$old_root_json" true
            local stage_dir
            stage_dir=$(mktemp -d)/stage-shared
            mkdir -p "$stage_dir"
            stage_plugin_run "$UPSTREAM_DIR" "$stage_dir"
            apply_decisions_for_scope "$target_dir" "$stage_dir" "shared"
            rm -rf "$(dirname "$stage_dir")" 2>/dev/null || true
        fi

        if [[ "$SHARED_ONLY" != true ]]; then
            # --- Per-module scopes ----------------------------------------
            local module_scope_root module_old_json module_lang
            for m in "${modules[@]}"; do
                module_scope_root="$target_dir/$m"
                if ! manifest_exists "$module_scope_root"; then
                    print_warning "module '$m' has no manifest — skipping (run --create-manifest to bootstrap)"
                    continue
                fi
                module_old_json=$(manifest_read "$module_scope_root") || continue
                module_lang=$(echo "$module_old_json" | jq -r '.scaffold_options.languages[0] // empty')
                populate_setup_state_from_manifest "$module_old_json" false "$module_lang" "$m"

                local mstage
                mstage=$(mktemp -d)/stage-"$m"
                mkdir -p "$mstage"
                stage_plugin_run "$UPSTREAM_DIR" "$mstage"
                apply_decisions_for_scope "$module_scope_root" "$mstage" "$m"
                rm -rf "$(dirname "$mstage")" 2>/dev/null || true
            done
        fi
    else
        # Single-mode target.
        populate_setup_state_from_manifest "$old_root_json" false
        local stage_dir
        stage_dir=$(mktemp -d)/stage
        mkdir -p "$stage_dir"
        stage_plugin_run "$UPSTREAM_DIR" "$stage_dir"
        apply_decisions_for_scope "$target_dir" "$stage_dir" ""
        rm -rf "$(dirname "$stage_dir")" 2>/dev/null || true
    fi

    {
        printf '─────────────────────────────────────────────\n'
        if [[ "$DRY_RUN" == true ]]; then
            printf '  Dry-run; no files were modified.\n'
        else
            printf '  Manifest updated.\n'
        fi
    } >&2

    return 0
}

# Populate setup.sh's plugin/option globals from a manifest's
# scaffold_options so that load_selected_plugins picks the same flavors
# the project was originally scaffolded with.
#
# Usage: populate_setup_state_from_manifest <manifest_json> <is_root_scope> [<single_lang>] [<module_name>]
populate_setup_state_from_manifest() {
    local manifest_json="$1"
    local is_root_scope="$2"
    local single_lang="${3:-}"
    local module_name="${4:-}"

    # Reset per-run selections.
    SELECTED_LANGUAGES=()
    SELECTED_SERVICES=()
    POSTGRESQL_ENABLED=false
    MYSQL_ENABLED=false
    REDIS_ENABLED=false
    CELERY_ENABLED=false
    GITHUB_ACTIONS_ENABLED=false
    AUTO_TAG_ENABLED=false
    CODEX_ENABLED=false
    LOADED_PLUGINS=()
    PLUGIN_NAMES=()

    if [[ -n "$single_lang" ]]; then
        SELECTED_LANGUAGES+=("$single_lang")
    else
        local lang
        while IFS= read -r lang; do
            [[ -n "$lang" ]] && SELECTED_LANGUAGES+=("$lang")
        done < <(echo "$manifest_json" | jq -r '.scaffold_options.languages[]?')
    fi

    local svc
    while IFS= read -r svc; do
        case "$svc" in
            postgresql) POSTGRESQL_ENABLED=true; SELECTED_SERVICES+=("postgresql") ;;
            mysql)      MYSQL_ENABLED=true;      SELECTED_SERVICES+=("mysql") ;;
            redis)      REDIS_ENABLED=true;      SELECTED_SERVICES+=("redis") ;;
            celery)     CELERY_ENABLED=true;     SELECTED_SERVICES+=("celery") ;;
        esac
    done < <(echo "$manifest_json" | jq -r '.scaffold_options.services[]?')

    GITHUB_ACTIONS_ENABLED=$(echo "$manifest_json" | jq -r '.scaffold_options.github_actions_enabled // false')
    AUTO_TAG_ENABLED=$(echo "$manifest_json" | jq -r '.scaffold_options.auto_tag_enabled // false')
    CODEX_ENABLED=$(echo "$manifest_json" | jq -r '.scaffold_options.codex_enabled // false')
    MONOREPO_MODE=$(echo "$manifest_json" | jq -r '.scaffold_options.monorepo // false')

    # In monorepo per-module scopes we want the language plugins to take
    # the _module path, not _shared. Easiest way: pretend we're in
    # add-module mode for that module.
    if [[ "$is_root_scope" != true ]] && [[ -n "$module_name" ]]; then
        IS_ADD_MODULE_MODE=true
        ADD_MODULE_NAME="$module_name"
        ADD_MODULE_LANG="$single_lang"
        MODULES=("${module_name}:${single_lang}")
    else
        IS_ADD_MODULE_MODE=false
        ADD_MODULE_NAME=""
        ADD_MODULE_LANG=""
        MODULES=()
    fi

    PROJECT_NAME="$(basename "$(pwd)")"
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

    # Manifest modes (#265) short-circuit before any scaffold work. They
    # operate on existing project trees and have nothing to do with
    # project name, language selection, or plugin pipelines.
    if [[ "$CREATE_MANIFEST_MODE" == true ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/scripts/lib/manifest.sh"
        run_create_manifest "$(pwd)"
        exit $?
    fi

    if [[ "$UPGRADE_MODE" == true ]]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/scripts/lib/manifest.sh"
        run_upgrade "$(pwd)"
        exit $?
    fi

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

    # Resolve operating mode (single | monorepo init | add-module). Populates
    # MONOREPO_MODE, IS_ADD_MODULE_MODE, MODULES, and SELECTED_LANGUAGES.
    # Single mode (the only mode in pre-#263 setup.sh) is the no-op default.
    resolve_setup_mode

    # In add-module mode, check for module-name collisions before doing any
    # work so the user can decline without partial writes (FR-9).
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        check_add_module_conflict
    fi

    # Select language if not specified (single-mode only — monorepo derives
    # SELECTED_LANGUAGES from MODULES inside resolve_setup_mode).
    if [[ "$MONOREPO_MODE" != true ]] && [[ ${#SELECTED_LANGUAGES[@]} -eq 0 ]]; then
        prompt_language_selection
    fi

    # In add-module mode, filter the service-selection menu to only the
    # services not already present in the existing docker-compose.yml.
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        filter_available_services_for_add_module
    fi

    # Select services if not specified
    if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
        prompt_service_selection
    fi

    # Prompt for optional features if in interactive mode. In add-module mode
    # these plugins are skipped by load_selected_plugins (they own root assets
    # already installed by the original --monorepo init), so prompting would
    # create a silent no-op (Warning #5 from #263 review).
    if check_tty_available && [[ "$IS_ADD_MODULE_MODE" != true ]]; then
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

    # Same reasoning for the explicit CLI flags — emit a one-time warning if
    # the user passed them with --add-module so they know they will be no-ops.
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        if [[ "$CODEX_ENABLED" == true ]]; then
            print_warning "--codex is ignored in add-module mode (Codex was set up by the original --monorepo init)"
            CODEX_ENABLED=false
        fi
        if [[ "$GITHUB_ACTIONS_ENABLED" == true ]]; then
            print_warning "--github-actions is ignored in add-module mode (already installed by the original --monorepo init)"
            GITHUB_ACTIONS_ENABLED=false
        fi
        if [[ "$AUTO_TAG_ENABLED" == true ]]; then
            print_warning "--auto-tag is ignored in add-module mode (already installed by the original --monorepo init)"
            AUTO_TAG_ENABLED=false
        fi
    fi

    # Confirm settings
    print_section "Setup Configuration"
    echo "Project name:         $PROJECT_NAME"
    if [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        echo "Mode:                 add-module (${MODULES[0]})"
    elif [[ "$MONOREPO_MODE" == true ]]; then
        echo "Mode:                 monorepo init"
        echo "Modules:              ${MODULES[*]}"
    else
        echo "Mode:                 single-project"
    fi
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

    # Monorepo registry maintenance (#263). Decoupled from the plugin
    # pipeline so that add-module mode (which skips core plugin) still
    # writes modules.json + per-module CLAUDE.md.
    if [[ "$MONOREPO_MODE" == true ]] || [[ "$IS_ADD_MODULE_MODE" == true ]]; then
        print_info "Updating monorepo registry..."
        # Source core plugin once to expose the registry helpers — cheap and
        # avoids duplicating the implementation in setup.sh itself.
        unset_plugin_functions
        source "${TEMPLATES_DIR}/core/plugin.sh"
        core_seed_modules_json "$TARGET_DIR"
        core_write_per_module_claude_md "$TARGET_DIR"
        unset_plugin_functions
    fi

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
    echo "  /design    - Design architecture for a GitHub Issue"
    echo "  /implement - Implement a GitHub Issue"
    echo "  /review    - Code review via Codex CLI"
    echo "  /pr        - Create a Pull Request"
    echo ""
    echo "Workflow: /issue → /design → /implement → /review → /pr"
}

# Run main function
main "$@"
