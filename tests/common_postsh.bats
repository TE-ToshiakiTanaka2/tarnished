#!/usr/bin/env bats

# Unit tests for common.sh::post_sh_add_block (#325): marker-guarded,
# position-aware post.sh blocks.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/scripts/lib/common.sh"
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    POST="$SCRATCH/post.sh"
    printf '#!/bin/bash\nset -e\necho start\n' > "$POST"
    chmod +x "$POST"
}

teardown() {
    case "${SCRATCH:-}" in
        /tmp/*) rm -rf "$SCRATCH" ;;
    esac
}

_add() {
    local marker="$1"
    shift
    post_sh_add_block "$POST" "$marker" "$@" <<EOF
echo "body of ${marker}"
EOF
}

_line_of() {
    grep -nxF -- "$1" "$POST" | head -n 1 | cut -d: -f1
}

@test "post_sh_add_block appends when there is no before-marker" {
    run _add "# mise Runtime Setup"
    assert_success
    run tail -n 6 "$POST"
    assert_output $'echo start\n\n# -----------------------------------------------------------------------------\n# mise Runtime Setup\n# -----------------------------------------------------------------------------\necho "body of # mise Runtime Setup"'
}

@test "post_sh_add_block is a no-op when the marker is already present" {
    _add "# Codex CLI Setup"
    cp "$POST" "$SCRATCH/before"
    run _add "# Codex CLI Setup"
    assert_success
    run cmp "$POST" "$SCRATCH/before"
    assert_success
}

@test "post_sh_add_block returns 0 silently for a missing post.sh" {
    rm -f "$POST"
    run _add "# Codex CLI Setup"
    assert_success
    assert_output ""
    [[ ! -e "$POST" ]]
}

@test "post_sh_add_block inserts before the before-marker, keeping rule and blank intact" {
    _add "# Claude Code Plugin Setup"
    run _add "# Codex CLI Setup" "# Claude Code Plugin Setup"
    assert_success
    local codex plugins
    codex="$(_line_of '# Codex CLI Setup')"
    plugins="$(_line_of '# Claude Code Plugin Setup')"
    [[ "$codex" -lt "$plugins" ]]
    run sed -n "$((plugins - 2)),$((plugins))p" "$POST"
    assert_output $'\n# -----------------------------------------------------------------------------\n# Claude Code Plugin Setup'
    run sed -n "$((plugins - 3))p" "$POST"
    assert_output 'echo "body of # Codex CLI Setup"'
}

@test "post_sh_add_block uses the earliest of several before-markers" {
    _add "# Claude Code Plugin Setup"
    _add "# Codex CLI Setup" "# Claude Code Plugin Setup"
    run _add "# Claude Code Setup" "# Codex CLI Setup" "# Claude Code Plugin Setup"
    assert_success
    local c codex plugins
    c="$(_line_of '# Claude Code Setup')"
    codex="$(_line_of '# Codex CLI Setup')"
    plugins="$(_line_of '# Claude Code Plugin Setup')"
    [[ "$c" -lt "$codex" ]]
    [[ "$codex" -lt "$plugins" ]]
}

@test "post_sh_add_block yields mise < claude < codex < plugins in the core->claude->codex order" {
    _add "# mise Runtime Setup" "# Claude Code Setup" "# Codex CLI Setup" "# Claude Code Plugin Setup"
    _add "# Claude Code Setup" "# Codex CLI Setup" "# Claude Code Plugin Setup"
    _add "# Claude Code Plugin Setup"
    _add "# Codex CLI Setup" "# Claude Code Plugin Setup"
    local m c x p
    m="$(_line_of '# mise Runtime Setup')"
    c="$(_line_of '# Claude Code Setup')"
    x="$(_line_of '# Codex CLI Setup')"
    p="$(_line_of '# Claude Code Plugin Setup')"
    [[ "$m" -lt "$c" ]]
    [[ "$c" -lt "$x" ]]
    [[ "$x" -lt "$p" ]]
    run bash -n "$POST"
    assert_success
}

@test "post_sh_add_block keeps the executable bit" {
    _add "# mise Runtime Setup"
    [[ -x "$POST" ]]
}

@test "post_sh_add_block does not reorder when the developer already moved a block" {
    _add "# Claude Code Plugin Setup"
    _add "# Codex CLI Setup"
    cp "$POST" "$SCRATCH/before"
    run _add "# Codex CLI Setup" "# Claude Code Plugin Setup"
    assert_success
    run cmp "$POST" "$SCRATCH/before"
    assert_success
}

# setup.sh stages distributions in `bash -e -o pipefail`; a before-marker that
# is absent (grep exit 1) must not abort the helper there.
@test "post_sh_add_block survives errexit and pipefail with absent before-markers" {
    run bash -e -o pipefail -c '
        source "$1"
        printf "echo hi\n" > "$2"
        post_sh_add_block "$2" "# mise Runtime Setup" "# Claude Code Setup" "# Codex CLI Setup" <<< "echo body"
        grep -qxF "# mise Runtime Setup" "$2"
    ' _ "${SCRIPT_DIR}/scripts/lib/common.sh" "$POST"
    assert_success
}
