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
    cp "${SCRIPT_DIR}/templates/core/.devcontainer/scripts/refresh-assets.sh" .devcontainer/scripts/refresh-assets.sh
    echo '{}' > .devcontainer/devcontainer.json
    echo "version: '3'" > docker-compose.yml
    echo '{}' > .claude/settings.json
    echo "# CLAUDE" > CLAUDE.md
    echo "# README" > README.md
}

# Bootstrap manifest, commit so the tree is clean for FR-9.
bootstrap_and_commit() {
    bash "$SETUP_SH" --create-manifest -y >/dev/null 2>&1
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
    echo "" >> .devcontainer/scripts/refresh-assets.sh
    echo "# user customization line" >> .devcontainer/scripts/refresh-assets.sh
    git add -A; git commit -q -m "user edit"

    run bash "$SETUP_SH" --upgrade --dry-run -y
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipped (edited)"* ]]
    [[ "$output" == *".devcontainer/scripts/refresh-assets.sh"* ]]
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
    bash "$SETUP_SH" --create-manifest -y >/dev/null 2>&1

    # Manifest must contain core tracked files but not .github/*.
    run jq -r '.files | keys[]' .tarnished-manifest.json
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "^.devcontainer/scripts/refresh-assets.sh$"
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
    # the existing manifest.files map. We use the real current-file hash so
    # that (current == old) and (has_new == false), which is the exact
    # combination that triggers PRUNE under --prune; without the FR-2
    # OLD_HASHES filter, this entry would be deleted.
    local real_hash
    real_hash=$(sha256sum .github/workflows/auto-tag.yml | awk '{print "sha256:"$1}')
    jq --arg h "$real_hash" \
        '.manifest_version = 1 | .files[".github/workflows/auto-tag.yml"] = $h' \
        .tarnished-manifest.json > .tarnished-manifest.json.tmp
    mv .tarnished-manifest.json.tmp .tarnished-manifest.json
    git add -A; git commit -q -m "inject pre-#286 .github entry"

    run bash "$SETUP_SH" --upgrade --prune -y
    [[ "$status" -eq 0 ]]
    # Legacy ownership is reported and removed without touching the file.
    [[ "$output" == *"dropping its ownership claim"* ]]
    # File must still be on disk.
    [[ -f .github/workflows/auto-tag.yml ]]
    # New manifest must no longer list it.
    run jq -r '.files | keys[]' .tarnished-manifest.json
    ! echo "$output" | grep -q "^\.github/"
}

@test "#286: --upgrade does not resurrect a deleted .github/versioning.yml" {
    seed_scaffold
    bootstrap_and_commit

    # Pre-condition: versioning.yml is not part of the seed, so .github/
    # contains only the workflows/ directory. Without the github-actions
    # plugins' UPGRADE_MODE guard, rerun_post_copy_on_target would create
    # versioning.yml during --upgrade — violating the user-owned contract.
    [[ ! -f .github/versioning.yml ]]

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    [[ ! -f .github/versioning.yml ]]
}

# -----------------------------------------------------------------------------
# #308: --upgrade renders template placeholders in the staging tree
# -----------------------------------------------------------------------------
#
# `.tarnished/agent-profile.json` and `.tarnished/workflows/*.md` are the
# only files that are BOTH placeholder-bearing AND manifest-tracked (every
# other placeholder-bearing file sits in MANIFEST_EXCLUDE_GLOBS). Before
# #308 the staging run never called replace_placeholders, so an UPDATE
# decision on one of these wrote raw {{...}} tokens over the rendered
# downstream file.

