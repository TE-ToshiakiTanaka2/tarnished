#!/usr/bin/env bats

# Real setup dispatch and current runtime updater, using a private distribution.
load 'libs/bats-support/load'
load 'libs/bats-assert/load'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    SCRATCH=$(mktemp -d)
    DIST="$SCRATCH/distribution"
    PROJECT="$SCRATCH/project"
    mkdir -p "$DIST/scripts" "$DIST/templates/core/.devcontainer/scripts" \
        "$DIST/templates/agent-workflows/.tarnished" "$PROJECT/.tarnished" \
        "$PROJECT/src" "$PROJECT/tests" "$PROJECT/docs" "$PROJECT/.claude" \
        "$PROJECT/.codex" "$PROJECT/.devcontainer/scripts"
    cp "$REPO_ROOT/setup.sh" "$DIST/setup.sh"
    cp -a "$REPO_ROOT/scripts/lib" "$DIST/scripts/lib"
    cp "$REPO_ROOT/templates/core/.devcontainer/scripts/refresh-assets.sh" \
        "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
    cp "$REPO_ROOT/templates/agent-workflows/.tarnished/refresh.json" \
        "$DIST/templates/agent-workflows/.tarnished/refresh.json"
    local source
    while IFS= read -r source; do
        if [[ "$source" == *.md ]]; then
            mkdir -p "$DIST/$(dirname "$source")"
            printf 'distributed %s\n' "$source" > "$DIST/$source"
        else
            mkdir -p "$DIST/$source/sample"
            printf 'distributed %s\n' "$source" > "$DIST/$source/sample/SKILL.md"
        fi
    done < <(jq -r '.managed_paths[].src' "$DIST/templates/agent-workflows/.tarnished/refresh.json")
    jq --arg cache "$SCRATCH/cache" '.clone_dir = $cache' \
        "$DIST/templates/agent-workflows/.tarnished/refresh.json" > "$PROJECT/.tarnished/refresh.json"
    echo 'software in progress' > "$PROJECT/src/work.py"
    echo 'developer tests' > "$PROJECT/tests/work.py"
    echo 'developer docs' > "$PROJECT/docs/work.md"
    echo '{"project":"custom"}' > "$PROJECT/.claude/settings.json"
    echo 'model = "developer-selected"' > "$PROJECT/.codex/config.toml"
    echo '{"postStartCommand":"custom hook"}' > "$PROJECT/.devcontainer/devcontainer.json"
    echo 'custom post script' > "$PROJECT/.devcontainer/scripts/post.sh"
    set_profile claude-main
    cd "$PROJECT"
}

