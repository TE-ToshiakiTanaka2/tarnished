#!/bin/bash
# =============================================================================
# Template Plugin: github-actions/project-integration
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides GitHub Project integration using gh CLI:
# - Automatic issue linking to GitHub Projects
# - PR status updates for linked issues
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
    echo "GitHub Project integration workflows using gh CLI (reusable workflows)"
}

# =============================================================================
# Helper Functions for gh CLI Integration
# =============================================================================

# Check if gh CLI is available
check_gh_available() {
    command -v gh &> /dev/null
}

# Get repository in owner/repo format
get_current_repo() {
    if check_gh_available; then
        gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null
    else
        # Try to extract from git remote
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            # Extract owner/repo from various URL formats
            echo "$remote_url" | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$|\1|'
        fi
    fi
}

# Get current user's login
get_current_user() {
    if check_gh_available; then
        gh api user --jq '.login' 2>/dev/null
    fi
}

# Get projects for owner using gh CLI
# Returns JSON: {"projects": [...]}
get_owner_projects() {
    local owner="$1"
    if check_gh_available && [[ -n "$owner" ]]; then
        gh project list --owner "$owner" --format json 2>/dev/null
    fi
}

# Get project field details using gh CLI
# Returns JSON: {"fields": [...]}
get_project_fields() {
    local owner="$1"
    local number="$2"
    if check_gh_available && [[ -n "$owner" ]] && [[ -n "$number" ]]; then
        gh project field-list "$number" --owner "$owner" --format json 2>/dev/null
    fi
}

