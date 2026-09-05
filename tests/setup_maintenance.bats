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

@test "explicit false preserves a known legacy catalog byte for byte" {
    jq --slurpfile old "$DIST/scripts/lib/refresh-legacy.json" \
        '.use_default_managed_paths = false | .managed_paths = $old[0].managed_path_catalogs[0]' \
        "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    mv "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    local before
    before=$(sha256sum "$PROJECT/.tarnished/refresh.json")
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ "$(sha256sum "$PROJECT/.tarnished/refresh.json")" == "$before" ]]
    assert_output --partial 'Preserving custom managed_paths'
}

@test "actual scaffolded workflow contracts adopt and update without unresolved profile placeholders" {
    # Use real template bytes instead of this suite's small synthetic catalog.
    rm -rf "$DIST/templates"
    cp -a "$REPO_ROOT/templates" "$DIST/templates"
    local fresh="$SCRATCH/fresh"
    mkdir "$fresh"
    cd "$fresh"
    run bash "$DIST/setup.sh" --lang go --ai-profile codex-main -y fresh
    assert_success
    cmp .tarnished/workflows/README.md "$DIST/templates/agent-workflows/.tarnished/workflows/README.md"
    cmp .tarnished/workflows/review.md "$DIST/templates/agent-workflows/.tarnished/workflows/review.md"
    local profile_before
    profile_before=$(sha256sum .tarnished/agent-profile.json)
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    jq -e '.entries[".tarnished/workflows/README.md"].origin == "upstream" and .entries[".tarnished/workflows/review.md"].origin == "upstream"' .tarnished/refresh-state.json
    printf '\nUpdated shared review contract.\n' >> "$DIST/templates/agent-workflows/.tarnished/workflows/review.md"
    printf '\nUpdated shared workflow introduction.\n' >> "$DIST/templates/agent-workflows/.tarnished/workflows/README.md"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    cmp .tarnished/workflows/README.md "$DIST/templates/agent-workflows/.tarnished/workflows/README.md"
    cmp .tarnished/workflows/review.md "$DIST/templates/agent-workflows/.tarnished/workflows/review.md"
    ! grep -q '{{' .tarnished/workflows/README.md .tarnished/workflows/review.md
    [[ "$(sha256sum .tarnished/agent-profile.json)" == "$profile_before" ]]
}

@test "refresh preserves legacy helper deletion and retains other v2 tombstones when recording helper proof" {
    local helper='.devcontainer/scripts/refresh-assets.sh' other='.devcontainer/scripts/deleted.sh' hash
    hash="sha256:$(sha256sum "$DIST/templates/core/$helper" | cut -d' ' -f1)"
    jq -n --arg helper "$helper" --arg hash "$hash" \
        '{manifest_version:1,tarnished_version:"legacy",tarnished_commit:"",created_at:"",scaffold_options:{},files:{($helper):$hash}}' \
        > "$PROJECT/.tarnished-manifest.json"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ ! -e "$PROJECT/$helper" ]]
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ ! -e "$PROJECT/$helper" ]]
    # An explicit restoration may be adopted; another deletion still survives
    # the manifest writer used for updater baseline installation.
    cp "$DIST/templates/core/$helper" "$PROJECT/$helper"
    jq -n --arg helper "$helper" --arg other "$other" --arg hash "$hash" \
        '{manifest_version:2,tarnished_version:"prior",tarnished_commit:"",created_at:"",scaffold_options:{},files:{($helper):$hash},deleted_paths:[$other]}' \
        > "$PROJECT/.tarnished-manifest.json"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    jq -e --arg other "$other" '.deleted_paths == [$other]' "$PROJECT/.tarnished-manifest.json"
    [[ ! -e "$PROJECT/$other" ]]
}

