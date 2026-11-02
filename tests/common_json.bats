#!/usr/bin/env bats

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

@test "merge_devcontainer_json accepts comments without corrupting string values" {
    local base_file="$SCRATCH/base.jsonc"
    local overlay_file="$SCRATCH/overlay.jsonc"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSONC'
{
  // User-authored devcontainer comment.
  "name": "testapp",
  "features": {
    "ghcr.io/devcontainers/features/git:1": {}
  },
  "customizations": {
    "vscode": {
      "settings": {
        "example.url": "https://example.com/path//keep",
        "example.literal": "not a // comment and not /* block */",
        "example.quote": "escaped \" // still string"
      },
      "extensions": [
        "rust-lang.rust-analyzer", // inline comment
        "tamasfe.even-better-toml"
      ]
    }
  }
}
JSONC

    cat > "$overlay_file" <<'JSONC'
{
  /* Plugin overlay comment. */
  "features": {
    "ghcr.io/devcontainers/features/rust:1": {
      "version": "latest",
      "profile": "default"
    }
  },
  "customizations": {
    "vscode": {
      "settings": {
        "files.exclude": {
          "**/target": true
        }
      },
      "extensions": [
        "rust-lang.rust-analyzer",
        "vadimcn.vscode-lldb"
      ]
    }
  }
}
JSONC

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq empty "$output_file"
    assert_success

    run jq -r '.customizations.vscode.settings["example.url"]' "$output_file"
    assert_success
    assert_output "https://example.com/path//keep"

    run jq -r '.customizations.vscode.settings["example.literal"]' "$output_file"
    assert_success
    assert_output "not a // comment and not /* block */"

    run jq -r '.features["ghcr.io/devcontainers/features/rust:1"].version' "$output_file"
    assert_success
    assert_output "latest"

    run jq -r '.customizations.vscode.settings["files.exclude"]["**/target"]' "$output_file"
    assert_success
    assert_output "true"

    run jq -r '.customizations.vscode.extensions | length' "$output_file"
    assert_success
    assert_output "3"
}

@test "merge_devcontainer_json remains idempotent with normalized output" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"

    cat > "$base_file" <<'JSON'
{
  "features": {
    "ghcr.io/devcontainers/features/git:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": ["rust-lang.rust-analyzer"],
      "settings": {}
    }
  }
}
JSON

    cat > "$overlay_file" <<'JSON'
{
  "features": {
    "ghcr.io/devcontainers/features/rust:1": {
      "version": "latest"
    }
  },
  "customizations": {
    "vscode": {
      "extensions": ["rust-lang.rust-analyzer", "vadimcn.vscode-lldb"],
      "settings": {}
    }
  }
}
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$first_output"
    assert_success

    run merge_devcontainer_json "$first_output" "$overlay_file" "$second_output"
    assert_success

    run jq -S . "$first_output"
    assert_success
    local first_sorted="$output"

    run jq -S . "$second_output"
    assert_success
    assert_output "$first_sorted"
}

@test "merge_devcontainer_json removes output on invalid JSON after comment stripping" {
    local base_file="$SCRATCH/base.jsonc"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSONC'
{
  "name": "testapp",
}
JSONC
    echo '{"features": {}}' > "$overlay_file"
    echo "stale" > "$output_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_failure
    [[ ! -e "$output_file" ]]
}

@test "merge_devcontainer_json removes output on unterminated block comment" {
    local base_file="$SCRATCH/base.jsonc"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSONC'
{
  "name": "testapp"
  /* unfinished
}
JSONC
    echo '{"features": {}}' > "$overlay_file"
    echo "stale" > "$output_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_failure
    [[ ! -e "$output_file" ]]
}

@test "merge_devcontainer_json treats block comments as whitespace" {
    local base_file="$SCRATCH/base.jsonc"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSONC'
{
  "value": 1/* this must not become 12 */2
}
JSONC
    echo '{"features": {}}' > "$overlay_file"
    echo "stale" > "$output_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_failure
    [[ ! -e "$output_file" ]]
}

# settings.json carries top-level keys beyond permissions and hooks -- `model`,
# and anything the user added. Rebuilding the object from only the two
# special-cased keys silently dropped them on every re-run and every
# `setup.sh --upgrade`. Regression guard for that loss.
@test "merge_claude_settings preserves unrelated top-level keys across repeated merges" {
    local base_file="$SCRATCH/settings.json"
    local overlay_file="$SCRATCH/plugin.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"

    cat > "$base_file" <<'JSON'
{
  "userOwnedKey": "keep me",
  "permissions": { "allow": [], "deny": [] },
  "hooks": { "PreToolUse": [], "SessionStart": [{ "hooks": [] }] }
}
JSON

    cat > "$overlay_file" <<'JSON'
{
  "model": "claude-fable-5",
  "permissions": { "allow": [], "deny": ["Bash(rm -rf /*)"] },
  "hooks": { "PreToolUse": [] }
}
JSON

    run merge_claude_settings "$base_file" "$overlay_file" "$first_output"
    assert_success

    run jq -r '.model' "$first_output"
    assert_output "claude-fable-5"

    run jq -r '.userOwnedKey' "$first_output"
    assert_output "keep me"

    # Hook events the merge does not special-case survive too.
    run jq '.hooks.SessionStart | length' "$first_output"
    assert_output "1"

    # The re-merge path (`setup.sh --upgrade`) must not drop them either.
    run merge_claude_settings "$first_output" "$overlay_file" "$second_output"
    assert_success

    run jq -r '.model' "$second_output"
    assert_output "claude-fable-5"

    run jq -r '.userOwnedKey' "$second_output"
    assert_output "keep me"

    run jq '.hooks.SessionStart | length' "$second_output"
    assert_output "1"
}