# Seed a scaffold whose .tarnished/ files are rendered but stale, so the
# upgrade must take the UPDATE branch on them.
seed_tarnished_scaffold() {
    seed_scaffold
    # devcontainer.json is user-owned and carries the rendered project
    # name; stage_render_placeholders prefers it over the directory
    # basename (the scratch dir has a mktemp name).
    echo '{"name": "my-proj"}' > .devcontainer/devcontainer.json
    mkdir -p .tarnished/workflows
    sed -e "s|{{PROJECT_NAME}}|my-proj|g" \
        -e "s|{{AI_PROFILE}}|claude-main|g" \
        -e "s|{{AI_PRIMARY_AGENT}}|Claude Code|g" \
        -e "s|{{AI_REVIEW_AGENT}}|Codex CLI|g" \
        "${SCRIPT_DIR}/templates/agent-workflows/.tarnished/agent-profile.json" \
        > .tarnished/agent-profile.json
    for f in README design implement issue pr review; do
        sed -e "s|{{PROJECT_NAME}}|my-proj|g" \
            -e "s|{{AI_PROFILE}}|claude-main|g" \
            -e "s|{{AI_PRIMARY_AGENT}}|Claude Code|g" \
            -e "s|{{AI_REVIEW_AGENT}}|Codex CLI|g" \
            "${SCRIPT_DIR}/templates/agent-workflows/.tarnished/workflows/${f}.md" \
            > ".tarnished/workflows/${f}.md"
        # Make the seeded copy differ from the upgraded template so the
        # lifecycle engine picks UPDATE rather than NOOP.
        echo "" >> ".tarnished/workflows/${f}.md"
        echo "<!-- stale marker from an older tarnished -->" >> ".tarnished/workflows/${f}.md"
    done
}

@test "#308: --upgrade does not write raw placeholders into .tarnished/" {
    seed_tarnished_scaffold
    bootstrap_and_commit

    # Pre-condition: the seeded tree is fully rendered.
    ! grep -rq '{{' .tarnished/
    local before
    before=$(sha256sum .tarnished/agent-profile.json)

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]

    # Root upgrades now replace distributed workflows with verified backups.
    ! grep -q "stale marker" .tarnished/workflows/README.md
    grep -rq "stale marker" .tarnished/backups

    # The whole point: no placeholder token survives the upgrade.
    run grep -rl '{{' .tarnished/workflows .tarnished/agent-profile.json
    [[ "$status" -ne 0 ]]

    # Profile choices remain project-owned.
    [[ "$(sha256sum .tarnished/agent-profile.json)" == "$before" ]]
    run jq -r '.ai_profile' .tarnished/agent-profile.json
    [[ "$output" == "claude-main" ]]
}

@test "#308: --upgrade manifest records rendered hashes, so a re-run is a NOOP" {
    seed_tarnished_scaffold
    bootstrap_and_commit

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    git add -A; git commit -q -m "post-upgrade"

    local readme_before manifest_before
    readme_before=$(sha256sum .tarnished/workflows/README.md | cut -d' ' -f1)
    manifest_before=$(jq -S -r '.files' .tarnished-manifest.json | sha256sum | cut -d' ' -f1)

    # If NEW_HASHES had recorded unrendered staging hashes, the manifest
    # would disagree with the on-disk rendered file and the second run
    # would reclassify it — as SKIP_EDITED, or as a repeated UPDATE that
    # rewrites the same bytes. Assert the file and the tracked hash map are
    # both byte-for-byte unchanged, which only a true NOOP produces.
    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    # The summary always prints every category label, so assert on counts.
    [[ "$output" =~ Updated:[[:space:]]+0[[:space:]]file ]]
    [[ "$output" =~ Skipped[[:space:]]\(edited\):[[:space:]]+0[[:space:]]file ]]
    [[ "$output" != *".tarnished/workflows/README.md"* ]]

    local readme_after manifest_after
    readme_after=$(sha256sum .tarnished/workflows/README.md | cut -d' ' -f1)
    manifest_after=$(jq -S -r '.files' .tarnished-manifest.json | sha256sum | cut -d' ' -f1)
    [[ "$readme_before" == "$readme_after" ]]
    [[ "$manifest_before" == "$manifest_after" ]]
    ! grep -rq '{{' .tarnished/
}

@test "#308: --upgrade with a service plugin does not stage a deleted overlay" {
    # Service plugins copy a docker-compose overlay through
    # copy_with_confirm and then delete it once merged. If the staging
    # recorder's entry survives into NEW_HASHES, manifest_apply's NEW
    # branch tries to `cp` a staging path that no longer exists and aborts
    # the upgrade partway through the apply phase.
    seed_tarnished_scaffold
    # Make detect_scaffold_options record postgresql, so --upgrade loads
    # the service plugin.
    cat > docker-compose.yml <<'YML'
services:
  my-proj-db:
    image: postgres:16
YML
    bootstrap_and_commit

    run jq -r '.scaffold_options.services[]?' .tarnished-manifest.json
    [[ "$output" == *"postgresql"* ]]

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"No such file or directory"* ]]
    # The overlay is a build artifact of the merge; it must not survive.
    [[ ! -f docker-compose.postgresql.yml ]]
    # And it must not be recorded as a tracked file.
    run jq -r '.files | keys[]' .tarnished-manifest.json
    ! echo "$output" | grep -q "docker-compose.postgresql.yml"
}