@test "helper migration preserves edits made during temporary copy and retains baseline" {
    bash "$DIST/setup.sh" --refresh -y >/dev/null
    printf '\n# next updater\n' >> "$DIST/templates/core/.devcontainer/scripts/refresh-assets.sh"
    local before real_cp
    before=$(sha256sum "$PROJECT/.tarnished-manifest.json")
    real_cp=$(command -v cp)
    mkdir "$SCRATCH/race-bin"
    cat > "$SCRATCH/race-bin/cp" <<MOCK
#!/bin/bash
"$real_cp" "\$@" || exit 1
for arg in "\$@"; do
    if [[ "\$arg" == */.refresh-updater.* ]]; then
        printf '# developer saved during update\\n' > "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    fi
done
MOCK
    chmod +x "$SCRATCH/race-bin/cp"
    run env PATH="$SCRATCH/race-bin:$PATH" bash "$DIST/setup.sh" --refresh -y
    assert_failure
    [[ "$(cat "$PROJECT/.devcontainer/scripts/refresh-assets.sh")" == '# developer saved during update' ]]
    [[ "$(sha256sum "$PROJECT/.tarnished-manifest.json")" == "$before" ]]
    assert_output --partial 'Updater changed during preparation'
}

@test "new and deletion-preserved updater diagnostics distinguish wiring from file installation" {
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    assert_output --partial 'New updater file does not establish container-start wiring'
    assert_output --partial 'Existing hooks/settings are preserved'
    rm "$PROJECT/.devcontainer/scripts/refresh-assets.sh"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    assert_output --partial 'updater is absent; preserving recorded deletion'
    refute_output --partial 'updater remains old or locally edited'
}

@test "self-checkout and nested source refresh reject overlap before any target mutation" {
    # Disposable distribution self-hosts a legacy marker and old catalog.
    mkdir -p "$DIST/.tarnished"
    jq -n '{manifest_version:1,tarnished_version:"legacy",tarnished_commit:"",created_at:"",scaffold_options:{},files:{}}' \
        > "$DIST/.tarnished-manifest.json"
    jq --slurpfile legacy "$DIST/scripts/lib/refresh-legacy.json" \
        'del(.use_default_managed_paths) | .managed_paths=$legacy[0].managed_path_catalogs[0]' \
        "$DIST/templates/agent-workflows/.tarnished/refresh.json" > "$DIST/.tarnished/refresh.json"
    local before
    before=$(find "$DIST" -type f -exec sha256sum {} + | LC_ALL=C sort)
    cd "$DIST"
    run bash "$DIST/setup.sh" --refresh -y
    assert_failure
    assert_output --partial 'Refresh source/target overlap'
    [[ "$(find "$DIST" -type f -exec sha256sum {} + | LC_ALL=C sort)" == "$before" ]]
    [[ ! -e "$DIST/.devcontainer" ]]
    mkdir "$DIST/downstream"
    cd "$DIST/downstream"
    run bash "$DIST/setup.sh" --refresh -y
    assert_failure
    assert_output --partial 'Refresh source/target overlap'
    [[ -z "$(find . -mindepth 1 -print)" ]]
}

@test "ordinary project beneath a host alias refreshes while a symlink root leaf is rejected" {
    mkdir "$SCRATCH/host"
    mv "$PROJECT" "$SCRATCH/host/project"
    PROJECT="$SCRATCH/host/project"
    ln -s "$SCRATCH/host" "$SCRATCH/host-alias"
    cd "$SCRATCH/host-alias/project"
    run bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ -f "$PROJECT/.claude/skills/sample/SKILL.md" ]]
    ln -s "$PROJECT" "$SCRATCH/project-link"
    cd "$SCRATCH/project-link"
    run bash "$DIST/setup.sh" --refresh -y
    assert_failure
    assert_output --partial 'Unsafe project root'
}

@test "bare refresh at a real monorepo root preserves module trees and explicit add-module still works" {
    rm -rf "$DIST/templates"
    cp -a "$REPO_ROOT/templates" "$DIST/templates"
    local monorepo="$SCRATCH/monorepo"
    mkdir "$monorepo"
    cd "$monorepo"
    run bash "$DIST/setup.sh" --monorepo --module backend:go -y monorepo
    assert_success
    printf 'package backend // work in progress\n' > backend/work.go
    mkdir -p backend/tests backend/docs
    printf 'developer test\n' > backend/tests/test.txt
    printf 'developer document\n' > backend/docs/design.md
    local before
    before=$(find backend -type f -exec sha256sum {} + | LC_ALL=C sort)
    run bash "$DIST/setup.sh" -y
    assert_success
    [[ "$(find backend -type f -exec sha256sum {} + | LC_ALL=C sort)" == "$before" ]]
    jq -e '.entries[".tarnished/workflows/flow.md"].origin == "upstream"' .tarnished/refresh-state.json
    run bash "$DIST/setup.sh" --add-module frontend --lang node -y
    assert_success
    [[ "$(find backend -type f -exec sha256sum {} + | LC_ALL=C sort)" == "$before" ]]
    jq -e '[.modules[].name] == ["backend","frontend"]' modules.json
}

