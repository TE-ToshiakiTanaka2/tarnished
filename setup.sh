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
CORE_TEMPLATE="${TEMPLATES_DIR}/core"
NODE_TEMPLATE="${TEMPLATES_DIR}/node"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║         Devcontainer Boilerplate Setup Script                     ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

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

Features Included:
    - Git and GitHub CLI
    - Claude Code CLI
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
        echo ""
        echo "Please install the missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        echo "  macOS:         brew install ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# =============================================================================
# Template Functions
# =============================================================================

copy_core_template() {
    local target_dir="$1"

    print_info "Copying core template files..."

    # Copy all files from core template
    cp -r "${CORE_TEMPLATE}/.devcontainer" "${target_dir}/"
    cp -r "${CORE_TEMPLATE}/docker" "${target_dir}/"
    cp -r "${CORE_TEMPLATE}/.claude" "${target_dir}/"
    cp "${CORE_TEMPLATE}/docker-compose.yml" "${target_dir}/"

    # Make post.sh executable
    chmod +x "${target_dir}/.devcontainer/scripts/post.sh"

    print_success "Core template files copied"
}

merge_language_features() {
    local target_dir="$1"
    local lang_template="$2"

    print_info "Merging language-specific features..."

    local core_config="${target_dir}/.devcontainer/devcontainer.json"
    local lang_config="${lang_template}/.devcontainer/devcontainer.json"
    local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

    # Merge JSON files using jq
    # Strategy: deep merge, combining features and customizations
    jq -s '
        .[0] as $core | .[1] as $lang |
        $core * {
            features: ($core.features + $lang.features),
            customizations: {
                vscode: {
                    extensions: (($core.customizations.vscode.extensions // []) + ($lang.customizations.vscode.extensions // []) | unique),
                    settings: (($core.customizations.vscode.settings // {}) + ($lang.customizations.vscode.settings // {}))
                }
            }
        }
    ' "$core_config" "$lang_config" > "$temp_file"

    mv "$temp_file" "$core_config"

    print_success "Language features merged"
}

replace_placeholders() {
    local target_dir="$1"
    local project_name="$2"

    print_info "Replacing placeholders with project name: ${project_name}"

    # Files to process
    local files=(
        "${target_dir}/.devcontainer/devcontainer.json"
        "${target_dir}/docker-compose.yml"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            # Use sed to replace placeholder
            if [[ "$(uname)" == "Darwin" ]]; then
                # macOS
                sed -i '' "s/{{PROJECT_NAME}}/${project_name}/g" "$file"
            else
                # Linux
                sed -i "s/{{PROJECT_NAME}}/${project_name}/g" "$file"
            fi
        fi
    done

    print_success "Placeholders replaced"
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
    echo "  └── .claude/"
    echo "      └── settings.json"
    echo ""
}

show_completion() {
    local project_name="$1"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete!                                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_success "Devcontainer environment created successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Open the project in VS Code"
    echo "  2. Click 'Reopen in Container' when prompted"
    echo "     Or use Command Palette: 'Dev Containers: Reopen in Container'"
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

    # Check if templates exist
    if [[ ! -d "$CORE_TEMPLATE" ]]; then
        print_error "Core template not found at: $CORE_TEMPLATE"
        print_info "Please run this script from the devcontainer-boilerplate repository"
        exit 1
    fi

    if [[ ! -d "$NODE_TEMPLATE" ]]; then
        print_error "Node.js template not found at: $NODE_TEMPLATE"
        exit 1
    fi

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

    # Execute setup
    copy_core_template "$target_dir"
    merge_language_features "$target_dir" "$NODE_TEMPLATE"
    replace_placeholders "$target_dir" "$project_name"

    show_completion "$project_name"
}

# Run main function
main "$@"
