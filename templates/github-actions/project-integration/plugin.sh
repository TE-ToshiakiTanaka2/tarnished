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
        gh repo view --json nameWithOwner --jq '.nameWithOwner' </dev/null 2>/dev/null
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
        gh api user --jq '.login' </dev/null 2>/dev/null
    fi
}

# Get projects for owner using gh CLI
# Returns JSON: {"projects": [...]}
get_owner_projects() {
    local owner="$1"
    if check_gh_available && [[ -n "$owner" ]]; then
        gh project list --owner "$owner" --format json </dev/null 2>/dev/null
    fi
}

# Get project field details using gh CLI
# Returns JSON: {"fields": [...]}
get_project_fields() {
    local owner="$1"
    local number="$2"
    if check_gh_available && [[ -n "$owner" ]] && [[ -n "$number" ]]; then
        gh project field-list "$number" --owner "$owner" --format json </dev/null 2>/dev/null
    fi
}

# Get detailed project fields using GraphQL API
# Returns complete field information including dataType, options, and iterations
# Falls back to gh project field-list if GraphQL fails
# shellcheck disable=SC2016  # Single quotes are intentional for GraphQL query
get_project_fields_detailed() {
    local owner="$1"
    local number="$2"

    if ! check_gh_available || [[ -z "$owner" ]] || [[ -z "$number" ]]; then
        return 1
    fi

    # Try user-owned project first, then organization
    local result
    result=$(gh api graphql -f query='
query($owner: String!, $number: Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
          ... on ProjectV2IterationField {
            id
            name
            configuration {
              iterations {
                id
                title
                startDate
                duration
              }
            }
          }
        }
      }
    }
  }
}' -f owner="$owner" -F number="$number" </dev/null 2>/dev/null)

    # Check if user query returned valid data
    if [[ -n "$result" ]] && echo "$result" | jq -e '.data.user.projectV2.fields.nodes' &>/dev/null; then
        echo "$result"
        return 0
    fi

    # Try organization-owned project
    result=$(gh api graphql -f query='
query($owner: String!, $number: Int!) {
  organization(login: $owner) {
    projectV2(number: $number) {
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
          ... on ProjectV2IterationField {
            id
            name
            configuration {
              iterations {
                id
                title
                startDate
                duration
              }
            }
          }
        }
      }
    }
  }
}' -f owner="$owner" -F number="$number" </dev/null 2>/dev/null)

    if [[ -n "$result" ]] && echo "$result" | jq -e '.data.organization.projectV2.fields.nodes' &>/dev/null; then
        echo "$result"
        return 0
    fi

    return 1
}

# Categorize fields by type from GraphQL response
# Sets global variables: SINGLE_SELECT_FIELDS_JSON, ITERATION_FIELDS_JSON, DATE_FIELDS_JSON
categorize_fields() {
    local fields_json="$1"

    if [[ -z "$fields_json" ]] || ! command -v jq &> /dev/null; then
        SINGLE_SELECT_FIELDS_JSON="[]"
        ITERATION_FIELDS_JSON="[]"
        DATE_FIELDS_JSON="[]"
        return 1
    fi

    # Extract nodes from either user or organization response
    local nodes
    nodes=$(echo "$fields_json" | jq -r '.data.user.projectV2.fields.nodes // .data.organization.projectV2.fields.nodes // []')

    # Extract Single Select fields (have options array)
    SINGLE_SELECT_FIELDS_JSON=$(echo "$nodes" | jq '[.[] | select(.options != null)]')

    # Extract Iteration fields (have configuration.iterations)
    ITERATION_FIELDS_JSON=$(echo "$nodes" | jq '[.[] | select(.configuration.iterations != null)]')

    # Extract Date fields (dataType == "DATE")
    DATE_FIELDS_JSON=$(echo "$nodes" | jq '[.[] | select(.dataType == "DATE")]')

    return 0
}