teardown() {
    cd /
    [[ "$SCRATCH" == /tmp/* ]] && rm -rf "$SCRATCH"
}

set_profile() {
    jq -n --arg profile "$1" '{ai_profile:$profile, roles:{executor:{model:"developer-model"}}}' \
        > "$PROJECT/.tarnished/agent-profile.json"
}

project_owned_snapshot() {
    sha256sum "$PROJECT/src/work.py" "$PROJECT/tests/work.py" "$PROJECT/docs/work.md" \
        "$PROJECT/.claude/settings.json" "$PROJECT/.codex/config.toml" \
        "$PROJECT/.devcontainer/devcontainer.json" "$PROJECT/.devcontainer/scripts/post.sh" \
        "$PROJECT/.tarnished/agent-profile.json"
}

full_snapshot() {
    find "$PROJECT" -printf '%P %y %l\n' | LC_ALL=C sort
    find "$PROJECT" -type f -exec sha256sum {} + | LC_ALL=C sort
}

@test "bare existing-project rerun updates AI assets and preserves application settings and custom skills" {
    mkdir -p "$PROJECT/.claude/skills/custom"
    echo custom > "$PROJECT/.claude/skills/custom/SKILL.md"
    local before
    before=$(project_owned_snapshot)
    run bash "$DIST/setup.sh" -y
    assert_success
    [[ "$(project_owned_snapshot)" == "$before" ]]
    [[ "$(cat "$PROJECT/.claude/skills/custom/SKILL.md")" == custom ]]
    [[ -f "$PROJECT/.claude/skills/sample/SKILL.md" ]]
    [[ -f "$PROJECT/.tarnished/workflows/flow.md" ]]
    [[ ! -e "$PROJECT/.agents/skills" ]]
    [[ "$(jq -r '.manifest_version' "$PROJECT/.tarnished-manifest.json")" == 2 ]]
}

@test "refresh always executes the distribution updater and preserves unproven installed scripts" {
    printf '#!/bin/bash\ntouch "%s"\n' "$SCRATCH/unsafe-executed" \
        > "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    local before
    before=$(sha256sum "$PROJECT/.devcontainer/scripts/refresh-assets.sh")
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ ! -e "$SCRATCH/unsafe-executed" ]]
    [[ "$(sha256sum "$PROJECT/.devcontainer/scripts/refresh-assets.sh")" == "$before" ]]
    [[ -f "$PROJECT/.claude/skills/sample/SKILL.md" ]]
    assert_output --partial 'Container-start updater remains old or locally edited'
    assert_output --partial "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
}

@test "refresh dry-run including missing configuration leaves all target entries unchanged" {
    rm "$PROJECT/.tarnished/refresh.json"
    local before
    before=$(full_snapshot)
    run bash "$DIST/setup.sh" --refresh --dry-run -y
    assert_success
    [[ "$(full_snapshot)" == "$before" ]]
    [[ ! -e "$SCRATCH/cache" ]]
    assert_output --partial 'Install default refresh configuration'
    assert_output --partial '.claude/skills/sample/SKILL.md'
}

@test "malformed project markers fail safely without falling back to scaffolding" {
    printf 'invalid json' > "$PROJECT/.tarnished/refresh.json"
    local before
    before=$(full_snapshot)
    run bash "$DIST/setup.sh" -y
    assert_failure
    assert_output --partial 'Malformed project marker'
    [[ "$(full_snapshot)" == "$before" ]]
}

@test "symlink project markers fail before maintenance writes" {
    rm "$PROJECT/.tarnished/refresh.json"
    ln -s "$SCRATCH/outside.json" "$PROJECT/.tarnished/refresh.json"
    local before
    before=$(full_snapshot)
    run bash "$DIST/setup.sh" -y
    assert_failure
    assert_output --partial 'Unsafe project marker'
    [[ "$(full_snapshot)" == "$before" && ! -e "$SCRATCH/outside.json" ]]
}

@test "explicit scaffold flags cannot re-scaffold an existing target" {
    local before flag
    before=$(full_snapshot)
    for flag in --overwrite --codex --monorepo; do
        run bash "$DIST/setup.sh" "$flag" -y
        assert_failure
        assert_output --partial 'scaffold flags'
        [[ "$(full_snapshot)" == "$before" ]]
    done
    run bash "$DIST/setup.sh" --lang python -y
    assert_failure
    [[ "$(full_snapshot)" == "$before" ]]
}

@test "codex-main and dual refresh selected capabilities while preserving profile and model choices" {
    local profile before
    for profile in codex-main dual; do
        set_profile "$profile"
        before=$(project_owned_snapshot)
        run bash "$DIST/setup.sh" --refresh -y
        assert_success
        [[ "$(project_owned_snapshot)" == "$before" ]]
        [[ -f "$PROJECT/.agents/skills/sample/SKILL.md" ]]
        [[ -f "$PROJECT/.claude/skills/sample/SKILL.md" ]]
        [[ -f "$PROJECT/.tarnished/workflows/flow.md" ]]
    done
}

@test "claude-main retains existing Codex capability during refresh" {
    mkdir -p "$PROJECT/.agents/skills/custom"
    echo custom > "$PROJECT/.agents/skills/custom/SKILL.md"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ -f "$PROJECT/.agents/skills/sample/SKILL.md" ]]
    [[ "$(cat "$PROJECT/.agents/skills/custom/SKILL.md")" == custom ]]
}

@test "known legacy catalog adopts evolving defaults while preserving upstream and cache settings" {
    jq --slurpfile legacy "$DIST/scripts/lib/refresh-legacy.json" \
        '.managed_paths = $legacy[0].managed_path_catalogs[0] | del(.use_default_managed_paths) |
        .upstream = {repo_url:"https://example.invalid/custom.git",branch:"project-branch"}' \
        "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    mv "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ "$(jq -r '.use_default_managed_paths' "$PROJECT/.tarnished/refresh.json")" == true ]]
    [[ "$(jq -r '.upstream.repo_url' "$PROJECT/.tarnished/refresh.json")" == https://example.invalid/custom.git ]]
    [[ "$(jq -r '.upstream.branch' "$PROJECT/.tarnished/refresh.json")" == project-branch ]]
    [[ "$(jq -r '.clone_dir' "$PROJECT/.tarnished/refresh.json")" == "$SCRATCH/cache" ]]
}

@test "custom and intentionally empty catalogs remain byte-identical" {
    local expression before
    for expression in '.managed_paths = [.managed_paths[1]]' '.managed_paths = []'; do
        jq "$expression | del(.use_default_managed_paths)" \
            "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
        mv "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
        before=$(sha256sum "$PROJECT/.tarnished/refresh.json")
        run bash "$DIST/setup.sh" --refresh -y
        assert_success
        [[ "$(sha256sum "$PROJECT/.tarnished/refresh.json")" == "$before" ]]
        assert_output --partial 'Preserving custom managed_paths'
    done
}

@test "known legacy helper migrates and v2 installed proof supports the next helper release" {
    local commit before
    commit=$(jq -r '.helper_hashes[0].commit' "$DIST/scripts/lib/refresh-legacy.json")
    git -C "$REPO_ROOT" show "$commit:templates/core/.devcontainer/scripts/refresh-assets.sh" \
        > "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    before=$(project_owned_snapshot)
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    cmp "$PROJECT/.devcontainer/scripts/refresh-assets.sh" \
        "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
    printf '\n# next safe updater release\n' >> "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    cmp "$PROJECT/.devcontainer/scripts/refresh-assets.sh" \
        "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
    [[ "$(project_owned_snapshot)" == "$before" ]]
    [[ "$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' "$PROJECT/.tarnished-manifest.json")" == \
        "sha256:$(sha256sum "$PROJECT/.devcontainer/scripts/refresh-assets.sh" | cut -d ' ' -f 1)" ]]
}

@test "trusted helper developer edits and deletions survive subsequent refresh" {
    bash "$DIST/setup.sh" --refresh -y >/dev/null
    local baseline
    baseline=$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' "$PROJECT/.tarnished-manifest.json")
    echo '# local updater edit' >> "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    local before
    before=$(sha256sum "$PROJECT/.devcontainer/scripts/refresh-assets.sh")
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ "$(sha256sum "$PROJECT/.devcontainer/scripts/refresh-assets.sh")" == "$before" ]]
    [[ "$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' "$PROJECT/.tarnished-manifest.json")" == "$baseline" ]]
    rm "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ ! -e "$PROJECT/.devcontainer/scripts/refresh-assets.sh" ]]
    [[ "$(jq -r '.files[".devcontainer/scripts/refresh-assets.sh"]' "$PROJECT/.tarnished-manifest.json")" == "$baseline" ]]
}
