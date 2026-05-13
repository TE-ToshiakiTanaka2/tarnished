#!/usr/bin/env bats

# Regression tests for #276: the project-integration plugin's gh CLI
# helpers must:
#   - Always return 0 (no `set -e` abort inside `var=$(helper)`)
#   - Persist the first line of gh's stderr to GH_LAST_ERROR_FILE so the
#     parent shell can surface it after the helper's subshell returns
#   - Let `_print_gh_warning` append that captured line to a print_warning
#
# Tests use a PATH-prepended fake `gh` (controlled via env vars) so they
# do not touch the real GitHub API.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PLUGIN_SH="${SCRIPT_DIR}/templates/github-actions/project-integration/plugin.sh"
COMMON_SH="${SCRIPT_DIR}/scripts/lib/common.sh"

setup() {
    SCRATCH="$(mktemp -d)"
    export SCRATCH

    # Build a stub `gh` whose behavior is controlled by env vars set by
    # each test:
    #   GH_STUB_STDOUT    — string to print to stdout
    #   GH_STUB_STDERR    — string to print to stderr
    #   GH_STUB_EXIT      — exit code (default 0)
    mkdir -p "$SCRATCH/bin"
    cat > "$SCRATCH/bin/gh" <<'STUB'
#!/bin/bash
[[ -n "${GH_STUB_STDOUT:-}" ]] && printf '%s' "$GH_STUB_STDOUT"
[[ -n "${GH_STUB_STDERR:-}" ]] && printf '%s\n' "$GH_STUB_STDERR" >&2
exit "${GH_STUB_EXIT:-0}"
STUB
    chmod +x "$SCRATCH/bin/gh"
    export PATH="$SCRATCH/bin:$PATH"

    # Source the plugin and its print-function dependencies. plugin.sh
    # registers an EXIT trap to clean GH_LAST_ERROR_FILE; that is fine
    # for bats — each test runs in its own subshell.
    # shellcheck disable=SC1090
    source "$COMMON_SH"
    # shellcheck disable=SC1090
    source "$PLUGIN_SH"
}

teardown() {
    if [[ -n "${SCRATCH:-}" ]] && [[ -d "$SCRATCH" ]]; then
        case "$SCRATCH" in
            /tmp/*) rm -rf "$SCRATCH" ;;
        esac
    fi
    unset GH_STUB_STDOUT GH_STUB_STDERR GH_STUB_EXIT
}

# ---------------------------------------------------------------------------
# _gh_run
# ---------------------------------------------------------------------------

@test "_gh_run: success path emits stdout and leaves GH_LAST_ERROR_FILE empty" {
    export GH_STUB_STDOUT="alice"
    export GH_STUB_STDERR=""
    export GH_STUB_EXIT=0

    run _gh_run gh api user --jq '.login'
    assert_success
    assert_output "alice"

    run cat "$GH_LAST_ERROR_FILE"
    assert_success
    assert_output ""
}

@test "_gh_run: failure path leaves stdout empty and writes first stderr line to file" {
    export GH_STUB_STDOUT=""
    export GH_STUB_STDERR="gh: To get started with GitHub CLI, please run: gh auth login"
    export GH_STUB_EXIT=1

    run _gh_run gh api user --jq '.login'
    # _gh_run swallows the exit code — always 0.
    assert_success
    assert_output ""

    run cat "$GH_LAST_ERROR_FILE"
    assert_success
    assert_output "gh: To get started with GitHub CLI, please run: gh auth login"
}

@test "_gh_run: multi-line stderr captures first line only" {
    export GH_STUB_STDOUT=""
    # shellcheck disable=SC2034
    GH_STUB_STDERR="line one error
line two recovery hint
line three usage example"
    export GH_STUB_STDERR
    export GH_STUB_EXIT=1

    run _gh_run gh api user
    assert_success

    run cat "$GH_LAST_ERROR_FILE"
    assert_output "line one error"
}

@test "_gh_run: exit 0 with empty stdout resets GH_LAST_ERROR_FILE" {
    # Prime GH_LAST_ERROR_FILE with a prior error to ensure it is reset.
    printf 'prior error\n' > "$GH_LAST_ERROR_FILE"

    export GH_STUB_STDOUT=""
    export GH_STUB_STDERR=""
    export GH_STUB_EXIT=0

    run _gh_run gh api user
    assert_success

    run cat "$GH_LAST_ERROR_FILE"
    assert_output ""
}

# ---------------------------------------------------------------------------
# Helpers built on _gh_run survive `set -e` even when gh fails
# ---------------------------------------------------------------------------

@test "get_current_user: gh failure returns 0 (empty stdout); manual fallback reachable under set -e" {
    set -e
    export GH_STUB_STDOUT=""
    export GH_STUB_STDERR="gh: not authenticated"
    export GH_STUB_EXIT=1

    # Pre-#276 this assignment aborted the test under set -e.
    user=$(get_current_user)
    [[ -z "$user" ]]

    # And GH_LAST_ERROR_FILE persists across the subshell.
    err=$(cat "$GH_LAST_ERROR_FILE")
    [[ "$err" == "gh: not authenticated" ]]
}

@test "get_owner_projects: gh failure returns 0 (empty stdout)" {
    set -e
    export GH_STUB_STDOUT=""
    export GH_STUB_STDERR="gh: HTTP 500"
    export GH_STUB_EXIT=1

    projects=$(get_owner_projects "someuser")
    [[ -z "$projects" ]]

    err=$(cat "$GH_LAST_ERROR_FILE")
    [[ "$err" == "gh: HTTP 500" ]]
}

@test "get_owner_projects: success path returns JSON" {
    set -e
    export GH_STUB_STDOUT='{"projects":[{"number":1,"title":"P1","owner":{"login":"alice"}}]}'
    export GH_STUB_STDERR=""
    export GH_STUB_EXIT=0

    projects=$(get_owner_projects "alice")
    [[ "$projects" == '{"projects":[{"number":1,"title":"P1","owner":{"login":"alice"}}]}' ]]
}

# ---------------------------------------------------------------------------
# _print_gh_warning
# ---------------------------------------------------------------------------

@test "_print_gh_warning: appends captured gh stderr when present" {
    printf 'gh: not authenticated\n' > "$GH_LAST_ERROR_FILE"

    run _print_gh_warning "Could not determine current user"
    assert_success
    assert_output --partial "Could not determine current user"
    assert_output --partial "(gh: gh: not authenticated)"
}

@test "_print_gh_warning: no parenthetical suffix when GH_LAST_ERROR_FILE empty" {
    : > "$GH_LAST_ERROR_FILE"

    run _print_gh_warning "No projects found for someuser"
    assert_success
    assert_output --partial "No projects found for someuser"
    refute_output --partial "(gh:"
}
