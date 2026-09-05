#!/usr/bin/env bats

# Unit tests for #265: scripts/lib/common.sh sha256_file + manifest recording
# extension, and scripts/lib/manifest.sh helpers.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    source "${SCRIPT_DIR}/scripts/lib/common.sh"
    source "${SCRIPT_DIR}/scripts/lib/manifest.sh"

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

# Existing apply fixtures take their decision observation before invoking the API.
apply_fixture() {
    local current="" desired=""
    [[ ! -f "$4" || -L "$4" ]] || current=$(sha256_file "$4")
    [[ ! -f "$3" || -L "$3" ]] || desired=$(sha256_file "$3")
    manifest_apply "$1" "$2" "$3" "$4" "$current" "$desired"
}

# -----------------------------------------------------------------------------
# sha256_file
# -----------------------------------------------------------------------------

@test "sha256_file emits sha256:<64 hex>" {
    echo "hello" > "$SCRATCH/a.txt"
    run sha256_file "$SCRATCH/a.txt"
    [[ "$status" -eq 0 ]]
    [[ "$output" == sha256:* ]]
    [[ ${#output} -eq $((7 + 64)) ]]
}

@test "sha256_file is deterministic" {
    echo "same content" > "$SCRATCH/a.txt"
    echo "same content" > "$SCRATCH/b.txt"
    h1=$(sha256_file "$SCRATCH/a.txt")
    h2=$(sha256_file "$SCRATCH/b.txt")
    [[ "$h1" == "$h2" ]]
}

@test "sha256_file detects content change" {
    echo "v1" > "$SCRATCH/a.txt"
    h1=$(sha256_file "$SCRATCH/a.txt")
    echo "v2" > "$SCRATCH/a.txt"
    h2=$(sha256_file "$SCRATCH/a.txt")
    [[ "$h1" != "$h2" ]]
}

@test "sha256_file errors on missing file" {
    run sha256_file "$SCRATCH/missing.txt"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# manifest_path / manifest_exists
# -----------------------------------------------------------------------------

@test "manifest_path returns <root>/.tarnished-manifest.json" {
    run manifest_path "/tmp/myproj"
    [[ "$output" == "/tmp/myproj/.tarnished-manifest.json" ]]
}

@test "manifest_exists is false for missing manifest" {
    run manifest_exists "$SCRATCH"
    [[ "$status" -ne 0 ]]
}

@test "manifest_exists is true once file is present" {
    : > "$SCRATCH/.tarnished-manifest.json"
    run manifest_exists "$SCRATCH"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Recording lifecycle
# -----------------------------------------------------------------------------

@test "recording is off by default" {
    [[ "$MANIFEST_RECORDING" == false ]]
}

@test "manifest_recording_start enables recording and clears state" {
    MANIFEST_TRACKED["stale"]="sha256:dead"
    manifest_recording_start "$SCRATCH"
    [[ "$MANIFEST_RECORDING" == true ]]
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]
}

@test "copy records successful runtime helpers but never application seeds" {
    mkdir -p "$SCRATCH/.devcontainer/scripts"
    echo data > "$SCRATCH/src.txt"
    manifest_recording_start "$SCRATCH"
    copy_with_confirm "$SCRATCH/src.txt" "$SCRATCH/.devcontainer/scripts/helper.sh"
    copy_with_confirm "$SCRATCH/src.txt" "$SCRATCH/.devcontainer/scripts/post.sh"
    copy_with_confirm "$SCRATCH/src.txt" "$SCRATCH/app.py"
    [[ ${#MANIFEST_TRACKED[@]} -eq 1 ]]
    [[ "${MANIFEST_TRACKED[.devcontainer/scripts/helper.sh]}" == "$(sha256_file "$SCRATCH/src.txt")" ]]
}

@test "declined and failed helper copies establish no provenance" {
    mkdir -p "$SCRATCH/.devcontainer/scripts"
    echo custom > "$SCRATCH/.devcontainer/scripts/helper.sh"
    echo upstream > "$SCRATCH/source"
    manifest_recording_start "$SCRATCH"
    skip_confirm=true
    copy_with_confirm "$SCRATCH/source" "$SCRATCH/.devcontainer/scripts/helper.sh"
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]
    cp() { return 1; }
    if copy_with_confirm "$SCRATCH/source" "$SCRATCH/.devcontainer/scripts/new.sh"; then
        fail "copy failure was swallowed"
    fi
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]
}

@test "rehash visits only successfully delivered helpers after rendering" {
    mkdir -p "$SCRATCH/.devcontainer/scripts"
    echo original > "$SCRATCH/source"
    manifest_recording_start "$SCRATCH"
    copy_with_confirm "$SCRATCH/source" "$SCRATCH/.devcontainer/scripts/helper.sh"
    echo rendered > "$SCRATCH/.devcontainer/scripts/helper.sh"
    echo custom > "$SCRATCH/.devcontainer/scripts/custom.sh"
    manifest_recording_rehash
    [[ ${#MANIFEST_TRACKED[@]} -eq 1 ]]
    [[ "${MANIFEST_TRACKED[.devcontainer/scripts/helper.sh]}" == "$(sha256_file "$SCRATCH/.devcontainer/scripts/helper.sh")" ]]
}

@test "positive policy rejects seeds sidecars traversal and supports module helpers" {
    local rel
    for rel in src/main.rs tests/app.py README.md .codex/config.toml \
        .agents/skills/flow/SKILL.md .devcontainer/scripts/post.sh \
        .devcontainer/scripts/custom.local/helper.sh ../.devcontainer/scripts/h.sh \
        /tmp/.devcontainer/scripts/h.sh .devcontainer//scripts/h.sh; do
        ! _manifest_path_eligible "$rel"
    done
    _manifest_path_eligible '.devcontainer/scripts/nested/helper with space.sh'
    _manifest_path_eligible 'modules/my app/.devcontainer/scripts/helper.sh'
}

@test "private inventory includes only eligible helper files and respects scopes" {
    mkdir -p "$SCRATCH/.devcontainer/scripts" "$SCRATCH/module/.devcontainer/scripts"
    echo a > "$SCRATCH/.devcontainer/scripts/helper.sh"
    echo b > "$SCRATCH/module/.devcontainer/scripts/helper.sh"
    echo c > "$SCRATCH/app.py"
    echo d > "$SCRATCH/.devcontainer/scripts/post.sh"
    run manifest_walk_directory "$SCRATCH" module
    [[ "$status" -eq 0 ]]
    [[ "$output" == .devcontainer/scripts/helper.sh$'\t'sha256:* ]]
    [[ "$output" != *module/* && "$output" != *app.py* && "$output" != *post.sh* ]]
}

# -----------------------------------------------------------------------------
# manifest_decide — full FR-4 8-row state table
# -----------------------------------------------------------------------------

@test "manifest_decide row 1: NOOP (unchanged & unedited)" {
    [[ "$(manifest_decide sha256:a sha256:a sha256:a)" == "NOOP" ]]
}

@test "manifest_decide row 2: UPDATE (upstream changed, unedited)" {
    [[ "$(manifest_decide sha256:a sha256:a sha256:b)" == "UPDATE" ]]
}

@test "manifest_decide row 3: SKIP_EDITED (upstream changed, edited)" {
    [[ "$(manifest_decide sha256:a sha256:b sha256:c)" == "SKIP_EDITED" ]]
}

@test "manifest_decide row 3 sub: SKIP_EDITED (upstream unchanged, edited)" {
    # Edge: new == old but current differs. Treat as edited for safety.
    [[ "$(manifest_decide sha256:a sha256:b sha256:a)" == "SKIP_EDITED" ]]
}

@test "manifest_decide row 4: NEW (added upstream, no local file)" {
    [[ "$(manifest_decide '' '' sha256:a)" == "NEW" ]]
}

@test "manifest_decide row 5: SKIP_NEW_CONFLICT (added upstream, user has file)" {
    [[ "$(manifest_decide '' sha256:b sha256:a)" == "SKIP_NEW_CONFLICT" ]]
}

@test "manifest_decide row 6 default: LEAVE_REMOVED (removed upstream, unedited)" {
    PRUNE_ENABLED=false
    [[ "$(manifest_decide sha256:a sha256:a '')" == "LEAVE_REMOVED" ]]
}

@test "manifest_decide row 6 with --prune: PRUNE" {
    PRUNE_ENABLED=true
    [[ "$(manifest_decide sha256:a sha256:a '')" == "PRUNE" ]]
}

@test "manifest_decide row 7: LEAVE_REMOVED (removed upstream, edited — never prune)" {
    PRUNE_ENABLED=true
    [[ "$(manifest_decide sha256:a sha256:b '')" == "LEAVE_REMOVED" ]]
}

@test "manifest_decide row 8: SKIP_USER_DELETED" {
    [[ "$(manifest_decide sha256:a '' sha256:a)" == "SKIP_USER_DELETED" ]]
}

@test "manifest_decide void case: NOOP (file in neither manifest)" {
    [[ "$(manifest_decide '' '' '')" == "NOOP" ]]
}

# -----------------------------------------------------------------------------
# manifest_write + manifest_read round-trip
# -----------------------------------------------------------------------------

@test "v2 round-trip preserves spaces and unchanged state bytes" {
    manifest_recording_start "$SCRATCH"
    local rel='.devcontainer/scripts/helper with space.sh'
    local hash="sha256:$(printf '%064d' 0)"
    MANIFEST_TRACKED["$rel"]="$hash"
    manifest_write "$SCRATCH" v1 abc '{}'
    local before
    jq '.created_at = "2000-01-01T00:00:00Z"' "$SCRATCH/.tarnished-manifest.json" > "$SCRATCH/dated"
    mv "$SCRATCH/dated" "$SCRATCH/.tarnished-manifest.json"
    before=$(sha256_file "$SCRATCH/.tarnished-manifest.json")
    manifest_write "$SCRATCH" v1 abc '{}'
    [[ "$(sha256_file "$SCRATCH/.tarnished-manifest.json")" == "$before" ]]
    run manifest_read "$SCRATCH"
    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s' "$output" | jq -r .manifest_version)" == 2 ]]
    [[ "$(printf '%s' "$output" | jq -r --arg rel "$rel" '.files[$rel]')" == "$hash" ]]
}

@test "manifest read rejects malformed state traversal hashes and unsupported versions" {
    local hash="sha256:$(printf '%064d' 0)" input
    for input in 'not json' '{"manifest_version":999,"files":{},"scaffold_options":{}}' \
        '{"manifest_version":2,"files":{".devcontainer/scripts/a.sh":"sha256:bad"},"scaffold_options":{}}' \
        "{\"manifest_version\":1,\"files\":{\"../escape\":\"$hash\"},\"scaffold_options\":{}}" \
        "{\"manifest_version\":2,\"files\":{\"src/app.py\":\"$hash\"},\"scaffold_options\":{}}" \
        "{\"manifest_version\":1,\"files\":{\"bad\\nkey\":\"$hash\"},\"scaffold_options\":{}}"; do
        if printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
            printf '%s' "$input" | jq '. + {tarnished_version:"v1", tarnished_commit:"abc", created_at:"2026-01-01"}' > "$SCRATCH/.tarnished-manifest.json"
        else
            printf '%s' "$input" > "$SCRATCH/.tarnished-manifest.json"
        fi
        run manifest_read "$SCRATCH"
        [[ "$status" -ne 0 ]]
    done
}

@test "manifest read and write reject symlink metadata and parent paths" {
    mkdir -p "$SCRATCH/project" "$SCRATCH/outside"
    echo keep > "$SCRATCH/outside/state"
    ln -s "$SCRATCH/outside/state" "$SCRATCH/project/.tarnished-manifest.json"
    run manifest_read "$SCRATCH/project"
    [[ "$status" -ne 0 ]]
    run manifest_write "$SCRATCH/project" v1 abc '{}'
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$SCRATCH/outside/state")" == keep ]]
    ln -s "$SCRATCH/project" "$SCRATCH/link"
    ! manifest_safe_path "$SCRATCH/link" '.devcontainer/scripts/helper.sh'
}

@test "legacy arbitrary claims cannot become ownership but exact helpers are adopted" {
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo keep > "$SCRATCH/project/app.py"
    echo same > "$SCRATCH/project/.devcontainer/scripts/good.sh"
    cp "$SCRATCH/project/.devcontainer/scripts/good.sh" "$SCRATCH/staging/.devcontainer/scripts/good.sh"
    echo custom > "$SCRATCH/project/.devcontainer/scripts/edited.sh"
    echo upstream > "$SCRATCH/staging/.devcontainer/scripts/edited.sh"
    local old
    old=$(jq -n --arg hash "$(sha256_file "$SCRATCH/project/app.py")" \
        '{manifest_version:1,files:{"app.py":$hash,".devcontainer/scripts/edited.sh":$hash}}')
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ ${#MANIFEST_TRACKED[@]} -eq 1 ]]
    [[ -n "${MANIFEST_TRACKED[.devcontainer/scripts/good.sh]:-}" ]]
    [[ "$(cat "$SCRATCH/project/app.py")" == keep ]]
    [[ "$(cat "$SCRATCH/project/.devcontainer/scripts/edited.sh")" == custom ]]
}

@test "bootstrap retains v2 baselines on edited deleted and obsolete helpers" {
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo custom > "$SCRATCH/project/.devcontainer/scripts/edited.sh"
    echo upstream > "$SCRATCH/staging/.devcontainer/scripts/edited.sh"
    local hash="sha256:$(printf '%064d' 0)" old
    old=$(jq -n --arg hash "$hash" '{manifest_version:2,files:{
        ".devcontainer/scripts/edited.sh":$hash,
        ".devcontainer/scripts/deleted.sh":$hash,
        ".devcontainer/scripts/obsolete.sh":$hash}}')
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ ${#MANIFEST_TRACKED[@]} -eq 3 ]]
    [[ "${MANIFEST_TRACKED[.devcontainer/scripts/edited.sh]}" == "$hash" ]]
    [[ "${MANIFEST_TRACKED[.devcontainer/scripts/deleted.sh]}" == "$hash" ]]
    [[ "${MANIFEST_TRACKED[.devcontainer/scripts/obsolete.sh]}" == "$hash" ]]
}

@test "identical desired bytes are acknowledged with or without a prior baseline" {
    [[ "$(manifest_decide '' sha256:a sha256:a)" == NOOP ]]
    [[ "$(manifest_decide sha256:b sha256:a sha256:a)" == NOOP ]]
}

@test "apply atomically installs eligible helpers with executable mode and safely prunes" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project" "$SCRATCH/staging/.devcontainer/scripts"
    echo upstream > "$SCRATCH/staging/$rel"
    chmod +x "$SCRATCH/staging/$rel"
    apply_fixture NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    [[ -x "$SCRATCH/project/$rel" ]]
    [[ "$(cat "$SCRATCH/project/$rel")" == upstream ]]
    apply_fixture PRUNE "$rel" '' "$SCRATCH/project/$rel"
    [[ ! -e "$SCRATCH/project/$rel" ]]
    [[ -d "$SCRATCH/project/.devcontainer/scripts" ]]
}

@test "apply rejects source target symlinks collisions traversal and non-runtime seeds" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo keep > "$SCRATCH/outside"
    ln -s "$SCRATCH/outside" "$SCRATCH/project/$rel"
    echo new > "$SCRATCH/staging/$rel"
    run apply_fixture UPDATE "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/outside")" == keep ]]
    rm "$SCRATCH/project/$rel"
    mkdir "$SCRATCH/project/$rel"
    run apply_fixture UPDATE "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    [[ "$status" -ne 0 ]]
    rmdir "$SCRATCH/project/$rel"
    rm "$SCRATCH/staging/$rel"
    ln -s "$SCRATCH/outside" "$SCRATCH/staging/$rel"
    run apply_fixture NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    [[ "$status" -ne 0 && ! -e "$SCRATCH/project/$rel" ]]
    run apply_fixture PRUNE app.py '' "$SCRATCH/outside"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/outside")" == keep ]]
}

@test "dry-run apply leaves target hierarchy absent" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project" "$SCRATCH/staging/.devcontainer/scripts"
    echo new > "$SCRATCH/staging/$rel"
    DRY_RUN=true
    apply_fixture NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    [[ ! -e "$SCRATCH/project/.devcontainer" ]]
}

@test "serialization over argument limits uses valid eligible entries via stdin" {
    manifest_recording_start "$SCRATCH"
    local i hash="sha256:$(printf '%064d' 0)" prefix
    prefix=$(printf '%0100d' 0)
    for ((i = 0; i < 250; i++)); do
        MANIFEST_TRACKED[".devcontainer/scripts/$prefix/$prefix/$prefix/$prefix/$prefix/helper_${i}.sh"]="$hash"
    done
    manifest_write "$SCRATCH" v1 abc '{}'
    [[ "$(jq '.files | length' "$SCRATCH/.tarnished-manifest.json")" -eq 250 ]]
}

@test "scaffold copy and directory copy reject dangling links and linked ancestors before mutation" {
    mkdir -p "$SCRATCH/project" "$SCRATCH/outside" "$SCRATCH/source"
    echo upstream > "$SCRATCH/source/helper.sh"
    manifest_recording_start "$SCRATCH/project"
    ln -s "$SCRATCH/outside/missing" "$SCRATCH/project/file"
    run copy_with_confirm "$SCRATCH/source/helper.sh" "$SCRATCH/project/file"
    [[ "$status" -ne 0 && ! -e "$SCRATCH/outside/missing" ]]
    ln -s "$SCRATCH/outside" "$SCRATCH/project/linked"
    run copy_dir_with_confirm "$SCRATCH/source" "$SCRATCH/project/linked/subtree"
    [[ "$status" -ne 0 && ! -e "$SCRATCH/outside/subtree" ]]
    run copy_dir_with_confirm "$SCRATCH/source" "$SCRATCH/project/../outside/subtree"
    [[ "$status" -ne 0 && ! -e "$SCRATCH/outside/subtree" ]]
}

@test "validated v1 manifest remains readable for conservative migration" {
    jq -n --arg hash "sha256:$(printf '%064d' 0)" '{manifest_version:1,
        tarnished_version:"v1",tarnished_commit:"abc",created_at:"2026-01-01",
        scaffold_options:{},files:{"src/app.py":$hash}}' > "$SCRATCH/.tarnished-manifest.json"
    run manifest_read "$SCRATCH"
    [[ "$status" -eq 0 ]]
    [[ "$(printf '%s' "$output" | jq -r .manifest_version)" == 1 ]]
}

@test "manifest rejects malicious plugin paths unknown profiles and nonboolean flags" {
    local options
    for options in '{"languages":["../../../../tmp/evil"]}' \
        '{"services":["../../custom"]}' '{"languages":["unknown"]}' \
        '{"ai_profile":"injected"}' '{"monorepo":"false"}' \
        '{"codex_enabled":null}' '{"services":null}'; do
        jq -n --argjson options "$options" '{manifest_version:1,
            tarnished_version:"v1",tarnished_commit:"abc",created_at:"2026-01-01",
            scaffold_options:$options,files:{}}' > "$SCRATCH/.tarnished-manifest.json"
        run manifest_read "$SCRATCH"
        [[ "$status" -ne 0 ]]
        [[ "$output" == *'Invalid manifest scaffold options'* ]]
    done
    manifest_options_valid '{}'
    manifest_options_valid '{"languages":["go","rust"],"services":["redis"],"ai_profile":"dual","codex_enabled":true}'
}

@test "failed staged enumeration cannot replace ownership or create copy targets" {
    mkdir -p "$SCRATCH/staging" "$SCRATCH/project"
    manifest_recording_start "$SCRATCH/project"
    local rel='.devcontainer/scripts/retained.sh' hash="sha256:$(printf '%064d' 0)"
    MANIFEST_TRACKED["$rel"]="$hash"
    find() { return 1; }
    if manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" '{}'; then
        fail "partial inventory was accepted"
    fi
    [[ "${MANIFEST_TRACKED[$rel]}" == "$hash" ]]
    if copy_dir_with_confirm "$SCRATCH/staging" "$SCRATCH/project/new"; then
        fail "failed directory enumeration was accepted"
    fi
    [[ ! -e "$SCRATCH/project/new" ]]
}

@test "failed candidate hashing rejects the whole adoption inventory and retains baselines" {
    mkdir -p "$SCRATCH/staging/.devcontainer/scripts" "$SCRATCH/project"
    echo upstream > "$SCRATCH/staging/.devcontainer/scripts/helper.sh"
    manifest_recording_start "$SCRATCH/project"
    local rel='.devcontainer/scripts/retained.sh' hash="sha256:$(printf '%064d' 0)"
    MANIFEST_TRACKED["$rel"]="$hash"
    sha256_file() { return 1; }
    if manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" '{}'; then
        fail "failed candidate hashing was accepted"
    fi
    [[ "${MANIFEST_TRACKED[$rel]}" == "$hash" ]]
}

@test "rehash failure preserves the previous recording and fails staging" {
    mkdir -p "$SCRATCH/.devcontainer/scripts"
    echo upstream > "$SCRATCH/.devcontainer/scripts/helper.sh"
    manifest_recording_start "$SCRATCH"
    local rel='.devcontainer/scripts/helper.sh' hash="sha256:$(printf '%064d' 0)"
    MANIFEST_TRACKED["$rel"]="$hash"
    sha256_file() { return 1; }
    if manifest_recording_rehash; then
        fail "failed rehash was accepted"
    fi
    [[ "${MANIFEST_TRACKED[$rel]}" == "$hash" ]]
}

@test "legacy missing helpers become durable tombstones while arbitrary missing source stays unowned" {
    mkdir -p "$SCRATCH/project" "$SCRATCH/staging/.devcontainer/scripts"
    echo upstream > "$SCRATCH/staging/.devcontainer/scripts/deleted.sh"
    local rel='.devcontainer/scripts/deleted.sh' old
    old=$(jq -n --arg hash "sha256:$(printf '%064d' 0)" '{manifest_version:1,files:{
        ".devcontainer/scripts/deleted.sh":$hash,"src/app.py":$hash,
        ".devcontainer/scripts/obsolete.sh":$hash}}')
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 && ${#MANIFEST_DELETED[@]} -eq 2 ]]
    manifest_write "$SCRATCH/project" v1 abc '{}'
    old=$(manifest_read "$SCRATCH/project")
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ -n "${MANIFEST_DELETED[$rel]:-}" && ${#MANIFEST_TRACKED[@]} -eq 0 ]]
    [[ ! -e "$SCRATCH/project/$rel" ]]
    manifest_write "$SCRATCH/project" v1 abc '{}'
    [[ "$(cat "$SCRATCH/project/.tarnished-manifest.json")" == "$old" ]]
}

@test "restoring exact distribution bytes clears a tombstone but differing bytes preserve it" {
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    local rel='.devcontainer/scripts/deleted.sh'
    local old='{"manifest_version":2,"files":{},"deleted_paths":[".devcontainer/scripts/deleted.sh"]}'
    echo upstream > "$SCRATCH/staging/$rel"
    echo local > "$SCRATCH/project/$rel"
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ -n "${MANIFEST_DELETED[$rel]:-}" && ${#MANIFEST_TRACKED[@]} -eq 0 ]]
    cp "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel"
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ -z "${MANIFEST_DELETED[$rel]:-}" && -n "${MANIFEST_TRACKED[$rel]:-}" ]]
}

@test "manifest rejects malformed unsafe and contradictory deletion intent" {
    manifest_recording_start "$SCRATCH"
    manifest_write "$SCRATCH" v1 abc '{}'
    local deleted
    cp "$SCRATCH/.tarnished-manifest.json" "$SCRATCH/base"
    for deleted in 'null' '{}' '["../escape"]' '["src/app.py"]' \
        '[".devcontainer/scripts/bad\nname.sh"]'; do
        jq --argjson deleted "$deleted" '.deleted_paths = $deleted' "$SCRATCH/base" \
            > "$SCRATCH/.tarnished-manifest.json"
        run manifest_read "$SCRATCH"
        [[ "$status" -ne 0 ]]
    done
    jq --arg hash "sha256:$(printf '%064d' 0)" '.files[".devcontainer/scripts/a.sh"] = $hash |
        .deleted_paths = [".devcontainer/scripts/a.sh"]' "$SCRATCH/base" \
        > "$SCRATCH/.tarnished-manifest.json"
    run manifest_read "$SCRATCH"
    [[ "$status" -ne 0 ]]
    MANIFEST_DELETED['.devcontainer/scripts/a.sh']=1
    manifest_recording_start "$SCRATCH"
    [[ ${#MANIFEST_DELETED[@]} -eq 0 ]]
}

@test "hashing and manifest adoption preserve literal backslash filenames" {
    local rel='.devcontainer/scripts/skill\name.sh'
    mkdir -p "$SCRATCH/staging/.devcontainer/scripts" "$SCRATCH/project/.devcontainer/scripts"
    echo content > "$SCRATCH/staging/$rel"
    echo content > "$SCRATCH/plain"
    local hash old
    hash=$(sha256_file "$SCRATCH/plain")
    [[ "$(sha256_file "$SCRATCH/staging/$rel")" == "$hash" ]]
    manifest_apply NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" '' "$hash"
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" '{}'
    manifest_write "$SCRATCH/project" v1 abc '{}'
    old=$(manifest_read "$SCRATCH/project")
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" "$old"
    [[ ${#MANIFEST_TRACKED[@]} -eq 1 && "${MANIFEST_TRACKED[$rel]}" == "$hash" ]]
    manifest_write "$SCRATCH/project" v1 abc '{}'
    [[ "$(manifest_read "$SCRATCH/project")" == "$old" ]]
}

@test "physical host prefixes work while root leaves and internal symlinks remain rejected" {
    mkdir -p "$SCRATCH/physical/project/.devcontainer/scripts"
    ln -s "$SCRATCH/physical" "$SCRATCH/host-alias"
    local root="$SCRATCH/host-alias/project"
    [[ "$(manifest_physical_root "$root")" == "$SCRATCH/physical/project" ]]
    [[ "$(manifest_physical_root "$SCRATCH/host-alias/new/private")" == "$SCRATCH/physical/new/private" ]]
    manifest_safe_path "$root" '.devcontainer/scripts/helper.sh'
    manifest_recording_start "$root"
    echo content > "$SCRATCH/source"
    copy_with_confirm "$SCRATCH/source" "$root/.devcontainer/scripts/helper.sh"
    [[ -n "${MANIFEST_TRACKED[.devcontainer/scripts/helper.sh]:-}" ]]
    ln -s "$SCRATCH/physical/project" "$SCRATCH/project-alias"
    ! manifest_physical_root "$SCRATCH/project-alias"
    ! manifest_physical_root "$SCRATCH/project-alias/"
    ln -s "$SCRATCH" "$root/internal"
    ! manifest_safe_path "$root" 'internal/outside.sh'
    ! manifest_safe_path "$root" '../outside.sh'
}

@test "UPDATE refuses an edit made during temporary copying" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo old > "$SCRATCH/project/$rel"
    echo upstream > "$SCRATCH/staging/$rel"
    local before desired
    before=$(sha256_file "$SCRATCH/project/$rel")
    desired=$(sha256_file "$SCRATCH/staging/$rel")
    cp() { command cp "$@" || return 1; echo 'concurrent edit' > "$SCRATCH/project/$rel"; }
    run manifest_apply UPDATE "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" "$before" "$desired"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/project/$rel")" == 'concurrent edit' ]]
}

@test "NEW refuses a collision introduced during temporary copying" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo upstream > "$SCRATCH/staging/$rel"
    local desired
    desired=$(sha256_file "$SCRATCH/staging/$rel")
    cp() { command cp "$@" || return 1; echo 'new developer file' > "$SCRATCH/project/$rel"; }
    run manifest_apply NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" '' "$desired"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/project/$rel")" == 'new developer file' ]]
}

@test "PRUNE and NOOP reject destinations changed since the driver's observation" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project/.devcontainer/scripts"
    echo old > "$SCRATCH/project/$rel"
    local before
    before=$(sha256_file "$SCRATCH/project/$rel")
    echo edited > "$SCRATCH/project/$rel"
    run manifest_apply PRUNE "$rel" '' "$SCRATCH/project/$rel" "$before" ''
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/project/$rel")" == edited ]]
    run manifest_apply NOOP "$rel" '' "$SCRATCH/project/$rel" "$before" "$before"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/project/$rel")" == edited ]]
}

@test "UPDATE verifies copied desired bytes before replacing the target" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project/.devcontainer/scripts" "$SCRATCH/staging/.devcontainer/scripts"
    echo old > "$SCRATCH/project/$rel"
    echo upstream > "$SCRATCH/staging/$rel"
    local before desired
    before=$(sha256_file "$SCRATCH/project/$rel")
    desired=$(sha256_file "$SCRATCH/staging/$rel")
    cp() { echo corrupt > "${@: -1}"; }
    run manifest_apply UPDATE "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" "$before" "$desired"
    [[ "$status" -ne 0 && "$(cat "$SCRATCH/project/$rel")" == old ]]
}

@test "BSD-like hashing and mv tools support helper installation without GNU options" {
    local rel='.devcontainer/scripts/skill\name.sh'
    mkdir -p "$SCRATCH/project" "$SCRATCH/staging/.devcontainer/scripts"
    echo content > "$SCRATCH/staging/$rel"
    local desired
    desired=$(sha256_file "$SCRATCH/staging/$rel")
    command() {
        if [[ "$1" == -v && "$2" == sha256sum ]]; then return 1; fi
        builtin command "$@"
    }
    realpath() { echo 'unsupported realpath option' >&2; return 1; }
    mv() {
        local arg
        for arg in "$@"; do [[ "$arg" != -*T* ]] || return 1; done
        command mv "$@"
    }
    [[ "$(sha256_file "$SCRATCH/staging/$rel")" == "$desired" ]]
    manifest_apply NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" '' "$desired"
    manifest_adopt_distribution "$SCRATCH/project" "$SCRATCH/staging" '{}'
    manifest_write "$SCRATCH/project" v1 abc '{}'
    [[ "$(sha256_file "$SCRATCH/project/$rel")" == "$desired" ]]
}

@test "portable rename directory race fails its postcondition without recording success" {
    local rel='.devcontainer/scripts/helper.sh'
    mkdir -p "$SCRATCH/project" "$SCRATCH/staging/.devcontainer/scripts"
    echo upstream > "$SCRATCH/staging/$rel"
    local desired
    desired=$(sha256_file "$SCRATCH/staging/$rel")
    manifest_recording_start "$SCRATCH/project"
    manifest_tally_reset
    mv() {
        mkdir -p "${@: -1}"
        command mv "$@"
    }
    if manifest_apply NEW "$rel" "$SCRATCH/staging/$rel" "$SCRATCH/project/$rel" '' "$desired"; then
        fail 'directory race incorrectly reported a successful installation'
    fi
    [[ -d "$SCRATCH/project/$rel" && "$TALLY_NEW" -eq 0 ]]
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]
}

@test "manifest writer rejects portable rename success into a raced directory" {
    manifest_recording_start "$SCRATCH"
    mv() {
        mkdir -p "${@: -1}"
        command mv "$@"
    }
    run manifest_write "$SCRATCH" v1 abc '{}'
    [[ "$status" -ne 0 ]]
    [[ "$output" == *'Manifest replacement changed or failed'* ]]
    [[ -d "$SCRATCH/.tarnished-manifest.json" ]]
}
