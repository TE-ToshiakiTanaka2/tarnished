#!/bin/bash
# =============================================================================
# Test Helper: Mock Functions
# Provides mock implementations for interactive and I/O functions
# =============================================================================

# Prevent multiple loading
if [[ -n "${_TEST_MOCK_LOADED:-}" ]]; then
    return 0
fi
_TEST_MOCK_LOADED=1

# =============================================================================
# Mock State Tracking
# =============================================================================

# Array to track mock calls
declare -a MOCK_CALLS=()

# Clear all mock call records
mock_clear_calls() {
    MOCK_CALLS=()
}

# Record a mock call
mock_record_call() {
    local func_name="$1"
    shift
    MOCK_CALLS+=("${func_name}:$*")
}

# Check if a mock was called
mock_was_called() {
    local func_name="$1"
    local call
    for call in "${MOCK_CALLS[@]}"; do
        if [[ "${call}" == "${func_name}:"* ]]; then
            return 0
        fi
    done
    return 1
}

# Get the number of times a mock was called
mock_call_count() {
    local func_name="$1"
    local count=0
    local call
    for call in "${MOCK_CALLS[@]}"; do
        if [[ "${call}" == "${func_name}:"* ]]; then
            ((count++))
        fi
    done
    echo "${count}"
}

# =============================================================================
# Mock Return Value Configuration
# =============================================================================

# Associative array for mock return values
declare -A MOCK_RETURN_VALUES=()

# Set a mock return value
mock_set_return() {
    local func_name="$1"
    local return_value="$2"
    MOCK_RETURN_VALUES["${func_name}"]="${return_value}"
}

# Get a mock return value
mock_get_return() {
    local func_name="$1"
    echo "${MOCK_RETURN_VALUES["${func_name}"]:-}"
}

# =============================================================================
# Interactive Function Mocks
# =============================================================================

# Mock for prompt_project_name
mock_prompt_project_name() {
    mock_record_call "prompt_project_name" "$@"
    local return_val="${MOCK_RETURN_VALUES["prompt_project_name"]:-test-project}"
    echo "${return_val}"
}

# Mock for prompt_language_selection
mock_prompt_language_selection() {
    mock_record_call "prompt_language_selection" "$@"
    # Set SELECTED_LANGUAGES based on mock config
    local return_val="${MOCK_RETURN_VALUES["prompt_language_selection"]:-python}"
    SELECTED_LANGUAGES=("${return_val}")
}

# Mock for prompt_playwright
mock_prompt_playwright() {
    mock_record_call "prompt_playwright" "$@"
    local return_val="${MOCK_RETURN_VALUES["prompt_playwright"]:-false}"
    PLAYWRIGHT_ENABLED="${return_val}"
}

# =============================================================================
# File Operation Mocks
# =============================================================================

# Mock for copy_template_dir (no-op version)
mock_copy_template_dir_noop() {
    mock_record_call "copy_template_dir" "$@"
    return 0
}

# Mock for copy_template_dir (copies to temp)
mock_copy_template_dir_to_temp() {
    mock_record_call "copy_template_dir" "$@"
    local source_dir="$1"
    local target_dir="$2"

    if [[ -d "${source_dir}" ]]; then
        cp -r "${source_dir}"/* "${target_dir}/" 2>/dev/null || true
    fi
    return 0
}

# =============================================================================
# Plugin Hook Mocks
# =============================================================================

# Mock for execute_plugins_hook (tracks calls only)
mock_execute_plugins_hook() {
    mock_record_call "execute_plugins_hook" "$@"
    return 0
}

# =============================================================================
# Mock Installation Functions
# =============================================================================

# Install mocks for integration testing
install_integration_mocks() {
    # Save original functions if they exist
    if declare -f prompt_project_name >/dev/null 2>&1; then
        eval "original_prompt_project_name() { $(declare -f prompt_project_name | tail -n +2); }"
    fi
    if declare -f prompt_language_selection >/dev/null 2>&1; then
        eval "original_prompt_language_selection() { $(declare -f prompt_language_selection | tail -n +2); }"
    fi
    if declare -f prompt_playwright >/dev/null 2>&1; then
        eval "original_prompt_playwright() { $(declare -f prompt_playwright | tail -n +2); }"
    fi

    # Replace with mocks
    prompt_project_name() { mock_prompt_project_name "$@"; }
    prompt_language_selection() { mock_prompt_language_selection "$@"; }
    prompt_playwright() { mock_prompt_playwright "$@"; }

    export -f prompt_project_name
    export -f prompt_language_selection
    export -f prompt_playwright
}

# Restore original functions
restore_original_functions() {
    if declare -f original_prompt_project_name >/dev/null 2>&1; then
        eval "prompt_project_name() { $(declare -f original_prompt_project_name | tail -n +2); }"
    fi
    if declare -f original_prompt_language_selection >/dev/null 2>&1; then
        eval "prompt_language_selection() { $(declare -f original_prompt_language_selection | tail -n +2); }"
    fi
    if declare -f original_prompt_playwright >/dev/null 2>&1; then
        eval "prompt_playwright() { $(declare -f original_prompt_playwright | tail -n +2); }"
    fi
}
