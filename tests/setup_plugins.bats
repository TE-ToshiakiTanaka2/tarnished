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
# setup_plugins — non-fatal under post.sh `set -e`
# -----------------------------------------------------------------------------

@test "setup_plugins: missing credentials -> skips with guidance, claude never invoked" {
    # Run setup_plugins under `set -e`, with `claude` mocked to record any
    # invocation and return 1 (so any actual call would also break the script).
    run bash -c "
        set -e
        export PATH='$SCRATCH/bin:$PATH'
        mkdir -p '$SCRATCH/bin'
        cat > '$SCRATCH/bin/claude' <<'EOF'
#!/usr/bin/env bash
echo 'claude was invoked with: \$@' >> '$SCRATCH/claude.log'
exit 1
EOF
        chmod +x '$SCRATCH/bin/claude'
        source '$WORKSPACE_SETUP'
        setup_plugins
        echo SURVIVED
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not yet authenticated"* ]]
    [[ "$output" == *"SURVIVED"* ]]
    [[ ! -e "$SCRATCH/claude.log" ]]
}

@test "setup_plugins: claude plugins list failure -> set -e survives, return 0" {
    # Authenticated path. Mock `claude` to succeed for marketplace ops but
    # fail for `plugins list`. Pre-#273 review fix, the unguarded
    # plugins_output=$(claude plugins list) assignment could exit the
    # function under `set -e`.
    mkdir -p "$HOME/.claude"
    echo '{"oauth": "stub"}' > "$HOME/.claude/.credentials.json"

    run bash -c "
        set -e
        export PATH='$SCRATCH/bin:$PATH'
        mkdir -p '$SCRATCH/bin'
        cat > '$SCRATCH/bin/claude' <<'EOF'
#!/usr/bin/env bash
case \"\$1 \$2\" in
    'plugins marketplace') exit 0 ;;
    'plugins list') exit 1 ;;
    *) exit 1 ;;
esac
EOF
        chmod +x '$SCRATCH/bin/claude'
        source '$WORKSPACE_SETUP'
        setup_plugins
        echo SURVIVED
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"failed to query installed plugins"* ]]
    [[ "$output" == *"SURVIVED"* ]]
}

@test "setup_plugins: marketplace registration failure -> set -e survives, return 0" {
    mkdir -p "$HOME/.claude"
    echo '{"oauth": "stub"}' > "$HOME/.claude/.credentials.json"

    run bash -c "
        set -e
        export PATH='$SCRATCH/bin:$PATH'
        mkdir -p '$SCRATCH/bin'
        cat > '$SCRATCH/bin/claude' <<'EOF'
#!/usr/bin/env bash
# 'plugins marketplace list' -> empty (no marketplaces registered)
# 'plugins marketplace add'  -> fail (simulated network or auth issue)
case \"\$1 \$2 \$3\" in
    'plugins marketplace list') exit 0 ;;
    'plugins marketplace add') exit 1 ;;
    *) exit 1 ;;
esac
EOF
        chmod +x '$SCRATCH/bin/claude'
        source '$WORKSPACE_SETUP'
        setup_plugins
        echo SURVIVED
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"marketplace registration failure"* ]]
    [[ "$output" == *"SURVIVED"* ]]
}

# -----------------------------------------------------------------------------
# Workspace ↔ template parity (#273 invariant)
# -----------------------------------------------------------------------------

@test "workspace and template setup_plugins.sh are byte-identical" {
    run diff "$WORKSPACE_SETUP" "$TEMPLATE_SETUP"
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}
