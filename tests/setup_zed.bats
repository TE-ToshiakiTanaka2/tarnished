#!/usr/bin/env bats

# End-to-end tests for `setup.sh --zed` (#323 optional Zed editor support).

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup.sh"

setup() {
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

@test "--help documents --zed" {
    run bash "$SETUP_SH" --help
    assert_success
    assert_output --partial "--zed"
}

@test "scaffold without --zed creates no .zed directory" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust -y no-zed-proj
    assert_success

    [[ ! -e "$SCRATCH/.zed" ]]

    run jq '.customizations | has("zed")' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_output "false"
}

# NFR-1: with no Zed input anywhere, the devcontainer's customizations
# subtree is exactly what it was before #323 -- the vscode merge is
# unaffected and no zed key appears. (merge_devcontainer_json's own
# byte-identity guarantee is proven directly in tests/common_json.bats;
# this is the end-to-end restatement.)
@test "scaffold without --zed leaves the devcontainer customizations unchanged" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust -y no-zed-proj
    assert_success

    run jq -Sc '.customizations | keys' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_output '["vscode"]'

    run jq -c '.customizations.vscode.extensions' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_output --partial "rust-lang.rust-analyzer"
}

@test "scaffold with --zed writes .zed/settings.json" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    [[ -f "$SCRATCH/.zed/settings.json" ]]

    run jq empty "$SCRATCH/.zed/settings.json"
    assert_success

    run jq -r '.terminal.shell.program' "$SCRATCH/.zed/settings.json"
    assert_output "bash"

    run jq -c '.file_scan_exclusions' "$SCRATCH/.zed/settings.json"
    assert_output --partial '"..."'
}

@test "scaffold with --zed merges the language fragment into .zed/settings.json" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    run jq -r '.lsp["rust-analyzer"].initialization_options.check.command' "$SCRATCH/.zed/settings.json"
    assert_output "clippy"

    # Both contributors present: core's base survives the rust merge.
    run jq -r '.terminal.shell.program' "$SCRATCH/.zed/settings.json"
    assert_output "bash"
}

@test "scaffold with --zed writes customizations.zed.extensions" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    run jq -Sc '.customizations.zed.extensions' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_output '["dockerfile","toml"]'
}

@test "scaffold with --zed keeps customizations.vscode" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    run jq -r '.customizations.vscode.extensions | length' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_success
    [[ "$output" -gt 0 ]]
}

@test "scaffold with --zed and a service adds the service extension" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --postgresql --zed -y zed-proj
    assert_success

    run jq -Sc '.customizations.zed.extensions' "$SCRATCH/.devcontainer/devcontainer.json"
    assert_output '["dockerfile","sql","toml"]'
}

@test "--zed --dry-run writes nothing" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed --dry-run -y zed-proj
    assert_success

    [[ ! -e "$SCRATCH/.zed" ]]
    [[ ! -e "$SCRATCH/.devcontainer" ]]
    [[ -z "$(ls -A "$SCRATCH")" ]]
}

@test "scaffold with --zed records zed_enabled in the manifest" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    run jq -r '.scaffold_options.zed_enabled' "$SCRATCH/.tarnished-manifest.json"
    assert_output "true"
}

@test "scaffold without --zed records zed_enabled false in the manifest" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust -y no-zed-proj
    assert_success

    run jq -r '.scaffold_options.zed_enabled' "$SCRATCH/.tarnished-manifest.json"
    assert_output "false"
}

@test "scaffold with --zed does not track .zed/settings.json in the manifest" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust --zed -y zed-proj
    assert_success

    run jq '.files | has(".zed/settings.json")' "$SCRATCH/.tarnished-manifest.json"
    assert_output "false"
}

@test "--zed is rejected against an existing Tarnished project" {
    cd "$SCRATCH"
    run bash "$SETUP_SH" --lang rust -y existing-proj
    assert_success

    run bash "$SETUP_SH" --zed -y
    assert_failure
    assert_output --partial "Existing Tarnished project"
}

@test "--zed is ignored in add-module mode" {
    local monorepo="$SCRATCH/monorepo"
    mkdir "$monorepo"
    cd "$monorepo"
    run bash "$SETUP_SH" --monorepo --module backend:python -y monorepo
    assert_success

    run bash "$SETUP_SH" --add-module frontend --lang node --zed -y
    assert_success
    assert_output --partial "--zed is ignored in add-module mode"

    [[ ! -e "$monorepo/.zed" ]]
}
