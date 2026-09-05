#!/bin/bash
# =============================================================================
# Manifest Module — for setup.sh --create-manifest / --upgrade (#265)
# =============================================================================
# This library provides:
#   - Manifest read/write (.tarnished-manifest.json)
#   - Per-file lifecycle decisions (manifest_decide — the FR-4 8-case state
#     machine)
#   - manifest_apply (mutate the target tree per decision)
#   - manifest_walk_directory (private staged distribution inventory)
#   - manifest_adopt_distribution (exact matches and retained v2 baselines)
#   - manifest_summary_print (FR-11 end-of-run summary)
#
# Sourced by setup.sh in --create-manifest and --upgrade modes only. The
# scaffold modes may use recording helpers from common.sh before writing v2 state.
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
readonly MANIFEST_SUPPORTED_VERSION=2

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

# Validate every option that selects a plugin before it can become a source path.
# Historical manifests may omit keys, but present values must have known types.
manifest_options_valid() {
    printf '%s' "$1" | jq -e '
        type == "object" and
        ((has("languages") | not) or
            (.languages | type == "array" and all(.[];
                . == "rust" or . == "python" or . == "node" or
                . == "deno" or . == "latex" or . == "go"))) and
        ((has("services") | not) or
            (.services | type == "array" and all(.[];
                . == "celery" or . == "mysql" or . == "postgresql" or . == "redis"))) and
        ((has("ai_profile") | not) or
            (.ai_profile == "claude-main" or .ai_profile == "codex-main" or
                .ai_profile == "dual")) and
        (. as $options | ["github_actions_enabled", "auto_tag_enabled",
            "codex_enabled", "monorepo"] | all(.[]; . as $key |
                ($options | has($key) | not) or ($options[$key] | type == "boolean")))
    ' >/dev/null 2>&1
}

