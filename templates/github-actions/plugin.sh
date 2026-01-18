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
#   - pr-status-update: Automatic issue status update when PR is opened
#
# Future Actions (planned):
#   - auto-label: Automatic PR labeling based on branch/files
#   - release-notes: Changelog generation on tag creation
#
# Note: Action source code is maintained in .github/actions/ at repo root.
#       This plugin contains only distribution files (action.yml + dist/).
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
    echo "GitHub Actions templates (auto-tag, project-automation, pr-status-update, CI/CD workflows)"
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
    "pr-status-update"
    # "auto-label"      # TODO: Implement
    # "release-notes"   # TODO: Implement
)

# =============================================================================
# Helper Functions
# =============================================================================

# Read input with masked display (shows * for each character)
# Supports paste and backspace for secure token entry
# Returns: input string via stdout
read_masked_input() {
    local input=""
    local old_stty_settings=""

    # Save current terminal settings and disable echo at stty level
    old_stty_settings=$(stty -g 2>/dev/null) || true
    stty -echo 2>/dev/null || true

    # Disable bracket paste mode to prevent escape sequences from being captured
    printf '\e[?2004l' >/dev/tty 2>/dev/null || true

    # Small delay to ensure settings take effect
    sleep 0.05

    # Read entire line at once (simpler and more reliable than char-by-char)
    IFS= read -r input < /dev/tty

    # Re-enable bracket paste mode
    printf '\e[?2004h' >/dev/tty 2>/dev/null || true

    # Restore terminal settings
    if [[ -n "$old_stty_settings" ]]; then
        stty "$old_stty_settings" 2>/dev/null || true
    else
        stty echo 2>/dev/null || true
    fi

    # Sanitize: remove bracket paste escape sequences and non-printable characters
    # \e[200~ is paste start, \e[201~ is paste end
    input=$(printf '%s' "$input" | sed 's/\x1b\[[0-9;]*[~A-Za-z]//g' | tr -cd '[:print:]')

    # Display asterisks for the sanitized input length
    local input_len=${#input}
    if [[ $input_len -gt 0 ]]; then
        printf '%*s' "$input_len" '' | tr ' ' '*' >&2
    fi
    echo "" >&2

    printf '%s' "$input"
}

# Check if an action exists in the plugin
action_exists() {
    local action_name="$1"
    local action_dir="${PLUGIN_DIR}/.github/actions/${action_name}"
    [[ -d "$action_dir" ]]
}

# Copy a single action to the target directory
# Only copies essential files (action.yml, dist/) and excludes development files
copy_action() {
    local action_name="$1"
    local target_dir="$2"

    local src_action="${PLUGIN_DIR}/.github/actions/${action_name}"
    local src_workflow="${PLUGIN_DIR}/.github/workflows/${action_name}.yml"
    local dest_action="${target_dir}/.github/actions/${action_name}"
    local dest_workflow="${target_dir}/.github/workflows/${action_name}.yml"

    # Copy action directory if exists (only essential files)
    if [[ -d "$src_action" ]]; then
        mkdir -p "$dest_action"

        # Copy action.yml
        if [[ -f "${src_action}/action.yml" ]]; then
            cp "${src_action}/action.yml" "$dest_action/"
        fi

        # Copy dist directory (bundled JavaScript)
        if [[ -d "${src_action}/dist" ]]; then
            cp -r "${src_action}/dist" "$dest_action/"
        fi

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
        echo -n "Overwrite? [y/N]: "
        IFS='' read -r overwrite < /dev/tty
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            print_info "Skipping project-automation setup"
            return 0
        fi
    fi

    # Prompt for PAT (temporary, for field discovery)
    echo "A GitHub Personal Access Token is required to fetch project fields."
    echo "This token will NOT be saved. You'll need to add it to repository secrets separately."
    echo ""

    local pat=""
    while true; do
        printf "GitHub Personal Access Token (for field discovery): "
        pat=$(read_masked_input)

        if [[ -z "$pat" ]]; then
            echo ""
            echo -n "No token provided. Skip project-automation setup? [Y/n]: "
            IFS='' read -r skip_confirm < /dev/tty
            if [[ -z "$skip_confirm" ]] || [[ "$skip_confirm" =~ ^[Yy] ]]; then
                print_info "Skipping project-automation setup"
                return 0
            fi
            # User chose not to skip, retry token input
            echo ""
            continue
        fi

        # Token provided, show confirmation and break
        print_success "Token received (${#pat} characters)"
        break
    done

    # Prompt for project type
    echo ""
    echo "Select GitHub Project type:"
    echo "  1) Organization Project"
    echo "  2) Repository (User) Project"
    echo -n "Choice [1-2]: "
    IFS='' read -r project_type_choice < /dev/tty

    local project_type
    case "$project_type_choice" in
        1) project_type="organization" ;;
        2) project_type="user" ;;
        *)
            print_warning "Invalid choice. Defaulting to organization."
            project_type="organization"
            ;;
    esac

    # Prompt for owner
    echo -n "Owner/Organization name: "
    IFS='' read -r owner < /dev/tty
    if [[ -z "$owner" ]]; then
        print_error "Owner name is required"
        return 1
    fi

    # Prompt for project number
    echo -n "Project number: "
    IFS='' read -r project_number < /dev/tty
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
        create_project_config "$config_file" "$project_type" "$owner" "$project_number" \
            "" "" "" "" "" "" "" "" "" ""
        return 0
    fi

    # Parse and display available fields
    echo ""
    print_info "Available fields:"
    echo "$fields_json" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || echo "  (Could not parse fields)"

    # Prompt for default values
    echo ""
    print_info "Configure default field values (press Enter to skip):"

    local status_field=""
    local status_value=""
    local priority_field=""
    local priority_value=""
    local iteration_field=""
    local iteration_value=""
    local start_field=""
    local start_value=""
    local end_field=""
    local end_value=""

    # Status field
    status_field=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "status") | .name' 2>/dev/null | head -1)
    local status_options
    status_options=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "status") | .options // [] | .[].name' 2>/dev/null)
    if [[ -n "$status_options" ]]; then
        echo ""
        echo "Available ${status_field:-Status} options:"
        echo "$status_options" | while read -r opt; do echo "  - $opt"; done
        echo -n "Default ${status_field:-Status}: "
        IFS='' read -r status_value < /dev/tty
    fi

    # Priority field
    priority_field=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "priority") | .name' 2>/dev/null | head -1)
    local priority_options
    priority_options=$(echo "$fields_json" | jq -r '.[] | select(.name | ascii_downcase == "priority") | .options // [] | .[].name' 2>/dev/null)
    if [[ -n "$priority_options" ]]; then
        echo ""
        echo "Available ${priority_field:-Priority} options:"
        echo "$priority_options" | while read -r opt; do echo "  - $opt"; done
        echo -n "Default ${priority_field:-Priority}: "
        IFS='' read -r priority_value < /dev/tty
    fi

    # Iteration field
    iteration_field=$(echo "$fields_json" | jq -r '.[] | select(.type == "ITERATION") | .name' 2>/dev/null | head -1)
    if [[ -n "$iteration_field" ]]; then
        # Get iteration options from API
        local iterations
        iterations=$(echo "$fields_json" | jq -r '.[] | select(.type == "ITERATION") | .iterations // [] | .[].title' 2>/dev/null)

        echo ""
        echo "Available ${iteration_field} options:"
        echo "  1) @current_iteration (現在のイテレーション)"
        local i=2
        while IFS= read -r iter; do
            if [[ -n "$iter" ]]; then
                echo "  $i) $iter"
                ((i++))
            fi
        done <<< "$iterations"

        echo -n "Default ${iteration_field} [1]: "
        IFS='' read -r iter_choice < /dev/tty

        # Process selection
        if [[ -z "$iter_choice" ]] || [[ "$iter_choice" == "1" ]]; then
            iteration_value="@current_iteration"
        else
            # Get specific iteration (subtract 1 for 0-based index, then subtract 1 more for @current_iteration option)
            local iter_index=$((iter_choice - 2))
            iteration_value=$(echo "$iterations" | sed -n "$((iter_index + 1))p")
            # Fallback to @current_iteration if invalid
            if [[ -z "$iteration_value" ]]; then
                iteration_value="@current_iteration"
            fi
        fi

        # Auto-set Start/End fields when Iteration is selected
        start_field=$(echo "$fields_json" | jq -r '.[] | select(.type == "DATE") | select(.name | ascii_downcase == "start") | .name' 2>/dev/null | head -1)
        end_field=$(echo "$fields_json" | jq -r '.[] | select(.type == "DATE") | select(.name | ascii_downcase == "end") | .name' 2>/dev/null | head -1)

        if [[ -n "$start_field" ]]; then
            start_value="@today"
            echo ""
            print_info "Auto-setting ${start_field}: @today"
        fi

        if [[ -n "$end_field" ]]; then
            end_value="@iteration_end"
            print_info "Auto-setting ${end_field}: @iteration_end"
        fi
    fi

    # Create configuration file
    create_project_config "$config_file" "$project_type" "$owner" "$project_number" \
        "$status_field" "$status_value" \
        "$priority_field" "$priority_value" \
        "$iteration_field" "$iteration_value" \
        "$start_field" "$start_value" \
        "$end_field" "$end_value"

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
            configuration {
              iterations {
                id
                title
              }
            }
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

    # Extract fields from response, including iteration configurations
    echo "$response" | jq -r ".data.${query_type}.projectV2.fields.nodes // [] | map({name: .name, type: .dataType, options: .options, iterations: .configuration.iterations})" 2>/dev/null
}

