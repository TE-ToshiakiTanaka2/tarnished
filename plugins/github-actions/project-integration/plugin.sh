#!/bin/sh
# =============================================================================
# GitHub Project Integration Plugin
# =============================================================================
# Provides GitHub Project integration workflows using erd CLI.

# Return devcontainer features JSON object (none for this plugin)
get_features() {
    :
}

# Return VSCode extensions JSON array (none for this plugin)
get_extensions() {
    :
}

# Return Dockerfile RUN commands (none for this plugin)
get_dockerfile_extras() {
    :
}

# Return post.sh setup script
get_post_setup() {
    owner="${PLUGIN_VAR_PROJECT_OWNER:-}"
    number="${PLUGIN_VAR_PROJECT_NUMBER:-1}"
    default_status="${PLUGIN_VAR_DEFAULT_STATUS:-Backlog}"
    pr_status="${PLUGIN_VAR_PR_OPEN_STATUS:-In Review}"

    cat << EOF
# -----------------------------------------------------------------------------
# GitHub Project Configuration
# -----------------------------------------------------------------------------
setup_project_config() {
    echo "Setting up GitHub Project configuration..."

    mkdir -p .github

    if [ ! -f ".github/project.yml" ]; then
        cat > .github/project.yml << 'PROJECTYML'
default_project:
  owner: "$owner"
  number: $number

field_defaults:
  Status: "$default_status"
  Size: "M"
  Priority: "P1"

pr_status:
  on_open: "$pr_status"
PROJECTYML
        echo "  - Created .github/project.yml"
    else
        echo "  - .github/project.yml already exists, skipping"
    fi
}
setup_project_config
EOF
}

# Return Claude Code hooks JSON array (none for this plugin)
get_hooks() {
    :
}
