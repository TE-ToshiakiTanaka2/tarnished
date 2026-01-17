#!/usr/bin/env bats
# =============================================================================
# Integration Tests: GitHub Operations in Setup Flow
# =============================================================================
# Tests the integration of GitHub operations with the setup.sh flow

# Load test helpers
setup() {
    load '../helpers/common'
    load '../helpers/mock'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Load bats libraries
    load_bats_libraries

    # Setup temp directory
    setup_temp_dir

    # Initialize global variables that setup.sh uses
    export SCRIPT_DIR="${PROJECT_ROOT}"
    export TEMPLATES_DIR="${PROJECT_ROOT}/templates"
    export LOADED_PLUGINS=()
    export PLUGIN_NAMES=()
    export SELECTED_LANGUAGES=()
    export AVAILABLE_LANGUAGES=()
    export PLAYWRIGHT_ENABLED="false"
    export DOCKER_ENABLED="false"
    export POSTGRESQL_ENABLED="false"
    export NEO4J_ENABLED="false"
    export REDIS_ENABLED="false"
    export GITHUB_ACTIONS_ENABLED="false"
    export CORE_PLUGINS=("core" "claude")
    declare -gA LANGUAGE_DISPLAY_NAMES=(
        ["node"]="Node.js 22.x (LTS)"
        ["python"]="Python 3.x"
        ["rust"]="Rust"
        ["deno"]="Deno"
    )

    # Extract key functions from setup.sh using awk
    TEMP_FUNCTIONS="$(mktemp)"

    # Extract all needed functions
    awk '
        /^check_gh_auth\(\)/ { printing=1 }
        /^setup_develop_branch\(\)/ { printing=1 }
        /^set_default_branch\(\)/ { printing=1 }
        /^auto_commit\(\)/ { printing=1 }
        /^setup_github_repository\(\)/ { printing=1 }
        /^load_plugin\(\)/ { printing=1 }
        /^load_selected_plugins\(\)/ { printing=1 }
        /^execute_plugins_hook\(\)/ { printing=1 }
        /^discover_available_languages\(\)/ { printing=1 }
        /^validate_project_name\(\)/ { printing=1 }
        /^check_dependencies\(\)/ { printing=1 }
        /^show_completion\(\)/ { printing=1 }
        printing { print }
        /^}$/ && printing { printing=0 }
    ' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"

    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"

    # Initialize mock state
    mock_clear_calls
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Full Flow Integration Tests
# =============================================================================

@test "integration: GitHub operations complete flow in test repository" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q

    # Mock gh commands
    function gh() {
        case "$1 $2" in
            "auth status")
                return 0  # Already authenticated
                ;;
            "repo edit")
                return 1  # Permission denied (expected in test)
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f gh

    # Mock git push
    function git() {
        if [[ "$1" == "push" ]]; then
            return 0  # Mock successful push
        fi
        command git "$@"
    }
    export -f git

    # Run the full GitHub repository setup
    run setup_github_repository
    assert_success
    assert_output --partial "GitHub repository setup complete"

    # Verify we're on develop branch
    local current_branch
    current_branch=$(command git branch --show-current)
    [[ "${current_branch}" == "develop" ]]
}

@test "integration: auto_commit works with plugin_copy output" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q
    git checkout -b develop -q

    # Simulate plugin_copy creating files
    mkdir -p .devcontainer
    echo '{"name": "test"}' > .devcontainer/devcontainer.json
    mkdir -p docker
    echo "FROM ubuntu" > docker/Dockerfile.dev

    # Run auto_commit
    run auto_commit "feat: initialize devcontainer environment"
    assert_success
    assert_output --partial "Committed: feat: initialize devcontainer environment"

    # Verify files are committed
    local status
    status=$(git status --porcelain)
    [[ -z "${status}" ]]

    # Verify commit message
    local commit_msg
    commit_msg=$(git log -1 --format=%s)
    [[ "${commit_msg}" == "feat: initialize devcontainer environment" ]]
}

