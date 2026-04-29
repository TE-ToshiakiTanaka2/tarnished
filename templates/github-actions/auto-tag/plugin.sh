#!/bin/bash
# =============================================================================
# Template Plugin: github-actions/auto-tag
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides automatic semantic versioning based on branch naming:
# - Auto-tagging on merge to develop/main branches
# - Configurable version bump rules via versioning.yml
#
# Workflow is implemented as a caller workflow that invokes the reusable workflow
# from the TE-ToshiakiTanaka2/tarnished repository.
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "github-actions-auto-tag"
}

# Return plugin description
plugin_description() {
    echo "Automatic semantic versioning workflow using erd CLI (reusable workflow)"
}

# =============================================================================
# Interactive Setup Functions
# =============================================================================

# Prompt for auto-tag configuration
plugin_interactive_setup() {
    print_section "Auto-Tag Workflow Setup"

    echo "This will configure automatic semantic versioning for your repository."
    echo "Tags are created when commits are merged to develop or main branches."
    echo ""

    # Auto-tag is enabled via AUTO_TAG_ENABLED flag in setup.sh
    # Set ENABLE_AUTO_TAG for internal use
    ENABLE_AUTO_TAG="y"

    # Check if TTY is available for erd ref configuration
    if ! check_tty_available; then
        AUTO_TAG_ERD_REF="${ERD_REF:-develop}"
        return 0
    fi

    # Get erd branch/tag to use (if not already set by project-integration)
    if [[ -z "${ERD_REF:-}" ]]; then
        echo "Which branch/tag of erd workflows should be used?" > /dev/tty
        echo "  - Use 'develop' for latest version (recommended)" > /dev/tty
        echo "  - Use a specific tag (e.g., v1.0.0) for pinned version" > /dev/tty
        echo -n "Enter erd workflow ref [develop]: " > /dev/tty
        read -r AUTO_TAG_ERD_REF < /dev/tty
        AUTO_TAG_ERD_REF="${AUTO_TAG_ERD_REF:-develop}"
    else
        AUTO_TAG_ERD_REF="${ERD_REF}"
        print_info "Using erd ref from project-integration: @${AUTO_TAG_ERD_REF}"
    fi

    echo ""
    print_success "Auto-tag configuration collected"
}

# =============================================================================
# Hook Functions
# =============================================================================

# Copy GitHub Actions workflow files
plugin_copy() {
    local target_dir="$1"

    # Note: This plugin is only loaded when AUTO_TAG_ENABLED=true in setup.sh
    # So we don't need to check ENABLE_AUTO_TAG here - if this function runs, it's enabled

    print_info "Copying auto-tag workflow..."

    # Create .github/workflows directory
    mkdir -p "${target_dir}/.github/workflows"

    # Copy workflow file with version replacement
    local workflow="${PLUGIN_DIR}/.github/workflows/auto-tag.yml"
    if [[ -f "$workflow" ]]; then
        local target_file="${target_dir}/.github/workflows/auto-tag.yml"

        if [[ -f "$target_file" ]]; then
            echo -n "  auto-tag.yml already exists. Overwrite? (y/n) [n]: "
            if check_tty_available; then
                read -r overwrite < /dev/tty
            else
                overwrite="n"
            fi
            if [[ "$overwrite" != "y" ]]; then
                print_info "Skipping auto-tag.yml"
                return 0
            fi
        fi

        # Use ERD_REF if set (from project-integration), otherwise use AUTO_TAG_ERD_REF
        local ref="${ERD_REF:-${AUTO_TAG_ERD_REF:-develop}}"

        # Replace __ERD_REF__ placeholder with actual ref
        sed "s/__ERD_REF__/${ref}/g" "$workflow" > "$target_file"
        # The output bypasses copy_with_confirm; register it explicitly so
        # the manifest tracking layer (#265) sees this verbatim file.
        manifest_track_file "$target_file"
        print_success "Created auto-tag.yml (using @${ref})"
    fi
}

# Post-copy processing - create versioning.yml
plugin_post_copy() {
    local target_dir="$1"

    # Note: This plugin is only loaded when AUTO_TAG_ENABLED=true in setup.sh
    # So we don't need to check ENABLE_AUTO_TAG here - if this function runs, it's enabled

    # Create .github/versioning.yml
    local versioning_config="${target_dir}/.github/versioning.yml"

    if [[ -f "$versioning_config" ]]; then
        print_warning "versioning.yml already exists, skipping"
    else
        print_info "Creating .github/versioning.yml..."

        mkdir -p "${target_dir}/.github"

        cat > "$versioning_config" << 'EOF'
# Auto-Tag Version Configuration
# For use with erd CLI: https://github.com/TE-ToshiakiTanaka2/tarnished

versioning:
  branch_prefixes:
    # Major version bump (X.0.0)
    major:
      - "major/"

    # Minor version bump (0.X.0)
    minor:
      - "release/"

    # Patch version bump (0.0.X)
    patch:
      - "feature/"
      - "fix/"
      - "bugfix/"
      - "hotfix/"

    # Note: Branches that don't match any prefix default to RC (0.0.0-rc.X)
EOF

        print_success "Created .github/versioning.yml"
    fi

    echo ""
    echo "Auto-tag workflow is configured to use erd @${ERD_REF:-${AUTO_TAG_ERD_REF:-develop}}"
    echo "Tags will be created when branches are merged to develop or main."
    echo ""
}