# Read and validate the manifest at <scope_root>. Streams the parsed JSON to
# stdout. Rejects unknown major manifest_version values.
# Usage: manifest_read <scope_root>
# Returns: 0 on success (object on stdout), 1 on missing file / parse error /
#          unsupported version.
manifest_read() {
    local scope_root="$1"
    local file
    scope_root=$(manifest_physical_root "$scope_root") || return 1
    file="$(manifest_path "$scope_root")"

    if [[ ! -f "$file" ]]; then
        print_error "manifest not found: $file"
        return 1
    fi

    if ! manifest_safe_path "$scope_root" "$MANIFEST_FILENAME"; then
        print_error "Unsafe manifest path: $file"
        return 1
    fi
    if ! jq -e '
        type == "object" and
        (.manifest_version == 1 or .manifest_version == 2) and
        (.tarnished_version | type == "string") and
        (.tarnished_commit | type == "string") and
        (.created_at | type == "string") and
        (.scaffold_options | type == "object") and
        (.scaffold_options.languages // [] | type == "array" and all(.[]; type == "string")) and
        (.scaffold_options.services // [] | type == "array" and all(.[]; type == "string")) and
        (.files | type == "object") and
        ((has("deleted_paths") | not) or
            (.deleted_paths | type == "array" and all(.[]; type == "string" and
                (explode | all(.[]; . >= 32 and . != 127))))) and
        (. as $manifest | all(.deleted_paths[]?; . as $path |
            ($manifest.files | has($path) | not))) and
        (.files | to_entries | all(.[];
            (.key | length > 0) and
            (.key | explode | all(.[]; . >= 32 and . != 127)) and
            (.value | type == "string" and test("^sha256:[0-9a-f]{64}$"))))
    ' "$file" >/dev/null 2>&1; then
        print_error "Invalid manifest schema/version/hash: $file"
        return 1
    fi
    if ! manifest_options_valid "$(jq -c '.scaffold_options' "$file")"; then
        print_error "Invalid manifest scaffold options: $file"
        return 1
    fi
    local version rel
    version=$(jq -r '.manifest_version' "$file")
    while IFS= read -r rel; do
        if ! _manifest_relative_path_valid "$rel" ||
            { [[ "$version" == 2 ]] && ! _manifest_path_eligible "$rel"; }; then
            print_error "Invalid manifest ownership path: $rel"
            return 1
        fi
    done < <(jq -r '.files | keys[]' "$file")
    while IFS= read -r rel; do
        if ! _manifest_path_eligible "$rel"; then
            print_error "Invalid manifest deletion path: $rel"
            return 1
        fi
    done < <(jq -r '.deleted_paths[]?' "$file")

    cat "$file"
}

# Write a manifest at <scope_root> from MANIFEST_TRACKED and MANIFEST_DELETED.
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

    if ! manifest_options_valid "$scaffold_options_json"; then
        print_error "manifest_write: invalid scaffold options"
        return 1
    fi
    local file tmp
    scope_root=$(manifest_physical_root "$scope_root") || return 1
    file="$(manifest_path "$scope_root")"
    if ! manifest_safe_path "$scope_root" "$MANIFEST_FILENAME"; then
        print_error "manifest_write: unsafe manifest path: $file"
        return 1
    fi
    tmp=$(mktemp "${file}.tmp.XXXXXX") || return 1

    local created_at
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build the {path: hash, ...} object from MANIFEST_TRACKED. Sort keys
    # for stable diffs.
    local files_json deleted_json
    if ! files_json=$(_manifest_files_to_json) ||
        ! deleted_json=$(_manifest_deleted_to_json); then
        rm -f "$tmp"
        print_error "manifest_write: failed to serialize files map"
        return 1
    fi

    # Feed the (unbounded) files map to jq via stdin rather than passing it as
    # an --argjson command-line argument. On large targets the serialized map
    # exceeds the kernel ARG_MAX limit, so execve rejects the jq invocation with
    # E2BIG ("Argument list too long") and no manifest is written. stdin is not
    # subject to ARG_MAX. The bounded scalars / scaffold_options object stay as
    # --arg/--argjson — they cannot overflow. The files map becomes jq's input
    # (with deletion intent); sorted keys are preserved. (#289)
    if ! printf '{"files":%s,"deleted_paths":%s}' "$files_json" "$deleted_json" | jq \
        --argjson manifest_version "$MANIFEST_SUPPORTED_VERSION" \
        --arg tarnished_version "$tarnished_version" \
        --arg tarnished_commit "$tarnished_commit" \
        --arg created_at "$created_at" \
        --argjson scaffold_options "$scaffold_options_json" \
        '.deleted_paths as $deleted | {
            manifest_version: $manifest_version,
            tarnished_version: $tarnished_version,
            tarnished_commit: $tarnished_commit,
            created_at: $created_at,
            scaffold_options: $scaffold_options,
            files: .files
        } + (if ($deleted | length) > 0 then {deleted_paths:$deleted} else {} end)' > "$tmp"; then
        rm -f "$tmp"
        print_error "manifest_write: jq build failed"
        return 1
    fi

    # Equivalent successful reconciliation must not churn timestamps/state.
    if [[ -f "$file" ]] && jq -e --slurp '
        (.[0] | del(.created_at)) == (.[1] | del(.created_at))
    ' "$file" "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        return 0
    fi
    if ! manifest_safe_path "$scope_root" "$MANIFEST_FILENAME" ||
        ! mv "$tmp" "$file"; then
        rm -f "$tmp"
        return 1
    fi
}

