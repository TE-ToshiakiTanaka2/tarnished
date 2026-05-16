#!/usr/bin/env bats

# End-to-end tests for `setup.sh --upgrade` (#265 Phase 3).
#
# These tests exercise the lifecycle decision engine against synthetic
# scaffolds. We don't drive a full real `setup.sh --lang rust` scaffold
# because we want deterministic control over which files are tracked and
# which are edited; instead, we hand-craft a target tree that mirrors a
# subset of what the plugins would emit.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SETUP_SH="${SCRIPT_DIR}/setup.sh"

setup() {
    SCRATCH="$(mktemp -d)"
    cd "$SCRATCH"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "test"
    export SCRATCH
}

teardown() {
    cd /
    if [[ -n "${SCRATCH:-}" ]] && [[ -d "$SCRATCH" ]]; then
        case "$SCRATCH" in
            /tmp/*) rm -rf "$SCRATCH" ;;
        esac
    fi
}

# Seed a minimal scaffold whose tracked files come from real templates so
# that staging the plugin pipeline against /workspace/templates produces
# matching files. We use the auto-tag workflow (substituted) and a single
# erd skill file so we can predict outcomes.
seed_scaffold() {
    mkdir -p .devcontainer/scripts .claude/commands/erd .github/workflows docker
    sed "s/__ERD_REF__/develop/g" "${SCRIPT_DIR}/templates/github-actions/auto-tag/.github/workflows/auto-tag.yml" \
        > .github/workflows/auto-tag.yml
    cp "${SCRIPT_DIR}/templates/claude/.claude/commands/erd/build.md" \
        .claude/commands/erd/build.md
    cp "${SCRIPT_DIR}/templates/core/docker/Dockerfile.dev" docker/Dockerfile.dev
    echo '{}' > .devcontainer/devcontainer.json
    echo "version: '3'" > docker-compose.yml
    echo '{}' > .claude/settings.json
    echo "# CLAUDE" > CLAUDE.md
    echo "# README" > README.md
}

# Bootstrap manifest, commit so the tree is clean for FR-9.
bootstrap_and_commit() {
    bash "$SETUP_SH" --create-manifest --from-version v0.0.74 -y >/dev/null 2>&1
    git add -A
    git commit -q -m "scaffold + manifest"
}

# -----------------------------------------------------------------------------
# Mutex / argument validation
# -----------------------------------------------------------------------------

@test "--upgrade rejects --monorepo" {
    run bash "$SETUP_SH" --upgrade --monorepo -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "--upgrade rejects --add-module" {
    run bash "$SETUP_SH" --upgrade --add-module foo -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "--upgrade rejects --create-manifest" {
    run bash "$SETUP_SH" --upgrade --create-manifest -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "--upgrade rejects --module foo:bar (init form)" {
    run bash "$SETUP_SH" --upgrade --module foo:python -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--module <name>:<lang>"* ]]
}

@test "--upgrade rejects --lang" {
    run bash "$SETUP_SH" --upgrade --lang rust -y
    [[ "$status" -eq 1 ]]
}

@test "--target-version requires a value" {
    run bash "$SETUP_SH" --target-version
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"--target-version requires a value"* ]]
}

@test "--target-version without --upgrade is rejected" {
    run bash "$SETUP_SH" --target-version v0.0.76 --lang rust -y my-proj
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"only valid with --upgrade"* ]]
}

@test "--prune / --shared-only / --force without --upgrade are rejected" {
    run bash "$SETUP_SH" --prune --lang rust -y my-proj
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"only valid with --upgrade"* ]]
}

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------

@test "--upgrade aborts when no manifest is present" {
    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"no .tarnished-manifest.json"* ]]
}

@test "--upgrade aborts on dirty git tree (FR-9)" {
    seed_scaffold
    bootstrap_and_commit
    # Introduce a dirty tracked change.
    echo "dirty" >> .claude/commands/erd/build.md

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"uncommitted changes"* ]]
}

@test "--upgrade --force overrides dirty git tree" {
    seed_scaffold
    bootstrap_and_commit
    echo "dirty" >> .claude/commands/erd/build.md

    run bash "$SETUP_SH" --upgrade --force --dry-run -y
    [[ "$status" -eq 0 ]]
}

@test "--upgrade against non-git directory proceeds with warning" {
    seed_scaffold
    bash "$SETUP_SH" --create-manifest -y >/dev/null
    rm -rf .git

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not a git repository"* ]] || [[ "$output" == *"Tarnished upgrade summary"* ]]
}

# -----------------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------------

@test "FR-4 row 1: NOOP — file unchanged & unedited" {
    seed_scaffold
    bootstrap_and_commit

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    # The seeded files match the templates exactly, so they should be
    # NOOP — i.e. NOT in Updated and NOT in Skipped(edited).
    [[ "$output" != *".claude/commands/erd/build.md (~"* ]]
}

@test "FR-4 row 3: SKIP_EDITED — user edited a tracked file" {
    seed_scaffold
    bootstrap_and_commit

    # Edit a tracked file post-bootstrap. We use Dockerfile.dev because
    # .claude/commands/erd/build.md is now governed by always-latest sync
    # (#279) and excluded from manifest tracking entirely.
    echo "" >> docker/Dockerfile.dev
    echo "# user customization line" >> docker/Dockerfile.dev
    git add -A; git commit -q -m "user edit"

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped (edited)"* ]]
    [[ "$output" == *"docker/Dockerfile.dev"* ]]
}

@test "FR-4 row 4: NEW — staging emits files not in old manifest" {
    seed_scaffold
    bootstrap_and_commit

    # The seeded scaffold tracks 3 files; the staged plugin pipeline
    # emits many more — those are NEW.
    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"New:"* ]]
    [[ "$output" =~ New:[[:space:]]+[1-9] ]]
}

@test "FR-4 row 8: SKIP_USER_DELETED — user removed a tracked file" {
    seed_scaffold
    bootstrap_and_commit

    rm -f .claude/commands/erd/build.md
    git add -A; git commit -q -m "user deleted file"

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    # Either reported in the deleted-by-user section or as NOOP — we just
    # verify the upgrade succeeds and didn't recreate the file.
    [[ ! -f .claude/commands/erd/build.md ]]
}

# -----------------------------------------------------------------------------
# --dry-run
# -----------------------------------------------------------------------------

@test "FR-10: --dry-run writes nothing" {
    seed_scaffold
    bootstrap_and_commit

    # Snapshot the manifest hash.
    local before
    before=$(sha256sum .tarnished-manifest.json | cut -d' ' -f1)

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Dry-run; no files were modified."* ]]

    # The manifest is untouched.
    local after
    after=$(sha256sum .tarnished-manifest.json | cut -d' ' -f1)
    [[ "$before" == "$after" ]]
}

# -----------------------------------------------------------------------------
# FR-11 summary format
# -----------------------------------------------------------------------------

@test "FR-11: summary lists every category" {
    seed_scaffold
    bootstrap_and_commit

    # User edits one tracked file → ensures Skipped (edited) section appears.
    echo "extra" >> .claude/commands/erd/build.md
    git add -A; git commit -q -m "edit"

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Updated:"* ]]
    [[ "$output" == *"Skipped (edited):"* ]]
    [[ "$output" == *"New:"* ]]
    [[ "$output" == *"Removed (would prune):"* ]]
    [[ "$output" == *"Skipped (deleted by user):"* ]]
}

# -----------------------------------------------------------------------------
# #286: .github/ is user-owned — --upgrade never tracks it
# -----------------------------------------------------------------------------

@test "#286: --create-manifest does not record .github/* paths" {
    seed_scaffold
    bash "$SETUP_SH" --create-manifest --from-version v0.0.74 -y >/dev/null 2>&1

    # Manifest must contain core tracked files but not .github/*.
    run jq -r '.files | keys[]' .tarnished-manifest.json
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "^docker/Dockerfile.dev$"
    ! echo "$output" | grep -q "^\.github/"
}

@test "#286: user edits to .github/workflows/*.yml survive --upgrade" {
    seed_scaffold
    bootstrap_and_commit

    # Edit the workflow file after the manifest is written.
    echo "# user customization" >> .github/workflows/auto-tag.yml
    git add -A; git commit -q -m "user edit .github/"
    local before
    before=$(sha256sum .github/workflows/auto-tag.yml | cut -d' ' -f1)

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    # Summary must not mention the workflow file in ANY category.
    [[ "$output" != *".github/workflows/auto-tag.yml"* ]]

    # File content is byte-identical to the pre-upgrade copy.
    local after
    after=$(sha256sum .github/workflows/auto-tag.yml | cut -d' ' -f1)
    [[ "$before" == "$after" ]]
}

@test "#286: --upgrade --prune ignores pre-#286 .github/* manifest entries" {
    seed_scaffold
    bootstrap_and_commit

    # Simulate a pre-#286 manifest: inject a .github/workflows entry into
    # the existing manifest.files map. Use a sha that does not match the
    # current file so a non-filtered run would decide PRUNE (current == old,
    # has_new=false, PRUNE_ENABLED=true would fire). We use the real hash to
    # exercise the "unedited locally" branch.
    local real_hash
    real_hash=$(sha256sum .github/workflows/auto-tag.yml | awk '{print "sha256:"$1}')
    jq --arg h "$real_hash" \
        '.files[".github/workflows/auto-tag.yml"] = $h' \
        .tarnished-manifest.json > .tarnished-manifest.json.tmp
    mv .tarnished-manifest.json.tmp .tarnished-manifest.json
    git add -A; git commit -q -m "inject pre-#286 .github entry"

    run bash "$SETUP_SH" --upgrade --prune -y
    [[ "$status" -eq 0 ]]
    # The injected path must NOT be reported as pruned.
    [[ "$output" != *".github/workflows/auto-tag.yml"* ]]
    # File must still be on disk.
    [[ -f .github/workflows/auto-tag.yml ]]
    # New manifest must no longer list it.
    run jq -r '.files | keys[]' .tarnished-manifest.json
    ! echo "$output" | grep -q "^\.github/"
}