# Create minimal project configuration (with dynamic defaults)
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
  # Project type: 'organization' or 'user'
  type: organization
  # Owner name (organization or user)
  owner: "your-org"
  # Project number (visible in project URL)
  number: 1

# Default field values
# Dynamic values: @current_iteration, @today, @iteration_end
defaults:
  Status: "Ready"
  Iteration: "@current_iteration"
  Start: "@today"
  End: "@iteration_end"
EOF
}

# Create project configuration with values
# Parameters:
#   $1  - config_file path
#   $2  - project_type (organization/user)
#   $3  - owner name
#   $4  - project number
#   $5  - status_field name (from API)
#   $6  - status_value
#   $7  - priority_field name (from API)
#   $8  - priority_value
#   $9  - iteration_field name (from API)
#   $10 - iteration_value
#   $11 - start_field name (from API)
#   $12 - start_value
#   $13 - end_field name (from API)
#   $14 - end_value
create_project_config() {
    local config_file="$1"
    local project_type="$2"
    local owner="$3"
    local number="$4"
    local status_field="$5"
    local status_value="$6"
    local priority_field="$7"
    local priority_value="$8"
    local iteration_field="$9"
    local iteration_value="${10}"
    local start_field="${11}"
    local start_value="${12}"
    local end_field="${13}"
    local end_value="${14}"

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
  # Project type: 'organization' or 'user'
  type: ${project_type}
  # Owner name (organization or user)
  owner: "${owner}"
  # Project number (visible in project URL)
  number: ${number}
EOF

    # Add defaults section if any values are set
    local has_defaults=false
    if [[ -n "$status_value" ]] || [[ -n "$priority_value" ]] || [[ -n "$iteration_value" ]]; then
        has_defaults=true
    fi

    if [[ "$has_defaults" == "true" ]]; then
        echo "" >> "$config_file"
        echo "# Default field values" >> "$config_file"
        echo "# Dynamic values: @current_iteration, @today, @iteration_end" >> "$config_file"
        echo "defaults:" >> "$config_file"

        if [[ -n "$status_value" ]]; then
            local field_name="${status_field:-Status}"
            echo "  ${field_name}: \"${status_value}\"" >> "$config_file"
        fi

        if [[ -n "$priority_value" ]]; then
            local field_name="${priority_field:-Priority}"
            echo "  ${field_name}: \"${priority_value}\"" >> "$config_file"
        fi

        if [[ -n "$iteration_value" ]]; then
            local field_name="${iteration_field:-Iteration}"
            echo "  ${field_name}: \"${iteration_value}\"" >> "$config_file"

            # Add Start/End if iteration is set
            if [[ -n "$start_value" ]]; then
                local start_name="${start_field:-Start}"
                echo "  ${start_name}: \"${start_value}\"" >> "$config_file"
            fi

            if [[ -n "$end_value" ]]; then
                local end_name="${end_field:-End}"
                echo "  ${end_name}: \"${end_value}\"" >> "$config_file"
            fi
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
        echo -n "Configure project-automation action? [Y/n]: "
        IFS='' read -r setup_project < /dev/tty
        # Default to yes if empty or starts with Y/y
        if [[ -z "$setup_project" ]] || [[ "$setup_project" =~ ^[Yy] ]]; then
            setup_project_automation "$target_dir"
        else
            print_info "Skipping project-automation setup"
        fi
    fi

    return 0
}

# =============================================================================
# Plugin Minimal Setup Hook (for non-interactive mode)
# =============================================================================

plugin_minimal_setup() {
    local target_dir="$1"

    # Check if project-automation action was installed
    if [[ -d "${target_dir}/.github/actions/project-automation" ]]; then
        local config_file="${target_dir}/.github/project-automation.yml"

        # Only create if not exists
        if [[ ! -f "$config_file" ]]; then
            print_info "Creating minimal project-automation configuration..."
            create_minimal_project_config "$config_file"
            print_success "  Created: ${config_file}"
            print_warning "  Remember to update the configuration with your project details!"
        fi
    fi

    return 0
}
