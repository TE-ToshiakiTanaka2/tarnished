#!/usr/bin/env bats
# =============================================================================
# Unit Tests: GitHub Operations Functions
# =============================================================================
# Tests for check_gh_auth, setup_develop_branch, set_default_branch, auto_commit

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

    # Configure git for tests (needed in CI environments)
    git config --global user.email "test@example.com" 2>/dev/null || true
    git config --global user.name "Test User" 2>/dev/null || true

    # Extract GitHub operations functions from setup.sh using awk
    TEMP_FUNCTIONS="$(mktemp)"
    awk '
        /^check_gh_auth\(\)/ { printing=1 }
        /^setup_develop_branch\(\)/ { printing=1 }
        /^set_default_branch\(\)/ { printing=1 }
        /^auto_commit\(\)/ { printing=1 }
        /^setup_github_repository\(\)/ { printing=1 }
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
# check_gh_auth Tests
# =============================================================================

@test "check_gh_auth: succeeds when gh is installed and authenticated" {
    # Mock gh command to return success
    function gh() {
        if [[ "$1" == "auth" && "$2" == "status" ]]; then
            return 0
        fi
        command gh "$@"
    }
    export -f gh

    run check_gh_auth
    assert_success
    assert_output --partial "GitHub CLI authenticated"
}

