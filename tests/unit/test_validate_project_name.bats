#!/usr/bin/env bats
# =============================================================================
# Unit Tests: validate_project_name function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root and source the required files
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first (provides print_* functions)
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Extract and source validate_project_name from setup.sh
    # We create a temp file with just the function we need
    TEMP_FUNCTIONS="$(mktemp)"
    sed -n '/^validate_project_name()/,/^}/p' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"
    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Valid Project Names
# =============================================================================

@test "validate_project_name: accepts simple lowercase name" {
    run validate_project_name "myproject"
    assert_success
}

@test "validate_project_name: accepts name with dashes" {
    run validate_project_name "my-project"
    assert_success
}

@test "validate_project_name: accepts name with underscores" {
    run validate_project_name "my_project"
    assert_success
}

@test "validate_project_name: accepts mixed case name" {
    run validate_project_name "MyProject"
    assert_success
}

@test "validate_project_name: accepts name with numbers" {
    run validate_project_name "project123"
    assert_success
}

@test "validate_project_name: accepts single character name" {
    run validate_project_name "a"
    assert_success
}

@test "validate_project_name: accepts complex valid name" {
    run validate_project_name "My_Test-Project123"
    assert_success
}

# =============================================================================
# Invalid Project Names - Empty/Whitespace
# =============================================================================

@test "validate_project_name: rejects empty name" {
    run validate_project_name ""
    assert_failure
    assert_output --partial "cannot be empty"
}

# =============================================================================
# Invalid Project Names - Starting Characters
# =============================================================================

@test "validate_project_name: rejects name starting with number" {
    run validate_project_name "123project"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "validate_project_name: rejects name starting with dash" {
    run validate_project_name "-myproject"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "validate_project_name: rejects name starting with underscore" {
    run validate_project_name "_myproject"
    assert_failure
    assert_output --partial "must start with a letter"
}

# =============================================================================
# Invalid Project Names - Invalid Characters
# =============================================================================

@test "validate_project_name: rejects name with spaces" {
    run validate_project_name "my project"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "validate_project_name: rejects name with dots" {
    run validate_project_name "my.project"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "validate_project_name: rejects name with slashes" {
    run validate_project_name "my/project"
    assert_failure
    assert_output --partial "must start with a letter"
}

@test "validate_project_name: rejects name with special characters" {
    run validate_project_name "project@name"
    assert_failure
    assert_output --partial "must start with a letter"
}

# =============================================================================
# Invalid Project Names - Length
# =============================================================================

@test "validate_project_name: rejects name exceeding 50 characters" {
    local long_name="a$(printf 'b%.0s' {1..50})"  # 51 characters
    run validate_project_name "${long_name}"
    assert_failure
    assert_output --partial "50 characters or less"
}

@test "validate_project_name: accepts name exactly 50 characters" {
    local exact_name="a$(printf 'b%.0s' {1..49})"  # 50 characters
    run validate_project_name "${exact_name}"
    assert_success
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "validate_project_name: accepts all valid names from fixture file" {
    local fixtures_dir
    fixtures_dir="$(get_tests_dir)/fixtures"

    while IFS= read -r name || [[ -n "$name" ]]; do
        # Skip empty lines
        [[ -z "$name" ]] && continue
        run validate_project_name "$name"
        assert_success
    done < "${fixtures_dir}/valid_project_names.txt"
}

@test "validate_project_name: rejects all invalid names from fixture file" {
    local fixtures_dir
    fixtures_dir="$(get_tests_dir)/fixtures"

    while IFS= read -r name || [[ -n "$name" ]]; do
        # Skip empty lines (but test empty string separately)
        [[ -z "$name" ]] && continue
        run validate_project_name "$name"
        assert_failure
    done < "${fixtures_dir}/invalid_project_names.txt"
}
