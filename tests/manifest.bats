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

@test "copy_with_confirm records into MANIFEST_TRACKED" {
    echo "data" > "$SCRATCH/src.txt"
    manifest_recording_start "$SCRATCH"
    copy_with_confirm "$SCRATCH/src.txt" "$SCRATCH/dst.txt"
    manifest_recording_stop
    [[ -n "${MANIFEST_TRACKED[dst.txt]:-}" ]]
    [[ "${MANIFEST_TRACKED[dst.txt]}" == sha256:* ]]
}

@test "copy_with_confirm does not record when recording is off (NFR-1)" {
    echo "data" > "$SCRATCH/src.txt"
    # Explicitly off — also the default state.
    manifest_recording_stop
    unset MANIFEST_TRACKED
    declare -gA MANIFEST_TRACKED
    copy_with_confirm "$SCRATCH/src.txt" "$SCRATCH/dst.txt"
    [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]
}

@test "MANIFEST_EXCLUDE_GLOBS paths are not recorded" {
    echo "{}" > "$SCRATCH/src.json"
    manifest_recording_start "$SCRATCH"
    copy_with_confirm "$SCRATCH/src.json" "$SCRATCH/modules.json"
    copy_with_confirm "$SCRATCH/src.json" "$SCRATCH/.gitignore"
    manifest_recording_stop
    [[ -z "${MANIFEST_TRACKED[modules.json]:-}" ]]
    [[ -z "${MANIFEST_TRACKED[.gitignore]:-}" ]]
}

@test ".github paths are not recorded (#286)" {
    echo "yaml" > "$SCRATCH/src.yml"
    mkdir -p "$SCRATCH/.github/workflows"
    manifest_recording_start "$SCRATCH"
    copy_with_confirm "$SCRATCH/src.yml" "$SCRATCH/.github/project.yml"
    copy_with_confirm "$SCRATCH/src.yml" "$SCRATCH/.github/versioning.yml"
    copy_with_confirm "$SCRATCH/src.yml" "$SCRATCH/.github/workflows/auto-tag.yml"
    copy_with_confirm "$SCRATCH/src.yml" "$SCRATCH/.github/workflows/project-integration.yml"
    manifest_recording_stop
    [[ -z "${MANIFEST_TRACKED[.github/project.yml]:-}" ]]
    [[ -z "${MANIFEST_TRACKED[.github/versioning.yml]:-}" ]]
    [[ -z "${MANIFEST_TRACKED[.github/workflows/auto-tag.yml]:-}" ]]
    [[ -z "${MANIFEST_TRACKED[.github/workflows/project-integration.yml]:-}" ]]
}

@test "manifest_track_file registers a file written by sed/awk" {
    manifest_recording_start "$SCRATCH"
    echo "from sed" > "$SCRATCH/out.yml"
    manifest_track_file "$SCRATCH/out.yml"
    manifest_recording_stop
    [[ -n "${MANIFEST_TRACKED[out.yml]:-}" ]]
}

# -----------------------------------------------------------------------------
# manifest_walk_directory
# -----------------------------------------------------------------------------

@test "manifest_walk_directory hashes every non-excluded file" {
    mkdir -p "$SCRATCH/sub"
    echo a > "$SCRATCH/a.txt"
    echo b > "$SCRATCH/sub/b.txt"
    : > "$SCRATCH/.gitignore"          # excluded
    : > "$SCRATCH/modules.json"        # excluded

    run manifest_walk_directory "$SCRATCH"
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "^a.txt"
    echo "$output" | grep -q "^sub/b.txt"
    ! echo "$output" | grep -q "^.gitignore"
    ! echo "$output" | grep -q "^modules.json"
}

@test "manifest_walk_directory skips .github/ tree (#286)" {
    mkdir -p "$SCRATCH/.github/workflows"
    echo y > "$SCRATCH/keep.txt"
    : > "$SCRATCH/.github/project.yml"
    : > "$SCRATCH/.github/versioning.yml"
    : > "$SCRATCH/.github/workflows/auto-tag.yml"
    : > "$SCRATCH/.github/workflows/rust-quality-check.yml"

    run manifest_walk_directory "$SCRATCH"
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "^keep.txt"
    ! echo "$output" | grep -q "^\.github/"
}