# A second merge of the same overlay (e.g. `setup.sh --upgrade`'s FR-5 re-run)
# must not duplicate hooks.PreToolUse entries. Regression guard for the
# deny-check Bash hook being appended twice.
@test "merge_claude_settings dedups hooks on repeated merge" {
    local base_file="$SCRATCH/settings.json"
    local overlay_file="$SCRATCH/plugin.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"

    cat > "$base_file" <<'JSON'
{ "permissions": { "allow": [], "deny": [] }, "hooks": { "PreToolUse": [], "PostToolUse": [] } }
JSON

    cat > "$overlay_file" <<'JSON'
{
  "permissions": { "allow": [], "deny": ["Bash(rm -rf /*)"] },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "deny-check.sh" }] }
    ]
  }
}
JSON

    run merge_claude_settings "$base_file" "$overlay_file" "$first_output"
    assert_success

    run jq '.hooks.PreToolUse | length' "$first_output"
    assert_success
    assert_output "1"

    # Re-merge the overlay onto the already-merged result.
    run merge_claude_settings "$first_output" "$overlay_file" "$second_output"
    assert_success

    run jq '.hooks.PreToolUse | length' "$second_output"
    assert_success
    assert_output "1"

    run jq '.permissions.deny | length' "$second_output"
    assert_success
    assert_output "1"
}

# NFR-1 (#323): with no customizations.zed anywhere, the merged output must
# not grow a "zed" key.
@test "merge_devcontainer_json omits customizations.zed when neither input declares it" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{
  "features": {},
  "customizations": {
    "vscode": { "extensions": ["rust-lang.rust-analyzer"], "settings": {} }
  }
}
JSON
    cat > "$overlay_file" <<'JSON'
{
  "features": {},
  "customizations": {
    "vscode": { "extensions": ["vadimcn.vscode-lldb"], "settings": {} }
  }
}
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq '.customizations | has("zed")' "$output_file"
    assert_success
    assert_output "false"

    run jq -Sc '.customizations.vscode.extensions' "$output_file"
    assert_success
    assert_output '["rust-lang.rust-analyzer","vadimcn.vscode-lldb"]'
}

@test "merge_devcontainer_json merges customizations.zed.extensions with unique semantics" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "customizations": { "zed": { "extensions": ["dockerfile"] } } }
JSON
    cat > "$overlay_file" <<'JSON'
{ "customizations": { "zed": { "extensions": ["toml", "dockerfile"] } } }
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -Sc '.customizations.zed.extensions' "$output_file"
    assert_success
    assert_output '["dockerfile","toml"]'
}

@test "merge_devcontainer_json preserves base customizations.zed when the overlay has none" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "customizations": { "zed": { "extensions": ["dockerfile"] } } }
JSON
    cat > "$overlay_file" <<'JSON'
{ "features": {} }
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -Sc '.customizations.zed.extensions' "$output_file"
    assert_success
    assert_output '["dockerfile"]'
}

@test "merge_devcontainer_json keeps customizations.vscode when only zed is in the overlay" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    cat > "$base_file" <<'JSON'
{ "customizations": { "vscode": { "extensions": ["rust-lang.rust-analyzer"], "settings": {} } } }
JSON
    cat > "$overlay_file" <<'JSON'
{ "customizations": { "zed": { "extensions": ["toml"] } } }
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -Sc '.customizations.vscode.extensions' "$output_file"
    assert_success
    assert_output '["rust-lang.rust-analyzer"]'

    run jq -Sc '.customizations.zed.extensions' "$output_file"
    assert_success
    assert_output '["toml"]'
}

@test "merge_devcontainer_json remains idempotent with customizations.zed" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local first_output="$SCRATCH/first.json"
    local second_output="$SCRATCH/second.json"

    cat > "$base_file" <<'JSON'
{
  "customizations": {
    "vscode": { "extensions": ["rust-lang.rust-analyzer"], "settings": {} },
    "zed": { "extensions": ["dockerfile"] }
  }
}
JSON
    cat > "$overlay_file" <<'JSON'
{
  "customizations": {
    "vscode": { "extensions": ["vadimcn.vscode-lldb"], "settings": {} },
    "zed": { "extensions": ["toml"] }
  }
}
JSON

    run merge_devcontainer_json "$base_file" "$overlay_file" "$first_output"
    assert_success

    run merge_devcontainer_json "$first_output" "$overlay_file" "$second_output"
    assert_success

    run jq -S . "$first_output"
    assert_success
    local first_sorted="$output"

    run jq -S . "$second_output"
    assert_success
    assert_output "$first_sorted"
}

