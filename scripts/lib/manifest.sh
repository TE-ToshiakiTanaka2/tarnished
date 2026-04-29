#!/bin/bash
# =============================================================================
# Manifest Module — for setup.sh --create-manifest / --upgrade (#265)
# =============================================================================
# This library provides:
#   - Manifest read/write (.tarnished-manifest.json)
#   - Per-file lifecycle decisions (manifest_decide — the FR-4 8-case state
#     machine)
#   - manifest_apply (mutate the target tree per decision)
#   - manifest_walk_directory (compute hashes from current state, used by
#     --create-manifest)
#   - manifest_summary_print (FR-11 end-of-run summary)
#
# Sourced by setup.sh in --create-manifest and --upgrade modes only. The
# scaffold modes (single, monorepo init, add-module) do not need this file.
#
# Depends on scripts/lib/common.sh for:
#   - sha256_file
#   - print_error / print_warning / print_info / print_success
#   - MANIFEST_TRACKED / MANIFEST_EXCLUDE_GLOBS / manifest_recording_*
# =============================================================================

# Guard against multiple sourcing.
[[ -n "${_MANIFEST_SH_LOADED:-}" ]] && return
_MANIFEST_SH_LOADED=1

# =============================================================================
# Constants
# =============================================================================

readonly MANIFEST_FILENAME=".tarnished-manifest.json"
readonly MANIFEST_SUPPORTED_VERSION=1

# MANIFEST_EXCLUDE_GLOBS is defined in scripts/lib/common.sh so that
# copy_with_confirm can consult it without sourcing manifest.sh. This file
# relies on the same array.

# =============================================================================
# Path / existence helpers
# =============================================================================

# Echo the manifest path for a given scope root.
# Usage: manifest_path <scope_root>
manifest_path() {
    local scope_root="$1"
    printf '%s/%s' "$scope_root" "$MANIFEST_FILENAME"
}

# Check whether the scope's manifest file exists.
# Usage: manifest_exists <scope_root>
# Returns: 0 if present, 1 if absent.
manifest_exists() {
    local scope_root="$1"
    [[ -f "$(manifest_path "$scope_root")" ]]
}

# =============================================================================
# Read / write
# =============================================================================

# Read and validate the manifest at <scope_root>. Streams the parsed JSON to
# stdout. Rejects unknown major manifest_version values.
# Usage: manifest_read <scope_root>
# Returns: 0 on success (object on stdout), 1 on missing file / parse error /
#          unsupported version.
manifest_read() {
    local scope_root="$1"
    local file
    file="$(manifest_path "$scope_root")"

    if [[ ! -f "$file" ]]; then
        print_error "manifest not found: $file"
        return 1
    fi

    local version
    if ! version=$(jq -r '.manifest_version // 0' "$file" 2>/dev/null); then
        print_error "manifest parse failed (invalid JSON): $file"
        return 1
    fi

    if ! [[ "$version" =~ ^[0-9]+$ ]] || [[ "$version" -lt 1 ]]; then
        print_error "manifest missing required 'manifest_version' field: $file"
        return 1
    fi

    if [[ "$version" -gt "$MANIFEST_SUPPORTED_VERSION" ]]; then
        print_error "Unsupported manifest_version: $version (max supported: $MANIFEST_SUPPORTED_VERSION). Upgrade setup.sh."
        return 1
    fi

    cat "$file"
}