@test "#308: --upgrade rejects a hostile project name instead of running it through sed" {
    # devcontainer.json is user-owned, and its "name" is interpolated into
    # a `sed s|…|…|` program. An unescaped `|` would end the replacement
    # and let the remainder parse as sed flags/commands — `w FILE` writes
    # an arbitrary file.
    seed_tarnished_scaffold
    echo '{"name": "evil|w '"$SCRATCH"'/PWNED"}' > .devcontainer/devcontainer.json
    bootstrap_and_commit

    run bash "$SETUP_SH" --upgrade -y
    [[ "$status" -eq 0 ]]
    # sed's `w` flag writes the rest of the program as the filename, so the
    # artifact is "PWNED|g" rather than "PWNED" — match the prefix.
    run bash -c 'ls "${SCRATCH}" | grep -c "^PWNED"'
    [[ "$output" == "0" ]]
    # Rejected, so the render falls back to the directory basename.
    ! grep -rq 'evil|w' .tarnished/
    ! grep -rq '{{' .tarnished/
}

@test "#316 legacy arbitrary work and unknown obsolete helper survive prune" {
    seed_scaffold
    bootstrap_and_commit
    mkdir -p src tests docs
    printf 'application\n' > src/work.py
    printf 'tests\n' > 'tests/test work.py'
    printf 'docs\n' > docs/notes.md
    printf 'private helper\n' > .devcontainer/scripts/obsolete.sh
    local files='{}' path hash
    for path in src/work.py 'tests/test work.py' docs/notes.md .devcontainer/scripts/obsolete.sh; do
        hash="sha256:$(sha256sum "$path" | cut -d' ' -f1)"
        files=$(jq --arg path "$path" --arg hash "$hash" '.[$path] = $hash' <<< "$files")
    done
    jq --argjson files "$files" '.manifest_version = 1 | .files += $files' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    run bash "$SETUP_SH" --upgrade --prune --force -y
    assert_success
    [[ "$(cat src/work.py)" == application ]]
    [[ "$(cat 'tests/test work.py')" == tests ]]
    [[ "$(cat docs/notes.md)" == docs ]]
    [[ "$(cat .devcontainer/scripts/obsolete.sh)" == 'private helper' ]]
    run jq -e '.manifest_version == 2 and (.files | has("src/work.py") or has(".devcontainer/scripts/obsolete.sh") | not)' .tarnished-manifest.json
    assert_success
}

@test "#318 trusted helper and AI settings update while application settings and seeds remain byte identical" {
    seed_scaffold
    bootstrap_and_commit
    printf 'older shipped helper\n' > .devcontainer/scripts/refresh-assets.sh
    local hash before
    hash="sha256:$(sha256sum .devcontainer/scripts/refresh-assets.sh | cut -d' ' -f1)"
    jq --arg hash "$hash" '.files[".devcontainer/scripts/refresh-assets.sh"] = $hash' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    before=$(sha256sum docker/Dockerfile.dev docker-compose.yml .devcontainer/devcontainer.json CLAUDE.md README.md)
    run bash "$SETUP_SH" --upgrade --force -y
    assert_success
    cmp .devcontainer/scripts/refresh-assets.sh "$SCRIPT_DIR/templates/core/.devcontainer/scripts/refresh-assets.sh"
    [[ "$(sha256sum docker/Dockerfile.dev docker-compose.yml .devcontainer/devcontainer.json CLAUDE.md README.md)" == "$before" ]]
}

@test "#316 conflict and removed helper baselines survive until successful prune" {
    seed_scaffold
    bootstrap_and_commit
    local old hash
    old=$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' .tarnished-manifest.json)
    printf '\n# local edit\n' >> .devcontainer/scripts/refresh-assets.sh
    printf 'obsolete distributed helper\n' > .devcontainer/scripts/obsolete.sh
    hash="sha256:$(sha256sum .devcontainer/scripts/obsolete.sh | cut -d' ' -f1)"
    jq --arg hash "$hash" '.files[".devcontainer/scripts/obsolete.sh"] = $hash' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    run bash "$SETUP_SH" --upgrade --force -y
    assert_success
    [[ "$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' .tarnished-manifest.json)" == "$old" ]]
    [[ "$(jq -r '.files[".devcontainer/scripts/obsolete.sh"]' .tarnished-manifest.json)" == "$hash" ]]
    run bash "$SETUP_SH" --upgrade --prune --force -y
    assert_success
    [[ ! -e .devcontainer/scripts/obsolete.sh ]]
    [[ "$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' .tarnished-manifest.json)" == "$old" ]]
}

