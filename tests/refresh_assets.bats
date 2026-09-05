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

    # 1. Build the "upstream" bare repo with seed assets.
    UPSTREAM_BARE="${SCRATCH}/upstream.git"
    UPSTREAM_WORK="${SCRATCH}/upstream-work"
    mkdir -p "$UPSTREAM_BARE" "$UPSTREAM_WORK"

    git init -q --bare "$UPSTREAM_BARE"
    git init -q -b develop "$UPSTREAM_WORK"
    git -C "$UPSTREAM_WORK" config user.email "test@example.com"
    git -C "$UPSTREAM_WORK" config user.name "test"

    mkdir -p "${UPSTREAM_WORK}/templates/claude/.claude/commands/erd" \
             "${UPSTREAM_WORK}/templates/claude/.claude/skills" \
             "${UPSTREAM_WORK}/templates/claude/.claude/scripts" \
             "${UPSTREAM_WORK}/templates/claude/.claude/rules"
    echo "v1-brainstorm" > "${UPSTREAM_WORK}/templates/claude/.claude/commands/erd/brainstorm.md"
    echo "v1-skill"      > "${UPSTREAM_WORK}/templates/claude/.claude/skills/issue.md"
    echo "v1-shell"      > "${UPSTREAM_WORK}/templates/claude/.claude/rules/shell.md"
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
    { "src": "templates/claude/.claude/commands",       "dst": ".claude/commands",       "overlay": ".claude/commands.local"       },
    { "src": "templates/claude/.claude/skills",         "dst": ".claude/skills",         "overlay": ".claude/skills.local"         },
    { "src": "templates/claude/.claude/rules/shell.md", "dst": ".claude/rules/shell.md", "overlay": ".claude/rules.local/shell.md" }
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
    run "$SUT"
    assert_success
    assert [ -d "${CLONE_DIR}/.git" ]
    assert [ -f "${PROJECT}/.claude/commands/erd/brainstorm.md" ]
    assert [ -f "${PROJECT}/.claude/skills/issue.md" ]
    assert [ -f "${PROJECT}/.claude/rules/shell.md" ]
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "v1-brainstorm"
}

@test "subsequent run with no upstream change reconciles without rewriting files" {
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

@test "upstream advances: unchanged owned files receive new content" {
    "$SUT" >/dev/null
    echo "v2-brainstorm" > "${UPSTREAM_WORK}/templates/claude/.claude/commands/erd/brainstorm.md"
    echo "v2-newfile"    > "${UPSTREAM_WORK}/templates/claude/.claude/commands/erd/newcmd.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "v2-brainstorm"
    assert [ -f "${PROJECT}/.claude/commands/erd/newcmd.md" ]
}

@test "upstream removes a directory: proven unchanged owned file is removed" {
    "$SUT" >/dev/null
    git -C "$UPSTREAM_WORK" rm -q templates/claude/.claude/commands/erd/brainstorm.md
    git -C "$UPSTREAM_WORK" commit -q -m "v2-remove"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    assert [ ! -f "${PROJECT}/.claude/commands/erd/brainstorm.md" ]
}

@test "file-managed shell rule refresh preserves language-specific rules" {
    mkdir -p "${PROJECT}/.claude/rules"
    echo "python-rule" > "${PROJECT}/.claude/rules/python.md"

    "$SUT" >/dev/null
    assert [ -f "${PROJECT}/.claude/rules/shell.md" ]
    run cat "${PROJECT}/.claude/rules/python.md"
    assert_output "python-rule"

    echo "v2-shell" > "${UPSTREAM_WORK}/templates/claude/.claude/rules/shell.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2-shell"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/rules/shell.md"
    assert_output "v2-shell"
    run cat "${PROJECT}/.claude/rules/python.md"
    assert_output "python-rule"
}

# -----------------------------------------------------------------------------
# Overlay precedence
# -----------------------------------------------------------------------------

@test "overlay file overrides upstream" {
    "$SUT" >/dev/null
    mkdir -p "${PROJECT}/.claude/commands.local/erd"
    echo "OVERRIDDEN" > "${PROJECT}/.claude/commands.local/erd/brainstorm.md"

    # Force a refresh by advancing upstream
    echo "v2-brainstorm" > "${UPSTREAM_WORK}/templates/claude/.claude/commands/erd/brainstorm.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/commands/erd/brainstorm.md"
    assert_output "OVERRIDDEN"
}

@test "file overlay overrides file-managed shell rule" {
    "$SUT" >/dev/null
    mkdir -p "${PROJECT}/.claude/rules.local"
    echo "LOCAL-SHELL" > "${PROJECT}/.claude/rules.local/shell.md"

    echo "v2-shell" > "${UPSTREAM_WORK}/templates/claude/.claude/rules/shell.md"
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m "v2-shell"
    git -C "$UPSTREAM_WORK" push -q origin develop

    run "$SUT"
    assert_success
    run cat "${PROJECT}/.claude/rules/shell.md"
    assert_output "LOCAL-SHELL"
}

@test "overlay source survives multiple refreshes" {
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

@test "changed cache origin: warns and preserves project" {
    "$SUT" >/dev/null
    # Now break the upstream remote
    git -C "$CLONE_DIR" remote set-url origin /nonexistent/upstream
    run "$SUT"
    assert_success
    assert_output --partial "unrecognized origin"
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

@test "non-writable clone_dir parent warns without selecting another cache" {
    # Point clone_dir at a location whose parent we make non-writable.
    local locked="${SCRATCH}/locked"
    mkdir -p "$locked"
    chmod 555 "$locked"
    sed -i "s|\"clone_dir\":.*|\"clone_dir\": \"${locked}/cache\",|" \
        "${PROJECT}/.tarnished/refresh.json"

    run "$SUT"
    assert_success
    assert_output --partial "choose a writable cache"
    assert [ ! -d "${locked}/cache" ]

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
    # exclusion list. Directory-managed paths require BOTH the directory entry
    # and the dir/* glob form; file-managed paths require the exact file path.
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
        while IFS=$'\''\t'\'' read -r src dst overlay; do
            if [[ ! -e "'"$REPO_ROOT"'/${src}" ]]; then
                echo "MISSING refresh source: $src" >&2
                rc=1
            fi
            for path in "$dst" "$overlay"; do
                [[ -z "$path" ]] && continue
                if ! is_excluded "$path"; then
                    echo "MISSING from MANIFEST_EXCLUDE_GLOBS: $path" >&2
                    rc=1
                fi
                if [[ -d "'"$REPO_ROOT"'/${src}" ]] && ! is_excluded "${path}/*"; then
                    echo "MISSING from MANIFEST_EXCLUDE_GLOBS: ${path}/*" >&2
                    rc=1
                fi
            done
        done < <(jq -r ".managed_paths[] | [.src, .dst, (.overlay // \"\")] | @tsv" "'"$TEMPLATE_REFRESH_JSON"'")
        exit $rc
    ' || rc=$?
    [[ $rc -eq 0 ]]
}

# -----------------------------------------------------------------------------
# CLI argument validation (regression guards from /review)
# -----------------------------------------------------------------------------

@test "--config without value warns and exits 0" {
    run "$SUT" --config
    assert_success
    assert_output --partial "--config requires a path"
}

@test "--config followed by another flag warns and exits 0" {
    run "$SUT" --config --dry-run
    assert_success
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
    { "src": "templates/claude/.claude/commands", "dst": "/etc/passwd_evil", "overlay": null }
  ]
}
EOF
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
    { "src": "templates/claude/.claude/commands", "dst": "../escape", "overlay": null }
  ]
}
EOF
    run "$SUT"
    assert_success
    assert_output --partial "escapes project root"
    assert [ ! -d "${SCRATCH}/escape" ]
}

