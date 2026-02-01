#!/bin/sh
# =============================================================================
# DevContainer Setup Script
# =============================================================================
# Dotfiles-style setup script for initializing DevContainer environments
# with Claude Code and SuperClaude support.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/main/setup.sh | bash
#   ./setup.sh
#
# POSIX sh compatible for maximum portability
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
REPO_URL="https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/main"

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
        features="${features}    \"ghcr.io/anthropics/devcontainer-features/claude-code:1.0\": {}\n"
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

    # Remove language setup placeholder for now
    processed=$(printf "%s" "$template" | sed '/{{LANGUAGE_SETUP}}/d')

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

    # Remove extras placeholder for now
    processed=$(printf "%s" "$template" | sed '/{{DOCKERFILE_EXTRAS}}/d')

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

    # Empty hooks for now
    processed=$(printf "%s" "$template" | sed 's/{{HOOKS}}//')

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
    echo ""
    echo "Features enabled:"
    [ "$FEATURE_GIT" = "y" ] && echo "  - git"
    [ "$FEATURE_GITHUB_CLI" = "y" ] && echo "  - github-cli"
    [ "$FEATURE_CLAUDE_CODE" = "y" ] && echo "  - claude-code"
    [ "$FEATURE_UV" = "y" ] && echo "  - uv (for SuperClaude)"
    echo ""
    echo "Next steps:"
    echo "  1. Open this folder in VS Code"
    echo "  2. Click 'Reopen in Container' when prompted"
    echo "  3. Wait for the container to build and start"
    echo "  4. Run 'claude' to start using Claude Code"
    echo ""
}

main() {
    show_banner
    check_prerequisites
    collect_project_info
    collect_feature_selection
    generate_files
    show_summary
}

main "$@"
