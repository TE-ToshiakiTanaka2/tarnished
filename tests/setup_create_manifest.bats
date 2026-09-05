#!/usr/bin/env bats

# End-to-end tests for `setup.sh --create-manifest` (#265 Phase 2).

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

# Helper: build a minimal single-mode tarnished-output-shaped target.
# Includes: verbatim files (workflow), excluded files (.gitignore,
# docker-compose.yml, devcontainer.json, CLAUDE.md, README.md), and a
# language marker (Cargo.toml).
make_single_mode_target() {
    mkdir -p "$SCRATCH/.devcontainer/scripts"
    mkdir -p "$SCRATCH/.claude/commands"
    mkdir -p "$SCRATCH/docker"
    mkdir -p "$SCRATCH/.github/workflows"

    cp "$SCRIPT_DIR/templates/core/.devcontainer/scripts/refresh-assets.sh" "$SCRATCH/.devcontainer/scripts/refresh-assets.sh"
    echo "FROM debian:trixie" > "$SCRATCH/docker/Dockerfile.dev"
    echo '{}' > "$SCRATCH/.devcontainer/devcontainer.json"
    echo "version: '3'" > "$SCRATCH/docker-compose.yml"
    echo '{}' > "$SCRATCH/.claude/settings.json"
    echo "# Project Setup" > "$SCRATCH/.claude/commands/setup.md"
    echo "name: rust-quality" > "$SCRATCH/.github/workflows/rust-quality-check.yml"
    cat > "$SCRATCH/Cargo.toml" <<EOF
[package]
name = "test"
version = "0.1.0"
EOF
    echo "# CLAUDE.md" > "$SCRATCH/CLAUDE.md"
    echo "# README" > "$SCRATCH/README.md"
}

# Helper: build a minimal monorepo-shaped target with two modules.
make_monorepo_target() {
    make_single_mode_target

    # Replace single-mode markers with monorepo equivalents.
    rm -f "$SCRATCH/Cargo.toml"
    cat > "$SCRATCH/modules.json" <<'EOF'
{
  "version": 1,
  "modules": [
    { "name": "alpha", "path": "alpha", "language": "python", "services": [] },
    { "name": "beta", "path": "beta", "language": "node", "services": [] }
  ]
}
EOF

    # Per-module file trees.
    mkdir -p "$SCRATCH/alpha/src"
    mkdir -p "$SCRATCH/alpha/tests"
    cat > "$SCRATCH/alpha/pyproject.toml" <<EOF
[project]
name = "alpha"
version = "0.0.1"
EOF
    echo "# alpha module" > "$SCRATCH/alpha/CLAUDE.md"
    echo "ALPHA_MARKER = 1" > "$SCRATCH/alpha/src/__init__.py"

    mkdir -p "$SCRATCH/beta/src"
    cat > "$SCRATCH/beta/package.json" <<EOF
{ "name": "beta", "version": "0.0.1" }
EOF
    echo "# beta module" > "$SCRATCH/beta/CLAUDE.md"
}

# -----------------------------------------------------------------------------
# Mutex / argument validation
# -----------------------------------------------------------------------------

