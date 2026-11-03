#!/bin/bash
# =============================================================================
# smoke-runtimes.sh - in-container runtime version assertions (#325)
# =============================================================================
# Run inside an image built from a scaffolded docker/Dockerfile.dev by
# .github/workflows/scaffold-build.yml. Repo-only: it is not shipped to
# generated projects.
#
# For every mise-managed tool the version printed by the binary must match
# `mise current <tool>`, once through `bash -c` (shims on PATH) and once
# through `bash -ic` (mise activated by ~/.bashrc), which is the FR-2
# acceptance. OS-level tools only need `--version` to succeed.
#
# Usage: smoke-runtimes.sh <tool>...
#   mise tools: node python uv pnpm go deno rust godot dotnet
#   gdtoolkit:  gdformat gdlint (both checked against `mise current gdtoolkit`)
#   other:      mise git gh npm cargo cargo-fmt cargo-clippy psql mysql redis-cli
# =============================================================================

set -euo pipefail

FAILURES=0

fail() {
    echo "FAIL: $*" >&2
    FAILURES=$((FAILURES + 1))
}

# run_in <bash-flags> <command>: run a command in a fresh bash.
run_in() {
    local flags="$1"
    local command_line="$2"
    # Interactive shells print job-control noise on stderr.
    bash "$flags" "$command_line" 2> /dev/null
}

# expect_contains <label> <actual> <needle>
expect_contains() {
    local label="$1"
    local actual="$2"
    local needle="$3"
    if [[ "$actual" != *"$needle"* ]]; then
        fail "${label}: expected '${needle}' in '${actual}'"
    else
        echo "ok   ${label}: ${actual}"
    fi
}

check_mise_tool() {
    local tool="$1"
    local flags actual wanted

    wanted="$(mise current "$tool" 2> /dev/null | head -n 1 | tr -d '[:space:]')"
    if [[ -z "$wanted" ]]; then
        fail "${tool}: 'mise current ${tool}' reported no version"
        return 0
    fi

    for flags in -c -ic; do
        case "$tool" in
            node)
                actual="$(run_in "$flags" 'node --version')" || { fail "node --version failed (bash ${flags})"; continue; }
                expect_contains "node (bash ${flags})" "$actual" "v${wanted}"
                ;;
            python)
                actual="$(run_in "$flags" 'python --version')" || { fail "python --version failed (bash ${flags})"; continue; }
                expect_contains "python (bash ${flags})" "$actual" "Python ${wanted}"
                ;;
            go)
                actual="$(run_in "$flags" 'go version')" || { fail "go version failed (bash ${flags})"; continue; }
                expect_contains "go (bash ${flags})" "$actual" "go${wanted}"
                ;;
            uv | pnpm | deno)
                actual="$(run_in "$flags" "${tool} --version")" || { fail "${tool} --version failed (bash ${flags})"; continue; }
                expect_contains "${tool} (bash ${flags})" "$actual" "$wanted"
                ;;
            rust)
                actual="$(run_in "$flags" 'rustc --version')" || { fail "rustc --version failed (bash ${flags})"; continue; }
                expect_contains "rustc (bash ${flags})" "$actual" "rustc "
                actual="$(run_in "$flags" 'rustup show active-toolchain')" || { fail "rustup show active-toolchain failed (bash ${flags})"; continue; }
                expect_contains "rust toolchain (bash ${flags})" "$actual" "stable"
                ;;
            godot)
                # `mise current godot` is 4.7.2-stable; the .NET build reports
                # 4.7.2.stable.mono.official.<hash>.
                actual="$(run_in "$flags" 'godot --headless --version' | tail -n 1)" || {
                    fail "godot --headless --version failed (bash ${flags})"
                    continue
                }
                expect_contains "godot (bash ${flags})" "$actual" "${wanted//-/.}.mono"
                ;;
            dotnet)
                actual="$(run_in "$flags" 'dotnet --version')" || {
                    fail "dotnet --version failed (bash ${flags})"
                    continue
                }
                expect_equals "dotnet (bash ${flags})" "$actual" "$wanted"
                ;;
            *)
                fail "unknown mise tool '${tool}'"
                return 0
                ;;
        esac
    done
}

# expect_equals <label> <actual> <wanted>
expect_equals() {
    local label="$1"
    local actual="$2"
    local wanted="$3"
    actual="$(echo "$actual" | tr -d '[:space:]')"
    if [[ "$actual" != "$wanted" ]]; then
        fail "${label}: expected '${wanted}', got '${actual}'"
    else
        echo "ok   ${label}: ${actual}"
    fi
}

# gdformat and gdlint ship in one package; mise tracks it as gdtoolkit.
check_gdtoolkit_tool() {
    local tool="$1"
    local flags actual wanted

    wanted="$(mise current gdtoolkit 2> /dev/null | head -n 1 | tr -d '[:space:]')"
    if [[ -z "$wanted" ]]; then
        fail "${tool}: 'mise current gdtoolkit' reported no version"
        return 0
    fi

    for flags in -c -ic; do
        actual="$(run_in "$flags" "${tool} --version")" || {
            fail "${tool} --version failed (bash ${flags})"
            continue
        }
        expect_contains "${tool} (bash ${flags})" "$actual" "$wanted"
    done
}

check_plain_tool() {
    local label="$1"
    local command_line="$2"
    local flags actual
    for flags in -c -ic; do
        if actual="$(run_in "$flags" "$command_line")"; then
            echo "ok   ${label} (bash ${flags}): ${actual%%$'\n'*}"
        else
            fail "${label}: '${command_line}' failed (bash ${flags})"
        fi
    done
}

main() {
    if [[ $# -eq 0 ]]; then
        echo "usage: $0 <tool>..." >&2
        exit 2
    fi

    local tool
    for tool in "$@"; do
        case "$tool" in
            node | python | uv | pnpm | go | deno | rust | godot | dotnet)
                check_mise_tool "$tool"
                ;;
            gdformat | gdlint) check_gdtoolkit_tool "$tool" ;;
            mise | git | gh | npm | cargo | psql | mysql | redis-cli) check_plain_tool "$tool" "${tool} --version" ;;
            cargo-fmt) check_plain_tool "cargo fmt" 'cargo fmt --version' ;;
            cargo-clippy) check_plain_tool "cargo clippy" 'cargo clippy --version' ;;
            *) fail "unknown tool '${tool}'" ;;
        esac
    done

    if [[ "$FAILURES" -gt 0 ]]; then
        echo "smoke-runtimes: ${FAILURES} check(s) failed" >&2
        exit 1
    fi
    echo "smoke-runtimes: all checks passed"
}

main "$@"
