#!/bin/bash
# =============================================================================
# GitHub Actions Plugin
# =============================================================================
#
# This plugin provides GitHub Actions templates for CI/CD automation.
#
# Available Actions:
#   - auto-tag: Automatic semantic versioning tags on PR merge
#
# Future Actions (planned):
#   - auto-label: Automatic PR labeling based on branch/files
#   - release-notes: Changelog generation on tag creation
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
    echo "GitHub Actions templates (auto-tag, CI/CD workflows)"
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