# --- #325: features are no longer special-cased ------------------------------

@test "merge_devcontainer_json emits no features key when neither input has one" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    echo '{"name": "app", "customizations": {"vscode": {"extensions": ["a.b"]}}}' > "$base_file"
    echo '{"customizations": {"vscode": {"extensions": ["c.d"]}}}' > "$overlay_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -r 'has("features")' "$output_file"
    assert_output "false"
    run jq -r '.customizations.vscode.extensions | length' "$output_file"
    assert_output "2"
}

@test "merge_devcontainer_json preserves a base-only features object" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    echo '{"features": {"ghcr.io/example/own:1": {"a": 1}}}' > "$base_file"
    echo '{"customizations": {"vscode": {"extensions": []}}}' > "$overlay_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -c '.features' "$output_file"
    assert_output '{"ghcr.io/example/own:1":{"a":1}}'
}

@test "merge_devcontainer_json deep-merges features declared on both sides" {
    local base_file="$SCRATCH/base.json"
    local overlay_file="$SCRATCH/overlay.json"
    local output_file="$SCRATCH/output.json"

    echo '{"features": {"x": {"a": 1}}}' > "$base_file"
    echo '{"features": {"x": {"b": 2}, "y": {}}}' > "$overlay_file"

    run merge_devcontainer_json "$base_file" "$overlay_file" "$output_file"
    assert_success

    run jq -c '.features' "$output_file"
    assert_output '{"x":{"a":1,"b":2},"y":{}}'
}

# --- #325: plugin keys survive the settings merges ---------------------------

_plugin_keys_json() {
    cat <<'JSON'
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": {
      "source": { "source": "github", "repo": "anthropics/claude-plugins-official" }
    }
  },
  "enabledPlugins": { "context7@claude-plugins-official": true }
}
JSON
}

@test "merge_claude_settings keeps plugin keys present only in the base" {
    _plugin_keys_json > "$SCRATCH/base.json"
    echo '{"permissions": {"allow": ["Bash(ls)"]}}' > "$SCRATCH/overlay.json"

    run merge_claude_settings "$SCRATCH/base.json" "$SCRATCH/overlay.json" "$SCRATCH/out.json"
    assert_success
    run jq -r '.enabledPlugins["context7@claude-plugins-official"]' "$SCRATCH/out.json"
    assert_output "true"
    run jq -r '.extraKnownMarketplaces["claude-plugins-official"].source.repo' "$SCRATCH/out.json"
    assert_output "anthropics/claude-plugins-official"
}

@test "merge_claude_settings keeps plugin keys present only in the overlay" {
    echo '{"permissions": {"allow": ["Bash(ls)"]}}' > "$SCRATCH/base.json"
    _plugin_keys_json > "$SCRATCH/overlay.json"

    run merge_claude_settings "$SCRATCH/base.json" "$SCRATCH/overlay.json" "$SCRATCH/out.json"
    assert_success
    run jq -r '.enabledPlugins["context7@claude-plugins-official"]' "$SCRATCH/out.json"
    assert_output "true"
}

@test "merge_claude_settings unions plugin keys present on both sides" {
    _plugin_keys_json > "$SCRATCH/base.json"
    echo '{"enabledPlugins": {"other@claude-plugins-official": true}}' > "$SCRATCH/overlay.json"

    run merge_claude_settings "$SCRATCH/base.json" "$SCRATCH/overlay.json" "$SCRATCH/out.json"
    assert_success
    run jq -c '.enabledPlugins' "$SCRATCH/out.json"
    assert_output '{"context7@claude-plugins-official":true,"other@claude-plugins-official":true}'
}

# merge_claude_settings_hooks only folds the overlay's hooks into the base, so
# the base's plugin keys must survive untouched.
@test "merge_claude_settings_hooks keeps the base plugin keys while merging hooks" {
    _plugin_keys_json > "$SCRATCH/base.json"
    echo '{"hooks": {"PostToolUse": [{"matcher": "Edit"}]}}' > "$SCRATCH/overlay.json"

    run merge_claude_settings_hooks "$SCRATCH/base.json" "$SCRATCH/overlay.json" "$SCRATCH/out.json"
    assert_success
    run jq -c '.enabledPlugins' "$SCRATCH/out.json"
    assert_output '{"context7@claude-plugins-official":true}'
    run jq -r '.extraKnownMarketplaces | has("claude-plugins-official")' "$SCRATCH/out.json"
    assert_output "true"
    run jq -r '.hooks.PostToolUse | length' "$SCRATCH/out.json"
    assert_output "1"
}