@test "--create-manifest rejects --monorepo" {
    run bash "$SETUP_SH" --create-manifest --monorepo -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "--create-manifest rejects --add-module" {
    run bash "$SETUP_SH" --create-manifest --add-module foo -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "--create-manifest rejects --lang" {
    run bash "$SETUP_SH" --create-manifest --lang rust -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--create-manifest does not accept --lang"* ]]
}

@test "--create-manifest rejects service flags" {
    run bash "$SETUP_SH" --create-manifest --postgresql -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--create-manifest does not accept service flags"* ]]
}

@test "--create-manifest rejects --mysql" {
    run bash "$SETUP_SH" --create-manifest --mysql -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--create-manifest does not accept service flags"* ]]
}

@test "--from-version requires --create-manifest" {
    run bash "$SETUP_SH" --from-version v0.0.74 --lang rust -y my-proj
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--from-version is only valid with --create-manifest"* ]]
}

@test "--from-version requires a value" {
    run bash "$SETUP_SH" --create-manifest --from-version
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--from-version requires a value"* ]]
}

# -----------------------------------------------------------------------------
# Single-mode target
# -----------------------------------------------------------------------------

@test "single-mode: writes one .tarnished-manifest.json with FR-3 exclusions" {
    make_single_mode_target
    cd "$SCRATCH"

    run bash "$SETUP_SH" --create-manifest --from-version HEAD -y
    [[ "$status" -eq 0 ]]
    [[ -f "$SCRATCH/.tarnished-manifest.json" ]]

    local m="$SCRATCH/.tarnished-manifest.json"

    [[ "$(jq -r .manifest_version "$m")" == "2" ]]
    [[ "$(jq -r .tarnished_version "$m")" == "HEAD" ]]
    [[ "$(jq -r '.scaffold_options.monorepo' "$m")" == "false" ]]

    # Only exact distribution helper matches are owned.
    [[ -z "$(jq -r '.files["docker/Dockerfile.dev"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files["Cargo.toml"] // empty' "$m")" ]]

    # Excluded by MANIFEST_EXCLUDE_GLOBS.
    [[ -z "$(jq -r '.files[".gitignore"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files[".devcontainer/devcontainer.json"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files["docker-compose.yml"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files["CLAUDE.md"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files["README.md"] // empty' "$m")" ]]
    [[ -z "$(jq -r '.files[".claude/settings.json"] // empty' "$m")" ]]
    # .github/ tree is excluded as user-owned (#286).
    [[ -z "$(jq -r '.files[".github/workflows/rust-quality-check.yml"] // empty' "$m")" ]]

    # The manifest file itself is never tracked.
    [[ -z "$(jq -r '.files[".tarnished-manifest.json"] // empty' "$m")" ]]
}

@test "single-mode: records invoked checkout identity when --from-version is absent" {
    make_single_mode_target
    cd "$SCRATCH"

    run bash "$SETUP_SH" --create-manifest -y
    [[ "$status" -eq 0 ]]
    [[ "$(jq -r .tarnished_commit "$SCRATCH/.tarnished-manifest.json")" == "$(git -C "$SCRIPT_DIR" rev-parse HEAD)" ]]
}

@test "single-mode: detects rust language from Cargo.toml" {
    make_single_mode_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    [[ "$(jq -r '.scaffold_options.languages | join(",")' "$SCRATCH/.tarnished-manifest.json")" == *"rust"* ]]
}

@test "single-mode: created_at is ISO-8601 UTC" {
    make_single_mode_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local ts
    ts=$(jq -r .created_at "$SCRATCH/.tarnished-manifest.json")
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "single-mode: idempotent (only created_at differs on re-run)" {
    make_single_mode_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local first
    first=$(jq 'del(.created_at)' "$SCRATCH/.tarnished-manifest.json")

    sleep 1
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local second
    second=$(jq 'del(.created_at)' "$SCRATCH/.tarnished-manifest.json")

    [[ "$first" == "$second" ]]
}

@test "single-mode: --dry-run writes nothing" {
    make_single_mode_target
    cd "$SCRATCH"

    run bash "$SETUP_SH" --create-manifest --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ ! -f "$SCRATCH/.tarnished-manifest.json" ]]
}

@test "single-mode: a failed manifest_write aborts with non-zero exit, no false success (#289)" {
    make_single_mode_target
    cd "$SCRATCH"

    # Force manifest_write's atomic temp write to fail by occupying its tmp
    # path with a directory, so the `> "$file.tmp"` redirect errors. Before
    # #289 the caller printed "[OK] wrote ..." and the run exited 0 regardless
    # of manifest_write's return code; now the failure must surface and the
    # command must exit non-zero, leaving no manifest behind.
    mkdir -p "$SCRATCH/.tarnished-manifest.json"

    run bash "$SETUP_SH" --create-manifest -y
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unsafe project marker"* ]]
    [[ "$output" != *"wrote $SCRATCH/.tarnished-manifest.json"* ]]
    [[ ! -f "$SCRATCH/.tarnished-manifest.json" ]]
}

# -----------------------------------------------------------------------------
# Monorepo target
# -----------------------------------------------------------------------------

@test "monorepo: writes root + per-module manifests" {
    make_monorepo_target
    cd "$SCRATCH"

    run bash "$SETUP_SH" --create-manifest --from-version HEAD -y
    [[ "$status" -eq 0 ]]

    # Root manifest exists and is flagged monorepo.
    [[ -f "$SCRATCH/.tarnished-manifest.json" ]]
    [[ "$(jq -r '.scaffold_options.monorepo' "$SCRATCH/.tarnished-manifest.json")" == "true" ]]
    [[ "$(jq -r '.scaffold_options.languages | sort | join(",")' "$SCRATCH/.tarnished-manifest.json")" == "node,python" ]]

    # Per-module manifests exist.
    [[ -f "$SCRATCH/alpha/.tarnished-manifest.json" ]]
    [[ -f "$SCRATCH/beta/.tarnished-manifest.json" ]]

    # Per-module scaffold_options carry the module's single language.
    [[ "$(jq -r '.scaffold_options.languages[0]' "$SCRATCH/alpha/.tarnished-manifest.json")" == "python" ]]
    [[ "$(jq -r '.scaffold_options.languages[0]' "$SCRATCH/beta/.tarnished-manifest.json")" == "node" ]]
    [[ "$(jq -r '.scaffold_options.monorepo' "$SCRATCH/alpha/.tarnished-manifest.json")" == "false" ]]

    # All module scaffold seeds remain developer-owned.
    [[ -z "$(jq -r '.files["CLAUDE.md"] // empty' "$SCRATCH/alpha/.tarnished-manifest.json")" ]]
    [[ -z "$(jq -r '.files["pyproject.toml"] // empty' "$SCRATCH/alpha/.tarnished-manifest.json")" ]]
    [[ -z "$(jq -r '.files["src/__init__.py"] // empty' "$SCRATCH/alpha/.tarnished-manifest.json")" ]]
}

@test "monorepo: root manifest does not include module subtrees" {
    make_monorepo_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null

    local root="$SCRATCH/.tarnished-manifest.json"
    # No alpha/* or beta/* paths in the root manifest.
    [[ -z "$(jq -r '.files | keys[] | select(startswith("alpha/")) // empty' "$root" | head -1)" ]]
    [[ -z "$(jq -r '.files | keys[] | select(startswith("beta/")) // empty' "$root" | head -1)" ]]
}

@test "monorepo: --from-version propagates to every per-module manifest" {
    make_monorepo_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest --from-version HEAD -y >/dev/null

    [[ "$(jq -r .tarnished_version "$SCRATCH/.tarnished-manifest.json")" == "HEAD" ]]
    [[ "$(jq -r .tarnished_version "$SCRATCH/alpha/.tarnished-manifest.json")" == "HEAD" ]]
    [[ "$(jq -r .tarnished_version "$SCRATCH/beta/.tarnished-manifest.json")" == "HEAD" ]]
}

@test "monorepo: idempotent" {
    make_monorepo_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local r1 a1 b1
    r1=$(jq 'del(.created_at)' "$SCRATCH/.tarnished-manifest.json")
    a1=$(jq 'del(.created_at)' "$SCRATCH/alpha/.tarnished-manifest.json")
    b1=$(jq 'del(.created_at)' "$SCRATCH/beta/.tarnished-manifest.json")

    sleep 1
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local r2 a2 b2
    r2=$(jq 'del(.created_at)' "$SCRATCH/.tarnished-manifest.json")
    a2=$(jq 'del(.created_at)' "$SCRATCH/alpha/.tarnished-manifest.json")
    b2=$(jq 'del(.created_at)' "$SCRATCH/beta/.tarnished-manifest.json")

    [[ "$r1" == "$r2" ]]
    [[ "$a1" == "$a2" ]]
    [[ "$b1" == "$b2" ]]
}

@test "#316 bootstrap owns exact helpers only and preserves arbitrary project work" {
    make_single_mode_target
    mkdir -p "$SCRATCH/src" "$SCRATCH/tests" "$SCRATCH/docs"
    printf 'developer source\n' > "$SCRATCH/src/work.py"
    printf 'developer tests\n' > "$SCRATCH/tests/test work.py"
    printf 'developer docs\n' > "$SCRATCH/docs/notes.md"
    printf 'unknown helper\n' > "$SCRATCH/.devcontainer/scripts/custom.sh"
    cd "$SCRATCH"
    run bash "$SETUP_SH" --create-manifest -y
    assert_success
    run jq -e '.manifest_version == 2 and (.files | keys == [".devcontainer/scripts/refresh-assets.sh"])' .tarnished-manifest.json
    assert_success
    [[ "$(cat src/work.py)" == 'developer source' ]]
    [[ "$(cat 'tests/test work.py')" == 'developer tests' ]]
}

@test "#316 repeated bootstrap retains installed baselines for edited and deleted helpers" {
    make_single_mode_target
    cd "$SCRATCH"
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    local old
    old=$(jq -c .files .tarnished-manifest.json)
    printf '\n# developer change\n' >> .devcontainer/scripts/refresh-assets.sh
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    [[ "$(jq -c .files .tarnished-manifest.json)" == "$old" ]]
    rm .devcontainer/scripts/refresh-assets.sh
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    [[ "$(jq -c .files .tarnished-manifest.json)" == "$old" ]]
    [[ ! -e .devcontainer/scripts/refresh-assets.sh ]]
}

@test "#316 explicit historical ref cannot certify arbitrary current helper bytes" {
    make_single_mode_target
    printf 'project-owned helper\n' > "$SCRATCH/.devcontainer/scripts/refresh-assets.sh"
    cd "$SCRATCH"
    run bash "$SETUP_SH" --create-manifest --from-version HEAD -y
    assert_success
    run jq -e '.files | length == 0' .tarnished-manifest.json
    assert_success
    [[ "$(cat .devcontainer/scripts/refresh-assets.sh)" == 'project-owned helper' ]]
}

@test "#316 hostile module scope and symlink marker are rejected before bootstrap" {
    cd "$SCRATCH"
    printf '{"version":1,"modules":[{"name":"../outside","language":"python"}]}\n' > modules.json
    run bash "$SETUP_SH" --create-manifest -y
    assert_failure
    [[ ! -e .tarnished-manifest.json ]]
    rm modules.json
    ln -s "$SCRATCH/nonexistent" .tarnished-manifest.json
    run bash "$SETUP_SH" --create-manifest -y
    assert_failure
    [[ ! -e "$SCRATCH/nonexistent" ]]
}