# =============================================================================
# Dynamic Field Selection Prompts
# =============================================================================

# Prompt user to select which Single Select fields to configure
# Sets: SELECTED_SINGLE_SELECT_FIELDS array with field names
prompt_select_fields_to_configure() {
    local fields_json="$1"
    local field_count
    field_count=$(echo "$fields_json" | jq 'length')

    SELECTED_SINGLE_SELECT_FIELDS=()

    if [[ "$field_count" -eq 0 ]]; then
        return 0
    fi

    echo "" > /dev/tty
    echo "Found $field_count configurable Single Select fields:" > /dev/tty

    local i
    for ((i=0; i<field_count; i++)); do
        local name options_count
        name=$(echo "$fields_json" | jq -r ".[$i].name")
        options_count=$(echo "$fields_json" | jq ".[$i].options | length")
        echo "  $((i+1))) $name [$options_count options]" > /dev/tty
    done

    echo "" > /dev/tty
    echo "Enter field numbers to configure (comma-separated, 'all', or 'none'):" > /dev/tty
    echo -n "Selection [all]: " > /dev/tty

    local selection
    read -r selection < /dev/tty
    selection="${selection:-all}"

    if [[ "$selection" == "none" ]]; then
        return 0
    elif [[ "$selection" == "all" ]]; then
        for ((i=0; i<field_count; i++)); do
            SELECTED_SINGLE_SELECT_FIELDS+=("$(echo "$fields_json" | jq -r ".[$i].name")")
        done
    else
        # Parse comma-separated numbers
        IFS=',' read -ra indices <<< "$selection"
        for idx in "${indices[@]}"; do
            idx=$(echo "$idx" | tr -d ' ')
            if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -ge 1 ]] && [[ "$idx" -le "$field_count" ]]; then
                SELECTED_SINGLE_SELECT_FIELDS+=("$(echo "$fields_json" | jq -r ".[$(( idx - 1 ))].name")")
            fi
        done
    fi
}

# Prompt for a single select field's default value
# Args: field_name, options_json, prompt_text (optional)
# Returns: Selected option value via echo
prompt_single_select_field_value() {
    local field_name="$1"
    local options_json="$2"
    # shellcheck disable=SC2016  # Single quotes intentional in default string
    local prompt_text="${3:-Select default value for '$field_name':}"

    local options_count
    options_count=$(echo "$options_json" | jq 'length')

    if [[ "$options_count" -eq 0 ]]; then
        echo ""
        return 1
    fi

    echo "" > /dev/tty
    echo "$prompt_text" > /dev/tty

    local i
    for ((i=0; i<options_count; i++)); do
        local option_name
        option_name=$(echo "$options_json" | jq -r ".[$i].name")
        echo "  $((i+1))) $option_name" > /dev/tty
    done

    echo -n "Enter selection [1]: " > /dev/tty
    local selection
    read -r selection < /dev/tty
    selection="${selection:-1}"

    local idx=$((selection - 1))
    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$options_count" ]]; then
        echo "$options_json" | jq -r ".[$idx].name"
    else
        echo "$options_json" | jq -r ".[0].name"
    fi
}