# Parse JSON array and display as selection menu
# Returns the selected item's index (0-based)
select_from_json_array() {
    local json_array="$1"
    local display_field="$2"
    local prompt_text="$3"

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        return 1
    fi

    # Get array length
    local count
    count=$(echo "$json_array" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        return 1
    fi

    # Display options
    echo "$prompt_text" > /dev/tty
    local i
    for ((i=0; i<count; i++)); do
        local display_value
        display_value=$(echo "$json_array" | jq -r ".[$i].$display_field // .[$i]")
        echo "  $((i+1))) $display_value" > /dev/tty
    done

    # Read selection
    local selection
    echo -n "Enter selection [1]: " > /dev/tty
    read -r selection < /dev/tty
    selection="${selection:-1}"

    # Validate and return 0-based index
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
        echo $((selection - 1))
        return 0
    fi

    echo "0"
    return 0
}

# =============================================================================
# Interactive Setup Functions
# =============================================================================

# Prompt for GitHub Project configuration with gh CLI integration
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
        DEFAULT_SIZE="M"
        DEFAULT_PRIORITY="P1"
        PR_OPEN_STATUS="In Review"
        ERD_REF="develop"
        return 0
    fi

    # Get erd branch/tag to use
    echo "Which branch/tag of erd workflows should be used?" > /dev/tty
    echo "  - Use 'develop' for latest version (recommended)" > /dev/tty
    echo "  - Use a specific tag (e.g., v1.0.0) for pinned version" > /dev/tty
    echo -n "Enter erd workflow ref [develop]: " > /dev/tty
    read -r ERD_REF < /dev/tty
    ERD_REF="${ERD_REF:-develop}"

    # Try to detect projects using gh CLI
    local use_gh_detection=false
    local owner_projects=""
    local current_user=""

    if check_gh_available; then
        print_info "Detected gh CLI, attempting to fetch projects..."
        current_user=$(get_current_user)

        if [[ -n "$current_user" ]]; then
            owner_projects=$(get_owner_projects "$current_user")
            if [[ -n "$owner_projects" ]]; then
                local project_count
                project_count=$(echo "$owner_projects" | jq '.projects | length')
                if [[ "$project_count" -gt 0 ]]; then
                    use_gh_detection=true
                    print_success "Found $project_count projects for $current_user"
                else
                    print_warning "No projects found for $current_user"
                fi
            else
                print_warning "Could not fetch projects for $current_user"
            fi
        else
            print_warning "Could not determine current user"
        fi
    else
        print_info "gh CLI not found, using manual configuration"
    fi

    # Project selection: gh auto-detection or manual input
    if [[ "$use_gh_detection" == true ]]; then
        echo "" > /dev/tty
        local project_count
        project_count=$(echo "$owner_projects" | jq '.projects | length')

        if [[ "$project_count" -eq 1 ]]; then
            # Single project: auto-select
            PROJECT_OWNER=$(echo "$owner_projects" | jq -r '.projects[0].owner.login')
            PROJECT_NUMBER=$(echo "$owner_projects" | jq -r '.projects[0].number')
            local project_title
            project_title=$(echo "$owner_projects" | jq -r '.projects[0].title')
            print_success "Auto-selected project: $project_title (#$PROJECT_NUMBER) @$PROJECT_OWNER"
        else
            # Multiple projects: let user choose
            echo "Found $project_count projects:" > /dev/tty
            local i
            for ((i=0; i<project_count; i++)); do
                local title owner number
                title=$(echo "$owner_projects" | jq -r ".projects[$i].title")
                owner=$(echo "$owner_projects" | jq -r ".projects[$i].owner.login")
                number=$(echo "$owner_projects" | jq -r ".projects[$i].number")
                echo "  $((i+1))) $title (#$number) @$owner" > /dev/tty
            done

            echo -n "Select project [1]: " > /dev/tty
            local selection
            read -r selection < /dev/tty
            selection="${selection:-1}"

            local idx=$((selection - 1))
            if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$project_count" ]]; then
                PROJECT_OWNER=$(echo "$owner_projects" | jq -r ".projects[$idx].owner.login")
                PROJECT_NUMBER=$(echo "$owner_projects" | jq -r ".projects[$idx].number")
            else
                PROJECT_OWNER=$(echo "$owner_projects" | jq -r '.projects[0].owner.login')
                PROJECT_NUMBER=$(echo "$owner_projects" | jq -r '.projects[0].number')
            fi
        fi

        # Fetch project field details
        echo "" > /dev/tty
        print_info "Fetching project field information..."
        local project_fields
        project_fields=$(get_project_fields "$PROJECT_OWNER" "$PROJECT_NUMBER")

        if [[ -n "$project_fields" ]]; then
            # Extract Status field options (gh CLI returns options as array of objects with name key)
            local status_options
            status_options=$(echo "$project_fields" | jq -r '[.fields[] | select(.name == "Status") | .options[]?.name] // []')

            # Extract Size field options
            local size_options
            size_options=$(echo "$project_fields" | jq -r '[.fields[] | select(.name == "Size") | .options[]?.name] // []')

            # Extract Priority field options
            local priority_options
            priority_options=$(echo "$project_fields" | jq -r '[.fields[] | select(.name == "Priority") | .options[]?.name] // []')

            # Interactive field selection: Status
            if [[ -n "$status_options" ]] && [[ "$status_options" != "[]" ]] && [[ "$status_options" != "null" ]]; then
                echo "" > /dev/tty
                echo "Select default Status for new issues:" > /dev/tty
                local status_count
                status_count=$(echo "$status_options" | jq 'length')
                for ((i=0; i<status_count; i++)); do
                    echo "  $((i+1))) $(echo "$status_options" | jq -r ".[$i]")" > /dev/tty
                done
                echo -n "Enter selection [1]: " > /dev/tty
                read -r selection < /dev/tty
                selection="${selection:-1}"
                local idx=$((selection - 1))
                if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$status_count" ]]; then
                    DEFAULT_STATUS=$(echo "$status_options" | jq -r ".[$idx]")
                else
                    DEFAULT_STATUS=$(echo "$status_options" | jq -r '.[0]')
                fi

                # PR open status selection from same options
                echo "" > /dev/tty
                echo "Select Status when PR is opened:" > /dev/tty
                for ((i=0; i<status_count; i++)); do
                    echo "  $((i+1))) $(echo "$status_options" | jq -r ".[$i]")" > /dev/tty
                done
                echo -n "Enter selection [1]: " > /dev/tty
                read -r selection < /dev/tty
                selection="${selection:-1}"
                idx=$((selection - 1))
                if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$status_count" ]]; then
                    PR_OPEN_STATUS=$(echo "$status_options" | jq -r ".[$idx]")
                else
                    PR_OPEN_STATUS=$(echo "$status_options" | jq -r '.[0]')
                fi
            else
                echo -n "Enter default status for new issues [Backlog]: " > /dev/tty
                read -r DEFAULT_STATUS < /dev/tty
                DEFAULT_STATUS="${DEFAULT_STATUS:-Backlog}"
                echo -n "Enter status when PR is opened [In Review]: " > /dev/tty
                read -r PR_OPEN_STATUS < /dev/tty
                PR_OPEN_STATUS="${PR_OPEN_STATUS:-In Review}"
            fi

            # Interactive field selection: Size
            if [[ -n "$size_options" ]] && [[ "$size_options" != "[]" ]] && [[ "$size_options" != "null" ]]; then
                echo "" > /dev/tty
                echo "Select default Size for new issues:" > /dev/tty
                local size_count
                size_count=$(echo "$size_options" | jq 'length')
                for ((i=0; i<size_count; i++)); do
                    echo "  $((i+1))) $(echo "$size_options" | jq -r ".[$i]")" > /dev/tty
                done
                echo -n "Enter selection [1]: " > /dev/tty
                read -r selection < /dev/tty
                selection="${selection:-1}"
                local idx=$((selection - 1))
                if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$size_count" ]]; then
                    DEFAULT_SIZE=$(echo "$size_options" | jq -r ".[$idx]")
                else
                    DEFAULT_SIZE=$(echo "$size_options" | jq -r '.[0]')
                fi
            else
                echo -n "Enter default size for new issues [M]: " > /dev/tty
                read -r DEFAULT_SIZE < /dev/tty
                DEFAULT_SIZE="${DEFAULT_SIZE:-M}"
            fi

            # Interactive field selection: Priority
            if [[ -n "$priority_options" ]] && [[ "$priority_options" != "[]" ]] && [[ "$priority_options" != "null" ]]; then
                echo "" > /dev/tty
                echo "Select default Priority for new issues:" > /dev/tty
                local priority_count
                priority_count=$(echo "$priority_options" | jq 'length')
                for ((i=0; i<priority_count; i++)); do
                    echo "  $((i+1))) $(echo "$priority_options" | jq -r ".[$i]")" > /dev/tty
                done
                echo -n "Enter selection [1]: " > /dev/tty
                read -r selection < /dev/tty
                selection="${selection:-1}"
                local idx=$((selection - 1))
                if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$priority_count" ]]; then
                    DEFAULT_PRIORITY=$(echo "$priority_options" | jq -r ".[$idx]")
                else
                    DEFAULT_PRIORITY=$(echo "$priority_options" | jq -r '.[0]')
                fi
            else
                echo -n "Enter default priority for new issues [P1]: " > /dev/tty
                read -r DEFAULT_PRIORITY < /dev/tty
                DEFAULT_PRIORITY="${DEFAULT_PRIORITY:-P1}"
            fi
        else
            print_warning "Could not fetch project details, using manual input"
            prompt_manual_field_defaults
        fi
    else
        # Manual input fallback
        prompt_manual_project_config
        prompt_manual_field_defaults
    fi

    echo ""
    print_success "Project configuration collected"
}

