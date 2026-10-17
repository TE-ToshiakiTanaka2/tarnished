#!/usr/bin/env bats

# #323: merge_zed_settings (deep merge for .zed/settings.json) and
# apply_zed_assets (the only reader of ZED_ENABLED; installs a flavor's
# .zed/ contributions into a target project).

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    SCRATCH="$(mktemp -d)"
    export SCRATCH
}

teardown() {
    if [[ -n "${SCRATCH:-}" ]] && [[ -d "$SCRATCH" ]]; then
        case "$SCRATCH" in
            /tmp/*) rm -rf "$SCRATCH" ;;
        esac
    fi
}

# =============================================================================
# merge_zed_settings
# =============================================================================

@test "merge_zed_settings deep-merges nested language objects" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "languages": { "Rust": { "format_on_save": "on" } } }
JSON
    cat > "$overlay_file" <<'JSON'
{ "languages": { "Python": { "format_on_save": "on" } } }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -r '.languages.Rust.format_on_save' "$output_file"
    assert_output "on"

    run jq -r '.languages.Python.format_on_save' "$output_file"
    assert_output "on"
}

@test "merge_zed_settings unions and de-duplicates array values" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "file_scan_exclusions": ["**/node_modules", "**/target", "..."] }
JSON
    cat > "$overlay_file" <<'JSON'
{ "file_scan_exclusions": ["**/target", "**/dist"] }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -Sc '.file_scan_exclusions' "$output_file"
    assert_output '["**/dist","**/node_modules","**/target","..."]'
}

@test "merge_zed_settings prefers the overlay for scalar conflicts" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    # Also covers the object-vs-string formatter mismatch (node + deno).
    cat > "$base_file" <<'JSON'
{ "languages": { "TypeScript": { "format_on_save": "off", "formatter": { "language_server": { "name": "biome" } } } } }
JSON
    cat > "$overlay_file" <<'JSON'
{ "languages": { "TypeScript": { "format_on_save": "on", "formatter": "language_server" } } }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -r '.languages.TypeScript.format_on_save' "$output_file"
    assert_output "on"

    run jq -r '.languages.TypeScript.formatter' "$output_file"
    assert_output "language_server"
}

@test "merge_zed_settings preserves keys only present in the base" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "theme": "One Dark", "file_scan_exclusions": ["**/custom-glob"] }
JSON
    cat > "$overlay_file" <<'JSON'
{ "languages": { "Python": { "format_on_save": "on" } } }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -r '.theme' "$output_file"
    assert_output "One Dark"

    run jq -c '.file_scan_exclusions' "$output_file"
    assert_output '["**/custom-glob"]'
}

@test "merge_zed_settings is idempotent across repeated merges" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"

    cat > "$base_file" <<'JSON'
{ "file_scan_exclusions": ["**/node_modules", "**/target", "..."] }
JSON
    cat > "$overlay_file" <<'JSON'
{ "file_scan_exclusions": ["**/target"], "lsp": { "rust-analyzer": { "initialization_options": { "check": { "command": "clippy" } } } } }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$first_output"
    assert_success

    run merge_zed_settings "$first_output" "$overlay_file" "$second_output"
    assert_success

    run jq -S . "$first_output"
    assert_success
    local first_sorted="$output"

    run jq -S . "$second_output"
    assert_success
    assert_output "$first_sorted"
}

@test "merge_zed_settings accepts comment-bearing Zed settings" {
    local base_file="$SCRATCH/base.jsonc"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSONC'
{
  // Developer note on the shell choice.
  "terminal": { "shell": { "program": "bash" } }
}
JSONC
    cat > "$overlay_file" <<'JSON'
{ "file_scan_exclusions": ["**/target"] }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq empty "$output_file"
    assert_success

    run jq -r '.terminal.shell.program' "$output_file"
    assert_output "bash"
}

@test "merge_zed_settings copies the base when the overlay is missing" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/missing-overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "terminal": { "shell": { "program": "bash" } } }
JSON

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -r '.terminal.shell.program' "$output_file"
    assert_output "bash"
}

