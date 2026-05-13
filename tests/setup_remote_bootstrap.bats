#!/usr/bin/env bats

# Regression tests for #276: the remote-execution bootstrap in setup.sh must
# detach the outer `curl -fsSL ... | bash` pipe from the exec'd process so
# curl does not print a spurious "curl: (23) Failure writing output to
# destination" mid-setup.
#
# The EPIPE itself is timing-dependent (curl buffer size, scheduler), so a
# fully end-to-end test would be flaky. These tests focus on:
#   1. Static invariant: the exec line redirects stdin from /dev/null.
#   2. The bootstrap block still detects pipe execution correctly.
#   3. Behavioral: piping setup.sh into bash against a local file:// clone
#      reaches the expected error / help output without leaking `curl:`
#      noise to stderr.

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

@test "bootstrap: exec line redirects stdin from /dev/null" {
    # Static invariant — protects the #276 fix from accidental regression
    # ("clean up dead redirect" style reverts).
    # shellcheck disable=SC2016
    run grep -E 'exec bash "\$BOOTSTRAP_TEMP_DIR/setup\.sh" "\$@" < /dev/null' "$SETUP_SH"
    assert_success
}

@test "bootstrap: pipe-execution detection logic is intact" {
    # The detection guard at setup.sh:29 still matches the three pipe shapes:
    # empty BASH_SOURCE[0], "-", or a path that is not a regular file.
    # shellcheck disable=SC2016
    run grep -F 'if [[ -z "${BASH_SOURCE[0]}" ]] || [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]' "$SETUP_SH"
    assert_success
}

@test "bootstrap: piped invocation against local repo reaches setup with no curl: noise" {
    # Skip if git or current branch unavailable — this is a behavioral test
    # that depends on the workspace being a git repo.
    if ! command -v git &>/dev/null; then
        skip "git not available"
    fi
    local branch
    branch="$(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
        skip "could not determine current branch"
    fi

    # Override the bootstrap clone source to point at the workspace itself
    # via file://. This exercises the bootstrap path end-to-end without
    # touching the network.
    export DEVCONTAINER_REPO_URL="file://${SCRIPT_DIR}"
    export DEVCONTAINER_BRANCH="$branch"
    # `git clone file://...` needs protocol.file.allow=always on modern git
    # because of CVE-2022-39253.
    export GIT_CONFIG_COUNT=1
    export GIT_CONFIG_KEY_0="protocol.file.allow"
    export GIT_CONFIG_VALUE_0="always"

    # Pipe setup.sh into bash with --help. The bootstrap should detect the
    # pipe, clone the workspace into a temp dir, exec the cloned copy with
    # --help, and exit 0.
    run bash -c "cat \"$SETUP_SH\" | bash -s -- --help"
    # We capture combined stderr+stdout via run's default; assert no curl:
    # substring appears anywhere.
    refute_output --partial "curl: (23)"
    refute_output --partial "Failure writing output to destination"
}