# Ownership and migration regressions (#316).
commit_upstream() {
    git -C "$UPSTREAM_WORK" add -A
    git -C "$UPSTREAM_WORK" commit -q -m 'advance assets'
    git -C "$UPSTREAM_WORK" push -q origin develop
}

local_refresh() {
    "$SUT" --project-root "$PROJECT" --source-dir "$UPSTREAM_WORK" "$@"
}

@test "first-run distributed collisions are backed up and custom siblings remain unowned" {
    mkdir -p "$PROJECT/.claude/skills"
    echo developer > "$PROJECT/.claude/skills/issue.md"
    echo custom > "$PROJECT/.claude/skills/custom.md"
    run local_refresh
    assert_success
    assert_output --partial '1 backed-up'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    assert_equal "$(cat "$PROJECT/.claude/skills/custom.md")" custom
    run jq -e '.entries | has(".claude/skills/custom.md")' "$PROJECT/.tarnished/refresh-state.json"
    assert_failure
}

@test "edited distributed files are backed up and user deletions are restored" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/before.json"
    echo developer > "$PROJECT/.claude/skills/issue.md"
    rm "$PROJECT/.claude/commands/erd/brainstorm.md"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    run local_refresh
    assert_success
    assert_output --partial '1 backed-up'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" changed
    assert [ -f "$PROJECT/.claude/commands/erd/brainstorm.md" ]
}

@test "same size and timestamp upstream changes update by hash" {
    local_refresh >/dev/null
    touch -r "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md" "$SCRATCH/timestamp"
    echo v2-skill > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    touch -r "$SCRATCH/timestamp" "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v2-skill
}

@test "overlay changes reconcile with unchanged upstream SHA and restore base on removal" {
    local_refresh >/dev/null
    mkdir -p "$PROJECT/.claude/skills.local"
    echo overlay > "$PROJECT/.claude/skills.local/issue.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" overlay
    echo overlay2 > "$PROJECT/.claude/skills.local/issue.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" overlay2
    rm "$PROJECT/.claude/skills.local/issue.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
}

@test "overlay-only file is preserved after sidecar removal and live edits are backed up" {
    mkdir -p "$PROJECT/.claude/skills.local"
    echo customization > "$PROJECT/.claude/skills.local/extra.md"
    local_refresh >/dev/null
    rm "$PROJECT/.claude/skills.local/extra.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/extra.md")" customization
    echo edited > "$PROJECT/.claude/skills/issue.md"
    echo overlay > "$PROJECT/.claude/skills.local/issue.md"
    run local_refresh
    assert_output --partial '1 backed-up'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" overlay
}

