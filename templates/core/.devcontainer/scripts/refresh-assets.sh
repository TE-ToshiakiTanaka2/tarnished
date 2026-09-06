#!/bin/bash
# Refresh distributed AI assets without claiming or deleting developer files.
# Standalone container-start helper: failures warn and return 0. Deliberately no -e.
set -uo pipefail

if ! declare -F print_info >/dev/null; then
    print_info() { echo "[INFO] $*"; }
fi
if ! declare -F print_success >/dev/null; then
    print_success() { echo "[OK] $*"; }
fi
if ! declare -F print_warning >/dev/null; then
    print_warning() { echo "[WARN] $*" >&2; }
fi

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    print_warning 'refresh-assets: Bash 4.4+ is required; install a modern Bash and retry'
    exit 0
fi

PROJECT_ROOT=""
PROJECT_INPUT_ROOT=""
SCRIPT_REPO_ROOT=""
SOURCE_DIR=""
CONFIG_PATH=""
DRY_RUN=false
QUIET=false
UPSTREAM_REPO_URL=""
UPSTREAM_BRANCH=""
CLONE_DIR=""
COMMIT=""
STATE_PATH=""
STATE='{"schema_version":1,"entries":{}}'
CATALOG='[]'
declare -A ENTRIES=()
declare -A CANDIDATES=()
CHANGED=0
REMOVED=0
UNCHANGED=0
ADOPTED=0
PRESERVED=0
CONFLICTS=0
UNKNOWN=0
UNSAFE=0
FAILURES=0
BACKED_UP=0
BACKUP_RUN=""
BACKUP_PATH=""
declare -a HASH_COMMAND=()

warn() {
    print_warning "refresh-assets: $*"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config|--project-root|--source-dir)
                if [[ $# -lt 2 || "$2" == --* || -z "$2" ]]; then
                    warn "$1 requires a path argument; supply it and retry"
                    return 2
                fi
                case "$1" in
                    --config) CONFIG_PATH="$2" ;;
                    --project-root) PROJECT_ROOT="$2" ;;
                    --source-dir) SOURCE_DIR="$2" ;;
                esac
                shift 2
                ;;
            --dry-run) DRY_RUN=true; shift ;;
            --quiet) QUIET=true; shift ;;
            --force-pull) shift ;; # Compatibility: valid caches are always fetched.
            -h|--help)
                print_info 'Usage: refresh-assets.sh [--config <path>] [--project-root <path>] [--source-dir <path>] [--dry-run] [--force-pull] [--quiet]'
                return 2
                ;;
            *) warn "unknown flag '$1'"; return 1 ;;
        esac
    done
}

# Canonicalize only the trusted outer root. Host prefixes such as /var may be
# symlinks; the root leaf itself and all later paths beneath it must be ordinary.
physical_root() {
    local path="$1" ancestor suffix="" part
    [[ "$path" == /* && ! "$path" =~ [[:cntrl:]] ]] || return 1
    while [[ "$path" != / && "$path" == */ ]]; do path="${path%/}"; done
    case "$path/" in */../*|*/./*) return 1 ;; esac
    [[ ! -L "$path" ]] || return 1
    ancestor="$path"
    while [[ ! -e "$ancestor" ]]; do
        part="${ancestor##*/}"
        suffix="/$part$suffix"
        ancestor="${ancestor%/*}"
        [[ -n "$ancestor" ]] || ancestor=/
    done
    [[ -d "$ancestor" ]] || return 1
    ancestor=$(cd -P -- "$ancestor" && pwd -P) || return 1
    if [[ "$ancestor" == / && -z "$suffix" ]]; then printf '/'; else printf '%s' "${ancestor%/}$suffix"; fi
}