# Internal: serialize MANIFEST_TRACKED to a sorted JSON object.
_manifest_files_to_json() {
    local key
    for key in "${!MANIFEST_TRACKED[@]}"; do
        if ! _manifest_path_eligible "$key" ||
            [[ ! "${MANIFEST_TRACKED[$key]}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
            print_error "Invalid manifest entry: $key" >&2
            return 1
        fi
    done
    {
        for key in "${!MANIFEST_TRACKED[@]}"; do
            printf '%s\t%s\n' "$key" "${MANIFEST_TRACKED[$key]}"
        done
    } | LC_ALL=C sort | jq -Rn '
        reduce inputs as $line ({};
            ($line | split("\t")) as $entry | .[$entry[0]] = $entry[1])'
}

# Serialize tombstones without turning them into installed hashes or relying on
# command-line argument limits. An adopted exact match must clear its tombstone.
_manifest_deleted_to_json() {
    local rel
    for rel in "${!MANIFEST_DELETED[@]}"; do
        if ! _manifest_path_eligible "$rel" || [[ -n "${MANIFEST_TRACKED[$rel]:-}" ]]; then
            print_error "Invalid or contradictory manifest deletion path: $rel"
            return 1
        fi
    done
    {
        for rel in "${!MANIFEST_DELETED[@]}"; do
            printf '%s\n' "$rel"
        done
    } | LC_ALL=C sort | jq -Rn '[inputs]'
}

# Load deletion intent from validated state without inferring installed bytes.
# Legacy missing eligible entries become tombstones, including helpers no longer
# in today's distribution. Existing v2 tombstones persist until an exact match is
# explicitly restored. Failure leaves the previous in-memory deletion map intact.
manifest_load_deleted() {
    local root="$1" old_json="$2" version rel
    local -A deleted=()
    version=$(printf '%s' "$old_json" | jq -r '.manifest_version // 0') || return 1
    if [[ "$version" == 2 ]]; then
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            _manifest_path_eligible "$rel" || return 1
            deleted["$rel"]=1
        done < <(printf '%s' "$old_json" | jq -r '.deleted_paths[]?')
    elif [[ "$version" == 1 ]]; then
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            if _manifest_path_eligible "$rel" && manifest_safe_path "$root" "$rel" &&
                [[ ! -e "$root/$rel" && ! -L "$root/$rel" ]]; then
                deleted["$rel"]=1
            fi
        done < <(printf '%s' "$old_json" | jq -r '.files | keys[]')
    fi
    unset MANIFEST_DELETED
    declare -gA MANIFEST_DELETED
    for rel in "${!deleted[@]}"; do
        MANIFEST_DELETED["$rel"]=1
    done
}

# Establish ownership only from a private distribution inventory. Never enumerate
# the downstream tree. Legacy hashes are intentionally ignored; v2 baselines are
# retained even when a developer changed or deleted the installed file.
# Usage: manifest_adopt_distribution <root> <staging> <validated-old-json-or-{}>
manifest_adopt_distribution() {
    local root="$1" staging="$2" old_json="$3" rel hash current inventory
    local version
    version=$(printf '%s' "$old_json" | jq -r '.manifest_version // 0') || return 1
    # An incomplete inventory is never evidence of an upstream removal.
    inventory=$(manifest_walk_directory "$staging") || return 1
    manifest_load_deleted "$root" "$old_json" || return 1
    unset MANIFEST_TRACKED
    declare -gA MANIFEST_TRACKED
    if [[ "$version" == 2 ]]; then
        while IFS=$'\t' read -r rel hash; do
            [[ -n "$rel" ]] || continue
            if _manifest_path_eligible "$rel"; then
                MANIFEST_TRACKED["$rel"]="$hash"
            fi
        done < <(printf '%s' "$old_json" | jq -r '.files | to_entries[] | "\(.key)\t\(.value)"')
    elif [[ "$version" == 1 ]]; then
        print_warning "Legacy manifest ownership is unproven; only exact distribution matches are adopted." >&2
        while IFS= read -r rel; do
            print_warning "Legacy claim requires verification (preserved): $root/$rel" >&2
        done < <(printf '%s' "$old_json" | jq -r '.files | keys[]')
    fi
    while IFS=$'\t' read -r rel hash; do
        [[ -n "$rel" ]] || continue
        if ! manifest_safe_path "$root" "$rel"; then
            print_warning "Unsafe candidate preserved: $root/$rel" >&2
            continue
        fi
        if [[ -f "$root/$rel" ]] && current=$(sha256_file "$root/$rel") &&
            [[ "$current" == "$hash" ]]; then
            MANIFEST_TRACKED["$rel"]="$hash"
            unset 'MANIFEST_DELETED[$rel]'
        elif [[ -e "$root/$rel" ]]; then
            print_warning "Unknown or edited file preserved: $root/$rel; compare with $staging/$rel and explicitly adopt the desired file." >&2
        fi
    done <<< "$inventory"
}

# =============================================================================
# Directory walk (used by --create-manifest)
# =============================================================================

# Walk a private distribution staging <root>, hashing eligible helpers only.
# Never call this against a downstream project to infer ownership.
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

    local abs_root inventory
    abs_root=$(manifest_physical_root "$root") || return 1
    inventory=$(mktemp) || return 1
    if ! find "$abs_root" \
        \( -type d \( -name .git -o -name .serena -o -name target -o -name node_modules -o -name .venv -o -name dist -o -name __pycache__ \) -prune \) -o \
        -type f -print0 > "$inventory"; then
        rm -f "$inventory"
        print_error "Cannot enumerate complete distribution: $abs_root"
        return 1
    fi

    while IFS= read -r -d '' path; do
        local rel="${path#${abs_root}/}"

        # Skip excluded globs.
        if ! _manifest_path_eligible "$rel" || ! manifest_safe_path "$abs_root" "$rel"; then
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
            rm -f "$inventory"
            print_error "Cannot hash distribution candidate: $path"
            return 1
        fi
        printf '%s\t%s\n' "$rel" "$hash"
        # find -prune below already excludes .git, .serena, target/, node_modules,
        # .venv, and dist — they are user-tooling/build artifacts and never part
        # of the tarnished-managed surface.
    done < "$inventory"
    rm -f "$inventory"

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

    if [[ "$has_new" == true && "$current" == "$new" ]]; then
        printf 'NOOP'
        return 0
    fi
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
# Apply decisions (Phase 3)
# =============================================================================
#
# manifest_apply tally globals — declared here so callers (run_upgrade) can
# zero them once per scope. Each holds a count; a parallel array per
# decision holds the affected paths for the end-of-run summary.

declare -gi TALLY_NOOP=0
declare -gi TALLY_UPDATED=0
declare -gi TALLY_SKIPPED_EDITED=0
declare -gi TALLY_NEW=0
declare -gi TALLY_SKIPPED_NEW_CONFLICT=0
declare -gi TALLY_LEAVE_REMOVED=0
declare -gi TALLY_PRUNED=0
declare -gi TALLY_SKIPPED_USER_DELETED=0

declare -ga UPDATED_FILES=()
declare -ga SKIPPED_EDITED_FILES=()
declare -ga SKIPPED_EDITED_DIFFS=()        # parallel array, same indices
declare -ga NEW_FILES=()
declare -ga SKIPPED_NEW_CONFLICT_FILES=()
declare -ga LEAVE_REMOVED_FILES=()
declare -ga PRUNED_FILES=()
declare -ga SKIPPED_USER_DELETED_FILES=()

# Reset tallies and file lists. Called by run_upgrade at the start of each
# scope so monorepo per-scope summaries are clean.
manifest_tally_reset() {
    TALLY_NOOP=0
    TALLY_UPDATED=0
    TALLY_SKIPPED_EDITED=0
    TALLY_NEW=0
    TALLY_SKIPPED_NEW_CONFLICT=0
    TALLY_LEAVE_REMOVED=0
    TALLY_PRUNED=0
    TALLY_SKIPPED_USER_DELETED=0
    UPDATED_FILES=()
    SKIPPED_EDITED_FILES=()
    SKIPPED_EDITED_DIFFS=()
    NEW_FILES=()
    SKIPPED_NEW_CONFLICT_FILES=()
    LEAVE_REMOVED_FILES=()
    PRUNED_FILES=()
    SKIPPED_USER_DELETED_FILES=()
}

# Apply a lifecycle decision to the target tree.
#   <decision>: one of NOOP / UPDATE / SKIP_EDITED / NEW / SKIP_NEW_CONFLICT /
#               LEAVE_REMOVED / PRUNE / SKIP_USER_DELETED
#   <rel_path>: scope-relative path (used for tally entries)
#   <staging_path>: absolute path of the file in the staging area (or "" if
#                   no staging file exists, e.g. LEAVE_REMOVED)
#   <target_path>: absolute path of the destination file under the user's tree
#
# Honors the global DRY_RUN to suppress filesystem mutations while still
# updating tallies — this is what powers --dry-run's preview output.
#
# Usage: manifest_apply <decision> <rel> <staged> <target> <expected-current> <expected-desired>
# Missing expected-current denotes an absent destination, not arbitrary content.
manifest_apply() {
    [[ "$#" -eq 6 ]] || { print_error "manifest_apply: expected content hashes required"; return 1; }
    local decision="$1" rel_path="$2" staging_path="$3" target_path="$4"
    local expected_current="$5" expected_desired="$6"
    local target_root staging_root tmp copied_hash
    [[ -z "$expected_current" || "$expected_current" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    [[ -z "$expected_desired" || "$expected_desired" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    if ! _manifest_path_eligible "$rel_path" || [[ "$target_path" != */"$rel_path" ]]; then
        print_warning "Refusing unsafe/ineligible maintenance path: $target_path" >&2
        return 1
    fi
    target_root=$(manifest_physical_root "${target_path%/"$rel_path"}") || return 1
    target_path="$target_root/$rel_path"
    if ! manifest_safe_path "$target_root" "$rel_path"; then
        print_warning "Refusing unsafe maintenance target: $target_path" >&2
        return 1
    fi
    if [[ "$decision" == UPDATE || "$decision" == NEW ]]; then
        [[ -n "$expected_desired" && "$staging_path" == */"$rel_path" ]] || return 1
        staging_root=$(manifest_physical_root "${staging_path%/"$rel_path"}") || return 1
        staging_path="$staging_root/$rel_path"
        manifest_safe_path "$staging_root" "$rel_path" && [[ -f "$staging_path" ]] || return 1
        if [[ "${DRY_RUN:-false}" != true ]]; then
            mkdir -p "$(dirname "$target_path")" || return 1
            manifest_safe_path "$target_root" "$rel_path" || return 1
            tmp=$(mktemp "$(dirname "$target_path")/.tarnished-copy.XXXXXX") || return 1
            if ! cp -p "$staging_path" "$tmp" ||
                ! copied_hash=$(sha256_file "$tmp") || [[ "$copied_hash" != "$expected_desired" ]] ||
                ! manifest_current_matches "$target_root" "$rel_path" "$expected_current" ||
                ! mv -f "$tmp" "$target_path"; then
                rm -f "$tmp"
                print_warning "Preserved changed or failed helper: $target_path; compare with $staging_path and retry" >&2
                return 1
            fi
            if ! manifest_current_matches "$target_root" "$rel_path" "$expected_desired"; then
                print_warning "Installed helper changed before recording: $target_path; preserve it and retry" >&2
                return 1
            fi
        fi
    elif [[ "$decision" == NOOP ]]; then
        # A NOOP can adopt a new baseline; verify the observed bytes still exist.
        manifest_current_matches "$target_root" "$rel_path" "$expected_current" || return 1
    fi

    case "$decision" in
        NOOP)
            ((TALLY_NOOP++)) || true
            ;;
        UPDATE)
            ((TALLY_UPDATED++)) || true
            UPDATED_FILES+=("$rel_path")
            ;;
        SKIP_EDITED)
            local diff
            diff=$(manifest_diff_summary "$staging_path" "$target_path" 2>/dev/null || echo '')
            ((TALLY_SKIPPED_EDITED++)) || true
            SKIPPED_EDITED_FILES+=("$rel_path")
            SKIPPED_EDITED_DIFFS+=("$diff")
            ;;
        NEW)
            ((TALLY_NEW++)) || true
            NEW_FILES+=("$rel_path")
            ;;
        SKIP_NEW_CONFLICT)
            ((TALLY_SKIPPED_NEW_CONFLICT++)) || true
            SKIPPED_NEW_CONFLICT_FILES+=("$rel_path")
            ;;
        LEAVE_REMOVED)
            ((TALLY_LEAVE_REMOVED++)) || true
            LEAVE_REMOVED_FILES+=("$rel_path")
            ;;
        PRUNE)
            if [[ "${DRY_RUN:-false}" != true ]]; then
                if ! manifest_current_matches "$target_root" "$rel_path" "$expected_current"; then
                    print_warning "Preserved helper changed before prune: $target_path; inspect it and retry" >&2
                    return 1
                fi
                rm -f "$target_path" || return 1
            fi
            ((TALLY_PRUNED++)) || true
            PRUNED_FILES+=("$rel_path")
            ;;
        SKIP_USER_DELETED)
            ((TALLY_SKIPPED_USER_DELETED++)) || true
            SKIPPED_USER_DELETED_FILES+=("$rel_path")
            ;;
        *)
            print_error "manifest_apply: unknown decision: $decision"
            return 1
            ;;
    esac
}