@test "#316 failed staging cannot authorize pruning prior helpers" {
    seed_scaffold
    bootstrap_and_commit
    printf 'old delivered helper\n' > .devcontainer/scripts/obsolete.sh
    local hash before real_cp
    hash="sha256:$(sha256sum .devcontainer/scripts/obsolete.sh | cut -d' ' -f1)"
    jq --arg hash "$hash" '.files[".devcontainer/scripts/obsolete.sh"] = $hash' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    before=$(sha256sum .tarnished-manifest.json .devcontainer/scripts/obsolete.sh)
    mkdir mock-bin
    real_cp=$(command -v cp)
    cat > mock-bin/cp <<MOCK
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == */templates/core/.devcontainer/scripts/refresh-assets.sh ]]; then
        exit 1
    fi
done
exec "$real_cp" "\$@"
MOCK
    chmod +x mock-bin/cp
    run env PATH="$SCRATCH/mock-bin:$PATH" bash "$SETUP_SH" --upgrade --prune --force -y
    assert_failure
    [[ "$output" == *"Staging failed"* ]]
    [[ "$(sha256sum .tarnished-manifest.json .devcontainer/scripts/obsolete.sh)" == "$before" ]]
}

@test "#316 legacy helper deletion survives two upgrades without acquiring an ownership hash" {
    seed_scaffold
    bootstrap_and_commit
    local rel='.devcontainer/scripts/refresh-assets.sh'
    jq '.manifest_version = 1' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    rm "$rel"
    local iteration
    for iteration in 1 2; do
        run bash "$SETUP_SH" --upgrade --force -y
        assert_success
        [[ ! -e "$rel" ]]
        jq -e --arg rel "$rel" '.manifest_version == 2 and
            (.files | has($rel) | not) and (.deleted_paths | index($rel) != null)' \
            .tarnished-manifest.json
    done
}