# Check every lexical component, including dangling links and non-directory parents.
ordinary_path() {
    local path="$1" part current="" i
    [[ "$path" == /* && ! "$path" =~ [[:cntrl:]] ]] || return 1
    local -a parts
    IFS=/ read -r -a parts <<< "$path"
    for i in "${!parts[@]}"; do
        part="${parts[$i]}"
        [[ -z "$part" ]] && continue
        [[ "$part" != . && "$part" != .. ]] || return 1
        current="${current}/${part}"
        [[ ! -L "$current" ]] || return 1
        if (( i < ${#parts[@]} - 1 )) && [[ -e "$current" && ! -d "$current" ]]; then
            return 1
        fi
    done
}

relative_path() {
    [[ -n "$1" && "$1" != /* && ! "$1" =~ [[:cntrl:]] ]] || return 1
    case "/$1/" in */../*|*/./*|*//* ) return 1 ;; esac
}

safe_join() {
    relative_path "$2" && ordinary_path "${1%/}/$2" || return 1
    printf '%s' "${1%/}/$2"
}

# Configuration does not grant ownership. Reject ambiguous overlapping projections.
valid_catalog() {
    jq -e '
        def rel: type == "string" and length > 0 and
            (explode | all(. >= 32 and . != 127)) and
            (startswith("/") | not) and
            (split("/") | all(. != "" and . != "." and . != ".."));
        type == "array" and all(.[];
            type == "object" and (.src | rel) and (.dst | rel) and
            ((.overlay == null) or (.overlay | rel))) and
        ([.[] | .dst, (.overlay // empty)] as $paths |
            all(range(0; $paths|length); . as $i |
                all(range($i+1; $paths|length); . as $j |
                    ($paths[$i] != $paths[$j]) and
                    ($paths[$i] | startswith($paths[$j]+"/") | not) and
                    ($paths[$j] | startswith($paths[$i]+"/") | not))))
    ' >/dev/null 2>&1
}

load_config() {
    [[ -n "$CONFIG_PATH" ]] || CONFIG_PATH="${PROJECT_ROOT}/.tarnished/refresh.json"
    [[ "$CONFIG_PATH" == /* ]] || CONFIG_PATH="${PWD}/${CONFIG_PATH}"
    if [[ "$CONFIG_PATH" == "$PROJECT_INPUT_ROOT/"* ]]; then
        CONFIG_PATH="$PROJECT_ROOT/${CONFIG_PATH#"$PROJECT_INPUT_ROOT/"}"
    elif [[ "$CONFIG_PATH" != "$PROJECT_ROOT/"* ]]; then
        local config_parent config_probe config_suffix config_physical
        [[ ! -L "$CONFIG_PATH" ]] || { warn 'unsafe config leaf; use an ordinary config file'; return 1; }
        config_parent=$(dirname "$CONFIG_PATH")
        config_probe="$config_parent"
        config_suffix="/${CONFIG_PATH##*/}"
        # Find any alternate spelling of the project boundary before permitting
        # host aliases in an explicitly supplied external config's ancestry.
        while [[ "$config_probe" != / ]]; do
            config_physical=$(cd -P -- "$config_probe" 2>/dev/null && pwd -P) || config_physical=""
            if [[ "$config_physical" == "$PROJECT_ROOT" ]]; then
                CONFIG_PATH="$PROJECT_ROOT$config_suffix"
                break
            fi
            config_suffix="/${config_probe##*/}$config_suffix"
            config_probe=$(dirname "$config_probe")
        done
        if [[ "$config_probe" == / ]]; then
            config_parent=$(cd -P -- "$config_parent" && pwd -P) || {
                warn 'unsafe config parent; use an ordinary config directory'; return 1;
            }
            CONFIG_PATH="${config_parent%/}/${CONFIG_PATH##*/}"
        fi
    fi
    if ! ordinary_path "$CONFIG_PATH" || [[ ! -f "$CONFIG_PATH" ]]; then
        warn "refresh.json missing or unsafe at ${CONFIG_PATH}; restore an ordinary config and retry"
        return 1
    fi
    if ! jq -e '.schema_version == 1 and (.upstream.repo_url | type == "string" and length > 0) and
        (.upstream.branch | type == "string" and length > 0) and
        (.clone_dir | type == "string" and startswith("/")) and
        ((has("use_default_managed_paths") | not) or (.use_default_managed_paths | type == "boolean"))' \
        "$CONFIG_PATH" >/dev/null 2>&1; then
        warn 'invalid config or unsupported schema_version; repair refresh.json and retry'
        return 1
    fi
    CATALOG=$(jq -c '.managed_paths' "$CONFIG_PATH") || return 1
    if ! valid_catalog <<< "$CATALOG"; then
        warn 'invalid/overlapping managed_paths (path escapes project root or overlay); repair config and retry'
        return 1
    fi
    UPSTREAM_REPO_URL=$(jq -r '.upstream.repo_url' "$CONFIG_PATH")
    UPSTREAM_BRANCH=$(jq -r '.upstream.branch' "$CONFIG_PATH")
    CLONE_DIR=$(jq -r '.clone_dir' "$CONFIG_PATH")
    UPSTREAM_REPO_URL="${DEVCONTAINER_REPO_URL:-$UPSTREAM_REPO_URL}"
    UPSTREAM_BRANCH="${DEVCONTAINER_BRANCH:-$UPSTREAM_BRANCH}"
    [[ ! "$UPSTREAM_REPO_URL" =~ [[:cntrl:]] && "$UPSTREAM_REPO_URL" != -* &&
        "$UPSTREAM_BRANCH" != -* ]] &&
        git check-ref-format "refs/heads/${UPSTREAM_BRANCH}" >/dev/null 2>&1 || {
        warn 'invalid upstream URL/branch; repair config and retry'; return 1;
    }
}

# Persistent caches may only be reset after origin, ownership and cleanliness checks.
validate_cache() {
    CLONE_DIR=$(physical_root "$CLONE_DIR") && ordinary_path "$CLONE_DIR" &&
        [[ "$CLONE_DIR" != / ]] || {
        warn "unsafe cache path ${CLONE_DIR}; choose a separate ordinary directory"; return 1;
    }
    if [[ "$CLONE_DIR" == "$PROJECT_ROOT" || "$CLONE_DIR" == "$PROJECT_ROOT/"* ||
          "$PROJECT_ROOT" == "$CLONE_DIR/"* ]]; then
        warn 'cache overlaps project; choose a cache outside the project'; return 1
    fi
    if [[ -n "$SCRIPT_REPO_ROOT" ]] &&
        [[ "$CLONE_DIR" == "$SCRIPT_REPO_ROOT" || "$CLONE_DIR" == "$SCRIPT_REPO_ROOT/"* ||
           "$SCRIPT_REPO_ROOT" == "$CLONE_DIR/"* ]]; then
        warn 'cache overlaps updater source checkout; choose a dedicated cache outside it'
        return 1
    fi
    if [[ -e "$CLONE_DIR" ]]; then
        if [[ ! -d "$CLONE_DIR/.git" ]] || ! ordinary_path "$CLONE_DIR/.git"; then
            warn "$CLONE_DIR is not a git repo with an ordinary .git directory; choose a dedicated cache"
            return 1
        fi
        local origin dirty top
        origin=$(git -C "$CLONE_DIR" remote get-url origin 2>/dev/null) || return 1
        top=$(git -C "$CLONE_DIR" rev-parse --show-toplevel 2>/dev/null) || return 1
        dirty=$(git --no-optional-locks -C "$CLONE_DIR" status --porcelain --untracked-files=all 2>/dev/null) || return 1
        if [[ "$origin" != "$UPSTREAM_REPO_URL" || "$top" != "$CLONE_DIR" || -n "$dirty" ]]; then
            warn "unrecognized origin or dirty cache at $CLONE_DIR; preserve its work and choose a clean dedicated cache"
            return 1
        fi
    fi
}

# Older defaults used /opt/tarnished without provisioning it for the container user.
# Select the historical home fallback only for that absent, unwritable default;
# an invalid existing cache is never bypassed. Validate the fallback identically.
select_cache() {
    validate_cache || return 1
    if [[ "$CLONE_DIR" == /opt/tarnished && ! -e "$CLONE_DIR" && ! -w /opt ]]; then
        local cache_home
        if [[ -z "${HOME:-}" ]] || ! cache_home=$(physical_root "$HOME") || [[ ! -d "$cache_home" ]]; then
            warn 'default cache unavailable and home directory unsafe; configure a writable cache'
            return 1
        fi
        CLONE_DIR="${cache_home%/}/.cache/tarnished"
        ordinary_path "$CLONE_DIR" || { warn "unsafe cache path $CLONE_DIR; repair it before retrying"; return 1; }
        print_info "refresh-assets: default cache unavailable; using home cache $CLONE_DIR"
        validate_cache || return 1
    fi
}

resolve_source() {
    if [[ -n "$SOURCE_DIR" ]]; then
        [[ "$SOURCE_DIR" == /* ]] || SOURCE_DIR="${PWD}/${SOURCE_DIR}"
        SOURCE_DIR=$(physical_root "$SOURCE_DIR") && ordinary_path "$SOURCE_DIR" || {
            warn 'unsafe source path; repair symlinks and retry'; return 1;
        }
        [[ -d "$SOURCE_DIR" && "$SOURCE_DIR" != / &&
            "$SOURCE_DIR" != "$PROJECT_ROOT" && "$SOURCE_DIR" != "$PROJECT_ROOT/"* &&
            "$PROJECT_ROOT" != "$SOURCE_DIR/"* ]] || {
            warn 'unsafe/unavailable source directory; provide a separate ordinary checkout'; return 1;
        }
        COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null) || COMMIT="uncommitted"
        return 0
    fi
    select_cache || return 1
    if [[ ! -e "$CLONE_DIR" ]]; then
        if $DRY_RUN; then
            print_info 'refresh-assets: [dry-run] upstream comparison unavailable; no persistent cache writes'
            return 1
        fi
        local parent temporary
        parent=$(dirname "$CLONE_DIR")
        if ! mkdir -p "$parent"; then
            warn "cannot create cache parent $parent; choose a writable cache"; return 1
        fi
        temporary=$(mktemp -d "$parent/.tarnished-clone.XXXXXX") || {
            warn "cannot create temporary cache; choose a writable cache directory"; return 1;
        }
        if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" --quiet -- "$UPSTREAM_REPO_URL" "$temporary" 2>/dev/null; then
            rm -rf -- "$temporary"
            warn 'clone failed; check upstream connectivity and retry'; return 1
        fi
        if [[ -e "$CLONE_DIR" || -L "$CLONE_DIR" ]] || ! ordinary_path "$CLONE_DIR" ||
            ! mv -- "$temporary" "$CLONE_DIR"; then
            rm -rf -- "$temporary"
            warn 'cache installation failed; inspect cache path and retry'; return 1
        fi
    elif ! $DRY_RUN; then
        if ! git -C "$CLONE_DIR" fetch --quiet -- origin "$UPSTREAM_BRANCH" 2>/dev/null; then
            warn 'fetch failed; retain project assets and retry when upstream is available'; return 1
        fi
        validate_cache || return 1
        if ! git -C "$CLONE_DIR" merge-base --is-ancestor HEAD FETCH_HEAD 2>/dev/null; then
            warn 'cache has local/diverged commits or incomplete ancestry; preserve it and choose a fresh cache'
            return 1
        fi
        if ! git -C "$CLONE_DIR" reset --hard --quiet FETCH_HEAD 2>/dev/null; then
            warn 'cache reset failed; inspect cache and retry'; return 1
        fi
    fi
    validate_cache || return 1
    SOURCE_DIR="$CLONE_DIR"
    COMMIT=$(git -C "$SOURCE_DIR" rev-parse HEAD 2>/dev/null) || return 1
}

load_state() {
    STATE_PATH="${PROJECT_ROOT}/.tarnished/refresh-state.json"
    ordinary_path "$STATE_PATH" || { warn 'unsafe refresh state path; repair it before retrying'; return 1; }
    if [[ -e "$STATE_PATH" ]]; then
        if [[ ! -f "$STATE_PATH" ]] || ! STATE=$(jq -ce '
            def rel: type == "string" and length > 0 and
                (explode | all(. >= 32 and . != 127)) and
                (startswith("/") | not) and
                (split("/") | all(. != "" and . != "." and . != ".."));
            (.schema_version == 1 and (.entries | type == "object") and
            (.entries | to_entries | all(.[];
                (.key | rel) and (.value.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
                (.value.origin == "upstream" or .value.origin == "overlay") and
                (.value.commit | type == "string") and
                (.value.mapping.repo | type == "string" and length > 0) and
                (.value.mapping | has("src") and has("dst"))))) as $valid |
            if $valid then . else error("invalid state") end' "$STATE_PATH" 2>/dev/null); then
            warn 'invalid refresh state; preserve it for inspection and restore a valid baseline before retrying'; return 1
        fi
    fi
    local path entry dst
    while IFS=$'\t' read -r path entry; do
        [[ -n "$path" ]] || continue
        relative_path "$path" || { warn 'invalid state destination; inspect refresh-state.json'; return 1; }
        valid_catalog <<< "[$(jq -c '.mapping' <<< "$entry")]" || {
            warn 'invalid state mapping; inspect refresh-state.json'; return 1;
        }
        dst=$(jq -r '.mapping.dst' <<< "$entry")
        [[ "$path" == "$dst" || "$path" == "$dst/"* ]] || {
            warn 'state destination outside mapping; inspect refresh-state.json'; return 1;
        }
        ENTRIES["$path"]="$entry"
    done < <(jq -r '.entries | to_entries[] | .key + "\t" + (.value | tojson)' <<< "$STATE")
}

codex_selected() {
    local profile="${PROJECT_ROOT}/.tarnished/agent-profile.json"
    local manifest="${PROJECT_ROOT}/.tarnished-manifest.json"
    if [[ -e "$profile" || -L "$profile" ]]; then
        if ordinary_path "$profile" && jq -e '.ai_profile | IN("claude-main", "codex-main", "dual")' "$profile" >/dev/null 2>&1; then
            jq -e '.ai_profile | IN("codex-main", "dual")' "$profile" >/dev/null && return 0
        else
            warn 'invalid agent profile; preserving installed capabilities; repair profile when convenient'
        fi
    fi
    if ordinary_path "$manifest" && [[ -f "$manifest" ]] &&
        jq -e '.scaffold_options.codex_enabled == true' "$manifest" >/dev/null 2>&1; then
        return 0
    fi
    if ordinary_path "$PROJECT_ROOT/.codex/config.toml" && [[ -f "$PROJECT_ROOT/.codex/config.toml" ]]; then
        return 0
    fi
    ordinary_path "$PROJECT_ROOT/.agents/skills" && [[ -d "$PROJECT_ROOT/.agents/skills" ]]
}

hash_file() {
    local result
    result=$("${HASH_COMMAND[@]}" < "$1") || return 1
    result="${result%% *}"
    [[ "$result" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$result"
}

record_entry() {
    local path="$1" mapping="$2" hash="$3" origin="$4" entry
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || {
        warn "invalid installed digest for $path; baseline retained; check checksum tooling"
        return 1
    }
    entry=$(jq -cn --argjson mapping "$mapping" --arg hash "$hash" --arg origin "$origin" \
        --arg commit "$COMMIT" '{mapping:$mapping,sha256:$hash,origin:$origin,commit:$commit}') || return 1
    # An unchanged installed baseline does not need a commit/timestamp-only rewrite.
    if [[ -n "${ENTRIES[$path]:-}" ]] && jq -e --argjson new "$entry" \
        'del(.commit) == ($new | del(.commit))' <<< "${ENTRIES[$path]}" >/dev/null; then
        return 0
    fi
    ENTRIES["$path"]="$entry"
}

# Backups are outside refresh/manifest ownership and never automatically removed.
# A private run directory also protects backups of settings containing secrets.
backup_file() {
    local target="$1" expected="$2" root="$PROJECT_ROOT/.tarnished/backups" relative parent recovery
    BACKUP_PATH=""
    ordinary_path "$root" && [[ ! -e "$root" || -d "$root" ]] || return 1
    if [[ -z "$BACKUP_RUN" ]]; then
        (umask 077; mkdir -p "$root") && ordinary_path "$root" || return 1
        BACKUP_RUN=$(umask 077; mktemp -d "$root/refresh.XXXXXX") || return 1
    fi
    ordinary_path "$BACKUP_RUN" && [[ -d "$BACKUP_RUN" ]] || return 1
    relative="${target#"$PROJECT_ROOT/"}"
    BACKUP_PATH="$BACKUP_RUN/$relative"
    parent=$(dirname "$BACKUP_PATH")
    ordinary_path "$BACKUP_PATH" && [[ ! -e "$BACKUP_PATH" ]] || return 1
    (umask 077; mkdir -p "$parent") && ordinary_path "$BACKUP_PATH" || return 1
    [[ ! -e "$BACKUP_PATH" ]] && ordinary_path "$target" && [[ -f "$target" ]] || return 1
    # noclobber reserves an ordinary new leaf before copying; never reuse backups.
    (umask 077; set -C; : > "$BACKUP_PATH") || return 1
    ordinary_path "$BACKUP_PATH" && [[ -f "$BACKUP_PATH" ]] &&
        cp -p -- "$target" "$BACKUP_PATH" && ordinary_path "$BACKUP_PATH" &&
        [[ -f "$BACKUP_PATH" && "$(hash_file "$BACKUP_PATH")" == "$expected" ]] || return 1
    BACKED_UP=$((BACKED_UP + 1))
    print_info "refresh-assets: backed up $target to $BACKUP_PATH"
    printf -v recovery 'cp -- %q %q' "$BACKUP_PATH" "$target"
    print_info "refresh-assets: restore with: $recovery"
    ordinary_path "$target" && [[ -f "$target" && "$(hash_file "$target")" == "$expected" ]]
}

# Atomic per-file installation with verified backup and last-moment content checks.
install_file() {
    local candidate="$1" target="$2" expected="$3" desired_hash="$4" temporary parent current=""
    ordinary_path "$candidate" && [[ -f "$candidate" ]] && ordinary_path "$target" || return 1
    parent=$(dirname "$target")
    mkdir -p "$parent" && ordinary_path "$target" || return 1
    temporary=$(mktemp "$parent/.refresh-file.XXXXXX") || return 1
    if ! ordinary_path "$candidate" || ! ordinary_path "$temporary" || ! cp -p -- "$candidate" "$temporary" ||
        ! ordinary_path "$temporary" || [[ ! -f "$temporary" || "$(hash_file "$temporary")" != "$desired_hash" ]]; then
        ordinary_path "$temporary" && rm -f -- "$temporary"; return 1
    fi
    BACKUP_PATH=""
    if [[ -n "$expected" ]] && ! backup_file "$target" "$expected"; then
        warn "backup failed or target changed for $target; target and baseline preserved; inspect $PROJECT_ROOT/.tarnished/backups and retry"
        ordinary_path "$temporary" && rm -f -- "$temporary"; return 1
    fi
    if ordinary_path "$target" && [[ -f "$target" ]]; then current=$(hash_file "$target") || current=error; fi
    if ! ordinary_path "$target" || [[ -e "$target" && ! -f "$target" ]] || [[ "$current" != "$expected" ]] ||
        ! ordinary_path "$temporary" || [[ ! -f "$temporary" || "$(hash_file "$temporary")" != "$desired_hash" ]] ||
        { [[ -n "$expected" ]] && { ! ordinary_path "$BACKUP_PATH" || [[ ! -f "$BACKUP_PATH" || "$(hash_file "$BACKUP_PATH")" != "$expected" ]]; }; } ||
        ! mv -f -- "$temporary" "$target"; then
        ordinary_path "$temporary" && rm -f -- "$temporary"; return 1
    fi
    ordinary_path "$target" && [[ -f "$target" ]] &&
        [[ "$(hash_file "$target")" == "$desired_hash" ]]
}

reconcile_file() {
    local path="$1" base="$2" overlay="$3" mapping="$4" removal_proven="$5"
    local target desired="" origin=upstream desired_hash="" current_hash="" old_hash="" old_origin=""
    local prior="${ENTRIES[$path]:-}"
    case "$path" in
        .tarnished/refresh.json|.tarnished/refresh-state.json|.tarnished/agent-profile.json|\
        .tarnished-manifest.json|.tarnished/backups|.tarnished/backups/*|\
        .codex/config.local.toml|.claude/settings.local.json|\
        .devcontainer/scripts/post.sh|AGENTS.md|CLAUDE.md|.git/*|.git|*.local|*.local/*)
            PRESERVED=$((PRESERVED + 1))
            UNKNOWN=$((UNKNOWN + 1))
            warn "preserve developer-owned configuration $path; remove it from the managed mapping"
            return
            ;;
    esac
    # Upstream inventory can select a relative path beneath a broad overlay
    # even when backup directories were excluded from overlay enumeration.
    case "$overlay" in
        "$PROJECT_ROOT/.tarnished/backups"|"$PROJECT_ROOT/.tarnished/backups/"*)
            UNSAFE=$((UNSAFE + 1))
            warn "reserved backup overlay for $path; choose a customization outside .tarnished/backups"
            return ;;
    esac
    target=$(safe_join "$PROJECT_ROOT" "$path") || { UNSAFE=$((UNSAFE + 1)); warn "unsafe destination $path; repair symlink/type conflict"; return; }
    if ! ordinary_path "$base" || { [[ -n "$overlay" ]] && ! ordinary_path "$overlay"; }; then
        UNSAFE=$((UNSAFE + 1))
        warn "unsafe source/overlay for $path; repair symlink/type conflict"; return
    fi
    if [[ -e "$target" && ! -f "$target" ]] || [[ -e "$base" && ! -f "$base" ]] ||
        [[ -n "$overlay" && -e "$overlay" && ! -f "$overlay" ]]; then
        UNSAFE=$((UNSAFE + 1))
        warn "file/directory collision at $path; inspect source, target and overlay"; return
    fi
    [[ ! -f "$base" ]] || desired="$base"
    if [[ -n "$overlay" && -f "$overlay" ]]; then desired="$overlay"; origin=overlay; fi
    if [[ -n "$prior" ]]; then
        if ! jq -e --argjson mapping "$mapping" '.mapping == $mapping' <<< "$prior" >/dev/null; then
            PRESERVED=$((PRESERVED + 1))
            UNKNOWN=$((UNKNOWN + 1))
            warn "changed mapping at $target; preserve previous ownership and review config"; return
        fi
        old_hash=$(jq -r '.sha256' <<< "$prior")
        old_origin=$(jq -r '.origin' <<< "$prior")
    fi
    if [[ -f "$target" ]]; then
        current_hash=$(hash_file "$target") || { FAILURES=$((FAILURES + 1)); warn "cannot hash $target; check permissions and retry"; return; }
    fi
    if [[ -n "$desired" ]]; then
        desired_hash=$(hash_file "$desired") || { FAILURES=$((FAILURES + 1)); warn "cannot hash $desired; check permissions and retry"; return; }
        if [[ "$current_hash" == "$desired_hash" ]]; then
            if record_entry "$path" "$mapping" "$desired_hash" "$origin"; then
                if [[ -n "$prior" && "$old_hash" == "$desired_hash" && "$old_origin" == "$origin" ]]; then
                    UNCHANGED=$((UNCHANGED + 1))
                else
                    ADOPTED=$((ADOPTED + 1))
                fi
            else
                FAILURES=$((FAILURES + 1))
            fi
            return
        fi
        if $DRY_RUN && [[ -n "$current_hash" ]]; then
            print_info "refresh-assets: [dry-run] backup $target under $PROJECT_ROOT/.tarnished/backups/<unique-run>/$path before replacement"
        fi
        print_info "refresh-assets: $(if $DRY_RUN; then printf '[dry-run] '; fi)install $target from $desired"
        if $DRY_RUN; then return; fi
        if install_file "$desired" "$target" "$current_hash" "$desired_hash"; then
            record_entry "$path" "$mapping" "$desired_hash" "$origin" || FAILURES=$((FAILURES + 1))
            CHANGED=$((CHANGED + 1))
        else
            FAILURES=$((FAILURES + 1))
            warn "copy failed for $target; baseline retained; check permissions and retry"
        fi
    elif [[ -n "$prior" && -n "$current_hash" ]]; then
        if [[ "$old_origin" == overlay || "$current_hash" != "$old_hash" || "$removal_proven" != true ]]; then
            PRESERVED=$((PRESERVED + 1))
            if [[ "$current_hash" != "$old_hash" ]]; then CONFLICTS=$((CONFLICTS + 1)); fi
            warn "preserve removed/edited asset $target; inspect prior mapping and customization before manual removal"
            return
        fi
        print_info "refresh-assets: $(if $DRY_RUN; then printf '[dry-run] '; fi)remove $target (unchanged upstream asset)"
        if $DRY_RUN; then return; fi
        if ordinary_path "$target" && [[ "$(hash_file "$target")" == "$old_hash" ]] && rm -- "$target"; then
            unset 'ENTRIES[$path]'
            REMOVED=$((REMOVED + 1))
        else
            FAILURES=$((FAILURES + 1))
            warn "remove failed for $target; baseline retained; inspect permissions and retry"
        fi
    fi
}

# Enumerate distribution and sidecars only, never walk a downstream managed directory.
reconcile_mapping() {
    local row="$1" src dst overlay src_abs dst_abs overlay_abs="" mapping path relative entry
    local kind=directory removal_proven=false listed
    src=$(jq -r '.src' <<< "$row")
    dst=$(jq -r '.dst' <<< "$row")
    overlay=$(jq -r '.overlay // ""' <<< "$row")
    src_abs=$(safe_join "$SOURCE_DIR" "$src") && dst_abs=$(safe_join "$PROJECT_ROOT" "$dst") || {
        UNSAFE=$((UNSAFE + 1))
        warn "unsafe mapping $src -> $dst; repair symlink/type conflict"; return;
    }
    case "$overlay" in
        .tarnished/backups|.tarnished/backups/*)
            UNSAFE=$((UNSAFE + 1))
            warn "reserved backup overlay $overlay; choose a project customization outside .tarnished/backups"; return ;;
    esac
    if [[ -n "$overlay" ]]; then
        overlay_abs=$(safe_join "$PROJECT_ROOT" "$overlay") || { UNSAFE=$((UNSAFE + 1)); warn "unsafe overlay $overlay; repair it and retry"; return; }
    fi
    mapping=$(jq -cn --arg repo "$UPSTREAM_REPO_URL" --arg src "$src" --arg dst "$dst" \
        --arg overlay "$overlay" '{repo:$repo,src:$src,dst:$dst,overlay:(if $overlay == "" then null else $overlay end)}')
    if [[ -f "$src_abs" ]]; then kind="file"; removal_proven=true
    elif [[ -d "$src_abs" ]]; then removal_proven=true
    elif [[ -e "$src_abs" ]]; then UNSAFE=$((UNSAFE + 1)); warn "unsupported source $src_abs; inspect mapping"; return
    else
        # A missing source in an arbitrary directory is not evidence of an upstream removal.
        if [[ "$COMMIT" != uncommitted ]] &&
            listed=$(git -C "$SOURCE_DIR" ls-tree "$COMMIT" -- "$src" 2>/dev/null) && [[ -z "$listed" ]]; then
            removal_proven=true
        else
            FAILURES=$((FAILURES + 1))
            warn "upstream $src unavailable; preserve previous files and retry with a valid checkout"
        fi
        [[ ! -f "$overlay_abs" ]] || kind="file"
        entry="${ENTRIES[$dst]:-}"
        [[ -z "$entry" ]] || kind="file"
    fi
    if [[ "$kind" == directory && ( -f "$dst_abs" || -f "$overlay_abs" ) ]] ||
        [[ "$kind" == file && ( -d "$dst_abs" || -d "$overlay_abs" ) ]]; then
        UNSAFE=$((UNSAFE + 1))
        warn "file/directory collision for $dst; inspect mapping and overlay"; return
    fi
    CANDIDATES=()
    if [[ "$kind" == file ]]; then CANDIDATES["$dst"]=1
    else
        local root inventory
        for root in "$src_abs" "$overlay_abs"; do
            [[ -n "$root" && -d "$root" ]] || continue
            inventory=$(mktemp) || { FAILURES=$((FAILURES + 1)); warn 'cannot inventory source; repair temporary storage and retry'; return; }
            if ! find "$root" -path "$PROJECT_ROOT/.tarnished/backups" -prune -o -type f -print0 > "$inventory"; then
                rm -f -- "$inventory"
                FAILURES=$((FAILURES + 1))
                warn "cannot enumerate $root; preserve mapping and repair permissions before retrying"
                return
            fi
            while IFS= read -r -d '' path; do
                relative="${path#"$root/"}"
                relative_path "$relative" || { UNSAFE=$((UNSAFE + 1)); warn "unsupported filename under $root; rename it and retry"; continue; }
                CANDIDATES["$dst/$relative"]=1
            done < "$inventory"
            rm -f -- "$inventory"
        done
    fi
    for path in "${!ENTRIES[@]}"; do
        [[ "$path" == "$dst" || "$path" == "$dst/"* ]] || continue
        if jq -e --argjson mapping "$mapping" '.mapping == $mapping' <<< "${ENTRIES[$path]}" >/dev/null; then
            CANDIDATES["$path"]=1
        fi
    done
    for path in "${!CANDIDATES[@]}"; do
        relative="${path#"$dst"}"
        reconcile_file "$path" "$src_abs$relative" "${overlay_abs:+$overlay_abs$relative}" "$mapping" "$removal_proven"
    done
}

persist_state() {
    $DRY_RUN && return 0
    local updated temporary entry
    updated=$({ for entry in "${!ENTRIES[@]}"; do
        jq -cn --arg path "$entry" --argjson value "${ENTRIES[$entry]}" '{key:$path,value:$value}' || return 1
    done; } | jq -sc '{schema_version:1,entries:from_entries}') || {
        warn 'cannot serialize refresh state; keep prior state and retry'; return 1;
    }
    [[ "$(jq -Sc . <<< "$STATE")" != "$(jq -Sc . <<< "$updated")" ]] || return 0
    ordinary_path "$STATE_PATH" && mkdir -p "$(dirname "$STATE_PATH")" || {
        warn 'cannot create refresh state directory; fix permissions and retry'; return 1;
    }
    temporary=$(mktemp "${STATE_PATH}.XXXXXX") || { warn 'state write failed; fix permissions and retry'; return 1; }
    if ! printf '%s\n' "$updated" > "$temporary" || ! ordinary_path "$STATE_PATH" ||
        [[ -e "$STATE_PATH" && ! -f "$STATE_PATH" ]] ||
        ! mv -f -- "$temporary" "$STATE_PATH" || ! ordinary_path "$STATE_PATH" ||
        [[ ! -f "$STATE_PATH" ]]; then
        rm -f -- "$temporary"
        warn 'state write failed; prior baseline retained; fix permissions and retry'
        return 1
    fi
}

main() {
    local rc=0 dependency catalog_path defaults row codex=false
    parse_args "$@" || rc=$?
    [[ "$rc" != 1 ]] || return 1
    [[ "$rc" == 0 ]] || return 0
    for dependency in jq git find cp mv mkdir mktemp rm dirname; do
        if ! command -v "$dependency" &>/dev/null; then
            warn "$dependency not found; install it and retry"; return 0
        fi
    done
    if command -v sha256sum &>/dev/null; then
        HASH_COMMAND=(sha256sum)
    elif command -v shasum &>/dev/null; then
        HASH_COMMAND=(shasum -a 256)
    else
        warn 'sha256sum or shasum not found; install a SHA-256 tool and retry'; return 0
    fi
    SCRIPT_REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null) || SCRIPT_REPO_ROOT=""
    if [[ -n "$SCRIPT_REPO_ROOT" ]]; then
        SCRIPT_REPO_ROOT=$(physical_root "$SCRIPT_REPO_ROOT") || SCRIPT_REPO_ROOT=""
    fi
    if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || return 0
    fi
    [[ "$PROJECT_ROOT" == /* ]] || PROJECT_ROOT="${PWD}/${PROJECT_ROOT}"
    PROJECT_INPUT_ROOT="${PROJECT_ROOT%/}"
    if ! PROJECT_ROOT=$(physical_root "$PROJECT_ROOT") || ! ordinary_path "$PROJECT_ROOT" ||
        [[ ! -d "$PROJECT_ROOT" || "$PROJECT_ROOT" == / || -z "$PROJECT_ROOT" ]]; then
        warn 'unsafe/unavailable project root; provide an ordinary directory'; return 0
    fi
    if ! load_config || ! load_state; then
        warn "configuration/state unavailable; resolve diagnostics above and retry"
        return 0
    fi
    if [[ "$CATALOG" == '[]' ]] && ! jq -e '.use_default_managed_paths == true' "$CONFIG_PATH" >/dev/null; then
        $QUIET || print_info 'refresh-assets: managed_paths is empty; nothing to sync'
        return 0
    fi
    resolve_source || { warn "upstream comparison unavailable; resolve source/cache diagnostics and retry"; return 0; }
    if jq -e '.use_default_managed_paths == true' "$CONFIG_PATH" >/dev/null; then
        catalog_path="$SOURCE_DIR/templates/agent-workflows/.tarnished/refresh.json"
        if ordinary_path "$catalog_path" && [[ -f "$catalog_path" ]] &&
            defaults=$(jq -ce '.managed_paths' "$catalog_path" 2>/dev/null) && valid_catalog <<< "$defaults"; then
            CATALOG="$defaults"
        else
            warn 'upstream default catalog unavailable/invalid; using project snapshot; retry after upstream repair'
        fi
    fi
    # Older shipped default catalogs predate CLI settings. The current updater
    # keeps these mandatory default targets while sourcing bytes at the selected ref.
    # Explicit custom/empty mappings never enter this compatibility path.
    if jq -e '.use_default_managed_paths == true' "$CONFIG_PATH" >/dev/null; then
        CATALOG=$(jq -c '
            reduce [{src:"templates/claude/.claude/settings.json",dst:".claude/settings.json"},
                    {src:"templates/codex/.codex/config.toml",dst:".codex/config.toml"}][] as $setting
                (. ; if any(.[]; .dst as $dst | $setting.dst == $dst or ($setting.dst | startswith($dst + "/")))
                     then . else . + [$setting] end)' <<< "$CATALOG") || {
            warn 'cannot extend legacy settings catalog; inspect config and retry'; return 0;
        }
        valid_catalog <<< "$CATALOG" || { warn 'settings catalog overlaps a customization; repair mappings and retry'; return 0; }
    fi
    codex_selected && codex=true
    while IFS= read -r row; do
        if ! $codex && jq -e '.dst == ".codex/config.toml" or .dst == ".agents/skills" or (.dst | startswith(".agents/skills/"))' <<< "$row" >/dev/null; then
            continue
        fi
        reconcile_mapping "$row"
    done < <(jq -c '.[]' <<< "$CATALOG")
    persist_state || FAILURES=$((FAILURES + 1))
    $QUIET || print_success "refresh-assets: reconciliation complete ($CHANGED installed, $BACKED_UP backed-up, $REMOVED removed, $UNCHANGED unchanged, $ADOPTED adopted, $PRESERVED preserved: $CONFLICTS conflicts, $UNKNOWN unknown; $UNSAFE unsafe, $FAILURES failures); upstream unchanged files still reconciled"
    return 0
}

main "$@"