@test "upstream removal preserves edited asset, custom sibling and overlay projection" {
    local_refresh >/dev/null
    echo edited > "$PROJECT/.claude/skills/issue.md"
    echo custom > "$PROJECT/.claude/commands/custom.md"
    mkdir -p "$PROJECT/.claude/commands.local/erd"
    echo override > "$PROJECT/.claude/commands.local/erd/brainstorm.md"
    local_refresh >/dev/null
    echo edited > "$PROJECT/.claude/skills/issue.md"
    rm "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md" "$UPSTREAM_WORK/templates/claude/.claude/commands/erd/brainstorm.md"
    commit_upstream
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" edited
    assert_equal "$(cat "$PROJECT/.claude/commands/erd/brainstorm.md")" override
    assert_equal "$(cat "$PROJECT/.claude/commands/custom.md")" custom
}

@test "absent source without committed removal proof preserves prior assets" {
    local_refresh >/dev/null
    rm -rf "$UPSTREAM_WORK/templates/claude/.claude/commands"
    run local_refresh
    assert_output --partial 'upstream templates/claude/.claude/commands unavailable'
    assert [ -f "$PROJECT/.claude/commands/erd/brainstorm.md" ]
}

@test "retired or changed mapping preserves previous state and destinations" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    jq '.managed_paths = []' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    cp "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    local_refresh >/dev/null
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    assert [ -f "$PROJECT/.claude/skills/issue.md" ]
}

@test "missing state adopts only identical bytes including an explicit overlay on identical base" {
    mkdir -p "$PROJECT/.claude/skills" "$PROJECT/.claude/skills.local"
    cp "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md" "$PROJECT/.claude/skills/issue.md"
    echo overlay > "$PROJECT/.claude/skills.local/issue.md"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" overlay
    jq -e '.entries[".claude/skills/issue.md"].origin == "overlay"' "$PROJECT/.tarnished/refresh-state.json"
}

@test "dry-run with local source previews installs and leaves target and cache byte-identical" {
    tar -cf "$SCRATCH/before.tar" -C "$PROJECT" .
    run local_refresh --dry-run
    assert_success
    assert_output --partial '[dry-run] install'
    tar -cf "$SCRATCH/after.tar" -C "$PROJECT" .
    cmp "$SCRATCH/before.tar" "$SCRATCH/after.tar"
    assert [ ! -e "$CLONE_DIR" ]
}

@test "dry-run without cache creates no cache parent or target entries" {
    jq --arg cache "$SCRATCH/nonexistent/parent/cache" '.clone_dir = $cache' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    cp "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    tar -cf "$SCRATCH/before.tar" -C "$PROJECT" .
    run "$SUT" --dry-run
    assert_output --partial 'upstream comparison unavailable'
    assert [ ! -e "$SCRATCH/nonexistent" ]
    tar -cf "$SCRATCH/after.tar" -C "$PROJECT" .
    cmp "$SCRATCH/before.tar" "$SCRATCH/after.tar"
}

@test "state symlink or malformed state blocks all refresh mutations" {
    echo marker > "$SCRATCH/external"
    ln -s "$SCRATCH/external" "$PROJECT/.tarnished/refresh-state.json"
    run local_refresh
    assert_output --partial 'unsafe refresh state'
    assert_equal "$(cat "$SCRATCH/external")" marker
    assert [ ! -e "$PROJECT/.claude" ]
    rm "$PROJECT/.tarnished/refresh-state.json"
    echo '{"schema_version":1,"entries":{"../escape":{}}}' > "$PROJECT/.tarnished/refresh-state.json"
    run local_refresh
    assert_output --partial 'invalid refresh state'
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "symlink destinations sources and overlay parents are never followed" {
    mkdir -p "$SCRATCH/outside" "$PROJECT/.claude"
    echo safe > "$SCRATCH/outside/issue.md"
    ln -s "$SCRATCH/outside" "$PROJECT/.claude/skills"
    ln -s "$SCRATCH/outside" "$PROJECT/.claude/commands.local"
    rm "$UPSTREAM_WORK/templates/claude/.claude/rules/shell.md"
    ln -s "$SCRATCH/outside/issue.md" "$UPSTREAM_WORK/templates/claude/.claude/rules/shell.md"
    run local_refresh
    assert_success
    assert_output --partial 'unsafe'
    assert_equal "$(cat "$SCRATCH/outside/issue.md")" safe
    assert [ ! -e "$PROJECT/.claude/commands" ]
    assert [ ! -e "$PROJECT/.claude/rules/shell.md" ]
}

@test "overlapping destination overlay or control-character mappings fail before writes" {
    for expression in '.managed_paths[1].dst = ".claude/commands/skills"' '.managed_paths[0].overlay = ".claude/commands"' '.managed_paths[0].dst = "bad\npath"'; do
        jq "$expression" "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
        run local_refresh --config "$SCRATCH/config"
        assert_output --partial 'invalid/overlapping managed_paths'
        assert [ ! -e "$PROJECT/.claude" ]
    done
}

@test "cache overlap dirty cache and symlink cache preserve developer bytes" {
    jq --arg cache "$PROJECT/cache" '.clone_dir = $cache' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run "$SUT" --config "$SCRATCH/config"
    assert_output --partial 'cache overlaps project'
    "$SUT" >/dev/null
    echo work > "$CLONE_DIR/developer.txt"
    run "$SUT"
    assert_output --partial 'dirty cache'
    assert_equal "$(cat "$CLONE_DIR/developer.txt")" work
    mv "$CLONE_DIR" "$SCRATCH/othercache"
    ln -s "$SCRATCH/othercache" "$CLONE_DIR"
    run "$SUT"
    assert_output --partial 'unsafe cache path'
}

@test "copy failure keeps old installed baseline and retries successfully" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo v2-skill > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin"
    printf '#!/bin/bash\nexit 1\n' > "$SCRATCH/bin/cp"
    chmod +x "$SCRATCH/bin/cp"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'copy failed'
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v2-skill
}

