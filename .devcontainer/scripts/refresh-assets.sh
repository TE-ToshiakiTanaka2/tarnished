#!/bin/bash
# =============================================================================
# refresh-assets.sh — Always-latest sync for shared Claude/Codex assets (#279)
# =============================================================================
# Mirrors a whitelist of operational assets (.claude/{commands,skills,scripts,
# rules}/) from upstream tarnished into the project, so a project scaffolded a
# month ago still picks up the latest skill/command revisions automatically.
#
# Invocation paths (both converge here):
#   1. First container boot — post.sh sources nothing; instead, the marker
#      block appended by templates/core/plugin.sh::plugin_post_copy runs the
#      script directly.
#   2. Every subsequent container start — postStartCommand in
#      templates/core/.devcontainer/devcontainer.json invokes it.
#
# FR-5 invariant: container start MUST NOT block on this script. Every
# failure path emits print_warning and returns 0. The only `exit 1` is for
# an unknown CLI flag (programmer error). `set -e` is deliberately NOT used
# — the script handles errors explicitly so a transient git/rsync failure
# never aborts container start.
# =============================================================================

# Strictness without -e: -u catches unset vars, -o pipefail catches early
# failures in pipes. -e is omitted because every fallible operation is
# explicitly checked; turning it on would override the FR-5 invariant.
set -uo pipefail

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
# When sourced from post.sh (which already loaded scripts/lib/common.sh in
# downstream contexts that source it), print_* may already exist. We define
# minimal fallbacks so the script works standalone (postStartCommand) too.

if ! declare -F print_info >/dev/null 2>&1; then
    print_info()    { echo "[INFO] $*"; }
fi
if ! declare -F print_success >/dev/null 2>&1; then
    print_success() { echo "[OK] $*"; }
fi
if ! declare -F print_warning >/dev/null 2>&1; then
    print_warning() { echo "[WARN] $*" >&2; }
fi
if ! declare -F print_error >/dev/null 2>&1; then
    print_error()   { echo "[ERROR] $*" >&2; }
fi

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
readonly REFRESH_SCHEMA_VERSION=1
readonly DEFAULT_CONFIG_RELPATH=".tarnished/refresh.json"
readonly FALLBACK_CACHE_DIR_RELPATH=".cache/tarnished"

# -----------------------------------------------------------------------------
# Globals populated from CLI flags
# -----------------------------------------------------------------------------
CONFIG_PATH=""
DRY_RUN=false
FORCE_PULL=false
QUIET=false

# Globals populated from refresh.json
UPSTREAM_REPO_URL=""
UPSTREAM_BRANCH=""
CLONE_DIR=""
declare -a MANAGED_SRC=()
declare -a MANAGED_DST=()
declare -a MANAGED_OVERLAY=()

# Set true by ensure_clone when it performs a fresh clone, so pull_if_changed
# does not short-circuit the very first sync (the just-cloned cache trivially
# matches origin/HEAD but the project still needs the initial mirror).
JUST_CLONED=false

# Globals tracking summary tallies
SYNCED_PATHS=0
ADDED_FILES=0
REMOVED_FILES=0
OVERLAY_FILES=0

# Repo root — the parent project where managed_paths apply.
PROJECT_ROOT=""

# -----------------------------------------------------------------------------
# parse_args — process CLI flags. Unknown flag is the only exit-1 path.
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                if [[ $# -lt 2 ]] || [[ "${2:0:2}" == "--" ]]; then
                    print_error "refresh-assets: --config requires a path argument"
                    return 1
                fi
                CONFIG_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force-pull)
                FORCE_PULL=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                cat <<EOF
Usage: refresh-assets.sh [--config <path>] [--dry-run] [--force-pull] [--quiet]

Always-latest sync for shared Claude/Codex assets. See #279.

Options:
  --config <path>   Path to refresh.json (default: <project_root>/${DEFAULT_CONFIG_RELPATH})
  --dry-run         Print actions; don't pull or rsync
  --force-pull      Skip the git ls-remote SHA cache check; always pull
  --quiet           Suppress per-path "no change" messages

Always returns 0 except for unknown CLI flags (exit 1).
EOF
                exit 0
                ;;
            *)
                print_error "refresh-assets: unknown flag '$1'"
                return 1
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# resolve_project_root — locate the project root (where refresh.json lives).
# Walks up from the script directory until .tarnished/ or .git/ is found.
# Falls back to $PWD.
# -----------------------------------------------------------------------------
resolve_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Common case: script is at <project>/.devcontainer/scripts/refresh-assets.sh
    local candidate
    candidate="$(cd "${script_dir}/../.." && pwd)"
    if [[ -d "${candidate}/.tarnished" ]] || [[ -d "${candidate}/.git" ]]; then
        PROJECT_ROOT="$candidate"
        return 0
    fi

    # Fallback: walk up from PWD looking for a marker.
    candidate="$PWD"
    while [[ "$candidate" != "/" ]]; do
        if [[ -d "${candidate}/.tarnished" ]] || [[ -d "${candidate}/.git" ]]; then
            PROJECT_ROOT="$candidate"
            return 0
        fi
        candidate="$(dirname "$candidate")"
    done

    PROJECT_ROOT="$PWD"
}