# Write a manifest at <scope_root> from the global MANIFEST_TRACKED snapshot.
# Atomic: writes to a tmp file then mv's it into place so a SIGINT mid-write
# leaves any prior manifest intact.
#
# Usage: manifest_write <scope_root> <tarnished_version> <tarnished_commit> <scaffold_options_json>
# Where <scaffold_options_json> is a JSON object string, e.g.:
#   '{"languages":["rust"],"services":[],"github_actions_enabled":false,
#     "auto_tag_enabled":false,"codex_enabled":false,"monorepo":false}'
# Returns: 0 on success, 1 on jq / IO error.
manifest_write() {
    local scope_root="$1"
    local tarnished_version="$2"
    local tarnished_commit="$3"
    local scaffold_options_json="$4"

    if [[ -z "$scope_root" ]]; then
        print_error "manifest_write: scope_root required"
        return 1
    fi

    local file tmp
    file="$(manifest_path "$scope_root")"
    tmp="${file}.tmp"

    local created_at
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build the {path: hash, ...} object from MANIFEST_TRACKED. Sort keys
    # for stable diffs.
    local files_json
    if ! files_json=$(_manifest_files_to_json); then
        print_error "manifest_write: failed to serialize files map"
        return 1
    fi

    if ! jq -n \
        --argjson manifest_version "$MANIFEST_SUPPORTED_VERSION" \
        --arg tarnished_version "$tarnished_version" \
        --arg tarnished_commit "$tarnished_commit" \
        --arg created_at "$created_at" \
        --argjson scaffold_options "$scaffold_options_json" \
        --argjson files "$files_json" \
        '{
            manifest_version: $manifest_version,
            tarnished_version: $tarnished_version,
            tarnished_commit: $tarnished_commit,
            created_at: $created_at,
            scaffold_options: $scaffold_options,
            files: $files
        }' > "$tmp"; then
        rm -f "$tmp"
        print_error "manifest_write: jq build failed"
        return 1
    fi

    mv "$tmp" "$file"
}

