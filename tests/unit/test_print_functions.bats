#!/usr/bin/env bats
# =============================================================================
# Unit Tests: print_* functions (output formatting)
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh (contains print_* functions)
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Load bats libraries
    load_bats_libraries
}

# =============================================================================
# Color Code Constants
# =============================================================================

# ANSI color codes (matching common.sh)
readonly EXPECTED_RED='\033[0;31m'
readonly EXPECTED_GREEN='\033[0;32m'
readonly EXPECTED_YELLOW='\033[1;33m'
readonly EXPECTED_BLUE='\033[0;34m'
readonly EXPECTED_NC='\033[0m'

# =============================================================================
# print_success Tests
# =============================================================================

@test "print_success: outputs message with checkmark" {
    run print_success "Test message"
    assert_success
    assert_output --partial "✓ Test message"
}

@test "print_success: uses green color" {
    run print_success "Test"
    assert_success
    # Check that output contains the green color code
    [[ "$output" == *"${COLOR_GREEN}"* ]] || [[ "$output" == *$'\033[0;32m'* ]]
}

@test "print_success: handles empty message" {
    run print_success ""
    assert_success
    assert_output --partial "✓"
}

@test "print_success: handles special characters" {
    run print_success "Test with 'quotes' and \"double quotes\""
    assert_success
    assert_output --partial "✓ Test with 'quotes' and \"double quotes\""
}

# =============================================================================
# print_error Tests
# =============================================================================

@test "print_error: outputs message with X mark" {
    run print_error "Error message"
    assert_success
    assert_output --partial "✗ Error message"
}

@test "print_error: uses red color" {
    run print_error "Error"
    assert_success
    [[ "$output" == *"${COLOR_RED}"* ]] || [[ "$output" == *$'\033[0;31m'* ]]
}

@test "print_error: handles empty message" {
    run print_error ""
    assert_success
    assert_output --partial "✗"
}

@test "print_error: handles multiline message" {
    run print_error "Line 1
Line 2"
    assert_success
    assert_output --partial "Line 1"
}

# =============================================================================
# print_warning Tests
# =============================================================================

@test "print_warning: outputs message with warning symbol" {
    run print_warning "Warning message"
    assert_success
    assert_output --partial "⚠ Warning message"
}

@test "print_warning: uses yellow color" {
    run print_warning "Warning"
    assert_success
    [[ "$output" == *"${COLOR_YELLOW}"* ]] || [[ "$output" == *$'\033[1;33m'* ]]
}

@test "print_warning: handles empty message" {
    run print_warning ""
    assert_success
    assert_output --partial "⚠"
}

# =============================================================================
# print_info Tests
# =============================================================================

@test "print_info: outputs message with info symbol" {
    run print_info "Info message"
    assert_success
    assert_output --partial "ℹ Info message"
}

@test "print_info: uses blue color" {
    run print_info "Info"
    assert_success
    [[ "$output" == *"${COLOR_BLUE}"* ]] || [[ "$output" == *$'\033[0;34m'* ]]
}

@test "print_info: handles empty message" {
    run print_info ""
    assert_success
    assert_output --partial "ℹ"
}

# =============================================================================
# Color Reset Tests
# =============================================================================

@test "print_success: resets color after message" {
    run print_success "Test"
    assert_success
    [[ "$output" == *"${COLOR_NC}"* ]] || [[ "$output" == *$'\033[0m'* ]]
}

@test "print_error: resets color after message" {
    run print_error "Test"
    assert_success
    [[ "$output" == *"${COLOR_NC}"* ]] || [[ "$output" == *$'\033[0m'* ]]
}

@test "print_warning: resets color after message" {
    run print_warning "Test"
    assert_success
    [[ "$output" == *"${COLOR_NC}"* ]] || [[ "$output" == *$'\033[0m'* ]]
}

@test "print_info: resets color after message" {
    run print_info "Test"
    assert_success
    [[ "$output" == *"${COLOR_NC}"* ]] || [[ "$output" == *$'\033[0m'* ]]
}

# =============================================================================
# Variable Expansion Tests
# =============================================================================

@test "print_success: expands variables in message" {
    local var="dynamic content"
    run print_success "Message with ${var}"
    assert_success
    assert_output --partial "✓ Message with dynamic content"
}

@test "print_error: expands variables in message" {
    local code=42
    run print_error "Exit code: ${code}"
    assert_success
    assert_output --partial "✗ Exit code: 42"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "print functions: handle long messages" {
    local long_msg
    long_msg=$(printf 'x%.0s' {1..200})
    run print_success "${long_msg}"
    assert_success
    assert_output --partial "✓ ${long_msg}"
}

@test "print functions: handle unicode" {
    run print_success "日本語テスト 🎉"
    assert_success
    assert_output --partial "✓ 日本語テスト 🎉"
}

@test "print functions: handle newlines in message" {
    run print_info $'Line1\nLine2'
    assert_success
    assert_output --partial "ℹ Line1"
}