# -----------------------------------------------------------------------------
# load_config — locate, read, and validate refresh.json.
# Populates UPSTREAM_REPO_URL, UPSTREAM_BRANCH, CLONE_DIR, MANAGED_*.
# Returns: 0 on success; 1 on missing/malformed/unsupported (caller exits 0).
# -----------------------------------------------------------------------------
load_config() {
    if [[ -z "$CONFIG_PATH" ]]; then
        CONFIG_PATH="${PROJECT_ROOT}/${DEFAULT_CONFIG_RELPATH}"
    fi

    if [[ ! -f "$CONFIG_PATH" ]]; then
        print_warning "refresh-assets: refresh.json missing at ${CONFIG_PATH}; nothing to sync"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        print_warning "refresh-assets: jq not found on PATH; cannot parse refresh.json"
        return 1
    fi

    local schema
    schema=$(jq -r '.schema_version // 0' "$CONFIG_PATH" 2>/dev/null) || schema=0
    if [[ "$schema" != "$REFRESH_SCHEMA_VERSION" ]]; then
        print_warning "refresh-assets: unsupported schema_version=${schema} (expected ${REFRESH_SCHEMA_VERSION}); refusing to sync"
        return 1
    fi

    UPSTREAM_REPO_URL=$(jq -r '.upstream.repo_url // ""' "$CONFIG_PATH" 2>/dev/null)
    UPSTREAM_BRANCH=$(jq -r '.upstream.branch // ""' "$CONFIG_PATH" 2>/dev/null)
    CLONE_DIR=$(jq -r '.clone_dir // ""' "$CONFIG_PATH" 2>/dev/null)

    # Env overrides (consistent with setup.sh:25-26).
    if [[ -n "${DEVCONTAINER_REPO_URL:-}" ]]; then
        UPSTREAM_REPO_URL="$DEVCONTAINER_REPO_URL"
    fi
    if [[ -n "${DEVCONTAINER_BRANCH:-}" ]]; then
        UPSTREAM_BRANCH="$DEVCONTAINER_BRANCH"
    fi

    if [[ -z "$UPSTREAM_REPO_URL" ]] || [[ -z "$UPSTREAM_BRANCH" ]] || [[ -z "$CLONE_DIR" ]]; then
        print_warning "refresh-assets: refresh.json missing required fields (upstream.repo_url/branch, clone_dir)"
        return 1
    fi

    # Read managed_paths into parallel arrays. jq emits TSV so we split safely
    # without arming bash word-splitting on user content.
    local src dst overlay
    while IFS=$'\t' read -r src dst overlay; do
        [[ -z "$src" ]] && continue
        MANAGED_SRC+=("$src")
        MANAGED_DST+=("$dst")
        MANAGED_OVERLAY+=("$overlay")
    done < <(jq -r '
        .managed_paths // []
        | .[]
        | [.src, .dst, (.overlay // "")]
        | @tsv
    ' "$CONFIG_PATH" 2>/dev/null)

    if [[ ${#MANAGED_SRC[@]} -eq 0 ]]; then
        # Empty whitelist is valid — script becomes a no-op.
        $QUIET || print_info "refresh-assets: managed_paths is empty; nothing to sync"
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# ensure_clone — make sure CLONE_DIR exists as a git checkout.
# Falls back to $HOME/<FALLBACK_CACHE_DIR_RELPATH> if CLONE_DIR's parent is
# not writable. Returns 0 if a usable clone is in place; 1 otherwise.
# -----------------------------------------------------------------------------
ensure_clone() {
    if [[ -d "$CLONE_DIR" ]]; then
        if [[ -d "${CLONE_DIR}/.git" ]]; then
            return 0
        fi
        # Directory exists but is not a git repo. Refuse to silently delete —
        # we cannot distinguish a corrupted clone from intentional content.
        # Manual cleanup is required, but we still exit 0 (FR-5: never block
        # container start); print_warning matches that contract.
        print_warning "refresh-assets: ${CLONE_DIR} exists but is not a git repo; remove it manually to enable refresh"
        return 1
    fi

    local parent
    parent="$(dirname "$CLONE_DIR")"

    # Try to create the parent if missing & we can.
    if [[ ! -d "$parent" ]]; then
        if ! mkdir -p "$parent" 2>/dev/null; then
            print_warning "refresh-assets: cannot create ${parent}; falling back to \$HOME/${FALLBACK_CACHE_DIR_RELPATH}"
            CLONE_DIR="${HOME}/${FALLBACK_CACHE_DIR_RELPATH}"
            mkdir -p "$(dirname "$CLONE_DIR")" 2>/dev/null || true
        fi
    elif [[ ! -w "$parent" ]]; then
        print_warning "refresh-assets: ${parent} not writable; falling back to \$HOME/${FALLBACK_CACHE_DIR_RELPATH}"
        CLONE_DIR="${HOME}/${FALLBACK_CACHE_DIR_RELPATH}"
        mkdir -p "$(dirname "$CLONE_DIR")" 2>/dev/null || true
    fi

    # If the fallback directory already exists and is a git repo, reuse it.
    if [[ -d "${CLONE_DIR}/.git" ]]; then
        return 0
    fi

    if $DRY_RUN; then
        print_info "refresh-assets: [dry-run] would clone ${UPSTREAM_REPO_URL}@${UPSTREAM_BRANCH} into ${CLONE_DIR}"
        return 1
    fi

    print_info "refresh-assets: cloning ${UPSTREAM_REPO_URL}@${UPSTREAM_BRANCH} into ${CLONE_DIR}..."
    if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" --quiet \
            "$UPSTREAM_REPO_URL" "$CLONE_DIR" 2>/dev/null; then
        print_warning "refresh-assets: clone failed (network unreachable?); project keeps existing assets"
        rm -rf "$CLONE_DIR" 2>/dev/null || true
        return 1
    fi

    # Mark for main() so pull_if_changed does not short-circuit the very
    # first sync — local SHA trivially equals the just-cloned origin SHA.
    JUST_CLONED=true
    return 0
}

# -----------------------------------------------------------------------------
# pull_if_changed — check upstream SHA against local HEAD; fetch + reset only
# when they differ. Returns 0 if the cache is usable for sync; 1 to skip
# sync (no-op or fetch failed but cache still usable).
# -----------------------------------------------------------------------------
pull_if_changed() {
    # Just-cloned caches always need the first sync, even though local SHA
    # trivially equals origin's. ensure_clone sets JUST_CLONED for us.
    if $JUST_CLONED; then
        return 0
    fi

    local local_sha
    local_sha=$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null) || local_sha=""

    if ! $FORCE_PULL && [[ -n "$local_sha" ]]; then
        local remote_sha
        remote_sha=$(git -C "$CLONE_DIR" ls-remote origin "$UPSTREAM_BRANCH" 2>/dev/null \
                        | awk '{print $1}' | head -1)
        if [[ -z "$remote_sha" ]]; then
            print_warning "refresh-assets: ls-remote failed; using cached upstream@${local_sha:0:7}"
            return 0
        fi
        if [[ "$remote_sha" == "$local_sha" ]]; then
            $QUIET || print_success "refresh-assets: upstream unchanged (sha=${local_sha:0:7})"
            return 1
        fi
    fi

    if $DRY_RUN; then
        print_info "refresh-assets: [dry-run] would fetch + reset --hard origin/${UPSTREAM_BRANCH}"
        return 0
    fi

    if ! git -C "$CLONE_DIR" fetch --quiet origin "$UPSTREAM_BRANCH" 2>/dev/null; then
        print_warning "refresh-assets: fetch failed; cache untouched (upstream@${local_sha:0:7})"
        return 0
    fi

    # The cache is treated as an immutable mirror — local edits are never
    # expected. Users wanting to test a local upstream patch should set
    # DEVCONTAINER_REPO_URL=file:///path/to/local/clone instead.
    if ! git -C "$CLONE_DIR" reset --hard --quiet "origin/${UPSTREAM_BRANCH}" 2>/dev/null; then
        print_warning "refresh-assets: reset --hard failed; cache may be in an unexpected state"
        return 0
    fi

    return 0
}

# -----------------------------------------------------------------------------
# safe_join — verify that joining <root>/<rel> stays within <root>. Rejects
# absolute paths, "..", and any segment escape after canonicalization. Returns
# the joined absolute path on stdout (no trailing slash) on success.
# Returns: 0 on success; 1 if <rel> escapes <root> or contains a forbidden
# pattern. The script is the only caller; refresh.json may be edited by the
# user, so this is a defensive check, not a trust gate.
# -----------------------------------------------------------------------------
safe_join() {
    local root="$1"
    local rel="$2"

    # Reject empty, absolute, or "..-bearing" inputs up front. Even with
    # canonicalization, an attacker-controlled refresh.json should never be
    # able to produce a joined path that resolves outside <root>.
    if [[ -z "$rel" ]]; then
        return 1
    fi
    if [[ "${rel:0:1}" == "/" ]]; then
        return 1
    fi
    case "/$rel/" in
        */../*) return 1 ;;
    esac

    local joined="${root%/}/${rel}"
    # Canonicalize WITHOUT requiring the path to exist (-m). Compare prefix.
    local canonical_root canonical_joined
    canonical_root=$(realpath -m "$root" 2>/dev/null) || return 1
    canonical_joined=$(realpath -m "$joined" 2>/dev/null) || return 1
    if [[ "$canonical_joined" != "$canonical_root" ]] \
        && [[ "$canonical_joined" != "${canonical_root%/}/"* ]]; then
        return 1
    fi
    printf '%s' "$canonical_joined"
}

# -----------------------------------------------------------------------------
# sync_paths — for each managed_paths entry, mirror upstream into project,
# then overlay <project>/<overlay>/ on top.
# -----------------------------------------------------------------------------
sync_paths() {
    if ! command -v rsync &>/dev/null; then
        print_warning "refresh-assets: rsync not found on PATH; cannot sync"
        return
    fi

    local i
    for i in "${!MANAGED_SRC[@]}"; do
        local src_rel="${MANAGED_SRC[$i]}"
        local dst_rel="${MANAGED_DST[$i]}"
        local overlay_rel="${MANAGED_OVERLAY[$i]}"

        # Defensive: refresh.json values must stay inside CLONE_DIR/PROJECT_ROOT.
        # Anything else (absolute paths, "..", etc.) is treated as a configuration
        # error — skip the entry with a warning, never write outside the bounds.
        local src_abs dst_abs
        src_abs=$(safe_join "$CLONE_DIR" "$src_rel") || {
            print_warning "refresh-assets: src ${src_rel} escapes clone_dir; skipping"
            continue
        }
        dst_abs=$(safe_join "$PROJECT_ROOT" "$dst_rel") || {
            print_warning "refresh-assets: dst ${dst_rel} escapes project root; skipping"
            continue
        }

        if [[ ! -d "$src_abs" ]]; then
            print_warning "refresh-assets: upstream ${src_rel} missing in cache; skipping"
            continue
        fi

        # Pass 1: mirror upstream → project (delete stale entries).
        local rsync_opts=(-a --delete)
        $DRY_RUN && rsync_opts+=(--dry-run)

        mkdir -p "$dst_abs" 2>/dev/null || true

        local rsync_log
        rsync_log=$(rsync "${rsync_opts[@]}" --itemize-changes \
                        "${src_abs}/" "${dst_abs}/" 2>&1) || {
            print_warning "refresh-assets: rsync of ${dst_rel} failed; skipping (sibling paths still attempted)"
            continue
        }

        # Tally added/removed from --itemize-changes output.
        local added removed
        added=$(grep -cE '^>f' <<<"$rsync_log" 2>/dev/null)
        removed=$(grep -cE '^\*deleting' <<<"$rsync_log" 2>/dev/null)
        ADDED_FILES=$((ADDED_FILES + added))
        REMOVED_FILES=$((REMOVED_FILES + removed))
        SYNCED_PATHS=$((SYNCED_PATHS + 1))

        # Pass 2: overlay sidecar (no --delete; user files win).
        if [[ -n "$overlay_rel" ]]; then
            local overlay_abs
            overlay_abs=$(safe_join "$PROJECT_ROOT" "$overlay_rel") || {
                print_warning "refresh-assets: overlay ${overlay_rel} escapes project root; skipping"
                continue
            }
            if [[ -d "$overlay_abs" ]]; then
                local overlay_opts=(-a)
                $DRY_RUN && overlay_opts+=(--dry-run)

                local overlay_log
                overlay_log=$(rsync "${overlay_opts[@]}" --itemize-changes \
                                "${overlay_abs}/" "${dst_abs}/" 2>&1) || {
                    print_warning "refresh-assets: overlay rsync of ${overlay_rel} failed"
                    continue
                }
                local overlaid
                overlaid=$(grep -cE '^>f' <<<"$overlay_log" 2>/dev/null)
                OVERLAY_FILES=$((OVERLAY_FILES + overlaid))
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# print_summary — one structured line per FR description.
# -----------------------------------------------------------------------------
print_summary() {
    local prefix="refresh-assets:"
    $DRY_RUN && prefix="refresh-assets [dry-run]:"
    print_success "${prefix} ${SYNCED_PATHS} paths synced (${ADDED_FILES} files added, ${REMOVED_FILES} removed); ${OVERLAY_FILES} overlay files preserved"
}

# -----------------------------------------------------------------------------
# main — orchestration. Always exits 0 except for unknown-flag exit 1.
# -----------------------------------------------------------------------------
main() {
    parse_args "$@" || exit 1

    resolve_project_root

    if ! load_config; then
        exit 0
    fi

    if ! ensure_clone; then
        exit 0
    fi

    if ! pull_if_changed; then
        # No-op (upstream unchanged); summary already printed.
        exit 0
    fi

    sync_paths
    print_summary
    exit 0
}

main "$@"
