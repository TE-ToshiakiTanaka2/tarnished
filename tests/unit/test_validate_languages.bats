#!/usr/bin/env bats
# =============================================================================
# Unit Tests: validate_languages function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh first (provides print_* functions)
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Define AVAILABLE_LANGUAGES (simulating setup.sh state)
    AVAILABLE_LANGUAGES=("python" "node" "rust" "deno")
    export AVAILABLE_LANGUAGES

    # Extract and source validate_languages from setup.sh
    TEMP_FUNCTIONS="$(mktemp)"
    sed -n '/^validate_languages()/,/^}/p' "${PROJECT_ROOT}/setup.sh" > "${TEMP_FUNCTIONS}"
    source "${TEMP_FUNCTIONS}"
    rm -f "${TEMP_FUNCTIONS}"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Valid Languages - Single
# =============================================================================

@test "validate_languages: accepts python" {
    run validate_languages "python"
    assert_success
}

@test "validate_languages: accepts node" {
    run validate_languages "node"
    assert_success
}

@test "validate_languages: accepts rust" {
    run validate_languages "rust"
    assert_success
}

@test "validate_languages: accepts deno" {
    run validate_languages "deno"
    assert_success
}

# =============================================================================
# Valid Languages - Multiple
# =============================================================================

@test "validate_languages: accepts two languages" {
    run validate_languages "python" "node"
    assert_success
}

@test "validate_languages: accepts three languages" {
    run validate_languages "python" "node" "rust"
    assert_success
}

@test "validate_languages: accepts all four languages" {
    run validate_languages "python" "node" "rust" "deno"
    assert_success
}

# =============================================================================
# Invalid Languages - Single
# =============================================================================

@test "validate_languages: rejects unknown language 'go'" {
    run validate_languages "go"
    assert_failure
    assert_output --partial "Unknown language(s): go"
    assert_output --partial "Available languages:"
}

@test "validate_languages: rejects unknown language 'java'" {
    run validate_languages "java"
    assert_failure
    assert_output --partial "Unknown language(s): java"
}

@test "validate_languages: rejects unknown language with typo 'pytohn'" {
    run validate_languages "pytohn"
    assert_failure
    assert_output --partial "Unknown language(s): pytohn"
}

# =============================================================================
# Invalid Languages - Mixed Valid and Invalid
# =============================================================================

@test "validate_languages: rejects mix of valid and invalid" {
    run validate_languages "python" "invalid"
    assert_failure
    assert_output --partial "Unknown language(s): invalid"
}

@test "validate_languages: lists all invalid languages in error" {
    run validate_languages "python" "go" "java"
    assert_failure
    assert_output --partial "Unknown language(s):"
    assert_output --partial "go"
    assert_output --partial "java"
}

# =============================================================================
# Case Sensitivity
# =============================================================================

@test "validate_languages: is case-sensitive (rejects PYTHON)" {
    run validate_languages "PYTHON"
    assert_failure
    assert_output --partial "Unknown language(s): PYTHON"
}

@test "validate_languages: is case-sensitive (rejects Python)" {
    run validate_languages "Python"
    assert_failure
    assert_output --partial "Unknown language(s): Python"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "validate_languages: handles empty input (no arguments)" {
    run validate_languages
    assert_success
    # No languages to validate = success
}

@test "validate_languages: rejects empty string as language" {
    run validate_languages ""
    assert_failure
    # Empty string is not in AVAILABLE_LANGUAGES
}

# =============================================================================
# Duplicate Languages
# =============================================================================

@test "validate_languages: accepts duplicate valid languages" {
    run validate_languages "python" "python"
    assert_success
}

@test "validate_languages: fails with duplicate invalid languages" {
    run validate_languages "invalid" "invalid"
    assert_failure
    assert_output --partial "Unknown language(s):"
}
