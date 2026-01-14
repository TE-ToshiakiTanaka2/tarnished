#!/usr/bin/env bats
# =============================================================================
# Unit Tests: parse_language_list function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root and source the required files
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Extract and source parse_language_list from setup.sh
    TEMP_FUNCTIONS="$(mktemp)"
    sed -n '/^parse_language_list()/,/^}/p' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"
    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Single Language
# =============================================================================

@test "parse_language_list: parses single language" {
    run parse_language_list "python"
    assert_success
    assert_output "python"
}

@test "parse_language_list: parses single language with trailing comma" {
    run parse_language_list "python,"
    assert_success
    assert_output "python"
}

# =============================================================================
# Multiple Languages
# =============================================================================

@test "parse_language_list: parses two languages" {
    run parse_language_list "python,node"
    assert_success
    assert_output "python node"
}

@test "parse_language_list: parses three languages" {
    run parse_language_list "python,node,rust"
    assert_success
    assert_output "python node rust"
}

@test "parse_language_list: parses all four languages" {
    run parse_language_list "python,node,rust,deno"
    assert_success
    assert_output "python node rust deno"
}

# =============================================================================
# Whitespace Handling
# =============================================================================

@test "parse_language_list: handles spaces after commas" {
    run parse_language_list "python, node, rust"
    assert_success
    assert_output "python node rust"
}

@test "parse_language_list: handles spaces before commas" {
    run parse_language_list "python ,node ,rust"
    assert_success
    assert_output "python node rust"
}

@test "parse_language_list: handles spaces around commas" {
    run parse_language_list "python , node , rust"
    assert_success
    assert_output "python node rust"
}

@test "parse_language_list: handles multiple spaces" {
    run parse_language_list "python  ,  node  ,  rust"
    assert_success
    assert_output "python node rust"
}

@test "parse_language_list: handles tabs" {
    run parse_language_list $'python\t,\tnode'
    assert_success
    assert_output "python node"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "parse_language_list: handles empty string" {
    run parse_language_list ""
    assert_success
    # Empty input should produce empty output (just whitespace from empty array)
    [[ -z "${output// /}" ]] || [[ "$output" == "" ]]
}

@test "parse_language_list: handles single comma" {
    run parse_language_list ","
    assert_success
    # Should produce empty elements which get trimmed
}

@test "parse_language_list: preserves case" {
    run parse_language_list "Python,NODE,Rust"
    assert_success
    assert_output "Python NODE Rust"
}

# =============================================================================
# Real-world Scenarios
# =============================================================================

@test "parse_language_list: parses typical user input 'python,node'" {
    run parse_language_list "python,node"
    assert_success
    assert_output "python node"
}

@test "parse_language_list: parses full stack 'python,node,rust,deno'" {
    run parse_language_list "python,node,rust,deno"
    assert_success
    assert_output "python node rust deno"
}
