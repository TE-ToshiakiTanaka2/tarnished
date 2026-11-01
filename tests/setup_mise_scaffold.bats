#!/usr/bin/env bats

# End-to-end tests for the #325 install contract: a scaffold carries no
# devcontainer features, declares runtimes in mise.toml, installs OS packages
# from Dockerfile.dev and orders the post.sh install blocks.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup.sh"

setup() {
    SCRATCH="$(mktemp -d)"
    export SCRATCH
    # setup.sh derives the project name of --add-module runs from the working
    # directory name, so use a valid one.
    mkdir "$SCRATCH/scaffold-proj"
    cd "$SCRATCH/scaffold-proj"
}

teardown() {
    cd /
    case "${SCRATCH:-}" in
        /tmp/*) rm -rf "$SCRATCH" ;;
    esac
}

# _scaffold <setup.sh args...>: scaffold into the CWD ($SCRATCH/scaffold-proj).
_scaffold() {
    run bash "$SETUP_SH" "$@" -y scaffold-proj
    assert_success
}

# Invariants every scaffold must satisfy (FR-1, FR-4, FR-6, NFR-1).
_assert_install_contract() {
    run jq -r 'has("features")' .devcontainer/devcontainer.json
    assert_output "false"

    run grep -c '^ARG MISE_VERSION=' docker/Dockerfile.dev
    assert_output "1"
    run grep -F 'ln -sf /bin/bash /bin/sh' docker/Dockerfile.dev
    assert_failure
    run grep -w 'latest' docker/Dockerfile.dev
    assert_failure
    run grep -c '^SHELL ' docker/Dockerfile.dev
    assert_output "1"

    local shell_line mise_line
    shell_line="$(grep -n '^SHELL ' docker/Dockerfile.dev | cut -d: -f1)"
    mise_line="$(grep -n '^# >>> mise runtimes >>>$' docker/Dockerfile.dev | cut -d: -f1)"
    [[ -n "$mise_line" ]]
    [[ "$shell_line" -lt "$mise_line" ]]

    # Everything above SHELL runs under dash: no bash extensions.
    run bash -c 'head -n "$1" docker/Dockerfile.dev | grep -E "^[^#]*(\[\[|<<<|source |pipefail)"' _ "$((shell_line - 1))"
    assert_failure

    [[ -f mise.toml ]]
    run grep -x 'node = "22"' mise.toml
    assert_success
    run grep -c '^node = ' mise.toml
    assert_output "1"

    run grep -rn 'devcontainers/features\|ghcr.io/.*features' .devcontainer docker
    assert_failure
    run grep -c 'setup_sudo_path' .devcontainer/scripts/post.sh
    assert_output "0"
}

_assert_mise_entry() {
    run grep -c "^$1 = " mise.toml
    assert_output "1"
}

@test "core-only scaffold: no features, node 22 in mise.toml, Dockerfile contract" {
    _scaffold
    _assert_install_contract
    run grep -c '^\[tools\]$' mise.toml
    assert_output "1"
    run grep -c '^\[env\]$' mise.toml
    assert_output "0"
}

@test "python scaffold: python, uv and the former Dockerfile ENV block live in mise.toml" {
    _scaffold --lang python
    _assert_install_contract
    run grep -x 'python = "3.12"' mise.toml
    assert_success
    _assert_mise_entry uv
    _assert_mise_entry UV_PYTHON
    run grep -F 'UV_PYTHON = { value = "{{ tools.python.path }}", tools = true }' mise.toml
    assert_success
    local var
    for var in PYTHONDONTWRITEBYTECODE PYTHONUNBUFFERED UV_COMPILE_BYTECODE UV_LINK_MODE; do
        _assert_mise_entry "$var"
    done
    run grep -c 'UV_HOME\|PYTHONUNBUFFERED' docker/Dockerfile.dev
    assert_output "0"
}

@test "node scaffold: node and pnpm, no corepack" {
    _scaffold --lang node
    _assert_install_contract
    _assert_mise_entry pnpm
    run grep -c corepack .devcontainer/scripts/post.sh
    assert_output "0"
}

@test "rust scaffold: rust stable with rustfmt and clippy" {
    _scaffold --lang rust
    _assert_install_contract
    run grep -F 'rust = { version = "stable", components = ["rustfmt", "clippy"] }' mise.toml
    assert_success
}

@test "go scaffold: pinned go" {
    _scaffold --lang go
    _assert_install_contract
    run grep -E '^go = "[0-9]+\.[0-9]+\.[0-9]+"$' mise.toml
    assert_success
}

@test "deno scaffold: pinned deno" {
    _scaffold --lang deno
    _assert_install_contract
    run grep -E '^deno = "[0-9]+\.[0-9]+\.[0-9]+"$' mise.toml
    assert_success
}

@test "postgresql scaffold: client is an apt block above SHELL, not a feature" {
    _scaffold --postgresql
    _assert_install_contract
    local open shell_line
    open="$(grep -n '^# >>> postgresql os-packages >>>$' docker/Dockerfile.dev | cut -d: -f1)"
    shell_line="$(grep -n '^SHELL ' docker/Dockerfile.dev | cut -d: -f1)"
    [[ -n "$open" ]]
    [[ "$open" -lt "$shell_line" ]]
    run grep -c '^    postgresql-client \\$' docker/Dockerfile.dev
    assert_output "1"
}

@test "mysql scaffold: client is an apt block above SHELL, not a feature" {
    _scaffold --mysql
    _assert_install_contract
    run grep -c '^    default-mysql-client \\$' docker/Dockerfile.dev
    assert_output "1"
    run grep -c '^# >>> mysql os-packages >>>$' docker/Dockerfile.dev
    assert_output "1"
}

@test "redis scaffold: core install contract only" {
    _scaffold --redis
    _assert_install_contract
    run grep -c 'os-packages' docker/Dockerfile.dev
    assert_output "0"
}

@test "celery scaffold: auto-enabled python and redis resolve through mise.toml" {
    _scaffold --lang python --celery
    _assert_install_contract
    run grep -x 'python = "3.12"' mise.toml
    assert_success
    _assert_mise_entry uv
}

@test "latex scaffold keeps its TeX Live apt block above SHELL" {
    _scaffold --lang latex
    _assert_install_contract
    local tex shell_line
    tex="$(grep -n 'texlive-full' docker/Dockerfile.dev | head -n 1 | cut -d: -f1)"
    shell_line="$(grep -n '^SHELL ' docker/Dockerfile.dev | cut -d: -f1)"
    [[ "$tex" -lt "$shell_line" ]]
}

@test "--codex scaffold orders post.sh blocks mise, Claude Code, Codex CLI, plugins" {
    _scaffold --codex --lang rust
    _assert_install_contract
    local m c x p
    m="$(grep -nxF '# mise Runtime Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    c="$(grep -nxF '# Claude Code Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    x="$(grep -nxF '# Codex CLI Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    p="$(grep -nxF '# Claude Code Plugin Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    [[ -n "$m" && -n "$c" && -n "$x" && -n "$p" ]]
    [[ "$m" -lt "$c" ]]
    [[ "$c" -lt "$x" ]]
    [[ "$x" -lt "$p" ]]
    run bash -n .devcontainer/scripts/post.sh
    assert_success
    run jq -r 'has("features")' .devcontainer/devcontainer.json
    assert_output "false"
}

@test "scaffold without --codex has no Codex block and keeps the order" {
    _scaffold
    run grep -c '^# Codex CLI Setup$' .devcontainer/scripts/post.sh
    assert_output "0"
    local m c p
    m="$(grep -nxF '# mise Runtime Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    c="$(grep -nxF '# Claude Code Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    p="$(grep -nxF '# Claude Code Plugin Setup' .devcontainer/scripts/post.sh | cut -d: -f1)"
    [[ "$m" -lt "$c" && "$c" -lt "$p" ]]
}

@test "scaffold ships the install helpers and the declarative plugin keys" {
    _scaffold
    local helper
    for helper in setup_mise.sh setup_claude.sh npm_global_cli.sh setup_plugins.sh; do
        [[ -f ".devcontainer/scripts/${helper}" ]]
    done
    run jq -r '.enabledPlugins | keys | join(",")' .claude/settings.json
    assert_output "context7@claude-plugins-official"
    run jq -r '.extraKnownMarketplaces | has("claude-plugins-official")' .claude/settings.json
    assert_output "true"
}

@test "scaffold with --zed keeps customizations.zed and has no features" {
    _scaffold --lang rust --zed
    run jq -r 'has("features")' .devcontainer/devcontainer.json
    assert_output "false"
    run jq -r '.customizations | has("zed")' .devcontainer/devcontainer.json
    assert_output "true"
}

@test "re-running setup over a scaffold leaves mise.toml byte-identical" {
    _scaffold --lang python
    cp mise.toml "$SCRATCH/mise.before"
    run bash "$SETUP_SH" --lang python --overwrite -y scaffold-proj
    run cmp mise.toml "$SCRATCH/mise.before"
    assert_success
}

@test "monorepo init: the root mise.toml holds the union of module runtimes once" {
    run bash "$SETUP_SH" --monorepo --module jing:python --module kir:node -y scaffold-proj
    assert_success
    _assert_install_contract
    local key
    for key in python uv node pnpm; do
        _assert_mise_entry "$key"
    done
    [[ ! -f jing/mise.toml && ! -f kir/mise.toml ]]
}

@test "add-module of an already declared language leaves mise.toml byte-identical" {
    run bash "$SETUP_SH" --monorepo --module jing:python -y scaffold-proj
    assert_success
    cp mise.toml "$SCRATCH/mise.before"
    run bash "$SETUP_SH" --add-module kir --lang python -y
    assert_success
    run cmp mise.toml "$SCRATCH/mise.before"
    assert_success
}

@test "add-module of a new language appends only its entries" {
    run bash "$SETUP_SH" --monorepo --module jing:python -y scaffold-proj
    assert_success
    run bash "$SETUP_SH" --add-module kir --lang rust -y
    assert_success
    assert_output --partial "mise install"
    run grep -c '^rust = ' mise.toml
    assert_output "1"
    _assert_mise_entry python
}

@test "add-module keeps a developer-changed node version" {
    run bash "$SETUP_SH" --monorepo --module kir:node -y scaffold-proj
    assert_success
    sed -i 's/^node = "22"$/node = "24"/' mise.toml
    run bash "$SETUP_SH" --add-module ori --lang node -y
    assert_success
    run grep -x 'node = "24"' mise.toml
    assert_success
    run grep -c '^node = ' mise.toml
    assert_output "1"
}

@test "add-module warns when the Dockerfile predates the mise layer" {
    run bash "$SETUP_SH" --monorepo --module kir:node -y scaffold-proj
    assert_success
    printf 'FROM debian\nSHELL ["/bin/bash", "-c"]\n' > docker/Dockerfile.dev
    run bash "$SETUP_SH" --add-module ori --lang node -y
    assert_success
    assert_output --partial "no mise runtime layer"
}

@test "--help describes mise.toml and mentions no --playwright" {
    run bash "$SETUP_SH" --help
    assert_success
    assert_output --partial "mise.toml"
    assert_output --partial "latex"
    refute_output --partial "--playwright"
}

@test "interactive-mode error lists real flags only" {
    run bash -c 'source "$1/scripts/lib/common.sh"; show_interactive_mode_error' _ "$SCRIPT_DIR"
    refute_output --partial "--playwright"
    refute_output --partial "--docker"
    refute_output --partial "--neo4j"
    assert_output --partial "--mysql"
}
