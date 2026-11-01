#!/usr/bin/env bats

# Regression tests for #273: setup_plugins.sh must satisfy the post.sh
# `set -e` non-fatal-return-0 contract on the dominant first-run failure
# modes — missing/empty credentials, and `claude plugins list` failure.
#
# These tests exercise the workspace copy of setup_plugins.sh. The workspace
# and template copies are byte-identical (kept in sync per #273), so a single
# fixture covers both — a separate file-equality check below makes that
# invariant explicit and fails fast if the copies diverge.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
WORKSPACE_SETUP="${SCRIPT_DIR}/.devcontainer/scripts/setup_plugins.sh"
TEMPLATE_SETUP="${SCRIPT_DIR}/templates/claude/.devcontainer/scripts/setup_plugins.sh"

# Helper: source $WORKSPACE_SETUP without spreading SC1090 directives over
# every test. shellcheck cannot statically follow a path stored in a variable.
# shellcheck disable=SC1090
source_workspace_setup() {
    source "$WORKSPACE_SETUP"
}

setup() {
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    # Re-route HOME so credential-file probes are isolated per test.
    export HOME="$SCRATCH"
}

teardown() {
    if [[ -n "${SCRATCH:-}" ]] && [[ -d "$SCRATCH" ]]; then
        case "$SCRATCH" in
            /tmp/*) rm -rf "$SCRATCH" ;;
        esac
    fi
}

# -----------------------------------------------------------------------------
# is_claude_authenticated — pure file-existence check
# -----------------------------------------------------------------------------

@test "is_claude_authenticated: missing credentials -> non-zero" {
    source_workspace_setup
    run is_claude_authenticated
    [[ "$status" -ne 0 ]]
}

@test "is_claude_authenticated: empty credentials -> non-zero" {
    mkdir -p "$HOME/.claude"
    : > "$HOME/.claude/.credentials.json"  # zero-byte
    source_workspace_setup
    run is_claude_authenticated
    [[ "$status" -ne 0 ]]
}

@test "is_claude_authenticated: non-empty credentials -> zero" {
    mkdir -p "$HOME/.claude"
    echo '{"oauth": "stub"}' > "$HOME/.claude/.credentials.json"
    source_workspace_setup
    run is_claude_authenticated
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# setup_plugins -- settings-driven (#325), non-fatal under post.sh `set -e`
# -----------------------------------------------------------------------------
# `claude` is mocked on a private PATH that also carries the few real tools the
# script needs (jq, grep, ...). The mock records every call in claude.log.

_prepare_sandbox() {
    BIN="$SCRATCH/bin"
    mkdir -p "$BIN"
    local tool
    for tool in bash jq grep dirname cat rm mkdir env; do
        ln -sf "$(command -v "$tool")" "$BIN/$tool"
    done
    SETTINGS="$SCRATCH/settings.json"
    export SETUP_PLUGINS_SETTINGS_FILE="$SETTINGS"
    echo '[]' > "$SCRATCH/installed.json"
}

_mock_claude() {
    cat > "$BIN/claude" <<'EOF'
#!/bin/bash
echo "$*" >> "$SCRATCH/claude.log"
case "$1 $2 $3" in
    "plugin list --json")
        [[ "${MOCK_LIST_FAIL:-0}" == 1 ]] && exit 1
        cat "$SCRATCH/installed.json"
        ;;
    "plugin marketplace list")
        cat "$SCRATCH/marketplaces.txt" 2>/dev/null
        exit 0
        ;;
    "plugin marketplace add")
        [[ "${MOCK_MARKETPLACE_FAIL:-0}" == 1 ]] && exit 1
        echo "$4" >> "$SCRATCH/marketplaces.txt"
        ;;
    "plugin install "*)
        [[ "$3" == "${MOCK_INSTALL_FAIL_ID:-}" ]] && exit 1
        ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$BIN/claude"
}

_login() {
    mkdir -p "$HOME/.claude"
    echo '{"oauth": "stub"}' > "$HOME/.claude/.credentials.json"
}

_write_settings() {
    cat > "$SETTINGS"
}

_run_setup_plugins() {
    run env -i HOME="$HOME" PATH="$BIN" SCRATCH="$SCRATCH" \
        SETUP_PLUGINS_SETTINGS_FILE="$SETUP_PLUGINS_SETTINGS_FILE" \
        MOCK_LIST_FAIL="${MOCK_LIST_FAIL:-0}" \
        MOCK_MARKETPLACE_FAIL="${MOCK_MARKETPLACE_FAIL:-0}" \
        MOCK_INSTALL_FAIL_ID="${MOCK_INSTALL_FAIL_ID:-}" \
        bash -c 'set -e; source "$1"; setup_plugins; echo SURVIVED' _ "$WORKSPACE_SETUP"
}

_installs() {
    grep '^plugin install' "$SCRATCH/claude.log" 2>/dev/null || true
}

_official_settings() {
    cat <<'JSON'
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": { "source": "github", "repo": "anthropics/claude-plugins-official" }
    }
  },
  "enabledPlugins": {
    "context7@claude-plugins-official": true,
    "off@claude-plugins-official": false
  }
}
JSON
}

@test "setup_plugins: missing claude -> warns, return 0, nothing invoked" {
    _prepare_sandbox
    _official_settings | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "Claude Code CLI is not installed"
    assert_output --partial "SURVIVED"
}

@test "setup_plugins: missing settings file -> warns, return 0" {
    _prepare_sandbox
    _mock_claude
    _run_setup_plugins
    assert_success
    assert_output --partial "not found; skipping plugin setup"
    assert_output --partial "SURVIVED"
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: invalid JSON -> warns, return 0" {
    _prepare_sandbox
    _mock_claude
    echo '{ not json' | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "not valid JSON"
    assert_output --partial "SURVIVED"
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: no enabledPlugins -> warns, return 0, claude never invoked" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"model": "x"}' | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "no enabledPlugins in .claude/settings.json"
    assert_output --partial "SURVIVED"
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: only false entries -> nothing to install" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"enabledPlugins": {"a@m": false}}' | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "no enabledPlugins"
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: missing credentials -> guidance, claude never invoked" {
    _prepare_sandbox
    _mock_claude
    _official_settings | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "not yet authenticated"
    assert_output --partial "SURVIVED"
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: installs enabled plugins that are not installed, project scope, no -y" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "SURVIVED"
    run _installs
    assert_output "plugin install context7@claude-plugins-official --scope project"
    run grep -E -- ' -y|--accept-command' "$SCRATCH/claude.log"
    assert_failure
}

@test "setup_plugins: skips plugins already reported by plugin list --json" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    echo '[{"id": "context7@claude-plugins-official"}]' > "$SCRATCH/installed.json"
    _run_setup_plugins
    assert_success
    assert_output --partial "context7@claude-plugins-official already installed"
    run _installs
    assert_output ""
}

@test "setup_plugins: does not treat a longer installed id as a match" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    echo '[{"id": "context7-extra@claude-plugins-official"}]' > "$SCRATCH/installed.json"
    _run_setup_plugins
    assert_success
    run _installs
    assert_output "plugin install context7@claude-plugins-official --scope project"
}

@test "setup_plugins: registers the declared marketplace once for several plugins" {
    _prepare_sandbox
    _mock_claude
    _login
    cat <<'JSON' | _write_settings
{
  "extraKnownMarketplaces": {
    "acme": { "source": { "source": "github", "repo": "acme/plugins" } }
  },
  "enabledPlugins": { "one@acme": true, "two@acme": true }
}
JSON
    _run_setup_plugins
    assert_success
    run grep -c '^plugin marketplace add' "$SCRATCH/claude.log"
    assert_output "1"
    run grep '^plugin marketplace add' "$SCRATCH/claude.log"
    assert_output "plugin marketplace add acme/plugins"
    run _installs
    assert_line "plugin install one@acme --scope project"
    assert_line "plugin install two@acme --scope project"
}

@test "setup_plugins: git marketplace sources register by url" {
    _prepare_sandbox
    _mock_claude
    _login
    cat <<'JSON' | _write_settings
{
  "extraKnownMarketplaces": { "corp": { "source": { "source": "git", "url": "https://git.example/p.git" } } },
  "enabledPlugins": { "tool@corp": true }
}
JSON
    _run_setup_plugins
    assert_success
    run grep '^plugin marketplace add' "$SCRATCH/claude.log"
    assert_output "plugin marketplace add https://git.example/p.git"
}

@test "setup_plugins: official marketplace defaults to the well-known repo when undeclared" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"enabledPlugins": {"context7@claude-plugins-official": true}}' | _write_settings
    _run_setup_plugins
    assert_success
    run grep '^plugin marketplace add' "$SCRATCH/claude.log"
    assert_output "plugin marketplace add anthropics/claude-plugins-official"
}

@test "setup_plugins: skips registration when the marketplace is already registered" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    echo "claude-plugins-official" > "$SCRATCH/marketplaces.txt"
    _run_setup_plugins
    assert_success
    run grep -c '^plugin marketplace add' "$SCRATCH/claude.log"
    assert_output "0"
}

@test "setup_plugins: unknown marketplace -> warns and skips its plugins" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"enabledPlugins": {"x@mystery": true}}' | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "no usable source"
    assert_output --partial "SURVIVED"
    run _installs
    assert_output ""
}

@test "setup_plugins: marketplace registration failure -> set -e survives, no install" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    MOCK_MARKETPLACE_FAIL=1 _run_setup_plugins
    assert_success
    assert_output --partial "Failed to register marketplace"
    assert_output --partial "SURVIVED"
    run _installs
    assert_output ""
}

@test "setup_plugins: plugin list --json failure -> still attempts the install" {
    _prepare_sandbox
    _mock_claude
    _login
    _official_settings | _write_settings
    MOCK_LIST_FAIL=1 _run_setup_plugins
    assert_success
    assert_output --partial "could not query installed plugins"
    assert_output --partial "SURVIVED"
    run _installs
    assert_output "plugin install context7@claude-plugins-official --scope project"
}

@test "setup_plugins: one failing install does not stop the next" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"enabledPlugins": {"bad@claude-plugins-official": true, "good@claude-plugins-official": true}}' | _write_settings
    MOCK_INSTALL_FAIL_ID="bad@claude-plugins-official" _run_setup_plugins
    assert_success
    assert_output --partial "Failed to install bad@claude-plugins-official"
    assert_output --partial "SURVIVED"
    run _installs
    assert_line "plugin install good@claude-plugins-official --scope project"
}

@test "setup_plugins: malformed plugin id is skipped" {
    _prepare_sandbox
    _mock_claude
    _login
    echo '{"enabledPlugins": {"no-marketplace": true, "$(touch pwned)@m": true, "ok@claude-plugins-official": true}}' | _write_settings
    _run_setup_plugins
    assert_success
    assert_output --partial "malformed plugin id"
    run _installs
    assert_output "plugin install ok@claude-plugins-official --scope project"
    [[ ! -e pwned ]]
}

@test "setup_plugins: serena and playwright are not installed by default" {
    run jq -r '.enabledPlugins | keys[]' "${SCRIPT_DIR}/templates/claude/.claude/settings.json"
    assert_success
    assert_output "context7@claude-plugins-official"
    run grep -c 'playwright\|serena' "$TEMPLATE_SETUP"
    assert_output "0"
}

# -----------------------------------------------------------------------------
# Workspace ↔ template parity (#273 invariant)
# -----------------------------------------------------------------------------

@test "workspace and template setup_plugins.sh are byte-identical" {
    run diff "$WORKSPACE_SETUP" "$TEMPLATE_SETUP"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}
