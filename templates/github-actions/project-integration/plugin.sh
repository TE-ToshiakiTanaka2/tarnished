#!/bin/bash
# =============================================================================
# Template Plugin: github-actions/project-integration
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides GitHub Project integration using erd CLI:
# - Automatic issue linking to GitHub Projects
# - PR status updates for linked issues
# - Project configuration file generation
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "github-actions-project-integration"
}

# Return plugin description
plugin_description() {
    echo "GitHub Project integration workflows using erd CLI"
}

# =============================================================================
# Interactive Setup Functions
# =============================================================================

# Prompt for GitHub Project configuration
plugin_interactive_setup() {
    print_section "GitHub Project Integration Setup"

    echo "This will configure GitHub Project integration for your repository."
    echo "You need a GitHub Personal Access Token with 'repo' and 'project' scopes."
    echo ""

    # Check if TTY is available
    if ! check_tty_available; then
        print_warning "Non-interactive mode: Using default values"
        PROJECT_OWNER=""
        PROJECT_NUMBER="1"
        DEFAULT_STATUS="Backlog"
        PR_OPEN_STATUS="In Review"
        return 0
    fi

    # Get project owner
    local default_owner=""
    if command -v gh &> /dev/null; then
        default_owner=$(gh api user --jq '.login' 2>/dev/null || echo "")
    fi

    echo -n "Enter GitHub Project owner (username or org)" > /dev/tty
    if [[ -n "$default_owner" ]]; then
        echo -n " [$default_owner]" > /dev/tty
    fi
    echo -n ": " > /dev/tty
    read -r PROJECT_OWNER < /dev/tty
    PROJECT_OWNER="${PROJECT_OWNER:-$default_owner}"

    # Get project number
    echo -n "Enter GitHub Project number [1]: " > /dev/tty
    read -r PROJECT_NUMBER < /dev/tty
    PROJECT_NUMBER="${PROJECT_NUMBER:-1}"

    # Get default status
    echo -n "Enter default status for new issues [Backlog]: " > /dev/tty
    read -r DEFAULT_STATUS < /dev/tty
    DEFAULT_STATUS="${DEFAULT_STATUS:-Backlog}"

    # Get PR open status
    echo -n "Enter status when PR is opened [In Review]: " > /dev/tty
    read -r PR_OPEN_STATUS < /dev/tty
    PR_OPEN_STATUS="${PR_OPEN_STATUS:-In Review}"

    echo ""
    print_success "Project configuration collected"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    print_info "Copying GitHub Project integration workflows..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow files
    if [[ -d "${PLUGIN_DIR}/.github/workflows" ]]; then
        for workflow in "${PLUGIN_DIR}/.github/workflows"/*.yml; do
            if [[ -f "$workflow" ]]; then
                local workflow_name
                workflow_name=$(basename "$workflow")
                copy_with_confirm "$workflow" "${target_dir}/.github/workflows/${workflow_name}"
            fi
        done
    fi

    print_success "GitHub Actions workflows copied"
}

# Post-copy processing - create project.yml config
plugin_post_copy() {
    local target_dir="$1"

    # Run interactive setup if not already done
    if [[ -z "${PROJECT_OWNER:-}" ]]; then
        plugin_interactive_setup
    fi

    # Create .github/project.yml
    local project_config="${target_dir}/.github/project.yml"

    if [[ -f "$project_config" ]]; then
        print_warning "project.yml already exists, skipping"
    else
        print_info "Creating .github/project.yml..."

        mkdir -p "${target_dir}/.github"

        cat > "$project_config" << EOF
# GitHub Project Integration Configuration
# For use with erd CLI: https://github.com/TE-ToshiakiTanaka2/tarnished

default_project:
  owner: "${PROJECT_OWNER}"
  number: ${PROJECT_NUMBER}

field_defaults:
  Status: "${DEFAULT_STATUS}"
  Size: "M"
  Priority: "P1"

pr_status:
  on_open: "${PR_OPEN_STATUS}"
EOF

        print_success "Created .github/project.yml"
    fi

    # Remind about PROJECT_TOKEN secret
    echo ""
    print_warning "Remember to add PROJECT_TOKEN secret to your repository:"
    echo "  Settings > Secrets and variables > Actions > New repository secret"
    echo "  Name: PROJECT_TOKEN"
    echo "  Value: Your GitHub Personal Access Token with 'repo' and 'project' scopes"
    echo ""
}