# Prompt for iteration field configuration
# Args: field_name, iterations_json
# Sets: ITERATION_CONFIG_VALUE ("current", "next", iteration name, or empty)
# Sets: ITERATION_FIELD_NAME
prompt_iteration_field() {
    local field_name="$1"
    local iterations_json="$2"

    ITERATION_FIELD_NAME="$field_name"

    local iter_count
    iter_count=$(echo "$iterations_json" | jq 'length')

    if [[ "$iter_count" -eq 0 ]]; then
        ITERATION_CONFIG_VALUE=""
        return 0
    fi

    echo "" > /dev/tty
    echo "Configure default Iteration for '$field_name' field:" > /dev/tty
    echo "  1) current - Iteration containing today's date (Recommended)" > /dev/tty
    echo "  2) next - First upcoming iteration" > /dev/tty
    echo "  3) Select specific iteration" > /dev/tty
    echo "  4) Skip iteration configuration" > /dev/tty

    echo -n "Enter selection [1]: " > /dev/tty
    local selection
    read -r selection < /dev/tty
    selection="${selection:-1}"

    case "$selection" in
        1)
            ITERATION_CONFIG_VALUE="current"
            ;;
        2)
            ITERATION_CONFIG_VALUE="next"
            ;;
        3)
            echo "" > /dev/tty
            echo "Available iterations:" > /dev/tty
            local i
            for ((i=0; i<iter_count; i++)); do
                local title start_date
                title=$(echo "$iterations_json" | jq -r ".[$i].title")
                start_date=$(echo "$iterations_json" | jq -r ".[$i].startDate")
                echo "  $((i+1))) $title (starts: $start_date)" > /dev/tty
            done
            echo -n "Enter selection [1]: " > /dev/tty
            local iter_selection
            read -r iter_selection < /dev/tty
            iter_selection="${iter_selection:-1}"
            local idx=$((iter_selection - 1))
            if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$iter_count" ]]; then
                ITERATION_CONFIG_VALUE=$(echo "$iterations_json" | jq -r ".[$idx].title")
            else
                ITERATION_CONFIG_VALUE=$(echo "$iterations_json" | jq -r ".[0].title")
            fi
            ;;
        *)
            ITERATION_CONFIG_VALUE=""
            ;;
    esac
}

# Prompt for date field configuration
# Args: field_name, is_end_field (true/false), has_iteration (true/false)
# Returns: Date value via echo ("today", "+Nd", "+Nw", or empty)
prompt_date_field() {
    local field_name="$1"
    local is_end_field="${2:-false}"
    local has_iteration="${3:-false}"

    echo "" > /dev/tty
    echo "Configure default value for '$field_name' date field:" > /dev/tty

    if [[ "$is_end_field" == "true" ]]; then
        echo "  1) +14d - 14 days from start (Recommended)" > /dev/tty
        echo "  2) today - Current date" > /dev/tty
    else
        echo "  1) today - Current date (Recommended)" > /dev/tty
        echo "  2) +7d - 7 days from today" > /dev/tty
    fi
    echo "  3) Enter custom relative value (+Nd or +Nw)" > /dev/tty
    if [[ "$has_iteration" == "true" ]]; then
        echo "  4) Derive from iteration (auto-calculated)" > /dev/tty
        echo "  5) Skip - no default" > /dev/tty
    else
        echo "  4) Skip - no default" > /dev/tty
    fi

    echo -n "Enter selection [1]: " > /dev/tty
    local selection
    read -r selection < /dev/tty
    selection="${selection:-1}"

    if [[ "$is_end_field" == "true" ]]; then
        case "$selection" in
            1) echo "+14d" ;;
            2) echo "today" ;;
            3)
                echo -n "Enter relative value (e.g., +7d, +2w): " > /dev/tty
                local custom_value
                read -r custom_value < /dev/tty
                echo "${custom_value:-+14d}"
                ;;
            4)
                if [[ "$has_iteration" == "true" ]]; then
                    echo ""  # Derive from iteration
                else
                    echo ""  # Skip
                fi
                ;;
            *) echo "" ;;
        esac
    else
        case "$selection" in
            1) echo "today" ;;
            2) echo "+7d" ;;
            3)
                echo -n "Enter relative value (e.g., +7d, +2w): " > /dev/tty
                local custom_value
                read -r custom_value < /dev/tty
                echo "${custom_value:-today}"
                ;;
            4)
                if [[ "$has_iteration" == "true" ]]; then
                    echo ""  # Derive from iteration
                else
                    echo ""  # Skip
                fi
                ;;
            *) echo "" ;;
        esac
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

