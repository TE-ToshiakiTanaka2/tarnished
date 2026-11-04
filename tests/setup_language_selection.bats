#!/usr/bin/env bats

# Tests for prompt_language_selection() in setup.sh
# These tests verify the language selection parsing logic.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # Source common library
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    # Set up global variables that setup.sh defines
    declare -ga SELECTED_LANGUAGES=()
    declare -ga AVAILABLE_LANGUAGES=("rust" "python" "node" "deno" "latex")
    declare -gA LANGUAGE_DISPLAY_NAMES=(
        ["rust"]="Rust"
        ["python"]="Python"
        ["node"]="Node.js/TypeScript"
        ["deno"]="Deno"
        ["latex"]="LaTeX"
    )
}

# Helper: extract and test the parsing logic directly
# Simulates what prompt_language_selection does after reading input
parse_language_input() {
    local response="$1"
    local lang_count=${#AVAILABLE_LANGUAGES[@]}

    SELECTED_LANGUAGES=()

    if [[ -z "$response" ]] || [[ "$response" == "none" ]]; then
        :
    elif [[ "$response" == "all" ]]; then
        SELECTED_LANGUAGES=("${AVAILABLE_LANGUAGES[@]}")
    else
        IFS=',' read -ra nums <<< "$response"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$lang_count" ]]; then
                SELECTED_LANGUAGES+=("${AVAILABLE_LANGUAGES[$((num-1))]}")
            fi
        done
    fi
}

# --- Empty input (none) ---

@test "empty input selects no languages" {
    parse_language_input ""
    assert_equal "${#SELECTED_LANGUAGES[@]}" "0"
}

@test "'none' keyword selects no languages" {
    parse_language_input "none"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "0"
}

# --- Single selection ---

@test "single number selects one language" {
    parse_language_input "2"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "1"
    assert_equal "${SELECTED_LANGUAGES[0]}" "python"
}

@test "first language can be selected" {
    parse_language_input "1"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "1"
    assert_equal "${SELECTED_LANGUAGES[0]}" "rust"
}

@test "last language can be selected" {
    parse_language_input "5"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "1"
    assert_equal "${SELECTED_LANGUAGES[0]}" "latex"
}

# --- Multiple selection ---

@test "comma-separated numbers select multiple languages" {
    parse_language_input "1,3"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "2"
    assert_equal "${SELECTED_LANGUAGES[0]}" "rust"
    assert_equal "${SELECTED_LANGUAGES[1]}" "node"
}

@test "comma-separated with spaces works" {
    parse_language_input "2, 4"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "2"
    assert_equal "${SELECTED_LANGUAGES[0]}" "python"
    assert_equal "${SELECTED_LANGUAGES[1]}" "deno"
}

@test "all five languages can be selected" {
    parse_language_input "1,2,3,4,5"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "5"
    assert_equal "${SELECTED_LANGUAGES[0]}" "rust"
    assert_equal "${SELECTED_LANGUAGES[1]}" "python"
    assert_equal "${SELECTED_LANGUAGES[2]}" "node"
    assert_equal "${SELECTED_LANGUAGES[3]}" "deno"
    assert_equal "${SELECTED_LANGUAGES[4]}" "latex"
}

# --- 'all' keyword ---

@test "'all' keyword selects all languages" {
    parse_language_input "all"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "5"
    assert_equal "${SELECTED_LANGUAGES[0]}" "rust"
    assert_equal "${SELECTED_LANGUAGES[1]}" "python"
    assert_equal "${SELECTED_LANGUAGES[2]}" "node"
    assert_equal "${SELECTED_LANGUAGES[3]}" "deno"
    assert_equal "${SELECTED_LANGUAGES[4]}" "latex"
}

# --- Invalid input handling ---

@test "out-of-range number is ignored" {
    parse_language_input "6"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "0"
}

@test "zero is ignored" {
    parse_language_input "0"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "0"
}

@test "non-numeric input is ignored" {
    parse_language_input "abc"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "0"
}

@test "mixed valid and invalid input keeps only valid" {
    parse_language_input "1,99,3"
    assert_equal "${#SELECTED_LANGUAGES[@]}" "2"
    assert_equal "${SELECTED_LANGUAGES[0]}" "rust"
    assert_equal "${SELECTED_LANGUAGES[1]}" "node"
}

# --- godot flavor (#331): checks against setup.sh itself, not the fixture above

@test "setup.sh registers godot as an available language with a display name" {
    run bash -c 'source "$1/setup.sh"; echo "${AVAILABLE_LANGUAGES[*]}"; echo "${LANGUAGE_DISPLAY_NAMES[godot]}"; validate_language godot' _ "$SCRIPT_DIR"
    assert_success
    assert_line --index 0 --partial "godot"
    assert_line --index 1 "Godot (GDScript + C#)"
}

@test "setup.sh keeps the existing language menu numbers stable" {
    run bash -c 'source "$1/setup.sh"; echo "${AVAILABLE_LANGUAGES[*]}"' _ "$SCRIPT_DIR"
    assert_output "rust python node deno latex go godot"
}

@test "godot plugin.sh satisfies the plugin contract in isolation" {
    [[ -f "${SCRIPT_DIR}/templates/languages/godot/plugin.sh" ]]
    run bash -c '
        source "$1/scripts/lib/common.sh"
        source "$1/templates/languages/godot/plugin.sh"
        [[ "$(plugin_name)" == "godot" ]] || exit 1
        [[ -n "$(plugin_description)" ]] || exit 1
        for fn in plugin_copy plugin_dockerfile plugin_post_copy_shared plugin_post_copy_module plugin_post_copy; do
            declare -f "$fn" > /dev/null || { echo "missing $fn"; exit 1; }
        done
    ' _ "$SCRIPT_DIR"
    assert_success
}

@test "manifest options accept the godot language id" {
    run bash -c 'source "$1/scripts/lib/common.sh"; source "$1/scripts/lib/manifest.sh"; manifest_options_valid "{\"languages\":[\"godot\"]}"' _ "$SCRIPT_DIR"
    assert_success
}