# Compare with the decision driver's observation immediately before mutation.
# Path validation is repeated after hashing so a type change is also rejected.
manifest_current_matches() {
    local root="$1" rel="$2" expected="$3" current=""
    manifest_safe_path "$root" "$rel" || return 1
    if [[ -f "$root/$rel" ]]; then
        current=$(sha256_file "$root/$rel") || return 1
    fi
    [[ "$current" == "$expected" ]] && manifest_safe_path "$root" "$rel"
}

# Compact "(~K +N -M)" summary line used in the SKIP_EDITED rows.
#   ~K : lines that differ between staging and target
#   +N : lines in staging not in target (additions if applied)
#   -M : lines in target not in staging (removals if applied)
#
# Bounds the diff at 999 in each direction so a giant divergence doesn't
# blow the column width of the summary block.
#
# Usage: manifest_diff_summary <staging_path> <target_path>
manifest_diff_summary() {
    local staging="$1"
    local target="$2"

    if [[ ! -f "$staging" ]] || [[ ! -f "$target" ]]; then
        printf '(diff unavailable)'
        return 0
    fi

    # `diff -u` line tally; ignore the "+++"/"---" header lines.
    local added removed
    added=$(diff "$target" "$staging" | grep -c '^>' || true)
    removed=$(diff "$target" "$staging" | grep -c '^<' || true)

    local changed
    changed=$(( added < removed ? added : removed ))
    local pure_add=$(( added - changed ))
    local pure_rm=$(( removed - changed ))

    [[ $changed  -gt 999 ]] && changed=999
    [[ $pure_add -gt 999 ]] && pure_add=999
    [[ $pure_rm  -gt 999 ]] && pure_rm=999

    printf '(~%d +%d -%d)' "$changed" "$pure_add" "$pure_rm"
}