@test "merge_zed_settings fails and leaves no output when the base is missing" {
    local base_file="$SCRATCH/missing-base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    echo '{}' > "$overlay_file"

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_failure
    [[ ! -e "$output_file" ]]
}

@test "merge_zed_settings removes the output when the base is invalid JSON" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    echo '{ "unterminated":' > "$base_file"
    echo '{}' > "$overlay_file"
    echo "stale" > "$output_file"

    run merge_zed_settings "$base_file" "$overlay_file" "$output_file"
    assert_failure
    [[ ! -e "$output_file" ]]
}

# =============================================================================
# apply_zed_assets
# =============================================================================

seed_target_devcontainer() {
    mkdir -p "$SCRATCH/target/.devcontainer"
    echo '{}' > "$SCRATCH/target/.devcontainer/devcontainer.json"
}

seed_plugin_zed_dir() {
    mkdir -p "$SCRATCH/plugin/.zed"
    cat > "$SCRATCH/plugin/.zed/devcontainer.json" <<'JSON'
{ "customizations": { "zed": { "extensions": ["dockerfile"] } } }
JSON
    cat > "$SCRATCH/plugin/.zed/settings.json" <<'JSON'
{ "file_scan_exclusions": ["**/node_modules", "**/target"] }
JSON
}

@test "apply_zed_assets does nothing when ZED_ENABLED is unset" {
    seed_target_devcontainer
    seed_plugin_zed_dir
    unset ZED_ENABLED

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    [[ ! -e "$SCRATCH/target/.zed" ]]

    run jq -c . "$SCRATCH/target/.devcontainer/devcontainer.json"
    assert_output "{}"
}

@test "apply_zed_assets does nothing when the flavor ships no .zed directory" {
    seed_target_devcontainer
    mkdir -p "$SCRATCH/plugin"
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    [[ ! -e "$SCRATCH/target/.zed" ]]
}

@test "apply_zed_assets creates .zed/settings.json for the first contributor" {
    seed_target_devcontainer
    seed_plugin_zed_dir
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    [[ -f "$SCRATCH/target/.zed/settings.json" ]]

    run jq empty "$SCRATCH/target/.zed/settings.json"
    assert_success

    run jq -Sc '.file_scan_exclusions' "$SCRATCH/target/.zed/settings.json"
    assert_output '["**/node_modules","**/target"]'
}

@test "apply_zed_assets merges a language fragment into an existing .zed/settings.json" {
    seed_target_devcontainer
    seed_plugin_zed_dir
    mkdir -p "$SCRATCH/target/.zed"
    cat > "$SCRATCH/target/.zed/settings.json" <<'JSON'
{ "terminal": { "shell": { "program": "bash" } } }
JSON
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    run jq -r '.terminal.shell.program' "$SCRATCH/target/.zed/settings.json"
    assert_output "bash"

    run jq -Sc '.file_scan_exclusions' "$SCRATCH/target/.zed/settings.json"
    assert_output '["**/node_modules","**/target"]'
}

@test "apply_zed_assets merges customizations.zed into the target devcontainer" {
    seed_target_devcontainer
    seed_plugin_zed_dir
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    run jq -c '.customizations.zed.extensions' "$SCRATCH/target/.devcontainer/devcontainer.json"
    assert_output '["dockerfile"]'
}

@test "apply_zed_assets leaves the live settings file unchanged when the merge fails" {
    seed_target_devcontainer
    seed_plugin_zed_dir
    mkdir -p "$SCRATCH/target/.zed"
    echo '{ "unterminated":' > "$SCRATCH/target/.zed/settings.json"
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    run cat "$SCRATCH/target/.zed/settings.json"
    assert_output '{ "unterminated":'

    [[ ! -e "$SCRATCH/target/.zed/settings.json.tmp" ]]
}

@test "apply_zed_assets skips the devcontainer step when the target devcontainer is absent" {
    mkdir -p "$SCRATCH/target"
    seed_plugin_zed_dir
    export ZED_ENABLED=true

    run apply_zed_assets "$SCRATCH/target" "$SCRATCH/plugin"
    assert_success

    [[ ! -e "$SCRATCH/target/.devcontainer" ]]
    [[ -f "$SCRATCH/target/.zed/settings.json" ]]
}