@test "integration: multiple auto_commits create proper history" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q
    git checkout -b develop -q

    # First commit - devcontainer
    mkdir -p .devcontainer
    echo '{"name": "test"}' > .devcontainer/devcontainer.json
    auto_commit "feat: initialize devcontainer environment"

    # Second commit - language config
    echo '{"dependencies": {}}' > package.json
    auto_commit "feat: configure node development environment"

    # Third commit - finalization
    echo "# Test Project" > README.md
    auto_commit "chore: finalize project configuration"

    # Verify commit history
    local commit_count
    commit_count=$(git rev-list --count HEAD)
    [[ "${commit_count}" == "4" ]]  # Initial + 3 auto commits

    # Verify commit messages in order (newest first)
    local commits
    commits=$(git log --format=%s -3)
    [[ "${commits}" == *"chore: finalize project configuration"* ]]
    [[ "${commits}" == *"feat: configure node development environment"* ]]
    [[ "${commits}" == *"feat: initialize devcontainer environment"* ]]
}

@test "integration: setup_develop_branch handles remote develop branch" {
    # Create a test git repository with "remote" develop
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q

    # Simulate remote develop branch by creating a ref
    git update-ref refs/remotes/origin/develop HEAD

    run setup_develop_branch
    assert_success
    assert_output --partial "Develop branch exists on remote"

    # Verify we're on develop
    local current_branch
    current_branch=$(git branch --show-current)
    [[ "${current_branch}" == "develop" ]]
}

@test "integration: show_completion displays git info" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q
    git checkout -b develop -q
    git commit --allow-empty -m "Second commit" -q

    # Set required variables
    SELECTED_LANGUAGES=("node")

    run show_completion "test-project"
    assert_success
    assert_output --partial "Git Status:"
    assert_output --partial "Branch:"
    assert_output --partial "develop"
    assert_output --partial "Commits:"
}

# =============================================================================
# Error Handling Integration Tests
# =============================================================================

@test "integration: setup handles missing git gracefully" {
    # Create a non-git directory
    local test_dir="${TEST_TEMP_DIR}/non-git"
    mkdir -p "${test_dir}"
    cd "${test_dir}"

    # Mock gh to succeed
    function gh() {
        return 0
    }
    export -f gh

    run setup_github_repository
    assert_failure
    assert_output --partial "Not a git repository"
}

@test "integration: setup handles missing origin gracefully" {
    # Create a git repo without origin
    local test_repo="${TEST_TEMP_DIR}/no-origin"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q

    # Mock gh to succeed
    function gh() {
        return 0
    }
    export -f gh

    run setup_github_repository
    assert_failure
    assert_output --partial "No 'origin' remote configured"
}

@test "integration: setup continues when default branch change fails" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/test-project"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q

    # Mock gh commands - auth succeeds, repo edit fails
    function gh() {
        case "$1 $2" in
            "auth status")
                return 0
                ;;
            "repo edit")
                return 1  # Permission denied
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f gh

    # Mock git push to fail too
    function git() {
        if [[ "$1" == "push" ]]; then
            return 1
        fi
        command git "$@"
    }
    export -f git

    # Setup should still succeed
    run setup_github_repository
    assert_success
    assert_output --partial "Could not push to remote"
    assert_output --partial "GitHub repository setup complete"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "integration: auto_commit handles empty repository" {
    # Create an empty git repository (no commits)
    local test_repo="${TEST_TEMP_DIR}/empty-repo"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git

    # Add a file
    echo "test" > test.txt

    # auto_commit should work on first commit
    run auto_commit "feat: initial setup"
    assert_success
    assert_output --partial "Committed: feat: initial setup"
}

@test "integration: setup_develop_branch on existing develop" {
    # Create a test git repository already on develop
    local test_repo="${TEST_TEMP_DIR}/on-develop"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q
    git checkout -b develop -q

    # Running setup_develop_branch should just stay on develop
    run setup_develop_branch
    assert_success

    # Still on develop
    local current_branch
    current_branch=$(git branch --show-current)
    [[ "${current_branch}" == "develop" ]]
}

@test "integration: auto_commit with special characters in message" {
    # Create a test git repository
    local test_repo="${TEST_TEMP_DIR}/special-chars"
    mkdir -p "${test_repo}"
    cd "${test_repo}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q

    # Add a file
    echo "test" > test.txt

    # Commit with special characters
    run auto_commit "feat: add node & python support"
    assert_success
    assert_output --partial "Committed: feat: add node & python support"

    # Verify commit message
    local commit_msg
    commit_msg=$(git log -1 --format=%s)
    [[ "${commit_msg}" == "feat: add node & python support" ]]
}