# Internal: serialize MANIFEST_TRACKED to a sorted JSON object.
_manifest_files_to_json() {
    if [[ ${#MANIFEST_TRACKED[@]} -eq 0 ]]; then
        printf '{}'
        return 0
    fi
    local key
    {
        printf '{'
        local first=true
        for key in $(printf '%s\n' "${!MANIFEST_TRACKED[@]}" | LC_ALL=C sort); do
            if [[ "$first" == true ]]; then
                first=false
            else
                printf ','
            fi
            # jq -Rs encodes both key and value safely.
            printf '%s:%s' \
                "$(printf '%s' "$key" | jq -Rs .)" \
                "$(printf '%s' "${MANIFEST_TRACKED[$key]}" | jq -Rs .)"
        done
        printf '}'
    }
}

# =============================================================================
# Directory walk (used by --create-manifest)
# =============================================================================

# Walk <root>, hashing every file that is not in MANIFEST_EXCLUDE_GLOBS.
# Emits one line per file: "<rel_path>\t<sha256:hex>".
# Honors an optional list of additional path prefixes to skip (e.g. monorepo
# module sub-trees when walking the root scope).
#
# Usage: manifest_walk_directory <root> [<additional_skip_prefix>...]
manifest_walk_directory() {
    local root="$1"
    shift
    local skip_prefixes=("$@")

    if [[ ! -d "$root" ]]; then
        print_error "manifest_walk_directory: not a directory: $root"
        return 1
    fi

    local abs_root
    abs_root="$(cd "$root" && pwd)"

    while IFS= read -r -d '' path; do
        local rel="${path#${abs_root}/}"

        # Skip excluded globs.
        if _manifest_path_excluded "$rel"; then
            continue
        fi

        # Skip caller-provided prefixes (used to omit module subtrees from
        # the root walk in monorepo mode).
        local skip=false
        local prefix
        for prefix in "${skip_prefixes[@]}"; do
            if [[ "$rel" == "${prefix}/"* ]] || [[ "$rel" == "$prefix" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == true ]] && continue

        local hash
        if ! hash=$(sha256_file "$path"); then
            continue
        fi
        printf '%s\t%s\n' "$rel" "$hash"
    done < <(find "$abs_root" -type f -print0)
}

# =============================================================================
# Lifecycle decisions
# =============================================================================
#
# manifest_decide is the single function that interprets "did the user edit
# this file" — the predicate is `current_hash == old_hash`. Every other
# upgrade-time behavior flows from the decision it emits.
#
# Inputs (each may be the empty string "" to denote "absent"):
#   <old_hash>      hash from the existing on-disk manifest
#   <current_hash>  hash of the user's current target file (or "" if missing)
#   <new_hash>      hash of the staging-area file produced by re-running plugins
#                   (or "" if the new tarnished version no longer emits this path)
#
# Output (one of):
#   NOOP                  unchanged & unedited (or impossible-to-occur void case)
#   UPDATE                upstream changed; user file matches old → safe to overwrite
#   SKIP_EDITED           user file diverged from old → preserve user edit
#   NEW                   not in old manifest; not in current target → create
#   SKIP_NEW_CONFLICT     not in old manifest; user already has the path → warn + skip
#   LEAVE_REMOVED         in old manifest; absent from new manifest → leave by default
#   PRUNE                 LEAVE_REMOVED + PRUNE_ENABLED=true → delete
#   SKIP_USER_DELETED     in old & new manifests; user file absent → respect deletion
#
# PRUNE_ENABLED is read from a global; it is set from --prune.
manifest_decide() {
    local old="${1:-}"
    local current="${2:-}"
    local new="${3:-}"

    local has_old=false has_current=false has_new=false
    [[ -n "$old" ]]     && has_old=true
    [[ -n "$current" ]] && has_current=true
    [[ -n "$new" ]]     && has_new=true

    if [[ "$has_new" == true ]]; then
        if [[ "$has_old" == false ]]; then
            # Not in old manifest — the new tarnished version added this file.
            if [[ "$has_current" == true ]]; then
                printf 'SKIP_NEW_CONFLICT'
            else
                printf 'NEW'
            fi
            return 0
        fi
        # In old manifest.
        if [[ "$has_current" == false ]]; then
            printf 'SKIP_USER_DELETED'
            return 0
        fi
        # Both old and current present.
        if [[ "$current" == "$old" ]]; then
            # Unedited locally.
            if [[ "$new" == "$old" ]]; then
                printf 'NOOP'
            else
                printf 'UPDATE'
            fi
        else
            # User edited locally.
            printf 'SKIP_EDITED'
        fi
        return 0
    fi

    # has_new == false → file was removed upstream.
    if [[ "$has_old" == false ]]; then
        # Total-function safety: not in old, not in new, possibly not in
        # current either. Treat as a no-op.
        printf 'NOOP'
        return 0
    fi
    if [[ "$has_current" == false ]]; then
        printf 'SKIP_USER_DELETED'
        return 0
    fi
    if [[ "$current" != "$old" ]]; then
        # User has edits to a file that is no longer shipped — always leave.
        printf 'LEAVE_REMOVED'
        return 0
    fi
    # Unedited and removed upstream — prune iff explicitly requested.
    if [[ "${PRUNE_ENABLED:-false}" == true ]]; then
        printf 'PRUNE'
    else
        printf 'LEAVE_REMOVED'
    fi
}

# =============================================================================
# Apply decisions (#265 Phase 3 — stub for now)
# =============================================================================

# manifest_apply mutates the target tree per the given decision. Stubbed in
# Phase 1; full implementation lands in Phase 3 alongside run_upgrade.
#
# Usage: manifest_apply <decision> <staging_path> <target_path>
manifest_apply() {
    print_error "manifest_apply: not implemented (Phase 3 of #265)"
    return 1
}

# manifest_diff_summary emits a compact "(~K +N -M)" summary string used in
# the SKIP_EDITED rows of the end-of-run summary. Stubbed in Phase 1.
manifest_diff_summary() {
    print_error "manifest_diff_summary: not implemented (Phase 3 of #265)"
    return 1
}

# manifest_summary_print emits the FR-11 end-of-run summary block to stderr.
# Stubbed in Phase 1.
manifest_summary_print() {
    print_error "manifest_summary_print: not implemented (Phase 3 of #265)"
    return 1
}
