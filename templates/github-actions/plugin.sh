#!/bin/bash
# =============================================================================
# GitHub Actions Plugin
# =============================================================================
#
# This plugin provides GitHub Actions templates for CI/CD automation.
#
# Available Actions:
#   - auto-tag: Automatic semantic versioning tags on PR merge
#   - project-automation: Automatic issue-to-project linking with field defaults
#
# Future Actions (planned):
#   - auto-label: Automatic PR labeling based on branch/files
#   - release-notes: Changelog generation on tag creation
#
# Testing:
#   Run tests for all actions:  ./scripts/test.sh
#   Run with coverage:          ./scripts/test.sh --coverage
#   Run in watch mode:          ./scripts/test.sh --watch
#
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Plugin Metadata
# =============================================================================

plugin_name() {
    echo "github-actions"
}

plugin_description() {
    echo "GitHub Actions templates (auto-tag, project-automation, CI/CD workflows)"
}

# =============================================================================
# Available Actions Configuration
# =============================================================================
#
# Add new actions here as they are implemented.
# Each action should have:
#   - A directory in .github/actions/{action-name}/
#   - A workflow file in .github/workflows/{action-name}.yml
#   - An entry in this array
#
declare -a AVAILABLE_ACTIONS=(
    "auto-tag"
    "project-automation"
    # "auto-label"      # TODO: Implement
    # "release-notes"   # TODO: Implement
)

# =============================================================================
# Helper Functions
# =============================================================================

# Check if an action exists in the plugin
action_exists() {
    local action_name="$1"
    local action_dir="${PLUGIN_DIR}/.github/actions/${action_name}"
    [[ -d "$action_dir" ]]
}

# Copy a single action to the target directory
copy_action() {
    local action_name="$1"
    local target_dir="$2"

    local src_action="${PLUGIN_DIR}/.github/actions/${action_name}"
    local src_workflow="${PLUGIN_DIR}/.github/workflows/${action_name}.yml"
    local dest_action="${target_dir}/.github/actions/${action_name}"
    local dest_workflow="${target_dir}/.github/workflows/${action_name}.yml"

    # Copy action directory if exists
    if [[ -d "$src_action" ]]; then
        mkdir -p "${target_dir}/.github/actions"
        cp -r "$src_action" "$dest_action"
        print_success "  Copied action: ${action_name}"
    fi

    # Copy workflow file if exists
    if [[ -f "$src_workflow" ]]; then
        mkdir -p "${target_dir}/.github/workflows"
        cp "$src_workflow" "$dest_workflow"
        print_success "  Copied workflow: ${action_name}.yml"
    fi
}

# =============================================================================
# Plugin Hooks
# =============================================================================

plugin_pre_copy() {
    local target_dir="$1"
    # No pre-copy actions needed
    return 0
}

plugin_copy() {
    local target_dir="$1"

    print_info "Installing GitHub Actions templates..."

    # Create .github directories
    mkdir -p "${target_dir}/.github/actions"
    mkdir -p "${target_dir}/.github/workflows"

    # Copy all available actions
    for action_name in "${AVAILABLE_ACTIONS[@]}"; do
        if action_exists "$action_name"; then
            copy_action "$action_name" "$target_dir"
        else
            print_warning "  Action not found: ${action_name} (skipped)"
        fi
    done

    # Copy shared configuration files
    if [[ -f "${PLUGIN_DIR}/.github/version.yml" ]]; then
        cp "${PLUGIN_DIR}/.github/version.yml" "${target_dir}/.github/"
        print_success "  Copied config: version.yml"
    fi

    return 0
}

plugin_post_copy() {
    local target_dir="$1"

    # Display summary of installed actions
    print_info "GitHub Actions installed:"
    for action_name in "${AVAILABLE_ACTIONS[@]}"; do
        if [[ -d "${target_dir}/.github/actions/${action_name}" ]]; then
            echo "    - ${action_name}"
        fi
    done

    return 0
}

plugin_validate() {
    local target_dir="$1"

    # Validate that at least one action was installed
    local installed_count=0
    for action_name in "${AVAILABLE_ACTIONS[@]}"; do
        if [[ -d "${target_dir}/.github/actions/${action_name}" ]]; then
            ((installed_count++))
        fi
    done

    if [[ $installed_count -eq 0 ]]; then
        print_warning "No GitHub Actions were installed"
    fi

    return 0
}

# =============================================================================
# Project Automation Interactive Setup
# =============================================================================