@test "#316 repeated bootstrap preserves legacy deletion until an exact helper is explicitly restored" {
    seed_scaffold
    bootstrap_and_commit
    local rel='.devcontainer/scripts/refresh-assets.sh'
    jq '.manifest_version = 1' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    rm "$rel"
    local iteration
    for iteration in 1 2; do
        run bash "$SETUP_SH" --create-manifest -y
        assert_success
        [[ ! -e "$rel" ]]
        jq -e --arg rel "$rel" '(.files | has($rel) | not) and
            (.deleted_paths | index($rel) != null)' .tarnished-manifest.json
    done
    run bash "$SETUP_SH" --upgrade --force -y
    assert_success
    [[ ! -e "$rel" ]]
    cp "$SCRIPT_DIR/templates/core/$rel" "$rel"
    run bash "$SETUP_SH" --create-manifest -y
    assert_success
    jq -e --arg rel "$rel" '(.files | has($rel)) and
        ((.deleted_paths // []) | index($rel) == null)' .tarnished-manifest.json
}

@test "#316 setup refresh preserves a missing legacy updater on successive runs" {
    seed_scaffold
    bootstrap_and_commit
    local rel='.devcontainer/scripts/refresh-assets.sh'
    jq '.manifest_version = 1' .tarnished-manifest.json > manifest.tmp
    mv manifest.tmp .tarnished-manifest.json
    rm "$rel"
    mkdir -p .tarnished
    jq '.managed_paths = [] | .use_default_managed_paths = false' \
        "$SCRIPT_DIR/templates/agent-workflows/.tarnished/refresh.json" > .tarnished/refresh.json
    local iteration
    for iteration in 1 2; do
        run bash "$SETUP_SH" --refresh -y
        assert_success
        [[ ! -e "$rel" ]]
    done
}

@test "root upgrade at preceding distribution updates AI settings and retains current installed updater" {
    local ref=f136b29
    git -C "$SCRIPT_DIR" cat-file -e "$ref^{commit}" || skip 'historical distribution unavailable in shallow checkout'
    seed_scaffold
    mkdir .codex
    echo '# old settings' > .codex/config.toml
    bootstrap_and_commit
    run bash "$SETUP_SH" --upgrade --target-version "$ref" -y --prune
    assert_success
    git -C "$SCRIPT_DIR" show "$ref:templates/codex/.codex/config.toml" > "$SCRATCH/expected-settings"
    cmp .codex/config.toml "$SCRATCH/expected-settings"
    cmp .devcontainer/scripts/refresh-assets.sh "$SCRIPT_DIR/templates/core/.devcontainer/scripts/refresh-assets.sh"
    assert_equal "$(cat "$(find .tarnished/backups -path '*/.codex/config.toml')")" '# old settings'
    assert_equal "$(jq -r '.tarnished_version' .tarnished-manifest.json)" "$ref"
    assert_equal "$(jq -r '.tarnished_commit' .tarnished-manifest.json)" "$(git -C "$SCRIPT_DIR" rev-parse "$ref")"
    local manifest_before
    manifest_before=$(sha256sum .tarnished-manifest.json)
    git add -A
    git commit -qm pinned-upgrade
    run bash "$SETUP_SH" --upgrade --target-version "$ref" -y --prune
    assert_success
    assert_equal "$(sha256sum .tarnished-manifest.json)" "$manifest_before"
}

@test "clean successful module-only upgrade preserves root AI settings and backup tree" {
    mkdir "$SCRATCH/project"
    cd "$SCRATCH/project"
    bash "$SETUP_SH" --monorepo --module backend:python -y project >/dev/null
    git init -q
    git config user.name test
    git config user.email test@example.com
    printf 'root custom skill\n' > .claude/skills/issue/SKILL.md
    printf '{"custom":"root"}\n' > .claude/settings.json
    git add -A
    git commit -qm baseline
    local before
    before=$(sha256sum .claude/settings.json .claude/skills/issue/SKILL.md .tarnished/refresh.json)
    run bash "$SETUP_SH" --upgrade --module backend -y --prune
    assert_success
    assert_equal "$(sha256sum .claude/settings.json .claude/skills/issue/SKILL.md .tarnished/refresh.json)" "$before"
    [[ ! -e .tarnished/backups ]]
}

@test "failed pinned legacy helper upgrade never installs its destructive refresher" {
    local ref=46f7be7
    git -C "$SCRIPT_DIR" cat-file -e "$ref^{commit}" || skip 'historical distribution unavailable in shallow checkout'
    seed_scaffold
    bootstrap_and_commit
    local before
    before=$(sha256sum .tarnished-manifest.json)
    mkdir mock-bin
    cat > mock-bin/mv <<'MOCK'
#!/bin/bash
if [[ "${@: -1}" == "$SCRATCH/.devcontainer/scripts/setup_plugins.sh" ]]; then
    exit 1
fi
exec /usr/bin/mv "$@"
MOCK
    chmod +x mock-bin/mv
    run env PATH="$SCRATCH/mock-bin:$PATH" bash "$SETUP_SH" --upgrade --target-version "$ref" -y
    assert_failure
    assert_output --partial 'manifest_apply failed for: .devcontainer/scripts/setup_plugins.sh'
    cmp .devcontainer/scripts/refresh-assets.sh "$SCRIPT_DIR/templates/core/.devcontainer/scripts/refresh-assets.sh"
    assert_equal "$(sha256sum .tarnished-manifest.json)" "$before"
}

@test "historical bootstrap still compares the actual historical refresher bytes" {
    local ref=46f7be7 rel='.devcontainer/scripts/refresh-assets.sh' hash
    git -C "$SCRIPT_DIR" cat-file -e "$ref^{commit}" || skip 'historical distribution unavailable in shallow checkout'
    seed_scaffold
    git -C "$SCRIPT_DIR" show "$ref:templates/core/$rel" > "$rel"
    hash="sha256:$(sha256sum "$rel" | cut -d ' ' -f 1)"
    run bash "$SETUP_SH" --create-manifest --from-version "$ref" -y
    assert_success
    assert_equal "$(jq -r --arg rel "$rel" '.files[$rel]' .tarnished-manifest.json)" "$hash"
    assert_equal "sha256:$(sha256sum "$rel" | cut -d ' ' -f 1)" "$hash"
}