# Initialize global variables for field configuration
init_field_config_vars() {
    # Associative array for field defaults (field_name -> default_value)
    declare -gA FIELD_DEFAULTS
    FIELD_DEFAULTS=()

    # Schedule-related configuration
    # Note: Field name variables are stored for future use in advanced config schema
    # (e.g., schedule_defaults.iteration.field: "Iteration")
    # shellcheck disable=SC2034  # Reserved for future field name mapping feature
    ITERATION_FIELD_NAME=""
    ITERATION_CONFIG_VALUE=""
    # shellcheck disable=SC2034  # Reserved for future field name mapping feature
    START_DATE_FIELD_NAME=""
    START_DATE_VALUE=""
    # shellcheck disable=SC2034  # Reserved for future field name mapping feature
    END_DATE_FIELD_NAME=""
    END_DATE_VALUE=""

    # PR status
    PR_OPEN_STATUS=""

    # Selected fields for configuration
    SELECTED_SINGLE_SELECT_FIELDS=()
}

# Prompt for GitHub Project configuration with gh CLI integration
plugin_interactive_setup() {
    print_section "GitHub Project Integration Setup"

    echo "This will configure GitHub Project integration for your repository."
    echo "Workflows will call reusable workflows from TE-ToshiakiTanaka2/tarnished."
    echo ""
    echo "You need a GitHub Personal Access Token with 'repo' and 'project' scopes."
    echo ""

    # Initialize configuration variables
    init_field_config_vars

    # Check if TTY is available
    if ! check_tty_available; then
        print_warning "Non-interactive mode: Using default values"
        PROJECT_OWNER=""
        PROJECT_NUMBER="1"
        FIELD_DEFAULTS["Status"]="Backlog"
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

        # Fetch detailed project fields using GraphQL
        echo "" > /dev/tty
        print_info "Fetching project field schema..."
        local detailed_fields
        detailed_fields=$(get_project_fields_detailed "$PROJECT_OWNER" "$PROJECT_NUMBER")

        if [[ -n "$detailed_fields" ]]; then
            # Categorize fields by type
            categorize_fields "$detailed_fields"

            local single_select_count iteration_count date_count
            single_select_count=$(echo "$SINGLE_SELECT_FIELDS_JSON" | jq 'length')
            iteration_count=$(echo "$ITERATION_FIELDS_JSON" | jq 'length')
            date_count=$(echo "$DATE_FIELDS_JSON" | jq 'length')

            print_success "Found $single_select_count Single Select, $iteration_count Iteration, $date_count Date fields"

            # === Single Select Fields Configuration ===
            if [[ "$single_select_count" -gt 0 ]]; then
                prompt_select_fields_to_configure "$SINGLE_SELECT_FIELDS_JSON"

                # Configure each selected field
                for field_name in "${SELECTED_SINGLE_SELECT_FIELDS[@]}"; do
                    local field_options
                    field_options=$(echo "$SINGLE_SELECT_FIELDS_JSON" | jq --arg name "$field_name" '[.[] | select(.name == $name) | .options][0]')

                    if [[ -n "$field_options" ]] && [[ "$field_options" != "null" ]]; then
                        local default_value
                        default_value=$(prompt_single_select_field_value "$field_name" "$field_options")
                        if [[ -n "$default_value" ]]; then
                            FIELD_DEFAULTS["$field_name"]="$default_value"
                        fi
                    fi
                done

                # Special handling for Status field - also ask for PR open status
                if [[ -v "FIELD_DEFAULTS[Status]" ]]; then
                    local status_options
                    status_options=$(echo "$SINGLE_SELECT_FIELDS_JSON" | jq '[.[] | select(.name == "Status") | .options][0]')
                    if [[ -n "$status_options" ]] && [[ "$status_options" != "null" ]]; then
                        PR_OPEN_STATUS=$(prompt_single_select_field_value "Status" "$status_options" "Select Status when PR is opened:")
                    fi
                fi
            fi

            # === Iteration Fields Configuration ===
            if [[ "$iteration_count" -gt 0 ]]; then
                # If multiple iteration fields, let user choose which one to configure
                if [[ "$iteration_count" -eq 1 ]]; then
                    local iter_field_name iter_iterations
                    iter_field_name=$(echo "$ITERATION_FIELDS_JSON" | jq -r '.[0].name')
                    iter_iterations=$(echo "$ITERATION_FIELDS_JSON" | jq '.[0].configuration.iterations')
                    prompt_iteration_field "$iter_field_name" "$iter_iterations"
                else
                    echo "" > /dev/tty
                    echo "Found $iteration_count Iteration fields:" > /dev/tty
                    for ((i=0; i<iteration_count; i++)); do
                        local name
                        name=$(echo "$ITERATION_FIELDS_JSON" | jq -r ".[$i].name")
                        echo "  $((i+1))) $name" > /dev/tty
                    done
                    echo "  $((iteration_count+1))) Skip iteration configuration" > /dev/tty
                    echo -n "Select iteration field to configure [1]: " > /dev/tty
                    read -r selection < /dev/tty
                    selection="${selection:-1}"

                    local idx=$((selection - 1))
                    if [[ "$idx" -ge 0 ]] && [[ "$idx" -lt "$iteration_count" ]]; then
                        local iter_field_name iter_iterations
                        iter_field_name=$(echo "$ITERATION_FIELDS_JSON" | jq -r ".[$idx].name")
                        iter_iterations=$(echo "$ITERATION_FIELDS_JSON" | jq ".[$idx].configuration.iterations")
                        prompt_iteration_field "$iter_field_name" "$iter_iterations"
                    fi
                fi
            fi

            # === Date Fields Configuration ===
            if [[ "$date_count" -gt 0 ]]; then
                local has_iteration="false"
                [[ -n "$ITERATION_CONFIG_VALUE" ]] && has_iteration="true"

                echo "" > /dev/tty
                echo "Configure Date field defaults?" > /dev/tty
                echo "  1) Yes - configure date fields" > /dev/tty
                echo "  2) No - skip date configuration" > /dev/tty
                echo -n "Enter selection [1]: " > /dev/tty
                read -r selection < /dev/tty
                selection="${selection:-1}"

                if [[ "$selection" == "1" ]]; then
                    # Look for common date field patterns
                    local start_field_name="" end_field_name=""

                    # Find Start field (Start, Start date, start_date)
                    start_field_name=$(echo "$DATE_FIELDS_JSON" | jq -r '[.[] | select(.name | test("^[Ss]tart"; "i"))][0].name // empty')
                    # Find End field (End, End date, Target date, Due date)
                    end_field_name=$(echo "$DATE_FIELDS_JSON" | jq -r '[.[] | select(.name | test("^[Ee]nd|[Tt]arget|[Dd]ue"; "i"))][0].name // empty')

                    # If no common patterns found, let user select
                    if [[ -z "$start_field_name" ]] && [[ -z "$end_field_name" ]]; then
                        echo "" > /dev/tty
                        echo "Available Date fields:" > /dev/tty
                        for ((i=0; i<date_count; i++)); do
                            local name
                            name=$(echo "$DATE_FIELDS_JSON" | jq -r ".[$i].name")
                            echo "  $((i+1))) $name" > /dev/tty
                        done

                        echo -n "Select Start date field (0 to skip): " > /dev/tty
                        read -r selection < /dev/tty
                        if [[ "$selection" =~ ^[1-9][0-9]*$ ]] && [[ "$selection" -le "$date_count" ]]; then
                            start_field_name=$(echo "$DATE_FIELDS_JSON" | jq -r ".[$((selection-1))].name")
                        fi

                        echo -n "Select End date field (0 to skip): " > /dev/tty
                        read -r selection < /dev/tty
                        if [[ "$selection" =~ ^[1-9][0-9]*$ ]] && [[ "$selection" -le "$date_count" ]]; then
                            end_field_name=$(echo "$DATE_FIELDS_JSON" | jq -r ".[$((selection-1))].name")
                        fi
                    fi

                    # Configure Start date
                    if [[ -n "$start_field_name" ]]; then
                        # shellcheck disable=SC2034  # Reserved for future field name mapping
                        START_DATE_FIELD_NAME="$start_field_name"
                        START_DATE_VALUE=$(prompt_date_field "$start_field_name" "false" "$has_iteration")
                    fi

                    # Configure End date
                    if [[ -n "$end_field_name" ]]; then
                        # shellcheck disable=SC2034  # Reserved for future field name mapping
                        END_DATE_FIELD_NAME="$end_field_name"
                        END_DATE_VALUE=$(prompt_date_field "$end_field_name" "true" "$has_iteration")
                    fi
                fi
            fi

            # If no Status field was configured but PR status is needed, ask manually
            if [[ -z "$PR_OPEN_STATUS" ]]; then
                echo "" > /dev/tty
                echo -n "Enter status when PR is opened [In Review]: " > /dev/tty
                read -r PR_OPEN_STATUS < /dev/tty
                PR_OPEN_STATUS="${PR_OPEN_STATUS:-In Review}"
            fi
        else
            print_warning "Could not fetch project details via GraphQL, trying basic field-list..."
            # Fallback to basic gh project field-list
            local basic_fields
            basic_fields=$(get_project_fields "$PROJECT_OWNER" "$PROJECT_NUMBER")
            if [[ -n "$basic_fields" ]]; then
                configure_fields_from_basic_list "$basic_fields"
            else
                print_warning "Could not fetch project details, using manual input"
                prompt_manual_field_defaults
            fi
        fi
    else
        # Manual input fallback
        prompt_manual_project_config
        prompt_manual_field_defaults
    fi

    echo ""
    print_success "Project configuration collected"
}

