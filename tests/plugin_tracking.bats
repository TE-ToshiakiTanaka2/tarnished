#!/usr/bin/env bats

# Tests for #265: every plugin's plugin_copy emits files that participate in
# MANIFEST_TRACKED (i.e., they all flow through copy_with_confirm). This is the
# regression net for the "audit direct cp calls" Phase 1 task — adding a new
# direct `cp` to any plugin will break this test.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # Each test runs in a fresh subprocess (bats default), so global state
    # from a previous plugin does not leak.
    source "${SCRIPT_DIR}/scripts/lib/common.sh"

    # Globals that some plugins read from setup.sh's parse_arguments. Provide
    # plausible defaults so plugin_copy doesn't error out before recording.
    export PROJECT_NAME="testproj"
    export MONOREPO_MODE=false
    export IS_ADD_MODULE_MODE=false
    declare -ga MODULES=()
    export OVERWRITE_ALL=true   # avoid interactive prompts in plugin_copy
    export skip_confirm=true

    STAGING="$(mktemp -d)"
    export STAGING
}

teardown() {
    if [[ -n "${STAGING:-}" ]] && [[ -d "$STAGING" ]]; then
        # Defensive: only delete inside /tmp.
        case "$STAGING" in
            /tmp/*) rm -rf "$STAGING" ;;
        esac
    fi
}

# Helper: source a plugin, run plugin_copy with manifest recording on, and
# assert every emitted file (modulo MANIFEST_EXCLUDE_GLOBS) appears in
# MANIFEST_TRACKED.
assert_plugin_tracks_emitted_files() {
    local plugin_path="$1"

    [[ -f "$plugin_path" ]] || fail "plugin not found: $plugin_path"

    # Provide the .devcontainer / .github / docker layout that some plugins
    # expect to already exist in the target. The core plugin would normally
    # create these; for plugins that depend on them, we pre-seed.
    mkdir -p "$STAGING/.devcontainer/scripts"
    mkdir -p "$STAGING/.github/workflows"
    mkdir -p "$STAGING/.github/scripts"
    mkdir -p "$STAGING/docker"
    mkdir -p "$STAGING/.claude"

    # shellcheck disable=SC1090
    source "$plugin_path"

    manifest_recording_start "$STAGING"
    plugin_copy "$STAGING" >/dev/null 2>&1
    manifest_recording_stop

    local missing=()
    while IFS= read -r -d '' f; do
        local rel="${f#${STAGING}/}"
        # Skip directories we pre-seeded but plugins did not write into.
        # We inspect every actual file under STAGING.
        if ! _manifest_path_eligible "$rel"; then
            continue
        fi
        if [[ -z "${MANIFEST_TRACKED[$rel]:-}" ]]; then
            missing+=("$rel")
        fi
    done < <(find "$STAGING" -type f -print0)

    for rel in "${!MANIFEST_TRACKED[@]}"; do
        _manifest_path_eligible "$rel" || fail "Ineligible ownership: $rel"
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'plugin %s did not record %d file(s):\n' "$plugin_path" "${#missing[@]}"
        printf '  %s\n' "${missing[@]}"
        return 1
    fi
}

@test "plugin_copy tracks emitted files: claude" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/claude/plugin.sh"
}

@test "plugin_copy tracks emitted files: codex" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/codex/plugin.sh"
}

@test "plugin_copy tracks emitted files: core" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/core/plugin.sh"
}

@test "plugin_copy tracks emitted files: github-actions/auto-tag" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/github-actions/auto-tag/plugin.sh"
}

@test "plugin_copy tracks emitted files: github-actions/project-integration" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/github-actions/project-integration/plugin.sh"
}

@test "plugin_copy tracks emitted files: languages/deno" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/languages/deno/plugin.sh"
}

@test "plugin_copy tracks emitted files: languages/latex" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/languages/latex/plugin.sh"
}

@test "plugin_copy tracks emitted files: languages/node" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/languages/node/plugin.sh"
}

@test "plugin_copy tracks emitted files: languages/python" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/languages/python/plugin.sh"
}

@test "plugin_copy tracks emitted files: languages/rust" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/languages/rust/plugin.sh"
}

@test "plugin_copy tracks emitted files: services/celery" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/services/celery/plugin.sh"
}

@test "plugin_copy tracks emitted files: services/mysql" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/services/mysql/plugin.sh"
}

@test "plugin_copy tracks emitted files: services/postgresql" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/services/postgresql/plugin.sh"
}

@test "plugin_copy tracks emitted files: services/redis" {
    assert_plugin_tracks_emitted_files "${SCRIPT_DIR}/templates/services/redis/plugin.sh"
}
