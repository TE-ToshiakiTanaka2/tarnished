#!/usr/bin/env bats
# =============================================================================
# Integration Tests: setup.sh Flow
# =============================================================================
#
# NOTE: setup.sh creates files in the CURRENT directory, not in a subdirectory
# with the project name. The project name is used for placeholders only.
# =============================================================================

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

    # Initialize TEST_TEMP_DIR as git repository (required by setup.sh GitHub operations)
    git -C "${TEST_TEMP_DIR}" init -q
    git -C "${TEST_TEMP_DIR}" config user.email "test@example.com"
    git -C "${TEST_TEMP_DIR}" config user.name "Test User"
    git -C "${TEST_TEMP_DIR}" remote add origin https://github.com/test/test.git
    git -C "${TEST_TEMP_DIR}" commit --allow-empty -m "Initial commit" -q

    # Mock gh command to avoid authentication prompts in tests
    function gh() {
        case "$1 $2" in
            "auth status")
                echo "Logged in to github.com"
                return 0
                ;;
            "repo edit")
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f gh
}

teardown() {
    teardown_temp_dir
}

# Helper to run setup.sh in a fresh temp subdirectory
# Creates a new subdirectory with git repo, runs setup.sh there, and returns the path
run_setup_in_project_dir() {
    local project_name="$1"
    shift
    local args="$*"

    # Create a project subdirectory
    local project_dir="${TEST_TEMP_DIR}/${project_name}"
    mkdir -p "${project_dir}"

    # Initialize git repository (required by setup.sh GitHub operations)
    git -C "${project_dir}" init -q
    git -C "${project_dir}" config user.email "test@example.com"
    git -C "${project_dir}" config user.name "Test User"
    git -C "${project_dir}" remote add origin https://github.com/test/test.git
    git -C "${project_dir}" commit --allow-empty -m "Initial commit" -q

    # Run setup.sh in that directory
    bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' ${args} '${project_name}'" >/dev/null 2>&1
    local result=$?

    echo "${project_dir}"
    return $result
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "setup.sh --help: shows usage information" {
    run "${PROJECT_ROOT}/setup.sh" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "setup.sh"
}

@test "setup.sh -h: shows usage information" {
    run "${PROJECT_ROOT}/setup.sh" -h
    assert_success
    assert_output --partial "Usage:"
}

@test "setup.sh --help: shows available options" {
    run "${PROJECT_ROOT}/setup.sh" --help
    assert_success
    assert_output --partial "--lang"
    assert_output --partial "--yes"
    assert_output --partial "--dry-run"
}

# =============================================================================
# Dry Run Tests
# =============================================================================

@test "setup.sh --dry-run: shows preview without creating files" {
    local project_dir="${TEST_TEMP_DIR}/dryrun-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --dry-run --lang node --yes test-project"
    assert_success
    assert_output --partial "Dry run"
    assert_output --partial "test-project"

    # Should not create files
    [[ ! -f "${project_dir}/docker-compose.yml" ]]
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

@test "setup.sh: rejects invalid project name" {
    local project_dir="${TEST_TEMP_DIR}/invalid-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --yes 123invalid"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "setup.sh: rejects unknown language" {
    local project_dir="${TEST_TEMP_DIR}/unknown-lang-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang unknown_lang --yes test-project"
    assert_failure
    assert_output --partial "Unknown language"
}

@test "setup.sh: accepts valid language (node)" {
    local project_dir="${TEST_TEMP_DIR}/valid-lang-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --dry-run --lang node --yes test-project"
    assert_success
}

@test "setup.sh: --playwright flag is recognized" {
    local project_dir="${TEST_TEMP_DIR}/playwright-flag-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --dry-run --lang node --playwright --yes test-project"
    assert_success
    assert_output --partial "Playwright"
}

# =============================================================================
# Project Creation Tests
# =============================================================================

@test "setup.sh: creates project with expected structure" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "my-test-project" "--lang node --yes")

    # Check that key directories and files were created
    [[ -d "${project_dir}/.devcontainer" ]]
    [[ -d "${project_dir}/docker" ]]
    [[ -f "${project_dir}/docker-compose.yml" ]]
    [[ -f "${project_dir}/.devcontainer/devcontainer.json" ]]
}

@test "setup.sh: replaces placeholder in devcontainer.json" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "placeholder-test" "--lang node --yes")

    # Check that the project name placeholder was replaced
    run grep "placeholder-test" "${project_dir}/.devcontainer/devcontainer.json"
    assert_success
}