# Configure fields from basic gh project field-list output (fallback)
configure_fields_from_basic_list() {
    local fields_json="$1"

    # Extract Single Select fields
    local single_select_fields
    single_select_fields=$(echo "$fields_json" | jq '[.fields[] | select(.type == "ProjectV2SingleSelectField")]')

    local field_count
    field_count=$(echo "$single_select_fields" | jq 'length')

    if [[ "$field_count" -gt 0 ]]; then
        echo "" > /dev/tty
        echo "Found $field_count Single Select fields:" > /dev/tty

        local i
        for ((i=0; i<field_count; i++)); do
            local name options_count
            name=$(echo "$single_select_fields" | jq -r ".[$i].name")
            options_count=$(echo "$single_select_fields" | jq ".[$i].options | length")
            echo "  $((i+1))) $name [$options_count options]" > /dev/tty
        done

        echo "" > /dev/tty
        echo "Enter field numbers to configure (comma-separated, 'all', or 'none'):" > /dev/tty
        echo -n "Selection [all]: " > /dev/tty

        local selection
        read -r selection < /dev/tty
        selection="${selection:-all}"

        local selected_indices=()
        if [[ "$selection" == "none" ]]; then
            : # No fields selected
        elif [[ "$selection" == "all" ]]; then
            for ((i=0; i<field_count; i++)); do
                selected_indices+=("$i")
            done
        else
            IFS=',' read -ra indices <<< "$selection"
            for idx in "${indices[@]}"; do
                idx=$(echo "$idx" | tr -d ' ')
                if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -ge 1 ]] && [[ "$idx" -le "$field_count" ]]; then
                    selected_indices+=("$((idx-1))")
                fi
            done
        fi

        # Configure each selected field
        for idx in "${selected_indices[@]}"; do
            local field_name field_options
            field_name=$(echo "$single_select_fields" | jq -r ".[$idx].name")
            field_options=$(echo "$single_select_fields" | jq ".[$idx].options")

            local options_count
            options_count=$(echo "$field_options" | jq 'length')

            echo "" > /dev/tty
            echo "Select default value for '$field_name':" > /dev/tty
            for ((i=0; i<options_count; i++)); do
                echo "  $((i+1))) $(echo "$field_options" | jq -r ".[$i].name")" > /dev/tty
            done
            echo -n "Enter selection [1]: " > /dev/tty
            read -r sel < /dev/tty
            sel="${sel:-1}"

            local sel_idx=$((sel - 1))
            if [[ "$sel_idx" -ge 0 ]] && [[ "$sel_idx" -lt "$options_count" ]]; then
                FIELD_DEFAULTS["$field_name"]=$(echo "$field_options" | jq -r ".[$sel_idx].name")
            else
                FIELD_DEFAULTS["$field_name"]=$(echo "$field_options" | jq -r ".[0].name")
            fi
        done

        # PR open status from Status field if configured
        if [[ -v "FIELD_DEFAULTS[Status]" ]]; then
            local status_options
            status_options=$(echo "$single_select_fields" | jq '[.[] | select(.name == "Status")][0].options')
            if [[ -n "$status_options" ]] && [[ "$status_options" != "null" ]]; then
                local options_count
                options_count=$(echo "$status_options" | jq 'length')
                echo "" > /dev/tty
                echo "Select Status when PR is opened:" > /dev/tty
                for ((i=0; i<options_count; i++)); do
                    echo "  $((i+1))) $(echo "$status_options" | jq -r ".[$i].name")" > /dev/tty
                done
                echo -n "Enter selection [1]: " > /dev/tty
                read -r sel < /dev/tty
                sel="${sel:-1}"
                local sel_idx=$((sel - 1))
                if [[ "$sel_idx" -ge 0 ]] && [[ "$sel_idx" -lt "$options_count" ]]; then
                    PR_OPEN_STATUS=$(echo "$status_options" | jq -r ".[$sel_idx].name")
                else
                    PR_OPEN_STATUS=$(echo "$status_options" | jq -r ".[0].name")
                fi
            fi
        fi
    fi

    # If no PR status set, ask manually
    if [[ -z "$PR_OPEN_STATUS" ]]; then
        echo "" > /dev/tty
        echo -n "Enter status when PR is opened [In Review]: " > /dev/tty
        read -r PR_OPEN_STATUS < /dev/tty
        PR_OPEN_STATUS="${PR_OPEN_STATUS:-In Review}"
    fi
}