# Manual project configuration (fallback)
prompt_manual_project_config() {
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

    echo -n "Enter GitHub Project number [1]: " > /dev/tty
    read -r PROJECT_NUMBER < /dev/tty
    PROJECT_NUMBER="${PROJECT_NUMBER:-1}"
}

# Manual field defaults (fallback)
prompt_manual_field_defaults() {
    echo -n "Enter default status for new issues [Backlog]: " > /dev/tty
    read -r DEFAULT_STATUS < /dev/tty
    DEFAULT_STATUS="${DEFAULT_STATUS:-Backlog}"

    echo -n "Enter default size for new issues [M]: " > /dev/tty
    read -r DEFAULT_SIZE < /dev/tty
    DEFAULT_SIZE="${DEFAULT_SIZE:-M}"

    echo -n "Enter default priority for new issues [P1]: " > /dev/tty
    read -r DEFAULT_PRIORITY < /dev/tty
    DEFAULT_PRIORITY="${DEFAULT_PRIORITY:-P1}"

    echo -n "Enter status when PR is opened [In Review]: " > /dev/tty
    read -r PR_OPEN_STATUS < /dev/tty
    PR_OPEN_STATUS="${PR_OPEN_STATUS:-In Review}"
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
  Size: "${DEFAULT_SIZE:-M}"
  Priority: "${DEFAULT_PRIORITY:-P1}"

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
    echo "Workflows are configured to use erd @${ERD_REF:-develop}"
    echo ""
}
