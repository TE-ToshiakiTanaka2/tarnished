#!/usr/bin/env bats
# =============================================================================
# Unit Tests: get_language_display_name function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Define LANGUAGE_DISPLAY_NAMES (from setup.sh)
    declare -gA LANGUAGE_DISPLAY_NAMES=(
        ["python"]="Python"
        ["node"]="Node.js/TypeScript"
        ["rust"]="Rust"
        ["deno"]="Deno"
    )

    # Extract and source get_language_display_name from setup.sh
    TEMP_FUNCTIONS="$(mktemp)"
    sed -n '/^get_language_display_name()/,/^}/p' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"
    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Known Languages
# =============================================================================

@test "get_language_display_name: returns 'Python' for 'python'" {
    run get_language_display_name "python"
    assert_success
    assert_output "Python"
}

@test "get_language_display_name: returns 'Node.js/TypeScript' for 'node'" {
    run get_language_display_name "node"
    assert_success
    assert_output "Node.js/TypeScript"
}

@test "get_language_display_name: returns 'Rust' for 'rust'" {
    run get_language_display_name "rust"
    assert_success
    assert_output "Rust"
}

@test "get_language_display_name: returns 'Deno' for 'deno'" {
    run get_language_display_name "deno"
    assert_success
    assert_output "Deno"
}

# =============================================================================
# Unknown Languages (fallback behavior)
# =============================================================================

@test "get_language_display_name: returns input for unknown language" {
    run get_language_display_name "go"
    assert_success
    assert_output "go"
}

@test "get_language_display_name: returns input for random string" {
    run get_language_display_name "foobar"
    assert_success
    assert_output "foobar"
}

@test "get_language_display_name: handles empty string" {
    run get_language_display_name ""
    # Empty string causes an error in bash associative array access
    # This is expected behavior - the function returns the input (empty)
    # but may produce a warning
    assert_success
    # Just verify it doesn't crash completely
}

# =============================================================================
# Case Sensitivity
# =============================================================================

@test "get_language_display_name: is case-sensitive (PYTHON returns PYTHON)" {
    run get_language_display_name "PYTHON"
    assert_success
    # Should return the input since it's not in the map
    assert_output "PYTHON"
}

@test "get_language_display_name: is case-sensitive (Python returns Python)" {
    run get_language_display_name "Python"
    assert_success
    assert_output "Python"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "get_language_display_name: handles whitespace in input" {
    run get_language_display_name " python "
    assert_success
    # Whitespace is preserved, so it won't match
    assert_output " python "
}

@test "get_language_display_name: handles special characters" {
    run get_language_display_name "c++"
    assert_success
    assert_output "c++"
}
