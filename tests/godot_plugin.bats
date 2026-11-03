#!/usr/bin/env bats

# Tests for the godot language flavor (#331): tooling-only scaffold, GUI
# overlay activation, hooks, post.sh block, gitignore block and monorepo split.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup.sh"
PLUGIN="${SCRIPT_DIR}/templates/languages/godot/plugin.sh"
OVERLAY_REF="../docker-compose.godot-gui.yml"

setup() {
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    export PROJECT_NAME="testproj"
    export MONOREPO_MODE=false
    export IS_ADD_MODULE_MODE=false
    export OVERWRITE_ALL=false
    export skip_confirm=true
    unset GODOT_GUI TARGET_DIR
    SKIP_CONFIRM=false
    UPGRADE_MODE=false
    CREATE_MANIFEST_MODE=false

    SCRATCH="$(mktemp -d)"
    export SCRATCH

    _seed_target "$SCRATCH"
    # Default: no terminal, whatever the host running bats has.
    check_tty_available() { return 1; }
    confirm() { echo "UNEXPECTED_CONFIRM" >&2; return 1; }
}

teardown() {
    case "${SCRATCH:-}" in
        /tmp/*) rm -rf "$SCRATCH" ;;
    esac
}

# Minimal scaffold layout the plugin edits.
_seed_target() {
    local t="$1"
    mkdir -p "$t/.devcontainer/scripts" "$t/.claude" "$t/docker" "$t/.github/workflows"
    echo '{"dockerComposeFile": ["../docker-compose.yml"]}' > "$t/.devcontainer/devcontainer.json"
    cp "${SCRIPT_DIR}/templates/claude/.claude/settings.json" "$t/.claude/settings.json"
    printf 'services:\n  testproj:\n    image: busybox\n' > "$t/docker-compose.yml"
    printf '[tools]\nnode = "22"\n' > "$t/mise.toml"
    : > "$t/.devcontainer/scripts/post.sh"
    chmod +x "$t/.devcontainer/scripts/post.sh"
    printf 'FROM debian:trixie\nSHELL ["/bin/bash", "-c"]\n' > "$t/docker/Dockerfile.dev"
}

_load_plugin() {
    # shellcheck disable=SC1090
    source "$PLUGIN"
}

_run_copy_and_post_copy() {
    _load_plugin
    plugin_copy "$SCRATCH" > /dev/null 2>&1
    plugin_post_copy "$SCRATCH" > /dev/null 2>&1
}

_compose_files() {
    jq -c '.dockerComposeFile' "$SCRATCH/.devcontainer/devcontainer.json"
}

# --- FR-11: tooling only ------------------------------------------------------

@test "scaffold creates no project.godot, export_presets.cfg or addons" {
    _run_copy_and_post_copy
    run find "$SCRATCH" \( -name project.godot -o -name export_presets.cfg -o -name addons \) -print
    assert_output ""
    [[ -f "$SCRATCH/gdlintrc" ]]
    [[ -f "$SCRATCH/.editorconfig" ]]
    [[ -f "$SCRATCH/docker-compose.godot-gui.yml" ]]
    [[ -f "$SCRATCH/.claude/rules/godot.md" ]]
    [[ -f "$SCRATCH/.github/workflows/godot-quality-check.yml" ]]
}

@test "pre-existing distributed files are kept when the copy is declined" {
    _load_plugin
    local f
    for f in gdlintrc .editorconfig docker-compose.godot-gui.yml .claude/rules/godot.md; do
        mkdir -p "$(dirname "$SCRATCH/$f")"
        echo "mine" > "$SCRATCH/$f"
    done
    plugin_copy "$SCRATCH" > /dev/null 2>&1
    plugin_post_copy "$SCRATCH" > /dev/null 2>&1
    for f in gdlintrc .editorconfig docker-compose.godot-gui.yml .claude/rules/godot.md; do
        run cat "$SCRATCH/$f"
        assert_output "mine"
    done
}

@test "an existing workflow is kept in non-TTY mode while the overlay is still copied" {
    _load_plugin
    echo "mine" > "$SCRATCH/.github/workflows/godot-quality-check.yml"
    run plugin_copy "$SCRATCH"
    assert_success
    assert_output --partial "Skipping godot-quality-check.yml"
    run cat "$SCRATCH/.github/workflows/godot-quality-check.yml"
    assert_output "mine"
    [[ -f "$SCRATCH/docker-compose.godot-gui.yml" ]]
}

# --- gitignore ----------------------------------------------------------------

@test "gitignore block is appended once and user lines survive a second run" {
    printf 'before.txt' > "$SCRATCH/.gitignore"
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    printf 'after.txt\n' >> "$SCRATCH/.gitignore"
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run grep -c '^# Godot (engine caches and export output)$' "$SCRATCH/.gitignore"
    assert_output "1"
    run grep -x 'before.txt' "$SCRATCH/.gitignore"
    assert_success
    run grep -x 'after.txt' "$SCRATCH/.gitignore"
    assert_success
    run grep -x '.godot/' "$SCRATCH/.gitignore"
    assert_success
    run grep -x 'build/' "$SCRATCH/.gitignore"
    assert_success
}

@test "gitignore marker is matched as an exact line" {
    printf '# Godot (engine caches and export output) extra\n' > "$SCRATCH/.gitignore"
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run grep -c '^# Godot (engine caches and export output)$' "$SCRATCH/.gitignore"
    assert_output "1"
}

# --- Claude hooks -------------------------------------------------------------

@test "Claude hooks: one Write|Edit entry with four handlers, unchanged by a second merge" {
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run jq -c '[.hooks.PostToolUse[] | select(.matcher == "Write|Edit") | .hooks[].if]' \
        "$SCRATCH/.claude/settings.json"
    assert_output '["Write(*.gd)","Edit(*.gd)","Write(*.cs)","Edit(*.cs)"]'
    local first
    first="$(cat "$SCRATCH/.claude/settings.json")"
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    [[ "$(cat "$SCRATCH/.claude/settings.json")" == "$first" ]]
}

# --- post.sh -------------------------------------------------------------------

@test "post.sh block lands before the Codex and plugin blocks and is added once" {
    printf '#!/bin/bash\n# first\n\n# -----\n# Codex CLI Setup\n# -----\necho codex\n\n# -----\n# Claude Code Plugin Setup\n# -----\necho plugin\n' \
        > "$SCRATCH/.devcontainer/scripts/post.sh"
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    local post="$SCRATCH/.devcontainer/scripts/post.sh"
    local g c p
    g="$(grep -nx '# Godot Engine Setup' "$post" | cut -d: -f1)"
    c="$(grep -nx '# Codex CLI Setup' "$post" | cut -d: -f1)"
    p="$(grep -nx '# Claude Code Plugin Setup' "$post" | cut -d: -f1)"
    [[ -n "$g" && "$g" -lt "$c" && "$c" -lt "$p" ]]
    local first
    first="$(cat "$post")"
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    [[ "$(cat "$post")" == "$first" ]]
}

@test "post.sh block is appended when no Codex or plugin block exists" {
    printf '#!/bin/bash\necho start\n' > "$SCRATCH/.devcontainer/scripts/post.sh"
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run tail -n 1 "$SCRATCH/.devcontainer/scripts/post.sh"
    assert_output "fi"
    run grep -c '^# Godot Engine Setup$' "$SCRATCH/.devcontainer/scripts/post.sh"
    assert_output "1"
}

# Run the generated post.sh under `set -e` with a restricted PATH.
_run_post_block() {
    local bin="$SCRATCH/fakebin"
    mkdir -p "$bin"
    local tool
    for tool in bash dirname cat grep sed rm env tail; do
        ln -s "$(command -v "$tool")" "$bin/$tool"
    done
    local stub
    for stub in "$@"; do
        printf '%s\n' "$(cat "$SCRATCH/stub_$stub")" > "$bin/$stub"
        chmod +x "$bin/$stub"
    done
    printf '#!/bin/bash\n' > "$SCRATCH/.devcontainer/scripts/post.sh"
    _load_plugin
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    {
        echo 'set -e'
        cat "$SCRATCH/.devcontainer/scripts/post.sh"
        echo 'echo AFTER_GODOT_BLOCK'
    } > "$SCRATCH/block.sh"
    HOME="$SCRATCH/home" PATH="$bin" run bash "$SCRATCH/block.sh"
}

@test "post.sh block under set -e: failing godot warns nothing fatal" {
    printf '#!/bin/bash\nexit 1\n' > "$SCRATCH/stub_godot"
    _run_post_block godot
    assert_success
    assert_output --partial "not runnable yet"
    assert_output --partial "AFTER_GODOT_BLOCK"
}

@test "post.sh block under set -e: missing godot prints a WARN hint" {
    _run_post_block
    assert_success
    assert_output --partial "[WARN] godot not found"
    assert_output --partial "AFTER_GODOT_BLOCK"
}

@test "post.sh block under set -e: a working godot without dotnet reports a version" {
    printf '#!/bin/bash\necho 4.7.2.stable.mono.official.abc123\n' > "$SCRATCH/stub_godot"
    _run_post_block godot
    assert_success
    assert_output --partial "godot: 4.7.2.stable.mono.official.abc123"
    refute_output --partial "dotnet:"
    assert_output --partial "Export templates not installed"
    assert_output --partial "AFTER_GODOT_BLOCK"
}

# --- GUI choice resolution -----------------------------------------------------

@test "non-TTY with GODOT_GUI=true enables the overlay through plugin_post_copy alone" {
    GODOT_GUI=true _run_copy_and_post_copy
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
}

@test "non-TTY with GODOT_GUI=true and SKIP_CONFIRM enables the overlay too" {
    SKIP_CONFIRM=true GODOT_GUI=true _run_copy_and_post_copy
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
}

@test "non-TTY with GODOT_GUI unset leaves dockerComposeFile unchanged and never prompts" {
    _run_copy_and_post_copy
    run _compose_files
    assert_output '["../docker-compose.yml"]'
    [[ -f "$SCRATCH/docker-compose.godot-gui.yml" ]]
}

@test "TTY with -y and GODOT_GUI unset: no prompt, not enabled" {
    check_tty_available() { return 0; }
    SKIP_CONFIRM=true
    _load_plugin
    plugin_interactive_setup
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output '["../docker-compose.yml"]'
}

@test "TTY without -y: prompt answered y enables the overlay" {
    check_tty_available() { return 0; }
    confirm() { echo "ASKED" >> "$SCRATCH/prompts"; return 0; }
    _load_plugin
    plugin_interactive_setup
    plugin_copy "$SCRATCH" > /dev/null 2>&1
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
    run wc -l < "$SCRATCH/prompts"
    assert_output "1"
}

@test "TTY without -y: prompt answered n leaves the overlay off" {
    check_tty_available() { return 0; }
    confirm() { return 1; }
    _load_plugin
    plugin_interactive_setup
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output '["../docker-compose.yml"]'
}

@test "prompt default is y only when the setup host looks like WSLg" {
    check_tty_available() { return 0; }
    confirm() { echo "$2" > "$SCRATCH/default"; return 1; }
    _load_plugin
    _godot_wslg_detected() { return 0; }
    plugin_interactive_setup
    run cat "$SCRATCH/default"
    assert_output "y"
    GODOT_GUI_ENABLED=""
    _godot_wslg_detected() { return 1; }
    plugin_interactive_setup
    run cat "$SCRATCH/default"
    assert_output "n"
}

@test "GODOT_GUI=false with a TTY: no prompt, no entry" {
    check_tty_available() { return 0; }
    GODOT_GUI=false
    _load_plugin
    plugin_interactive_setup
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output '["../docker-compose.yml"]'
}

@test "overlay already listed with a TTY: no prompt, result stays enabled without a duplicate" {
    check_tty_available() { return 0; }
    echo "{\"dockerComposeFile\": [\"../docker-compose.yml\", \"${OVERLAY_REF}\"]}" \
        > "$SCRATCH/.devcontainer/devcontainer.json"
    export TARGET_DIR="$SCRATCH"
    _load_plugin
    plugin_interactive_setup
    [[ "$GODOT_GUI_ENABLED" == true ]]
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
}

@test "staging runs (UPGRADE_MODE) never prompt, even with a TTY" {
    check_tty_available() { return 0; }
    UPGRADE_MODE=true
    _load_plugin
    plugin_interactive_setup
    [[ "$GODOT_GUI_ENABLED" == false ]]
    plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output '["../docker-compose.yml"]'
}

@test "re-sourcing the plugin resets the GUI choice" {
    _load_plugin
    GODOT_GUI_ENABLED=true
    _load_plugin
    [[ -z "$GODOT_GUI_ENABLED" ]]
}

# --- GUI activation -------------------------------------------------------------

@test "enabling twice adds no duplicate" {
    GODOT_GUI=true _run_copy_and_post_copy
    GODOT_GUI=true plugin_post_copy_shared "$SCRATCH" > /dev/null 2>&1
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
}

@test "a string-valued dockerComposeFile is normalized to an array" {
    echo '{"dockerComposeFile": "../docker-compose.yml"}' > "$SCRATCH/.devcontainer/devcontainer.json"
    GODOT_GUI=true _run_copy_and_post_copy
    run _compose_files
    assert_output "[\"../docker-compose.yml\",\"${OVERLAY_REF}\"]"
}

@test "a missing overlay file warns and adds no entry" {
    _load_plugin
    GODOT_GUI=true run plugin_post_copy_shared "$SCRATCH"
    assert_success
    assert_output --partial "docker-compose.godot-gui.yml is missing"
    run _compose_files
    assert_output '["../docker-compose.yml"]'
}

@test "a devcontainer.json with comments warns and stays byte-identical on activation" {
    _load_plugin
    cp "${SCRIPT_DIR}/templates/languages/godot/docker-compose.godot-gui.yml" \
        "$SCRATCH/docker-compose.godot-gui.yml"
    printf '{\n  // keep me\n  "dockerComposeFile": ["../docker-compose.yml"]\n}\n' \
        > "$SCRATCH/.devcontainer/devcontainer.json"
    cp "$SCRATCH/.devcontainer/devcontainer.json" "$SCRATCH/dc.before"
    run _godot_enable_gui_overlay "$SCRATCH"
    assert_success
    assert_output --partial "[WARN]"
    run cmp "$SCRATCH/.devcontainer/devcontainer.json" "$SCRATCH/dc.before"
    assert_success
    run find "$SCRATCH/.devcontainer" -name 'devcontainer.json.*'
    assert_output ""
}

@test "placeholders: the overlay service key equals the project name" {
    _run_copy_and_post_copy
    replace_placeholders "$SCRATCH" "my-game" > /dev/null 2>&1
    run grep -c '{{' "$SCRATCH/docker-compose.godot-gui.yml"
    assert_output "0"
    run grep -x '  my-game:' "$SCRATCH/docker-compose.godot-gui.yml"
    assert_success
}

# --- monorepo / add-module / inference -----------------------------------------

@test "--add-module with godot creates module files and leaves root assets unchanged" {
    cd "$SCRATCH"
    mkdir proj && cd proj
    git init -q .
    run bash "$SETUP_SH" --monorepo --module game:godot -y proj
    assert_success
    [[ -f game/gdlintrc ]]
    [[ ! -e gdlintrc ]]
    local f
    for f in mise.toml .gitignore .devcontainer/devcontainer.json .devcontainer/scripts/post.sh \
        docker/Dockerfile.dev docker-compose.godot-gui.yml; do
        cp "$f" "$SCRATCH/before.$(echo "$f" | tr / _)"
    done
    run bash "$SETUP_SH" --add-module level2 --lang godot -y
    assert_success
    [[ -f level2/gdlintrc ]]
    [[ -f level2/.editorconfig ]]
    for f in mise.toml .gitignore .devcontainer/devcontainer.json .devcontainer/scripts/post.sh \
        docker/Dockerfile.dev docker-compose.godot-gui.yml; do
        run cmp "$f" "$SCRATCH/before.$(echo "$f" | tr / _)"
        assert_success
    done
}

@test "infer_scaffold_options reports godot for a tree with gdlintrc" {
    mkdir -p "$SCRATCH/probe"
    touch "$SCRATCH/probe/gdlintrc"
    run bash -c 'source "$1/setup.sh"; infer_scaffold_options "$2" false | jq -c .languages' \
        _ "$SCRIPT_DIR" "$SCRATCH/probe"
    assert_success
    assert_output '["godot"]'
}

@test "infer_scaffold_options reports godot for a tree with only the workflow" {
    mkdir -p "$SCRATCH/probe/.github/workflows"
    touch "$SCRATCH/probe/.github/workflows/godot-quality-check.yml"
    run bash -c 'source "$1/setup.sh"; infer_scaffold_options "$2" false | jq -c .languages' \
        _ "$SCRIPT_DIR" "$SCRATCH/probe"
    assert_success
    assert_output '["godot"]'
}