@test "check_gh_auth: fails when gh is not installed" {
    # Override command to simulate gh not found
    function command() {
        if [[ "$2" == "gh" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    export -f command

    run check_gh_auth
    assert_failure
    assert_output --partial "GitHub CLI (gh) is not installed"
}

@test "check_gh_auth: prompts login when not authenticated" {
    local login_called=false

    # Mock gh command
    function gh() {
        if [[ "$1" == "auth" && "$2" == "status" ]]; then
            return 1  # Not authenticated
        elif [[ "$1" == "auth" && "$2" == "login" ]]; then
            echo "login_called" > "${TEST_TEMP_DIR}/login_called"
            return 0  # Login succeeds
        fi
        return 0
    }
    export -f gh

    run check_gh_auth
    assert_success

    # Verify login was called
    [[ -f "${TEST_TEMP_DIR}/login_called" ]]
}

@test "check_gh_auth: fails when login fails" {
    # Mock gh command where login fails
    function gh() {
        if [[ "$1" == "auth" && "$2" == "status" ]]; then
            return 1  # Not authenticated
        elif [[ "$1" == "auth" && "$2" == "login" ]]; then
            return 1  # Login fails
        fi
        return 0
    }
    export -f gh

    run check_gh_auth
    assert_failure
    assert_output --partial "GitHub authentication failed"
}

# =============================================================================
# setup_develop_branch Tests
# =============================================================================

@test "setup_develop_branch: fails when not in git repository" {
    # Create a non-git directory
    local non_git_dir="${TEST_TEMP_DIR}/non-git"
    mkdir -p "${non_git_dir}"
    cd "${non_git_dir}"

    run setup_develop_branch
    assert_failure
    assert_output --partial "Not a git repository"
}

@test "setup_develop_branch: fails when no origin remote" {
    # Create a git repository without origin
    local git_dir="${TEST_TEMP_DIR}/git-no-origin"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q

    run setup_develop_branch
    assert_failure
    assert_output --partial "No 'origin' remote configured"
}

@test "setup_develop_branch: checks out existing local develop branch" {
    # Create a git repository with develop branch
    local git_dir="${TEST_TEMP_DIR}/git-with-develop"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q
    git branch develop

    run setup_develop_branch
    assert_success
    assert_output --partial "Develop branch exists locally"

    # Verify we're on develop
    local current_branch
    current_branch=$(git branch --show-current)
    [[ "${current_branch}" == "develop" ]]
}

@test "setup_develop_branch: creates new develop branch when none exists" {
    # Create a git repository without develop branch
    local git_dir="${TEST_TEMP_DIR}/git-no-develop"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q

    run setup_develop_branch
    assert_success
    assert_output --partial "Creating new develop branch"

    # Verify we're on develop
    local current_branch
    current_branch=$(git branch --show-current)
    [[ "${current_branch}" == "develop" ]]
}

# =============================================================================
# set_default_branch Tests
# =============================================================================

@test "set_default_branch: succeeds when gh repo edit succeeds" {
    # Mock gh command to succeed
    function gh() {
        if [[ "$1" == "repo" && "$2" == "edit" ]]; then
            return 0
        fi
        return 0
    }
    export -f gh

    run set_default_branch
    assert_success
    assert_output --partial "Default branch set to develop"
}

@test "set_default_branch: falls back to push when gh repo edit fails" {
    # Create a git repository
    local git_dir="${TEST_TEMP_DIR}/git-repo"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git remote add origin https://github.com/test/test.git
    git commit --allow-empty -m "Initial commit" -q
    git checkout -b develop -q

    # Mock gh to fail, but git push to succeed (via mock remote)
    function gh() {
        if [[ "$1" == "repo" && "$2" == "edit" ]]; then
            return 1  # Permission denied
        fi
        return 0
    }
    export -f gh

    # Mock git push to succeed
    function git() {
        if [[ "$1" == "push" ]]; then
            echo "push_called" > "${TEST_TEMP_DIR}/push_called"
            return 0
        fi
        command git "$@"
    }
    export -f git

    run set_default_branch
    assert_success
    assert_output --partial "Could not set default branch"
    assert_output --partial "Please manually set develop as default branch"
}

@test "set_default_branch: handles push failure gracefully" {
    # Mock gh to fail
    function gh() {
        if [[ "$1" == "repo" && "$2" == "edit" ]]; then
            return 1
        fi
        return 0
    }
    export -f gh

    # Mock git push to fail
    function git() {
        if [[ "$1" == "push" ]]; then
            return 1
        fi
        command git "$@"
    }
    export -f git

    run set_default_branch
    assert_success  # Should still succeed (non-fatal)
    assert_output --partial "Could not push to remote"
}

# =============================================================================
# auto_commit Tests
# =============================================================================

@test "auto_commit: commits when there are changes" {
    # Create a git repository with changes
    local git_dir="${TEST_TEMP_DIR}/git-changes"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q

    # Create a new file
    echo "test content" > test.txt

    run auto_commit "feat: test commit"
    assert_success
    assert_output --partial "Committed: feat: test commit"

    # Verify commit was made
    local commit_msg
    commit_msg=$(git log -1 --format=%s)
    [[ "${commit_msg}" == "feat: test commit" ]]
}

@test "auto_commit: does nothing when no changes" {
    # Create a git repository without changes
    local git_dir="${TEST_TEMP_DIR}/git-no-changes"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q

    run auto_commit "feat: should not commit"
    assert_success
    assert_output --partial "No changes to commit"

    # Verify no new commit was made
    local commit_count
    commit_count=$(git rev-list --count HEAD)
    [[ "${commit_count}" == "1" ]]
}

@test "auto_commit: commits untracked files" {
    # Create a git repository
    local git_dir="${TEST_TEMP_DIR}/git-untracked"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    git commit --allow-empty -m "Initial commit" -q

    # Create multiple untracked files
    echo "file1" > file1.txt
    echo "file2" > file2.txt
    mkdir -p subdir
    echo "file3" > subdir/file3.txt

    run auto_commit "feat: add multiple files"
    assert_success
    assert_output --partial "Committed: feat: add multiple files"

    # Verify all files are tracked
    [[ -z "$(git ls-files --others --exclude-standard)" ]]
}

@test "auto_commit: commits staged changes" {
    # Create a git repository with staged changes
    local git_dir="${TEST_TEMP_DIR}/git-staged"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    echo "original" > test.txt
    git add test.txt
    git commit -m "Initial commit" -q

    # Modify and stage
    echo "modified" > test.txt
    git add test.txt

    run auto_commit "feat: modify file"
    assert_success
    assert_output --partial "Committed: feat: modify file"
}

@test "auto_commit: commits mixed staged and unstaged changes" {
    # Create a git repository
    local git_dir="${TEST_TEMP_DIR}/git-mixed"
    mkdir -p "${git_dir}"
    cd "${git_dir}"
    git init -q
    echo "file1" > file1.txt
    git add file1.txt
    git commit -m "Initial commit" -q

    # Create staged change
    echo "file2" > file2.txt
    git add file2.txt

    # Create unstaged change
    echo "modified" > file1.txt

    run auto_commit "feat: mixed changes"
    assert_success
    assert_output --partial "Committed: feat: mixed changes"

    # Verify both changes are committed
    [[ -z "$(git status --porcelain)" ]]
}

# =============================================================================
# setup_github_repository Integration Tests (Unit-level)
# =============================================================================

@test "setup_github_repository: fails when check_gh_auth fails" {
    # Mock check_gh_auth to fail
    function check_gh_auth() {
        print_error "Mock auth failure"
        return 1
    }
    export -f check_gh_auth

    run setup_github_repository
    assert_failure
    assert_output --partial "GitHub setup failed: authentication required"
}

@test "setup_github_repository: fails when setup_develop_branch fails" {
    # Mock check_gh_auth to succeed
    function check_gh_auth() {
        print_success "GitHub CLI authenticated"
        return 0
    }
    export -f check_gh_auth

    # Mock setup_develop_branch to fail
    function setup_develop_branch() {
        print_error "Mock branch failure"
        return 1
    }
    export -f setup_develop_branch

    run setup_github_repository
    assert_failure
    assert_output --partial "GitHub setup failed: could not setup develop branch"
}

@test "setup_github_repository: succeeds when all steps pass" {
    # Mock all functions to succeed
    function check_gh_auth() {
        print_success "GitHub CLI authenticated"
        return 0
    }
    export -f check_gh_auth

    function setup_develop_branch() {
        print_success "Now on develop branch"
        return 0
    }
    export -f setup_develop_branch

    function set_default_branch() {
        print_success "Default branch set to develop"
        return 0
    }
    export -f set_default_branch

    run setup_github_repository
    assert_success
    assert_output --partial "GitHub repository setup complete"
}