# Print the FR-11 end-of-run summary block to stderr.
#
# Usage: manifest_summary_print <old_version> <new_version> [<scope_label>]
# When <scope_label> is set (monorepo per-scope output), the section is
# preceded by `[<scope_label>]`.
manifest_summary_print() {
    local old_version="$1"
    local new_version="$2"
    local scope_label="${3:-}"

    {
        if [[ -n "$scope_label" ]]; then
            printf '[%s]\n' "$scope_label"
        else
            printf 'Tarnished upgrade summary (%s → %s)\n' "$old_version" "$new_version"
            printf '─────────────────────────────────────────────\n'
        fi
        printf '  Updated:                  %4d file(s)\n' "$TALLY_UPDATED"
        local f
        for f in "${UPDATED_FILES[@]}"; do
            printf '    %s\n' "$f"
        done

        printf '  Skipped (edited):         %4d file(s)\n' "$TALLY_SKIPPED_EDITED"
        local i=0
        while [[ $i -lt ${#SKIPPED_EDITED_FILES[@]} ]]; do
            printf '    %s %s\n' "${SKIPPED_EDITED_FILES[$i]}" "${SKIPPED_EDITED_DIFFS[$i]}"
            ((i++)) || true
        done

        printf '  New:                      %4d file(s)\n' "$TALLY_NEW"
        for f in "${NEW_FILES[@]}"; do
            printf '    %s\n' "$f"
        done

        if [[ "${PRUNE_ENABLED:-false}" == true ]]; then
            printf '  Pruned:                   %4d file(s)\n' "$TALLY_PRUNED"
            for f in "${PRUNED_FILES[@]}"; do
                printf '    %s\n' "$f"
            done
        else
            printf '  Removed (would prune):    %4d file(s)\n' "$TALLY_LEAVE_REMOVED"
            for f in "${LEAVE_REMOVED_FILES[@]}"; do
                printf '    %s\n' "$f"
            done
        fi

        printf '  Skipped (deleted by user):%4d file(s)\n' "$TALLY_SKIPPED_USER_DELETED"
        for f in "${SKIPPED_USER_DELETED_FILES[@]}"; do
            printf '    %s\n' "$f"
        done

        if [[ "$TALLY_SKIPPED_NEW_CONFLICT" -gt 0 ]]; then
            printf '  Skipped (new conflict):   %4d file(s)\n' "$TALLY_SKIPPED_NEW_CONFLICT"
            for f in "${SKIPPED_NEW_CONFLICT_FILES[@]}"; do
                printf '    %s\n' "$f"
            done
        fi

        if [[ -z "$scope_label" ]]; then
            printf '─────────────────────────────────────────────\n'
            if [[ "${DRY_RUN:-false}" == true ]]; then
                printf '  Dry-run; no files were modified.\n'
            else
                printf '  Manifest updated.\n'
            fi
        fi
    } >&2
}