@test "manifest_walk_directory honors caller-provided skip prefixes" {
    mkdir -p "$SCRATCH/mod1"
    mkdir -p "$SCRATCH/mod2"
    echo a > "$SCRATCH/root.txt"
    echo b > "$SCRATCH/mod1/inner.txt"
    echo c > "$SCRATCH/mod2/inner.txt"

    run manifest_walk_directory "$SCRATCH" "mod1" "mod2"
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "^root.txt"
    ! echo "$output" | grep -q "^mod1/"
    ! echo "$output" | grep -q "^mod2/"
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

@test "manifest_write + manifest_read round-trip" {
    manifest_recording_start "$SCRATCH"
    MANIFEST_TRACKED["a.txt"]="sha256:aaa"
    MANIFEST_TRACKED["sub/b.txt"]="sha256:bbb"

    local opts='{"languages":["rust"],"services":[],"github_actions_enabled":false,"auto_tag_enabled":false,"codex_enabled":false,"monorepo":false}'
    run manifest_write "$SCRATCH" "v0.0.76" "deadbeef" "$opts"
    [[ "$status" -eq 0 ]]
    [[ -f "$SCRATCH/.tarnished-manifest.json" ]]

    run manifest_read "$SCRATCH"
    [[ "$status" -eq 0 ]]

    # Validate fields via jq.
    local json="$output"
    [[ "$(echo "$json" | jq -r .manifest_version)" == "1" ]]
    [[ "$(echo "$json" | jq -r .tarnished_version)" == "v0.0.76" ]]
    [[ "$(echo "$json" | jq -r .tarnished_commit)" == "deadbeef" ]]
    [[ "$(echo "$json" | jq -r '.scaffold_options.languages[0]')" == "rust" ]]
    [[ "$(echo "$json" | jq -r '.files["a.txt"]')" == "sha256:aaa" ]]
    [[ "$(echo "$json" | jq -r '.files["sub/b.txt"]')" == "sha256:bbb" ]]
}

@test "manifest_read rejects unsupported manifest_version" {
    cat > "$SCRATCH/.tarnished-manifest.json" <<'EOF'
{"manifest_version": 999, "tarnished_version": "v0.0.76", "tarnished_commit": "", "created_at": "2026-04-29T00:00:00Z", "scaffold_options": {}, "files": {}}
EOF
    run manifest_read "$SCRATCH"
    [[ "$status" -ne 0 ]]
}

@test "manifest_read rejects malformed JSON" {
    echo "not json" > "$SCRATCH/.tarnished-manifest.json"
    run manifest_read "$SCRATCH"
    [[ "$status" -ne 0 ]]
}

@test "manifest_read errors when file is missing" {
    run manifest_read "$SCRATCH"
    [[ "$status" -ne 0 ]]
}

@test "manifest_write produces sorted file keys for stable diffs" {
    manifest_recording_start "$SCRATCH"
    MANIFEST_TRACKED["zebra.txt"]="sha256:zzz"
    MANIFEST_TRACKED["alpha.txt"]="sha256:aaa"
    MANIFEST_TRACKED["mike.txt"]="sha256:mmm"

    run manifest_write "$SCRATCH" "v0" "" '{}'
    [[ "$status" -eq 0 ]]

    # The first key in the files object must be alpha.txt.
    local first
    first=$(jq -r '.files | keys[0]' "$SCRATCH/.tarnished-manifest.json")
    [[ "$first" == "alpha.txt" ]]
}

@test "manifest_write handles a files map larger than ARG_MAX (#289 regression)" {
    manifest_recording_start "$SCRATCH"

    # Before #289, manifest_write passed the serialized files map to jq as a
    # single --argjson command-line argument. Once that argument exceeds the
    # kernel arg limits (Linux MAX_ARG_STRLEN ~128 KiB per single arg, ARG_MAX
    # total), execve rejects jq with E2BIG ("Argument list too long") and no
    # manifest is written. Feeding the map via stdin removes that ceiling.
    #
    # Build a map whose JSON comfortably exceeds getconf ARG_MAX using a handful
    # of large values, so the per-file jq escaping stays cheap (few processes).
    local arg_max
    arg_max=$(getconf ARG_MAX 2>/dev/null || echo 2097152)
    local big_val
    big_val="sha256:$(head -c 131072 /dev/zero | tr '\0' 'a')"   # ~128 KiB value
    local n=$(( arg_max / 131072 + 3 ))
    local i
    for ((i = 0; i < n; i++)); do
        MANIFEST_TRACKED["deep/path/to/file_${i}.bin"]="$big_val"
    done

    run manifest_write "$SCRATCH" "v1.2.3" "cafef00d" '{"monorepo":false}'
    [[ "$status" -eq 0 ]]
    [[ -f "$SCRATCH/.tarnished-manifest.json" ]]

    # Result is valid JSON containing every entry, with values intact.
    run jq -e '.files | length' "$SCRATCH/.tarnished-manifest.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" -eq "$n" ]]
    [[ "$(jq -r '.files["deep/path/to/file_0.bin"]' "$SCRATCH/.tarnished-manifest.json")" == "$big_val" ]]
}
