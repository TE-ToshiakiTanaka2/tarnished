#!/usr/bin/env bats
# =============================================================================
# Unit Tests: merge_json_files function
# =============================================================================

# Load test helpers
setup() {
    load '../helpers/common'

    # Get project root
    PROJECT_ROOT="$(get_project_root)"

    # Source common.sh (contains merge_json_files)
    source "${PROJECT_ROOT}/scripts/lib/common.sh"

    # Load bats libraries
    load_bats_libraries

    # Setup temp directory for test files
    setup_temp_dir
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Basic Merge Operations
# =============================================================================

@test "merge_json_files: merges two simple objects" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{"name": "base", "value": 1}' > "${base_file}"
    echo '{"name": "overlay", "extra": 2}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    # Verify the output
    run jq -r '.name' "${output_file}"
    assert_output "overlay"

    run jq -r '.value' "${output_file}"
    assert_output "1"

    run jq -r '.extra' "${output_file}"
    assert_output "2"
}

@test "merge_json_files: overlay overrides base values" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{"debug": false, "timeout": 30}' > "${base_file}"
    echo '{"debug": true}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    run jq -r '.debug' "${output_file}"
    assert_output "true"

    run jq -r '.timeout' "${output_file}"
    assert_output "30"
}

# =============================================================================
# Nested Object Merge
# =============================================================================

@test "merge_json_files: deep merges nested objects" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{"settings": {"debug": false, "timeout": 30}}' > "${base_file}"
    echo '{"settings": {"debug": true, "maxRetries": 3}}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    run jq -r '.settings.debug' "${output_file}"
    assert_output "true"

    run jq -r '.settings.timeout' "${output_file}"
    assert_output "30"

    run jq -r '.settings.maxRetries' "${output_file}"
    assert_output "3"
}

# =============================================================================
# Array Handling
# =============================================================================

@test "merge_json_files: replaces arrays (does not merge)" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{"features": ["core", "debug"]}' > "${base_file}"
    echo '{"features": ["extra"]}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    # jq's * operator replaces arrays, doesn't merge them
    run jq -r '.features | length' "${output_file}"
    assert_output "1"

    run jq -r '.features[0]' "${output_file}"
    assert_output "extra"
}

# =============================================================================
# Using Fixture Files
# =============================================================================

@test "merge_json_files: merges fixture files correctly" {
    local fixtures_dir
    fixtures_dir="$(get_tests_dir)/fixtures/sample_json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    run merge_json_files "${fixtures_dir}/base.json" "${fixtures_dir}/overlay.json" "${output_file}"
    assert_success

    # Check merged values
    run jq -r '.name' "${output_file}"
    assert_output "overlay"

    run jq -r '.settings.debug' "${output_file}"
    assert_output "true"

    run jq -r '.settings.timeout' "${output_file}"
    assert_output "30"

    run jq -r '.settings.maxRetries' "${output_file}"
    assert_output "3"
}

# =============================================================================
# Error Handling
# =============================================================================

@test "merge_json_files: fails if base file not found" {
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{}' > "${overlay_file}"

    run merge_json_files "/nonexistent/base.json" "${overlay_file}" "${output_file}"
    assert_failure
    assert_output --partial "Base file not found"
}

@test "merge_json_files: fails if overlay file not found" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{}' > "${base_file}"

    run merge_json_files "${base_file}" "/nonexistent/overlay.json" "${output_file}"
    assert_failure
    assert_output --partial "Overlay file not found"
}

@test "merge_json_files: fails with invalid JSON in base" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo 'not valid json' > "${base_file}"
    echo '{}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_failure
    assert_output --partial "Failed to merge"
}

@test "merge_json_files: fails with invalid JSON in overlay" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{}' > "${base_file}"
    echo 'not valid json' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_failure
    assert_output --partial "Failed to merge"
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "merge_json_files: handles empty objects" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{}' > "${base_file}"
    echo '{}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    run cat "${output_file}"
    assert_output "{}"
}

@test "merge_json_files: handles null values" {
    local base_file="${TEST_TEMP_DIR}/base.json"
    local overlay_file="${TEST_TEMP_DIR}/overlay.json"
    local output_file="${TEST_TEMP_DIR}/output.json"

    echo '{"value": "something"}' > "${base_file}"
    echo '{"value": null}' > "${overlay_file}"

    run merge_json_files "${base_file}" "${overlay_file}" "${output_file}"
    assert_success

    run jq -r '.value' "${output_file}"
    assert_output "null"
}
