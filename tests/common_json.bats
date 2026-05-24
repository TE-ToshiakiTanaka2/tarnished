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