# Setup project-automation action with interactive configuration
setup_project_automation() {
    local target_dir="$1"
    local config_file="${target_dir}/.github/project-automation.yml"

    print_info "Setting up Project Automation..."
    echo ""

    # Check if config already exists
    if [[ -f "$config_file" ]]; then
        print_warning "Configuration file already exists: ${config_file}"
        read -rp "Overwrite? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            print_info "Skipping project-automation setup"
            return 0
        fi
    fi

    # Prompt for PAT (temporary, for field discovery)
    echo "A GitHub Personal Access Token is required to fetch project fields."
    echo "This token will NOT be saved. You'll need to add it to repository secrets separately."
    echo ""
    read -rsp "GitHub Personal Access Token (for field discovery): " pat
    echo ""

    if [[ -z "$pat" ]]; then
        print_warning "No token provided. Creating minimal configuration."
        create_minimal_project_config "$config_file"
        return 0
    fi

    # Prompt for project type
    echo ""
    echo "Select GitHub Project type:"
    echo "  1) Organization Project"
    echo "  2) Repository (User) Project"
    read -rp "Choice [1-2]: " project_type_choice

    local project_type
    case "$project_type_choice" in
        1) project_type="organization" ;;
        2) project_type="repository" ;;
        *)
            print_warning "Invalid choice. Defaulting to organization."
            project_type="organization"
            ;;
    esac

    # Prompt for owner
    read -rp "Owner/Organization name: " owner
    if [[ -z "$owner" ]]; then
        print_error "Owner name is required"
        return 1
    fi

    # Prompt for project number
    read -rp "Project number: " project_number
    if [[ -z "$project_number" ]] || ! [[ "$project_number" =~ ^[0-9]+$ ]]; then
        print_error "Valid project number is required"
        return 1
    fi

    # Fetch project fields
    print_info "Fetching project fields..."
    local fields_json
    fields_json=$(fetch_project_fields "$pat" "$project_type" "$owner" "$project_number")

    if [[ -z "$fields_json" ]] || [[ "$fields_json" == "null" ]]; then
        print_warning "Could not fetch project fields. Creating minimal configuration."
        create_project_config "$config_file" "$project_type" "$owner" "$project_number" "" ""
        return 0
    fi

    # Parse and display available fields
    echo ""
    print_info "Available fields:"
    echo "$fields_json" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || echo "  (Could not parse fields)"

    # Prompt for default values
    echo ""
    print_info "Configure default field values (press Enter to skip):"

    local status_value=""
    local priority_value=""

    # Status field
    local status_options
    status_options=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "status") | .options // [] | .[].name' 2>/dev/null)
    if [[ -n "$status_options" ]]; then
        echo ""
        echo "Available Status options:"
        echo "$status_options" | while read -r opt; do echo "  - $opt"; done
        read -rp "Default Status: " status_value
    fi

    # Priority field
    local priority_options
    priority_options=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "priority") | .options // [] | .[].name' 2>/dev/null)
    if [[ -n "$priority_options" ]]; then
        echo ""
        echo "Available Priority options:"
        echo "$priority_options" | while read -r opt; do echo "  - $opt"; done
        read -rp "Default Priority: " priority_value
    fi

    # Create configuration file
    create_project_config "$config_file" "$project_type" "$owner" "$project_number" "$status_value" "$priority_value"

    print_success "Configuration created: ${config_file}"
    echo ""
    print_warning "Remember to add PROJECT_TOKEN to your repository secrets!"
    echo "  The token needs 'project' and 'repo' scopes."

    return 0
}

# Fetch project fields using GraphQL API
fetch_project_fields() {
    local token="$1"
    local project_type="$2"
    local owner="$3"
    local number="$4"

    local query_type
    if [[ "$project_type" == "organization" ]]; then
        query_type="organization"
    else
        query_type="user"
    fi

    local query
    query=$(cat <<EOF
query {
  ${query_type}(login: "${owner}") {
    projectV2(number: ${number}) {
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            name
            dataType
            options {
              name
            }
          }
          ... on ProjectV2IterationField {
            name
            dataType
          }
        }
      }
    }
  }
}
EOF
)

    local response
    response=$(curl -s -H "Authorization: bearer ${token}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "{\"query\": $(echo "$query" | jq -Rs .)}" \
        https://api.github.com/graphql 2>/dev/null)

    # Extract fields from response
    echo "$response" | jq -r ".data.${query_type}.projectV2.fields.nodes // [] | map({name: .name, type: .dataType, options: .options})" 2>/dev/null
}

# Create minimal project configuration (without defaults)
create_minimal_project_config() {
    local config_file="$1"

    mkdir -p "$(dirname "$config_file")"

    cat > "$config_file" <<'EOF'
# =============================================================================
# Project Automation Configuration
# =============================================================================
# This file configures automatic issue-to-project linking.
#
# Required Secret: PROJECT_TOKEN (PAT with 'project' scope)
# =============================================================================

project:
  # Project type: 'organization' or 'repository'
  type: organization
  # Owner name (organization or user)
  owner: "your-org"
  # Project number (visible in project URL)
  number: 1

# Default field values (uncomment and configure as needed)
# defaults:
#   status: "Backlog"
#   priority: "Medium"
EOF
}

# Create project configuration with values
create_project_config() {
    local config_file="$1"
    local project_type="$2"
    local owner="$3"
    local number="$4"
    local status="$5"
    local priority="$6"

    mkdir -p "$(dirname "$config_file")"

    cat > "$config_file" <<EOF
# =============================================================================
# Project Automation Configuration
# =============================================================================
# This file configures automatic issue-to-project linking.
#
# Required Secret: PROJECT_TOKEN (PAT with 'project' scope)
# =============================================================================

project:
  # Project type: 'organization' or 'repository'
  type: ${project_type}
  # Owner name (organization or user)
  owner: "${owner}"
  # Project number (visible in project URL)
  number: ${number}
EOF

    # Add defaults section if any values are set
    if [[ -n "$status" ]] || [[ -n "$priority" ]]; then
        echo "" >> "$config_file"
        echo "# Default field values" >> "$config_file"
        echo "defaults:" >> "$config_file"

        if [[ -n "$status" ]]; then
            echo "  status: \"${status}\"" >> "$config_file"
        fi

        if [[ -n "$priority" ]]; then
            echo "  priority: \"${priority}\"" >> "$config_file"
        fi
    fi
}

# =============================================================================
# Plugin Interactive Setup Hook
# =============================================================================

plugin_interactive_setup() {
    local target_dir="$1"

    # Check if project-automation action was installed
    if [[ -d "${target_dir}/.github/actions/project-automation" ]]; then
        echo ""
        read -rp "Configure project-automation action? [y/N]: " setup_project
        if [[ "$setup_project" =~ ^[Yy]$ ]]; then
            setup_project_automation "$target_dir"
        fi
    fi

    return 0
}
