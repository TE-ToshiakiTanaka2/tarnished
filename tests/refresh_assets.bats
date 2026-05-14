#!/usr/bin/env bats

# Unit + integration tests for #279 refresh-assets.sh.
#
# All tests use a local bare git repo as the "upstream" so SHA progression
# and offline behavior can be exercised deterministically without network.

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="${REPO_ROOT}/templates/core/.devcontainer/scripts/refresh-assets.sh"
COMMON_SH="${REPO_ROOT}/scripts/lib/common.sh"
TEMPLATE_REFRESH_JSON="${REPO_ROOT}/templates/agent-workflows/.tarnished/refresh.json"

setup() {
    SCRATCH="$(mktemp -d)"
    export HOME="${SCRATCH}/home"
    mkdir -p "$HOME"

    # rsync gates the sync_paths step; tests asserting on file content
    # explicitly check this. Tests that exercise CLI parsing, config
    # validation, the offline / corrupt-clone branches, and the manifest
    # subset invariant do NOT need rsync and run unconditionally.
    HAS_RSYNC=true
    command -v rsync >/dev/null 2>&1 || HAS_RSYNC=false
    export HAS_RSYNC

    # 1. Build the "upstream" bare repo with seed assets.
    UPSTREAM_BARE="${SCRATCH}/upstream.git"
    UPSTREAM_WORK="${SCRATCH}/upstream-work"
    mkdir -p "$UPSTREAM_BARE" "$UPSTREAM_WORK"

    git init -q --bare "$UPSTREAM_BARE"
    git init -q -b develop "$UPSTREAM_WORK"
    git -C "$UPSTREAM_WORK" config user.email "test@example.com"
    git -C "$UPSTREAM_WORK" config user.name "test"

    mkdir -p "${UPSTREAM_WORK}/.claude/commands/erd" \
             "${UPSTREAM_WORK}/.claude/skills" \
             "${UPSTREAM_WORK}/.claude/scripts" \
             "${UPSTREAM_WORK}/.claude/rules"
    echo "v1-brainstorm" > "${UPSTREAM_WORK}/.claude/commands/erd/brainstorm.md"
    echo "v1-skill"      > "${UPSTREAM_WORK}/.claude/skills/issue.md"
    echo "v1-shell"      > "${UPSTREAM_WORK}/.claude/rules/shell.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v1"
    git -C "$UPSTREAM_WORK" remote add origin "$UPSTREAM_BARE"
    git -C "$UPSTREAM_WORK" push -q -u origin develop

    # 2. Build a tiny "downstream project" tree.
    PROJECT="${SCRATCH}/project"
    mkdir -p "${PROJECT}/.tarnished" \
             "${PROJECT}/.devcontainer/scripts"
    git init -q "$PROJECT"

    # Custom refresh.json pointing at the bare upstream + a clone_dir under
    # SCRATCH so we never touch /opt or the host.
    CLONE_DIR="${SCRATCH}/cache"
    cat > "${PROJECT}/.tarnished/refresh.json" <<EOF
{
  "schema_version": 1,
  "upstream": {
    "repo_url": "${UPSTREAM_BARE}",
    "branch": "develop"
  },
  "clone_dir": "${CLONE_DIR}",
  "managed_paths": [
    { "src": ".claude/commands", "dst": ".claude/commands", "overlay": ".claude/commands.local" },
    { "src": ".claude/skills",   "dst": ".claude/skills",   "overlay": ".claude/skills.local"   },
    { "src": ".claude/rules",    "dst": ".claude/rules",    "overlay": ".claude/rules.local"    }
  ]
}
EOF

    # Place the script next to the project so resolve_project_root finds it.
    cp "$SCRIPT" "${PROJECT}/.devcontainer/scripts/refresh-assets.sh"
    chmod +x "${PROJECT}/.devcontainer/scripts/refresh-assets.sh"
    SUT="${PROJECT}/.devcontainer/scripts/refresh-assets.sh"

    export SCRATCH UPSTREAM_BARE UPSTREAM_WORK PROJECT CLONE_DIR SUT
}

