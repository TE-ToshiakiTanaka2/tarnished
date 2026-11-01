#!/usr/bin/env bats

# Tests for the post.sh install helpers introduced by #325:
#   npm_global_cli.sh::install_npm_global_cli, setup_claude.sh, setup_codex.sh,
#   setup_mise.sh. Each helper runs in a clean environment under `set -e` with
#   mocked claude/codex/npm/mise/sudo executables on a private PATH.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CORE_SCRIPTS="${SCRIPT_DIR}/templates/core/.devcontainer/scripts"
CODEX_SCRIPTS="${SCRIPT_DIR}/templates/codex/.devcontainer/scripts"

setup() {
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    BIN="$SCRATCH/bin"
    mkdir -p "$BIN" "$SCRATCH/home" "$SCRATCH/prefix"

    # Coreutils the helpers need; real node/npm/mise/claude must not leak in.
    local tool
    for tool in bash dirname mkdir cat head cut grep sed tr rm env touch; do
        ln -s "$(command -v "$tool")" "$BIN/$tool"
    done

    # sudo must never be called.
    cat > "$BIN/sudo" <<'EOF'
#!/bin/bash
echo "$*" >> "$SCRATCH/sudo.log"
exit 1
EOF
    chmod +x "$BIN/sudo"
}

teardown() {
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    case "${SCRATCH:-}" in
        /tmp/*) rm -rf "$SCRATCH" ;;
    esac
}

# A CLI mock that works iff $SCRATCH/<name>.ok exists.
_mock_cli() {
    local name="$1"
    cat > "$BIN/$name" <<EOF
#!/bin/bash
[[ -f "\$SCRATCH/${name}.ok" ]] || exit 127
echo "${name} 1.2.3"
EOF
    chmod +x "$BIN/$name"
}

# npm mock: records calls; installs <name> when NPM_INSTALL_OK=1.
_mock_npm() {
    cat > "$BIN/npm" <<'EOF'
#!/bin/bash
echo "$*" >> "$SCRATCH/npm.log"
case "$1" in
    prefix) echo "${NPM_PREFIX:-$SCRATCH/prefix}" ;;
    install)
        [[ "${NPM_INSTALL_OK:-1}" == 1 ]] || exit 1
        # last arg is the package spec; map it to a command
        case "${*: -1}" in
            *claude-code*) touch "$SCRATCH/claude.ok" ;;
            *codex*) touch "$SCRATCH/codex.ok" ;;
        esac
        ;;
esac
EOF
    chmod +x "$BIN/npm"
}

_mock_mise() {
    cat > "$BIN/mise" <<'EOF'
#!/bin/bash
echo "$PWD :: $*" >> "$SCRATCH/mise.log"
[[ "${MISE_FAIL:-0}" == 1 && "$1" == install ]] && exit 1
exit 0
EOF
    chmod +x "$BIN/mise"
}

# _run_helper <file-to-source> <command...>
_run_helper() {
    local file="$1"
    shift
    run env -i HOME="$SCRATCH/home" PATH="$BIN" SCRATCH="$SCRATCH" \
        NPM_INSTALL_OK="${NPM_INSTALL_OK:-1}" NPM_PREFIX="${NPM_PREFIX:-}" \
        MISE_FAIL="${MISE_FAIL:-0}" \
        CLAUDE_CODE_NPM_PACKAGE="${CLAUDE_CODE_NPM_PACKAGE:-}" \
        CODEX_NPM_PACKAGE="${CODEX_NPM_PACKAGE:-}" \
        bash -c 'set -e; source "$1"; shift; "$@"; echo "survived-set-e"' _ "$file" "$@"
}

_assert_no_sudo() {
    [[ ! -e "$SCRATCH/sudo.log" ]]
}

# --- install_npm_global_cli ---------------------------------------------------

@test "install_npm_global_cli skips npm when the command already runs" {
    _mock_cli claude; touch "$SCRATCH/claude.ok"
    _mock_npm
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "already installed: claude 1.2.3"
    assert_output --partial "survived-set-e"
    [[ ! -e "$SCRATCH/npm.log" ]]
}

@test "install_npm_global_cli reinstalls when a stale shim exists but does not run" {
    _mock_cli claude
    _mock_npm
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "installed successfully"
    run grep -c 'install -g @anthropic-ai/claude-code' "$SCRATCH/npm.log"
    assert_output "1"
    _assert_no_sudo
}

@test "install_npm_global_cli warns and returns 0 when npm is missing" {
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "[WARN] npm not found"
    assert_output --partial "npm install -g @anthropic-ai/claude-code"
    assert_output --partial "survived-set-e"
}

@test "install_npm_global_cli refuses a non-writable prefix without calling sudo" {
    [[ "$(id -u)" != "0" ]] || skip "root ignores directory permissions"
    _mock_npm
    chmod 555 "$SCRATCH/prefix"
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "is not writable; sudo is never used"
    run grep -c '^install' "$SCRATCH/npm.log"
    assert_output "0"
    _assert_no_sudo
}

@test "install_npm_global_cli warns with a manual command when npm install fails" {
    _mock_npm
    NPM_INSTALL_OK=0 _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "[WARN] Failed to install Claude Code"
    assert_output --partial "npm install -g @anthropic-ai/claude-code"
    assert_output --partial "survived-set-e"
    _assert_no_sudo
}

@test "install_npm_global_cli runs mise reshim when the fresh install is not yet on PATH" {
    _mock_npm
    _mock_mise
    # npm install succeeds but the CLI only becomes runnable after a reshim.
    cat > "$BIN/mise" <<'EOF'
#!/bin/bash
echo "$*" >> "$SCRATCH/mise.log"
[[ "$1" == reshim ]] && touch "$SCRATCH/claude.ok"
exit 0
EOF
    cat > "$BIN/claude" <<'EOF'
#!/bin/bash
[[ -f "$SCRATCH/claude.ok" ]] || exit 127
echo "claude 1.2.3"
EOF
    chmod +x "$BIN/claude"
    cat > "$BIN/npm" <<'EOF'
#!/bin/bash
case "$1" in prefix) echo "$SCRATCH/prefix" ;; esac
exit 0
EOF
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "installed successfully"
    run grep -c '^reshim' "$SCRATCH/mise.log"
    assert_output "1"
}

@test "install_npm_global_cli warns when the CLI stays off PATH after install" {
    cat > "$BIN/npm" <<'EOF'
#!/bin/bash
case "$1" in prefix) echo "$SCRATCH/prefix" ;; esac
exit 0
EOF
    chmod +x "$BIN/npm"
    _run_helper "$CORE_SCRIPTS/npm_global_cli.sh" install_npm_global_cli "Claude Code" "@anthropic-ai/claude-code" claude
    assert_success
    assert_output --partial "[WARN] Claude Code was installed but 'claude' is not on PATH"
}

# --- setup_claude / setup_codex -----------------------------------------------

@test "setup_claude installs through npm and creates ~/.claude" {
    _mock_cli claude
    _mock_npm
    _run_helper "$CORE_SCRIPTS/setup_claude.sh" setup_claude
    assert_success
    assert_output --partial "survived-set-e"
    run grep -c 'install -g @anthropic-ai/claude-code' "$SCRATCH/npm.log"
    assert_output "1"
    [[ -d "$SCRATCH/home/.claude" ]]
}

@test "setup_claude passes CLAUDE_CODE_NPM_PACKAGE through" {
    _mock_cli claude
    _mock_npm
    CLAUDE_CODE_NPM_PACKAGE="@anthropic-ai/claude-code@9.9.9" _run_helper "$CORE_SCRIPTS/setup_claude.sh" setup_claude
    assert_success
    run grep -c 'install -g @anthropic-ai/claude-code@9.9.9' "$SCRATCH/npm.log"
    assert_output "1"
}

@test "setup_claude warns and returns 0 when npm_global_cli.sh is missing" {
    mkdir "$SCRATCH/lonely"
    cp "$CORE_SCRIPTS/setup_claude.sh" "$SCRATCH/lonely/"
    _run_helper "$SCRATCH/lonely/setup_claude.sh" setup_claude
    assert_success
    assert_output --partial "[WARN] npm_global_cli.sh not found"
    assert_output --partial "./setup.sh --upgrade"
    assert_output --partial "survived-set-e"
}

@test "setup_codex installs through npm and keeps the sign-in hint" {
    mkdir "$SCRATCH/scripts"
    cp "$CORE_SCRIPTS/npm_global_cli.sh" "$CODEX_SCRIPTS/setup_codex.sh" "$SCRATCH/scripts/"
    _mock_cli codex
    _mock_npm
    _run_helper "$SCRATCH/scripts/setup_codex.sh" setup_codex
    assert_success
    assert_output --partial "survived-set-e"
    assert_output --partial "codex (and follow the sign-in prompt)"
    run grep -c 'install -g @openai/codex' "$SCRATCH/npm.log"
    assert_output "1"
    _assert_no_sudo
}

@test "setup_codex passes CODEX_NPM_PACKAGE through" {
    mkdir "$SCRATCH/scripts"
    cp "$CORE_SCRIPTS/npm_global_cli.sh" "$CODEX_SCRIPTS/setup_codex.sh" "$SCRATCH/scripts/"
    _mock_cli codex
    _mock_npm
    CODEX_NPM_PACKAGE="@openai/codex@0.1.0" _run_helper "$SCRATCH/scripts/setup_codex.sh" setup_codex
    assert_success
    run grep -c 'install -g @openai/codex@0.1.0' "$SCRATCH/npm.log"
    assert_output "1"
}

@test "setup_codex warns and returns 0 when npm_global_cli.sh is missing" {
    mkdir "$SCRATCH/lonely"
    cp "$CODEX_SCRIPTS/setup_codex.sh" "$SCRATCH/lonely/"
    _run_helper "$SCRATCH/lonely/setup_codex.sh" setup_codex
    assert_success
    assert_output --partial "[WARN] npm_global_cli.sh not found"
    assert_output --partial "survived-set-e"
}

# --- setup_mise ----------------------------------------------------------------

_project_with_mise() {
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ/.devcontainer/scripts"
    cp "$CORE_SCRIPTS/setup_mise.sh" "$PROJ/.devcontainer/scripts/"
}

@test "setup_mise warns and returns 0 when mise is missing" {
    _project_with_mise
    echo '[tools]' > "$PROJ/mise.toml"
    _run_helper "$PROJ/.devcontainer/scripts/setup_mise.sh" setup_mise
    assert_success
    assert_output --partial "[WARN] mise not found"
    assert_output --partial "docs/maintenance.md"
    assert_output --partial "survived-set-e"
}

@test "setup_mise returns 0 without running mise when no config exists" {
    _project_with_mise
    _mock_mise
    _run_helper "$PROJ/.devcontainer/scripts/setup_mise.sh" setup_mise
    assert_success
    assert_output --partial "No mise.toml found"
    [[ ! -e "$SCRATCH/mise.log" ]]
}

@test "setup_mise runs mise install in the project root" {
    _project_with_mise
    echo '[tools]' > "$PROJ/mise.toml"
    _mock_mise
    # Resolve symlinks (macOS /tmp) the same way the helper does.
    local root
    root="$(cd "$PROJ" && pwd)"
    _run_helper "$PROJ/.devcontainer/scripts/setup_mise.sh" setup_mise
    assert_success
    run cat "$SCRATCH/mise.log"
    assert_output "${root} :: install"
}

@test "setup_mise accepts a legacy .tool-versions file" {
    _project_with_mise
    echo 'nodejs 22.0.0' > "$PROJ/.tool-versions"
    _mock_mise
    _run_helper "$PROJ/.devcontainer/scripts/setup_mise.sh" setup_mise
    assert_success
    run grep -c ':: install' "$SCRATCH/mise.log"
    assert_output "1"
}

@test "setup_mise warns with a retry command when mise install fails" {
    _project_with_mise
    echo '[tools]' > "$PROJ/mise.toml"
    _mock_mise
    MISE_FAIL=1 _run_helper "$PROJ/.devcontainer/scripts/setup_mise.sh" setup_mise
    assert_success
    assert_output --partial "[WARN] mise install failed"
    assert_output --partial "&& mise install"
    assert_output --partial "survived-set-e"
}
