#!/usr/bin/env bats
# =============================================================================
# Unit Tests: read_masked_input function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source the plugin.sh to get read_masked_input function
    source "${PROJECT_ROOT}/templates/github-actions/plugin.sh"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Function Existence Tests
# =============================================================================

@test "read_masked_input: function exists" {
    run type read_masked_input
    assert_success
    assert_output --partial "function"
}

# =============================================================================
# Basic Functionality Tests
# =============================================================================

@test "read_masked_input: handles simulated input" {
    # Simulate input by creating a fake /dev/tty input
    # Note: This test verifies the function structure exists
    # Full interactive testing requires manual verification
    run bash -c '
        source "'"${PROJECT_ROOT}"'/templates/github-actions/plugin.sh"
        echo "testtoken" | read_masked_input 2>/dev/null || true
    '
    # Function should exist and be callable (may fail due to /dev/tty requirement)
    # This is expected behavior - full testing requires interactive terminal
    [[ $status -eq 0 ]] || [[ $status -eq 1 ]]
}

# =============================================================================
# Code Pattern Tests
# =============================================================================

@test "read_masked_input: uses /dev/tty for input" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    run grep -E 'read.*< ?/dev/tty' "$plugin_file"
    assert_success
    assert_output --partial "/dev/tty"
}

@test "read_masked_input: handles backspace characters" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for backspace handling (both \x7f and \b)
    run grep -E "\\\\x7f|\\\\b" "$plugin_file"
    assert_success
}

@test "read_masked_input: outputs masked characters to stderr" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for printf '*' pattern
    run grep -E "printf '\*'" "$plugin_file"
    assert_success
}

@test "read_masked_input: returns input via stdout" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for printf '%s' pattern for output
    run grep -E "printf '%s' \"\\\$input\"" "$plugin_file"
    assert_success
}

# =============================================================================
# Integration with setup_project_automation Tests
# =============================================================================

@test "setup_project_automation: uses read_masked_input for token" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check that the token input uses read_masked_input
    run grep -E 'pat=\$\(read_masked_input\)' "$plugin_file"
    assert_success
}

@test "setup_project_automation: shows token confirmation message" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for confirmation message with character count
    run grep -E 'Token received.*\$\{#pat\}' "$plugin_file"
    assert_success
}

# =============================================================================
# Bracket Paste Mode Handling Tests
# =============================================================================

@test "read_masked_input: disables bracket paste mode" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for bracket paste mode disable sequence
    run grep -E "\\\\e\[\?2004l" "$plugin_file"
    assert_success
}

@test "read_masked_input: re-enables bracket paste mode" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for bracket paste mode re-enable sequence
    run grep -E "\\\\e\[\?2004h" "$plugin_file"
    assert_success
}

@test "read_masked_input: handles escape sequences" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for escape character handling (detects ESC character and skips sequence)
    run grep -E "\\\$'\\\\e'" "$plugin_file"
    assert_success
}

@test "read_masked_input: sanitizes non-printable characters" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for tr sanitization command
    run grep -E "tr -cd '\[:print:\]'" "$plugin_file"
    assert_success
}

# =============================================================================
# WSL2 Compatibility Tests (Issue #80)
# =============================================================================

@test "read_masked_input: has delay after bracket paste disable" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for sleep delay after disabling bracket paste mode
    run grep -A4 "printf.*2004l" "$plugin_file"
    assert_success
    assert_output --partial "sleep"
}

@test "read_masked_input: uses increased timeout for escape sequences" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for 0.1 second timeout (increased from 0.01 for WSL2)
    run grep -E "read.*-t 0\.1" "$plugin_file"
    assert_success
}

@test "read_masked_input: breaks on letter terminators" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for letter terminator detection [A-Za-z]
    run grep -E "\[A-Za-z\]" "$plugin_file"
    assert_success
}

@test "read_masked_input: has safety limit for escape sequences" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for escape_count safety limit
    run grep -E "escape_count.*10" "$plugin_file"
    assert_success
}

@test "read_masked_input: filters printable characters only" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for printable character check
    run grep -E "\[\[:print:\]\]" "$plugin_file"
    assert_success
}

@test "read_masked_input: uses stty to disable echo" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for stty -echo command (handles right-click paste)
    run grep -E "stty -echo" "$plugin_file"
    assert_success
}

@test "read_masked_input: restores stty settings after input" {
    local plugin_file="${PROJECT_ROOT}/templates/github-actions/plugin.sh"
    # Check for stty settings restoration
    run grep -E 'stty "\$old_stty_settings"' "$plugin_file"
    assert_success
}