# Manual project configuration (fallback)
prompt_manual_project_config() {
    local default_owner=""
    if command -v gh &> /dev/null; then
        default_owner=$(gh api user --jq '.login' </dev/null 2>/dev/null || echo "")
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
    echo "" > /dev/tty
    echo "Configure field defaults manually." > /dev/tty
    echo "Enter field defaults (field_name=value). Press Enter on empty line to finish." > /dev/tty
    echo "Example: Status=Backlog" > /dev/tty
    echo "" > /dev/tty

    while true; do
        echo -n "Field default (or Enter to finish): " > /dev/tty
        local input
        read -r input < /dev/tty
        [[ -z "$input" ]] && break

        local field_name field_value
        field_name="${input%%=*}"
        field_value="${input#*=}"

        if [[ -n "$field_name" ]] && [[ -n "$field_value" ]] && [[ "$field_name" != "$field_value" ]]; then
            FIELD_DEFAULTS["$field_name"]="$field_value"
            print_info "Set $field_name = $field_value"
        else
            print_warning "Invalid format. Use: field_name=value"
        fi
    done

    # If no fields configured, add sensible defaults
    if [[ ${#FIELD_DEFAULTS[@]} -eq 0 ]]; then
        print_info "No fields configured. Adding default Status=Backlog"
        FIELD_DEFAULTS["Status"]="Backlog"
    fi

    # Schedule defaults
    echo "" > /dev/tty
    echo "Configure schedule defaults? (iteration/start/end dates)" > /dev/tty
    echo -n "Enter 'y' to configure, any other key to skip [n]: " > /dev/tty
    local configure_schedule
    read -r configure_schedule < /dev/tty

    if [[ "$configure_schedule" == "y" ]]; then
        echo -n "Default iteration (current/next/name) [current]: " > /dev/tty
        read -r ITERATION_CONFIG_VALUE < /dev/tty
        ITERATION_CONFIG_VALUE="${ITERATION_CONFIG_VALUE:-current}"

        echo -n "Start date value (today/+Nd) [today]: " > /dev/tty
        read -r START_DATE_VALUE < /dev/tty
        START_DATE_VALUE="${START_DATE_VALUE:-today}"

        echo -n "End date value (today/+Nd) [+14d]: " > /dev/tty
        read -r END_DATE_VALUE < /dev/tty
        END_DATE_VALUE="${END_DATE_VALUE:-+14d}"
    fi

    # PR status
    echo "" > /dev/tty
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

        # Build field_defaults YAML section
        local field_defaults_yaml=""
        if [[ ${#FIELD_DEFAULTS[@]} -gt 0 ]]; then
            for field_name in "${!FIELD_DEFAULTS[@]}"; do
                field_defaults_yaml+="  ${field_name}: \"${FIELD_DEFAULTS[$field_name]}\""$'\n'
            done
        else
            # Fallback if no fields configured
            field_defaults_yaml="  Status: \"Backlog\""$'\n'
        fi

        # Build schedule_defaults YAML section
        local schedule_defaults_yaml=""
        if [[ -n "$ITERATION_CONFIG_VALUE" ]] || [[ -n "$START_DATE_VALUE" ]] || [[ -n "$END_DATE_VALUE" ]]; then
            schedule_defaults_yaml=$'\n'"# Schedule-related field defaults"$'\n'
            schedule_defaults_yaml+="schedule_defaults:"$'\n'
            if [[ -n "$ITERATION_CONFIG_VALUE" ]]; then
                schedule_defaults_yaml+="  iteration: \"$ITERATION_CONFIG_VALUE\"  # \"current\", \"next\", or iteration name"$'\n'
            fi
            if [[ -n "$START_DATE_VALUE" ]]; then
                schedule_defaults_yaml+="  start: \"$START_DATE_VALUE\"  # ISO date or relative (\"today\", \"+7d\", \"+2w\")"$'\n'
            fi
            if [[ -n "$END_DATE_VALUE" ]]; then
                schedule_defaults_yaml+="  end: \"$END_DATE_VALUE\"  # ISO date or relative"$'\n'
            fi
        fi

        # Write the config file
        cat > "$project_config" << EOF
# GitHub Project Integration Configuration
# For use with erd CLI: https://github.com/TE-ToshiakiTanaka2/tarnished
# Generated by setup.sh project-integration plugin

default_project:
  owner: "${PROJECT_OWNER}"
  number: ${PROJECT_NUMBER}

field_defaults:
${field_defaults_yaml}${schedule_defaults_yaml}
# PR event status configuration
pr_status:
  on_open: "${PR_OPEN_STATUS:-In Review}"
EOF

        print_success "Created .github/project.yml"

        # Show configured fields summary
        echo ""
        print_info "Configured fields:"
        for field_name in "${!FIELD_DEFAULTS[@]}"; do
            echo "  - $field_name: ${FIELD_DEFAULTS[$field_name]}"
        done
        if [[ -n "$ITERATION_CONFIG_VALUE" ]]; then
            echo "  - Iteration: $ITERATION_CONFIG_VALUE"
        fi
        if [[ -n "$START_DATE_VALUE" ]]; then
            echo "  - Start date: $START_DATE_VALUE"
        fi
        if [[ -n "$END_DATE_VALUE" ]]; then
            echo "  - End date: $END_DATE_VALUE"
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