@test "setup refresh works with BSD-like mv and shasum-only hashing" {
    local toolbox="$SCRATCH/bsd-bin" tool real_mv
    mkdir "$toolbox"
    # Limit discovery to portable commands and shasum, deliberately omitting
    # GNU realpath and sha256sum. Host Perl remains shasum's shebang runtime.
    for tool in bash jq git cut cp dirname mktemp mkdir rm sed tr find basename date head cat sort awk grep shasum uname; do
        ln -s "$(command -v "$tool")" "$toolbox/$tool"
    done
    real_mv=$(command -v mv)
    cat > "$toolbox/mv" <<MOCK
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == -*T* ]]; then exit 64; fi
done
exec "$real_mv" "\$@"
MOCK
    chmod +x "$toolbox/mv"
    rm "$PROJECT/.tarnished/refresh.json"
    run env PATH="$toolbox" bash "$DIST/setup.sh" --refresh -y
    assert_success
    [[ -f "$PROJECT/.claude/skills/sample/SKILL.md" ]]
    [[ -f "$PROJECT/.devcontainer/scripts/refresh-assets.sh" ]]
    jq -e '.files[".devcontainer/scripts/refresh-assets.sh"] | test("^sha256:[0-9a-f]{64}$")' "$PROJECT/.tarnished-manifest.json"
}

@test "legacy configuration edits during preparation survive migration" {
    jq --slurpfile old "$DIST/scripts/lib/refresh-legacy.json" \
        'del(.use_default_managed_paths) | .managed_paths=$old[0].managed_path_catalogs[0]' \
        "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    mv "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    local real_mktemp
    real_mktemp=$(command -v mktemp)
    mkdir "$SCRATCH/config-race-bin"
    cat > "$SCRATCH/config-race-bin/mktemp" <<MOCK
#!/bin/bash
for arg in "\$@"; do
    if [[ "\$arg" == */.refresh-config.* ]]; then
        printf '{"developer":"concurrent edit"}\\n' > "$PROJECT/.tarnished/refresh.json"
    fi
done
exec "$real_mktemp" "\$@"
MOCK
    chmod +x "$SCRATCH/config-race-bin/mktemp"
    run env PATH="$SCRATCH/config-race-bin:$PATH" bash "$DIST/setup.sh" --refresh -y
    assert_failure
    [[ "$(cat "$PROJECT/.tarnished/refresh.json")" == '{"developer":"concurrent edit"}' ]]
    [[ ! -e "$PROJECT/.devcontainer/scripts/refresh-assets.sh" ]]
    [[ ! -e "$PROJECT/.tarnished-manifest.json" ]]
    assert_output --partial 'Refresh configuration changed during preparation'
}

@test "eligible backslash helper names survive repeated bootstrap and upgrade without renamed ownership keys" {
    rm -rf "$DIST/templates"
    cp -a "$REPO_ROOT/templates" "$DIST/templates"
    local helper='.devcontainer/scripts/tool\name.sh'
    printf '#!/bin/bash\nprintf "helper\\n"\n' > "$DIST/templates/core/$helper"
    cp "$DIST/templates/core/$helper" "$PROJECT/$helper"
    run bash "$DIST/setup.sh" --create-manifest -y
    assert_success
    run bash "$DIST/setup.sh" --create-manifest -y
    assert_success
    run bash "$DIST/setup.sh" --upgrade --force -y
    assert_success
    run bash "$DIST/setup.sh" --upgrade --force -y
    assert_success
    jq -e --arg helper "$helper" '.files | keys | map(select(contains("\\"))) == [$helper]' "$PROJECT/.tarnished-manifest.json"
    cmp "$PROJECT/$helper" "$DIST/templates/core/$helper"
}