teardown() {
    cd /
    if [[ -n "${SCRATCH:-}" ]] && [[ -d "$SCRATCH" ]]; then
        case "$SCRATCH" in
            /tmp/*) rm -rf "$SCRATCH" ;;
        esac
    fi
}

# -----------------------------------------------------------------------------
# Happy path
# -----------------------------------------------------------------------------

@test "first run: clones upstream and mirrors managed_paths" {
    $HAS_RSYNC || skip "rsync not available"
    run "$SUT"
    assert_success
    assert [ -d "${CLONE_DIR}/.git" ]
    assert [ -f "${PROJECT}/.claude/commands/erd/brainstorm.md" ]
    assert [ -f "${PROJECT}/.claude/skills/issue.md" ]
    assert [ -f "${PROJECT}/.claude/rules/shell.md" ]
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "v1-brainstorm"
}

@test "subsequent run with no upstream change: no-op (no rsync)" {
    $HAS_RSYNC || skip "rsync not available"
    "$SUT" >/dev/null
    # Sentinel: stash an extra file in cache that wouldn't survive a fresh
    # clone — if pull_if_changed went through, fetch+reset would keep it
    # since it's tracked nowhere; we instead detect "no rsync" via a
    # stable mtime on the project dst.
    local mtime_before
    mtime_before=$(stat -c %Y "${PROJECT}/.claude/commands/erd/brainstorm.md")
    sleep 1.1
    run "$SUT"
    assert_success
    assert_output --partial "upstream unchanged"
    local mtime_after
    mtime_after=$(stat -c %Y "${PROJECT}/.claude/commands/erd/brainstorm.md")
    [[ "$mtime_before" == "$mtime_after" ]]
}

@test "upstream advances: fetch + reset + rsync brings new content" {
    $HAS_RSYNC || skip "rsync not available"
    "$SUT" >/dev/null
    echo "v2-brainstorm" > "${UPSTREAM_WORK}/.claude/commands/erd/brainstorm.md"
    echo "v2-newfile"    > "${UPSTREAM_WORK}/.claude/commands/erd/newcmd.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "v2-brainstorm"
    assert [ -f "${PROJECT}/.claude/commands/erd/newcmd.md" ]
}

@test "upstream removes a file: rsync --delete drops it from the project" {
    $HAS_RSYNC || skip "rsync not available"
    "$SUT" >/dev/null
    git -C "$UPSTREAM_WORK" rm -q .claude/commands/erd/brainstorm.md
    git -C "$UPSTREAM_WORK" commit -q -m "v2-remove"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    assert [ ! -f "${PROJECT}/.claude/commands/erd/brainstorm.md" ]
}

# -----------------------------------------------------------------------------
# Overlay precedence
# -----------------------------------------------------------------------------

@test "overlay file overrides upstream" {
    $HAS_RSYNC || skip "rsync not available"
    "$SUT" >/dev/null
    mkdir -p "${PROJECT}/.claude/commands.local/erd"
    echo "OVERRIDDEN" > "${PROJECT}/.claude/commands.local/erd/brainstorm.md"

    # Force a refresh by advancing upstream
    echo "v2-brainstorm" > "${UPSTREAM_WORK}/.claude/commands/erd/brainstorm.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "OVERRIDDEN"
}

@test "overlay survives multiple refreshes (rsync --delete does not touch overlay source)" {
    $HAS_RSYNC || skip "rsync not available"
    "$SUT" >/dev/null
    mkdir -p "${PROJECT}/.claude/commands.local"
    echo "user-only" > "${PROJECT}/.claude/commands.local/myown.md"

    "$SUT" --force-pull >/dev/null
    "$SUT" --force-pull >/dev/null

    assert [ -f "${PROJECT}/.claude/commands.local/myown.md" ]
    run cat "${PROJECT}/.claude/commands.local/myown.md"
    assert_output "user-only"
    # overlay is also visible at base path after sync
    run cat "${PROJECT}/.claude/commands/myown.md"
    assert_output "user-only"
}

# -----------------------------------------------------------------------------
# Offline / failure paths (FR-5: always exit 0, never block)
# -----------------------------------------------------------------------------

@test "offline first-boot (unreachable upstream): warns and exits 0; project untouched" {
    # Replace upstream URL with a bogus path
    sed -i "s|${UPSTREAM_BARE}|/nonexistent/upstream|" "${PROJECT}/.tarnished/refresh.json"
    run "$SUT"
    assert_success
    assert_output --partial "clone failed"
    assert [ ! -d "${CLONE_DIR}/.git" ]
    # Project gets no .claude/commands because nothing to sync
    assert [ ! -d "${PROJECT}/.claude/commands" ]
}

@test "offline subsequent run (ls-remote fails): warns and uses cached" {
    $HAS_RSYNC || skip "rsync not available (test asserts post-sync file presence)"
    "$SUT" >/dev/null
    # Now break the upstream remote
    git -C "$CLONE_DIR" remote set-url origin /nonexistent/upstream
    run "$SUT"
    assert_success
    assert_output --partial "ls-remote failed"
    assert [ -f "${PROJECT}/.claude/commands/erd/brainstorm.md" ]
}

@test "clone_dir exists but is not a git repo: refuses to delete; exits 0" {
    mkdir -p "$CLONE_DIR"
    echo "user content" > "${CLONE_DIR}/important.txt"
    run "$SUT"
    assert_success
    assert_output --partial "is not a git repo"
    assert [ -f "${CLONE_DIR}/important.txt" ]
}

@test "malformed refresh.json: warns and exits 0" {
    echo "not json" > "${PROJECT}/.tarnished/refresh.json"
    run "$SUT"
    assert_success
    assert_output --partial "unsupported schema_version"
}

@test "missing refresh.json: warns and exits 0" {
    rm "${PROJECT}/.tarnished/refresh.json"
    run "$SUT"
    assert_success
    assert_output --partial "refresh.json missing"
}

@test "unsupported schema_version: warns and exits 0" {
    cat > "${PROJECT}/.tarnished/refresh.json" <<'EOF'
{ "schema_version": 99, "upstream": {"repo_url":"x","branch":"y"}, "clone_dir":"/tmp/x", "managed_paths":[] }
EOF
    run "$SUT"
    assert_success
    assert_output --partial "unsupported schema_version"
}

@test "empty managed_paths: no-op success" {
    sed -i 's|"managed_paths".*|"managed_paths": []|' "${PROJECT}/.tarnished/refresh.json"
    # Strip trailing array contents from the file (sed above truncates the
    # array open; rewrite as a clean fixture instead).
    cat > "${PROJECT}/.tarnished/refresh.json" <<EOF
{
  "schema_version": 1,
  "upstream": { "repo_url": "${UPSTREAM_BARE}", "branch": "develop" },
  "clone_dir": "${CLONE_DIR}",
  "managed_paths": []
}
EOF
    run "$SUT"
    assert_success
    assert_output --partial "managed_paths is empty"
}

# -----------------------------------------------------------------------------
# Permission fallback
# -----------------------------------------------------------------------------

@test "non-writable clone_dir parent falls back to \$HOME/.cache/tarnished" {
    # Point clone_dir at a location whose parent we make non-writable.
    local locked="${SCRATCH}/locked"
    mkdir -p "$locked"
    chmod 555 "$locked"
    sed -i "s|\"clone_dir\":.*|\"clone_dir\": \"${locked}/cache\",|" \
        "${PROJECT}/.tarnished/refresh.json"

    run "$SUT"
    assert_success
    assert_output --partial "falling back to"
    assert [ -d "${HOME}/.cache/tarnished/.git" ]

    chmod 755 "$locked"
}

# -----------------------------------------------------------------------------
# Dry-run
# -----------------------------------------------------------------------------

@test "--dry-run on first boot does not clone or sync" {
    run "$SUT" --dry-run
    assert_success
    assert_output --partial "[dry-run]"
    assert [ ! -d "${CLONE_DIR}/.git" ]
    assert [ ! -d "${PROJECT}/.claude/commands" ]
}

# -----------------------------------------------------------------------------
# CLI argument validation
# -----------------------------------------------------------------------------

@test "unknown flag exits 1" {
    run "$SUT" --bogus
    assert_failure
    assert_output --partial "unknown flag"
}

@test "--help exits 0 with usage" {
    run "$SUT" --help
    assert_success
    assert_output --partial "Usage: refresh-assets.sh"
}

# -----------------------------------------------------------------------------
# Sync invariant: refresh.json defaults must be a subset of MANIFEST_EXCLUDE_GLOBS
# -----------------------------------------------------------------------------

@test "refresh.json default managed_paths are excluded from manifest tracking" {
    # Source the constant from common.sh in a subshell, then check that
    # every dst (and overlay) in the template refresh.json appears in the
    # exclusion list as BOTH the directory entry AND the dir/* glob form
    # (since _manifest_path_excluded uses bash glob match — a missing
    # dir/* would silently leak files under the directory back into
    # manifest tracking).
    local rc=0
    bash -c '
        # shellcheck disable=SC1090
        source "'"$COMMON_SH"'"

        is_excluded() {
            local needle="$1"
            local g
            for g in "${MANIFEST_EXCLUDE_GLOBS[@]}"; do
                [[ "$g" == "$needle" ]] && return 0
            done
            return 1
        }

        rc=0
        for path in $(jq -r ".managed_paths[] | (.dst, .overlay) | select(.)" "'"$TEMPLATE_REFRESH_JSON"'"); do
            if ! is_excluded "$path"; then
                echo "MISSING from MANIFEST_EXCLUDE_GLOBS: $path" >&2
                rc=1
            fi
            if ! is_excluded "${path}/*"; then
                echo "MISSING from MANIFEST_EXCLUDE_GLOBS: ${path}/*" >&2
                rc=1
            fi
        done
        exit $rc
    ' || rc=$?
    [[ $rc -eq 0 ]]
}

# -----------------------------------------------------------------------------
# CLI argument validation (regression guards from /review)
# -----------------------------------------------------------------------------

@test "--config without value exits 1 with a clear error" {
    run "$SUT" --config
    assert_failure
    assert_output --partial "--config requires a path"
}

@test "--config followed by another flag exits 1" {
    run "$SUT" --config --dry-run
    assert_failure
    assert_output --partial "--config requires a path"
}

# -----------------------------------------------------------------------------
# Path traversal defenses (managed_paths must stay under PROJECT_ROOT/CLONE_DIR)
# -----------------------------------------------------------------------------

@test "absolute path in managed_paths.dst is rejected" {
    cat > "${PROJECT}/.tarnished/refresh.json" <<EOF
{
  "schema_version": 1,
  "upstream": { "repo_url": "${UPSTREAM_BARE}", "branch": "develop" },
  "clone_dir": "${CLONE_DIR}",
  "managed_paths": [
    { "src": ".claude/commands", "dst": "/etc/passwd_evil", "overlay": null }
  ]
}
EOF
    $HAS_RSYNC || skip "rsync not available (test asserts sync stage runs)"
    run "$SUT"
    assert_success
    assert_output --partial "escapes project root"
    assert [ ! -e "/etc/passwd_evil" ]
}

@test "../-bearing managed_paths.dst is rejected" {
    cat > "${PROJECT}/.tarnished/refresh.json" <<EOF
{
  "schema_version": 1,
  "upstream": { "repo_url": "${UPSTREAM_BARE}", "branch": "develop" },
  "clone_dir": "${CLONE_DIR}",
  "managed_paths": [
    { "src": ".claude/commands", "dst": "../escape", "overlay": null }
  ]
}
EOF
    $HAS_RSYNC || skip "rsync not available (test asserts sync stage runs)"
    run "$SUT"
    assert_success
    assert_output --partial "escapes project root"
    assert [ ! -d "${SCRATCH}/escape" ]
}
