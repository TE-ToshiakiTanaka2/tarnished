#!/bin/bash
# =============================================================================
# Template Plugin: github-actions/project-integration
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides GitHub Project integration using erd CLI:
# - Automatic issue linking to GitHub Projects
# - PR status updates for linked issues
# - Auto-tagging based on branch naming conventions
# - Project configuration file generation
#
# Workflows are implemented as caller workflows that invoke reusable workflows
# from the TE-ToshiakiTanaka2/tarnished repository.
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
    echo "GitHub Project integration workflows using erd CLI (reusable workflows)"
}

# =============================================================================
# Interactive Setup Functions
# =============================================================================

# Prompt for GitHub Project configuration
plugin_interactive_setup() {
    print_section "GitHub Project Integration Setup"

    echo "This will configure GitHub Project integration for your repository."
    echo "Workflows will call reusable workflows from TE-ToshiakiTanaka2/tarnished."
    echo ""
    echo "You need a GitHub Personal Access Token with 'repo' and 'project' scopes."
    echo ""

    # Check if TTY is available
    if ! check_tty_available; then
        print_warning "Non-interactive mode: Using default values"
        PROJECT_OWNER=""
        PROJECT_NUMBER="1"
        DEFAULT_STATUS="Backlog"
        PR_OPEN_STATUS="In Review"
        ERD_REF="develop"
        ENABLE_AUTO_TAG="n"
        return 0
    fi

    # Get erd branch/tag to use
    echo "Which branch/tag of erd workflows should be used?" > /dev/tty
    echo "  - Use 'develop' for latest version (recommended)" > /dev/tty
    echo "  - Use a specific tag (e.g., v1.0.0) for pinned version" > /dev/tty
    echo -n "Enter erd workflow ref [develop]: " > /dev/tty
    read -r ERD_REF < /dev/tty
    ERD_REF="${ERD_REF:-develop}"

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

    # Ask about auto-tag
    echo "" > /dev/tty
    echo -n "Enable auto-tagging workflow? (y/n) [n]: " > /dev/tty
    read -r ENABLE_AUTO_TAG < /dev/tty
    ENABLE_AUTO_TAG="${ENABLE_AUTO_TAG:-n}"

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

    # Copy workflow files with version replacement
    if [[ -d "${PLUGIN_DIR}/.github/workflows" ]]; then
        for workflow in "${PLUGIN_DIR}/.github/workflows"/*.yml; do
            if [[ -f "$workflow" ]]; then
                local workflow_name
                workflow_name=$(basename "$workflow")

                # Skip auto-tag if not enabled
                if [[ "$workflow_name" == "auto-tag.yml" && "${ENABLE_AUTO_TAG:-n}" != "y" ]]; then
                    print_info "Skipping auto-tag.yml (not enabled)"
                    continue
                fi

                # Read, replace version placeholder, and write
                local target_file="${target_dir}/.github/workflows/${workflow_name}"
                if [[ -f "$target_file" ]]; then
                    echo -n "  $workflow_name already exists. Overwrite? (y/n) [n]: "
                    if check_tty_available; then
                        read -r overwrite < /dev/tty
                    else
                        overwrite="n"
                    fi
                    if [[ "$overwrite" != "y" ]]; then
                        print_info "Skipping $workflow_name"
                        continue
                    fi
                fi

                # Replace __ERD_REF__ placeholder with actual ref
                sed "s/__ERD_REF__/${ERD_REF:-develop}/g" "$workflow" > "$target_file"
                print_success "Created $workflow_name (using @${ERD_REF:-develop})"
            fi
        done
    fi

    print_success "GitHub Actions workflows copied"
}

# Post-copy processing - create config files
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

    # Create .github/versioning.yml if auto-tag is enabled
    if [[ "${ENABLE_AUTO_TAG:-n}" == "y" ]]; then
        local versioning_config="${target_dir}/.github/versioning.yml"

        if [[ -f "$versioning_config" ]]; then
            print_warning "versioning.yml already exists, skipping"
        else
            print_info "Creating .github/versioning.yml..."

            cat > "$versioning_config" << 'EOF'
# Auto-Tag Version Configuration
# For use with erd CLI: https://github.com/TE-ToshiakiTanaka2/tarnished

branches:
  - prefix: "major/"
    bump: major
  - prefix: "release/"
    bump: minor
  - prefix: "feature/"
    bump: patch
  - prefix: "fix/"
    bump: patch
  - prefix: "bugfix/"
    bump: patch
  - prefix: "hotfix/"
    bump: patch

# Default bump type when branch doesn't match any prefix
default_bump: rc
EOF

            print_success "Created .github/versioning.yml"
        fi
    fi

    # Remind about PROJECT_TOKEN secret
    echo ""
    print_warning "Remember to add PROJECT_TOKEN secret to your repository:"
    echo "  Settings > Secrets and variables > Actions > New repository secret"
    echo "  Name: PROJECT_TOKEN"
    echo "  Value: Your GitHub Personal Access Token with 'repo' and 'project' scopes"
    echo ""
    echo "Workflows are configured to use erd @${ERD_REF:-develop}"
    echo ""
}