@test "Codex assets follow profile capability without rewriting model overrides" {
    mkdir -p "$UPSTREAM_WORK/templates/codex/.agents/skills"
    echo codex > "$UPSTREAM_WORK/templates/codex/.agents/skills/flow.md"
    jq '.managed_paths += [{src:"templates/codex/.agents/skills",dst:".agents/skills",overlay:".agents/skills.local"}]' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    cp "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    echo '{"ai_profile":"claude-main","roles":{"executor":{"model":"custom"}}}' > "$PROJECT/.tarnished/agent-profile.json"
    local_refresh >/dev/null
    assert [ ! -e "$PROJECT/.agents" ]
    echo '{"ai_profile":"dual","roles":{"executor":{"model":"custom"}}}' > "$PROJECT/.tarnished/agent-profile.json"
    cp "$PROJECT/.tarnished/agent-profile.json" "$SCRATCH/profile"
    local_refresh >/dev/null
    assert_equal "$(cat "$PROJECT/.agents/skills/flow.md")" codex
    cmp "$SCRATCH/profile" "$PROJECT/.tarnished/agent-profile.json"
}

@test "default catalog opt-in adds upstream mappings while custom empty catalog stays authoritative" {
    mkdir -p "$UPSTREAM_WORK/templates/agent-workflows/.tarnished"
    cp "$PROJECT/.tarnished/refresh.json" "$UPSTREAM_WORK/templates/agent-workflows/.tarnished/refresh.json"
    jq '.managed_paths = [] | .use_default_managed_paths = true' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    cp "$SCRATCH/config" "$PROJECT/.tarnished/refresh.json"
    local_refresh >/dev/null
    assert [ -f "$PROJECT/.claude/skills/issue.md" ]
    assert_equal "$(jq '.managed_paths | length' "$PROJECT/.tarnished/refresh.json")" 0
}

@test "unsafe source is rejected even when overlay exists and is safe" {
    local_refresh >/dev/null
    mkdir -p "$PROJECT/.claude/skills.local"
    echo override > "$PROJECT/.claude/skills.local/issue.md"
    rm "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    ln -s /etc/hosts "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    run local_refresh
    assert_output --partial 'unsafe source/overlay'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
}

@test "source ancestor and descendant overlap is rejected" {
    run "$SUT" --source-dir "$SCRATCH"
    assert_output --partial 'unsafe/unavailable source'
    mkdir "$PROJECT/source"
    run "$SUT" --source-dir "$PROJECT/source"
    assert_output --partial 'unsafe/unavailable source'
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "failed source enumeration never authorizes removal" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    mkdir "$SCRATCH/bin"
    printf '#!/bin/bash\nexit 1\n' > "$SCRATCH/bin/find"
    chmod +x "$SCRATCH/bin/find"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'cannot enumerate'
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    assert [ -f "$PROJECT/.claude/skills/issue.md" ]
}

@test "failed state persistence retains old state and exact installed bytes recover on retry" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin"
    cat > "$SCRATCH/bin/mv" <<'MOCK'
#!/bin/bash
for argument in "$@"; do
    [[ "$argument" != */refresh-state.json ]] || exit 1
done
exec /usr/bin/mv "$@"
MOCK
    chmod +x "$SCRATCH/bin/mv"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'state write failed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" changed
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    local_refresh >/dev/null
    run cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    assert_failure
}

@test "one cache initializes a second target at the same upstream commit" {
    "$SUT" >/dev/null
    mkdir -p "$SCRATCH/second/.tarnished"
    cp "$PROJECT/.tarnished/refresh.json" "$SCRATCH/second/.tarnished/refresh.json"
    run "$SUT" --project-root "$SCRATCH/second"
    assert_success
    assert_equal "$(cat "$SCRATCH/second/.claude/skills/issue.md")" v1-skill
}

@test "default catalog failure uses snapshot and explicit empty catalog performs no fetch" {
    jq '.use_default_managed_paths = true' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run local_refresh --config "$SCRATCH/config"
    assert_output --partial 'using project snapshot'
    assert [ -f "$PROJECT/.claude/skills/issue.md" ]
    jq '.managed_paths = [] | .upstream.repo_url = "/unavailable"' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run "$SUT" --config "$SCRATCH/config"
    assert_output --partial 'managed_paths is empty'
    assert [ ! -e "$CLONE_DIR" ]
}

@test "mapping without overlay produces reloadable state and preserved executable mode" {
    chmod +x "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    jq '.managed_paths |= map(del(.overlay))' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    local_refresh --config "$SCRATCH/config" >/dev/null
    assert [ -x "$PROJECT/.claude/skills/issue.md" ]
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    run local_refresh --config "$SCRATCH/config"
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" changed
}

@test "explicit mapping cannot install or overwrite project configuration or sidecars" {
    jq '.managed_paths = [{src:"templates/claude/.claude/skills/issue.md",dst:".claude/settings.local.json"}]' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run local_refresh --config "$SCRATCH/config"
    assert_output --partial 'preserve developer-owned configuration'
    assert [ ! -e "$PROJECT/.claude/settings.local.json" ]
}