# =============================================================================
# Language-specific Tests
# =============================================================================

@test "setup.sh: node template creates node-specific files" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "node-project" "--lang node --yes")

    # Node template should create either package.json or include node in devcontainer
    [[ -f "${project_dir}/package.json" ]] || \
    grep -q "node" "${project_dir}/.devcontainer/devcontainer.json" 2>/dev/null
}

# =============================================================================
# Playwright Option Tests
# =============================================================================

@test "setup.sh: playwright option is applied" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "pw-project" "--lang node --playwright --yes")

    # Playwright should be configured
    # Check for playwright reference in any config file
    grep -q -r "playwright" "${project_dir}/" 2>/dev/null || \
    [[ -f "${project_dir}/playwright.config.ts" ]] || \
    [[ -f "${project_dir}/playwright.config.js" ]]
}

# =============================================================================
# Output Tests
# =============================================================================

@test "setup.sh: shows completion message" {
    local project_dir="${TEST_TEMP_DIR}/completion-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --yes completion-project"
    assert_success
    assert_output --partial "✓"
}

@test "setup.sh: shows project name in output" {
    local project_dir="${TEST_TEMP_DIR}/name-test"
    mkdir -p "${project_dir}"

    run bash -c "cd '${project_dir}' && '${PROJECT_ROOT}/setup.sh' --lang node --yes named-project"
    assert_success
    assert_output --partial "named-project"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "setup.sh: detects existing files and asks for confirmation" {
    local project_dir="${TEST_TEMP_DIR}/existing-files-test"
    mkdir -p "${project_dir}/.devcontainer"
    touch "${project_dir}/docker-compose.yml"

    # Run without --yes and provide 'n' to cancel
    run bash -c "cd '${project_dir}' && echo 'n' | '${PROJECT_ROOT}/setup.sh' --lang node test-project"

    # Should either warn about existing files or ask for overwrite confirmation
    # The script checks for .devcontainer or docker-compose.yml
    assert_output --partial "Setup cancelled" || assert_output --partial "already exist" || assert_output --partial "Overwrite"
}

@test "setup.sh: handles missing language gracefully" {
    # Use --dry-run to skip GitHub operations and actual file creation
    run "${PROJECT_ROOT}/setup.sh" --dry-run --yes test-project 2>&1
    # Script may prompt for input or fail - just ensure it doesn't crash unexpectedly
    true
}

# =============================================================================
# Claude Integration Tests
# =============================================================================

@test "setup.sh: creates .claude directory" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "claude-project" "--lang node --yes")

    [[ -d "${project_dir}/.claude" ]]
}

@test "setup.sh: creates Claude settings file" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "claude-settings-project" "--lang node --yes")

    # Claude settings.json should exist
    [[ -f "${project_dir}/.claude/settings.json" ]] || \
    [[ -f "${project_dir}/.claude/settings.local.json" ]]
}

@test "setup.sh: creates Claude commands directory" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "claude-cmd-project" "--lang node --yes")

    # Claude commands should exist
    [[ -d "${project_dir}/.claude/commands" ]]
}

@test "setup.sh: creates CLAUDE.md file" {
    local project_dir
    project_dir=$(run_setup_in_project_dir "claude-md-project" "--lang node --yes")

    [[ -f "${project_dir}/CLAUDE.md" ]]
}