@test "cache pointing to updater source checkout is never fetched or reset" {
    mkdir -p "$UPSTREAM_WORK/.devcontainer/scripts"
    cp "$SCRIPT" "$UPSTREAM_WORK/.devcontainer/scripts/refresh-assets.sh"
    commit_upstream
    local before
    before=$(git -C "$UPSTREAM_WORK" rev-parse HEAD)
    jq --arg cache "$UPSTREAM_WORK" '.clone_dir = $cache' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run bash "$UPSTREAM_WORK/.devcontainer/scripts/refresh-assets.sh" --project-root "$PROJECT" --config "$SCRATCH/config"
    assert_output --partial 'cache overlaps updater source checkout'
    assert_equal "$(git -C "$UPSTREAM_WORK" rev-parse HEAD)" "$before"
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "clean cache with local committed work is preserved instead of reset" {
    "$SUT" >/dev/null
    git -C "$CLONE_DIR" config user.email test@example.com
    git -C "$CLONE_DIR" config user.name test
    echo committed-work > "$CLONE_DIR/work.txt"
    git -C "$CLONE_DIR" add work.txt
    git -C "$CLONE_DIR" commit -qm 'local developer work'
    local before
    before=$(git -C "$CLONE_DIR" rev-parse HEAD)
    run "$SUT"
    assert_output --partial 'cache has local/diverged commits'
    assert_equal "$(git -C "$CLONE_DIR" rev-parse HEAD)" "$before"
    assert_equal "$(cat "$CLONE_DIR/work.txt")" committed-work
}

@test "leading-hyphen branches are rejected before fetch is invoked" {
    "$SUT" >/dev/null
    mkdir "$SCRATCH/bin"
    cat > "$SCRATCH/bin/git" <<'MOCK'
#!/bin/bash
for argument in "$@"; do
    if [[ "$argument" == fetch ]]; then
        printf 'fetch invoked\n' > "$SCRATCH/fetch-called"
        exit 1
    fi
done
exec /usr/bin/git "$@"
MOCK
    chmod +x "$SCRATCH/bin/git"
    jq '.upstream.branch = "--upload-pack=unexpected-command"' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --config "$SCRATCH/config"
    assert_success
    assert_output --partial 'invalid upstream URL/branch'
    assert [ ! -e "$SCRATCH/fetch-called" ]
    run env PATH="$SCRATCH/bin:$PATH" DEVCONTAINER_BRANCH=--upload-pack=unexpected-command "$SUT"
    assert_success
    assert_output --partial 'invalid upstream URL/branch'
    assert [ ! -e "$SCRATCH/fetch-called" ]
}

@test "shipped default refresh works as nonroot using validated historical home cache" {
    [[ "$EUID" -ne 0 ]] || skip 'requires actual nonroot container user'
    [[ ! -w /opt && ! -e /opt/tarnished && ! -L /opt/tarnished ]] || skip 'requires unprovisioned shipped /opt default'
    local fixture_home="$SCRATCH/fixture-home"
    mkdir "$fixture_home"
    cp "$TEMPLATE_REFRESH_JSON" "$PROJECT/.tarnished/refresh.json"
    cp "$PROJECT/.tarnished/refresh.json" "$SCRATCH/config-before"
    # HOME is supplied only to the isolated child process to exercise its home lookup.
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" DEVCONTAINER_BRANCH=develop "$SUT"
    assert_success
    assert_output --partial 'default cache unavailable; using home cache'
    assert [ -d "$fixture_home/.cache/tarnished/.git" ]
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    cmp "$SCRATCH/config-before" "$PROJECT/.tarnished/refresh.json"
    echo v2-skill > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    commit_upstream
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" DEVCONTAINER_BRANCH=develop "$SUT"
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v2-skill
    # Legacy snapshots omit default-catalog opt-in but must reuse the same home cache.
    jq 'del(.use_default_managed_paths)' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" DEVCONTAINER_BRANCH=develop "$SUT" --config "$SCRATCH/config"
    assert_success
    assert_output --partial 'default cache unavailable; using home cache'
}

@test "unavailable shipped default dry-run makes no home cache directories" {
    [[ "$EUID" -ne 0 ]] || skip 'requires actual nonroot container user'
    [[ ! -w /opt && ! -e /opt/tarnished && ! -L /opt/tarnished ]] || skip 'requires unprovisioned shipped /opt default'
    local fixture_home="$SCRATCH/fixture-home"
    mkdir "$fixture_home"
    cp "$TEMPLATE_REFRESH_JSON" "$PROJECT/.tarnished/refresh.json"
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" DEVCONTAINER_BRANCH=develop "$SUT" --dry-run
    assert_success
    assert_output --partial 'upstream comparison unavailable'
    assert [ ! -e "$fixture_home/.cache" ]
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "home fallback rejects symlink overlapping untrusted and dirty caches without bypass" {
    [[ "$EUID" -ne 0 ]] || skip 'requires actual nonroot container user'
    [[ ! -w /opt && ! -e /opt/tarnished && ! -L /opt/tarnished ]] || skip 'requires unprovisioned shipped /opt default'
    local fixture_home="$SCRATCH/fixture-home"
    mkdir -p "$fixture_home/.cache"
    cp "$TEMPLATE_REFRESH_JSON" "$PROJECT/.tarnished/refresh.json"
    ln -s "$SCRATCH/outside" "$fixture_home/.cache/tarnished"
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" "$SUT"
    assert_output --partial 'unsafe cache path'
    assert [ ! -e "$SCRATCH/outside" ]
    rm "$fixture_home/.cache/tarnished"
    mkdir "$fixture_home/.cache/tarnished"
    echo developer > "$fixture_home/.cache/tarnished/work"
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" "$SUT"
    assert_output --partial 'is not a git repo'
    assert_equal "$(cat "$fixture_home/.cache/tarnished/work")" developer
    rm "$fixture_home/.cache/tarnished/work"
    rmdir "$fixture_home/.cache/tarnished"
    git clone -q --branch develop "$UPSTREAM_BARE" "$fixture_home/.cache/tarnished"
    echo developer > "$fixture_home/.cache/tarnished/work"
    run env HOME="$fixture_home" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" "$SUT"
    assert_output --partial 'dirty cache'
    assert_equal "$(cat "$fixture_home/.cache/tarnished/work")" developer
    run env HOME="$PROJECT" DEVCONTAINER_REPO_URL="$UPSTREAM_BARE" "$SUT"
    assert_output --partial 'cache overlaps project'
    assert [ ! -e "$PROJECT/.cache" ]
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "escaped filenames install adopt and refresh repeatedly with valid digest state" {
    local assets="$UPSTREAM_WORK/templates/claude/.claude/skills"
    local added='new\skill.md' adopted='adopt\skill.md'
    echo new > "$assets/$added"
    echo identical > "$assets/$adopted"
    mkdir -p "$PROJECT/.claude/skills"
    cp "$assets/$adopted" "$PROJECT/.claude/skills/$adopted"
    run local_refresh
    assert_success
    assert [ -f "$PROJECT/.claude/skills/$added" ]
    jq -e 'all(.entries[].sha256; test("^[0-9a-f]{64}$"))' "$PROJECT/.tarnished/refresh-state.json"
    echo updated > "$assets/$added"
    echo adopted-update > "$assets/$adopted"
    run local_refresh
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/$added")" updated
    assert_equal "$(cat "$PROJECT/.claude/skills/$adopted")" adopted-update
    run local_refresh
    assert_success
    assert_output --partial '0 failures'
}

@test "invalid checksum output cannot install or poison state" {
    mkdir "$SCRATCH/bin"
    printf '#!/bin/bash\nprintf "invalid-digest  -\\n"\n' > "$SCRATCH/bin/sha256sum"
    chmod +x "$SCRATCH/bin/sha256sum"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_success
    assert_output --partial 'cannot hash'
    assert [ ! -e "$PROJECT/.claude/skills/issue.md" ]
    assert [ ! -e "$PROJECT/.tarnished/refresh-state.json" ]
}

@test "symlinked host ancestors work for physical project source cache and config roots" {
    ln -s "$SCRATCH" "$SCRATCH/host-prefix"
    run "$SUT" --project-root "$SCRATCH/host-prefix/project" --source-dir "$SCRATCH/host-prefix/upstream-work" --config "$SCRATCH/host-prefix/project/.tarnished/refresh.json"
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    jq --arg cache "$SCRATCH/host-prefix/new-parent/cache" '.clone_dir = $cache' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run "$SUT" --project-root "$SCRATCH/host-prefix/project" --config "$SCRATCH/host-prefix/config"
    assert_success
    assert [ -d "$SCRATCH/new-parent/cache/.git" ]
    assert_output --partial '0 failures'
}

@test "symlinked host prefix does not permit root leaf or internal config source target links" {
    ln -s "$SCRATCH" "$SCRATCH/host-prefix"
    ln -s "$PROJECT" "$SCRATCH/project-link"
    run "$SUT" --project-root "$SCRATCH/host-prefix/project-link/" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'unsafe/unavailable project root'
    ln -s "$UPSTREAM_WORK" "$SCRATCH/source-link"
    run "$SUT" --project-root "$SCRATCH/host-prefix/project" --source-dir "$SCRATCH/source-link/"
    assert_output --partial 'unsafe source path'
    mv "$PROJECT/.tarnished" "$SCRATCH/config-target"
    ln -s "$SCRATCH/config-target" "$PROJECT/.tarnished"
    run "$SUT" --project-root "$SCRATCH/host-prefix/project" --source-dir "$UPSTREAM_WORK" --config "$SCRATCH/host-prefix/project/.tarnished/refresh.json"
    assert_output --partial 'refresh.json missing or unsafe'
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "portable refresh uses shasum and ordinary mv without GNU-only flags" {
    local portable_bin="$SCRATCH/portable-bin" dependency
    mkdir "$portable_bin"
    for dependency in jq git find cp mkdir mktemp rm dirname shasum; do
        ln -s "$(command -v "$dependency")" "$portable_bin/$dependency"
    done
    cat > "$portable_bin/mv" <<'MOCK'
#!/bin/bash
for argument in "$@"; do
    if [[ "$argument" == -T || "$argument" == -fT ]]; then
        printf 'GNU-only mv flag\n' >&2
        exit 1
    fi
done
exec /usr/bin/mv "$@"
MOCK
    cat > "$portable_bin/realpath" <<'MOCK'
#!/bin/bash
printf 'GNU realpath requested\n' > "$SCRATCH/realpath-called"
exit 1
MOCK
    chmod +x "$portable_bin/mv" "$portable_bin/realpath"
    run env PATH="$portable_bin" "$SUT"
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    echo updated > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    commit_upstream
    run env PATH="$portable_bin" "$SUT"
    assert_success
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" updated
    assert [ ! -e "$SCRATCH/realpath-called" ]
    jq -e 'all(.entries[].sha256; test("^[0-9a-f]{64}$"))' "$PROJECT/.tarnished/refresh-state.json"
}

@test "published overlay recovery adopts effective bytes with existing baseline" {
    local_refresh >/dev/null
    echo upstream-b > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    echo project-c > "$PROJECT/.claude/skills/issue.md"
    mkdir "$PROJECT/.claude/skills.local"
    cp "$PROJECT/.claude/skills/issue.md" "$PROJECT/.claude/skills.local/issue.md"
    cp "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md" "$PROJECT/.claude/skills/issue.md"
    run local_refresh
    assert_output --partial '1 backed-up'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" project-c
    cp "$PROJECT/.claude/skills.local/issue.md" "$PROJECT/.claude/skills/issue.md"
    run local_refresh
    assert_success
    assert_output --partial '3 unchanged'
    assert_output --partial '0 conflicts'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" project-c
    run local_refresh
    assert_output --partial '0 conflicts'
    rm "$PROJECT/.claude/skills.local/issue.md"
    cp "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md" "$PROJECT/.claude/skills/issue.md"
    run local_refresh
    assert_output --partial '1 adopted'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" upstream-b
}

@test "dry-run preserves existing cache index bytes and metadata after cached file mtime changes" {
    "$SUT" >/dev/null
    touch -m -d '2030-01-01' "$CLONE_DIR/templates/claude/.claude/skills/issue.md"
    local index_before metadata_before
    index_before=$(sha256sum < "$CLONE_DIR/.git/index")
    metadata_before=$(stat -c '%s:%y:%z' "$CLONE_DIR/.git/index")
    run "$SUT" --dry-run
    assert_success
    assert_equal "$(sha256sum < "$CLONE_DIR/.git/index")" "$index_before"
    assert_equal "$(stat -c '%s:%y:%z' "$CLONE_DIR/.git/index")" "$metadata_before"
}

@test "summary distinguishes unchanged adopted preserved conflicts unknown unsafe and failures" {
    local_refresh >/dev/null
    local assets="$UPSTREAM_WORK/templates/claude/.claude/skills"
    echo collision > "$assets/unknown.md"
    echo developer > "$PROJECT/.claude/skills/unknown.md"
    echo desired > "$assets/adopted.md"
    cp "$assets/adopted.md" "$PROJECT/.claude/skills/adopted.md"
    echo changed > "$assets/issue.md"
    echo edited > "$PROJECT/.claude/skills/issue.md"
    echo unsafe > "$assets/unsafe.md"
    ln -s "$SCRATCH/outside" "$PROJECT/.claude/skills/unsafe.md"
    echo fails > "$assets/fails.md"
    mkdir "$SCRATCH/bin"
    printf '#!/bin/bash\nexit 1\n' > "$SCRATCH/bin/cp"
    chmod +x "$SCRATCH/bin/cp"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_success
    assert_output --partial '0 installed, 0 backed-up, 0 removed, 2 unchanged, 1 adopted, 0 preserved: 0 conflicts, 0 unknown; 1 unsafe, 3 failures'
}

@test "portable rename directory race never advances installed baseline" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state-before"
    echo upstream-changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin"
    cat > "$SCRATCH/bin/mv" <<'MOCK'
#!/bin/bash
target="${@: -1}"
if [[ "$target" == */.claude/skills/issue.md ]]; then
    /usr/bin/rm -- "$target"
    /usr/bin/mkdir -- "$target"
fi
exec /usr/bin/mv "$@"
MOCK
    chmod +x "$SCRATCH/bin/mv"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_success
    assert_output --partial 'copy failed'
    assert_output --partial '1 failures'
    assert [ -d "$PROJECT/.claude/skills/issue.md" ]
    cmp "$SCRATCH/state-before" "$PROJECT/.tarnished/refresh-state.json"
}

@test "alternate project spelling cannot bypass internal symlink config validation" {
    ln -s "$SCRATCH" "$SCRATCH/host-prefix"
    mkdir -p "$SCRATCH/external-config/nested"
    cp "$PROJECT/.tarnished/refresh.json" "$SCRATCH/external-config/nested/refresh.json"
    mv "$PROJECT/.tarnished" "$SCRATCH/original-config"
    ln -s "$SCRATCH/external-config" "$PROJECT/.tarnished"
    run "$SUT" --project-root "$PROJECT" --source-dir "$UPSTREAM_WORK" --config "$SCRATCH/host-prefix/project/.tarnished/nested/refresh.json"
    assert_success
    assert_output --partial 'refresh.json missing or unsafe'
    assert [ ! -e "$PROJECT/.claude" ]
}

@test "replacement backups retain exact binary bytes and unique runs while repeats are no-ops" {
    mkdir -p "$PROJECT/.claude/skills"
    printf 'old\000bytes\377\n' > "$PROJECT/.claude/skills/issue.md"
    cp "$PROJECT/.claude/skills/issue.md" "$SCRATCH/original"
    run local_refresh
    assert_success
    assert_output --partial 'restore with: cp --'
    local backup first_count
    backup=$(find "$PROJECT/.tarnished/backups" -type f)
    cmp "$backup" "$SCRATCH/original"
    [[ "$(stat -c %a "$(dirname "$(dirname "$(dirname "$backup")")")")" == 700 ]]
    first_count=$(find "$PROJECT/.tarnished/backups" -type f | wc -l)
    run local_refresh
    assert_output --partial '0 backed-up'
    [[ "$(find "$PROJECT/.tarnished/backups" -type f | wc -l)" == "$first_count" ]]
    echo next > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    local_refresh >/dev/null
    [[ "$(find "$PROJECT/.tarnished/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 2 ]]
    cmp "$backup" "$SCRATCH/original"
}

@test "backup dry-run reports replacement and leaves existing content baseline and backups unchanged" {
    local_refresh >/dev/null
    echo edited > "$PROJECT/.claude/skills/issue.md"
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    run local_refresh --dry-run
    assert_success
    assert_output --partial '[dry-run] backup'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" edited
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    [[ ! -e "$PROJECT/.tarnished/backups" ]]
}

@test "backup root symlink or file prevents replacement and preserves prior baseline" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/outside"
    ln -s "$SCRATCH/outside" "$PROJECT/.tarnished/backups"
    run local_refresh
    assert_success
    assert_output --partial 'backup failed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    [[ -z "$(find "$SCRATCH/outside" -mindepth 1 -print -quit)" ]]
    rm "$PROJECT/.tarnished/backups"
    echo obstruction > "$PROJECT/.tarnished/backups"
    run local_refresh
    assert_output --partial 'backup failed'
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
}

@test "backup copy failure and concurrent live edit abort replacement without advancing state" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin"
    cat > "$SCRATCH/bin/cp" <<'MOCK'
#!/bin/bash
target="${@: -1}"
if [[ "$target" == */.tarnished/backups/* ]]; then exit 1; fi
exec /usr/bin/cp "$@"
MOCK
    chmod +x "$SCRATCH/bin/cp"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'backup failed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    cat > "$SCRATCH/bin/cp" <<'MOCK'
#!/bin/bash
/usr/bin/cp "$@" || exit
if [[ "${@: -1}" == */.tarnished/backups/* ]]; then
    printf 'concurrent edit\n' > "$PROJECT/.claude/skills/issue.md"
fi
MOCK
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'backup failed or target changed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" 'concurrent edit'
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
}

@test "backup content or parent changed after copy cannot authorize replacement" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin"
    cat > "$SCRATCH/bin/cp" <<'MOCK'
#!/bin/bash
/usr/bin/cp "$@" || exit
target="${@: -1}"
if [[ "$target" == */.tarnished/backups/* ]]; then printf 'damaged\n' > "$target"; fi
MOCK
    chmod +x "$SCRATCH/bin/cp"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'backup failed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
}

@test "reserved backup destinations and overlays cannot be refreshed even by broad mappings" {
    mkdir -p "$UPSTREAM_WORK/broad/backups/refresh.old" "$PROJECT/.tarnished/backups/refresh.old"
    echo upstream > "$UPSTREAM_WORK/broad/backups/refresh.old/saved"
    echo original > "$PROJECT/.tarnished/backups/refresh.old/saved"
    jq '.managed_paths = [{src:"broad",dst:".tarnished"}]' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run local_refresh --config "$SCRATCH/config"
    assert_equal "$(cat "$PROJECT/.tarnished/backups/refresh.old/saved")" original
    jq '.managed_paths = [{src:"broad",dst:".claude/skills",overlay:".tarnished/backups/refresh.old"}]' "$PROJECT/.tarnished/refresh.json" > "$SCRATCH/config"
    run local_refresh --config "$SCRATCH/config"
    assert_output --partial 'reserved backup overlay'
    [[ ! -e "$PROJECT/.claude/skills/saved" ]]
    run bash -c 'source "$1"; _manifest_path_excluded .tarnished/backups/refresh.old/saved' _ "$COMMON_SH"
    assert_success
}

@test "backup parent symlink introduced after copying preserves live file and baseline" {
    local_refresh >/dev/null
    cp "$PROJECT/.tarnished/refresh-state.json" "$SCRATCH/state"
    echo changed > "$UPSTREAM_WORK/templates/claude/.claude/skills/issue.md"
    mkdir "$SCRATCH/bin" "$SCRATCH/outside"
    cat > "$SCRATCH/bin/cp" <<'MOCK'
#!/bin/bash
/usr/bin/cp "$@" || exit
target="${@: -1}"
if [[ "$target" == */.tarnished/backups/* ]]; then
    parent="${target%/*}"
    /usr/bin/mv "$parent" "$parent.saved"
    /usr/bin/ln -s "$SCRATCH/outside" "$parent"
fi
MOCK
    chmod +x "$SCRATCH/bin/cp"
    run env PATH="$SCRATCH/bin:$PATH" "$SUT" --source-dir "$UPSTREAM_WORK"
    assert_output --partial 'backup failed'
    assert_equal "$(cat "$PROJECT/.claude/skills/issue.md")" v1-skill
    cmp "$SCRATCH/state" "$PROJECT/.tarnished/refresh-state.json"
    [[ -z "$(find "$SCRATCH/outside" -mindepth 1 -print -quit)" ]]
}
