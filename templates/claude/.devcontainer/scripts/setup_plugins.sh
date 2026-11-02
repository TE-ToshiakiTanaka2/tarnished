#!/bin/bash
# =============================================================================
# Claude Code Plugin Setup Script (settings-driven fallback)
# =============================================================================
# Claude Code plugins are declared in .claude/settings.json:
#
#   "extraKnownMarketplaces": { "<marketplace>": { "source": { ... } } }
#   "enabledPlugins":         { "<plugin>@<marketplace>": true }
#
# `enabledPlugins` alone does not fetch a plugin onto a machine that has never
# installed it, so this script, sourced by post.sh, installs every enabled
# plugin that is not installed yet (`claude plugin install <id> --scope project`).
# It never uninstalls anything and never passes -y / --accept-command.
#
# Prerequisites:
# - Claude Code CLI (setup_claude.sh) and jq
# - A logged-in Claude Code session (~/.claude/.credentials.json)
#
# Failure policy:
#   `setup_plugins` is best-effort: every failure is reported as a warning and
#   does NOT abort post.sh (which runs under `set -e`). A missing `claude`, jq,
#   settings file, `enabledPlugins` entry or login each skip the flow with a
#   one-line message (#273, #325).
#
# Test hook: SETUP_PLUGINS_SETTINGS_FILE overrides <root>/.claude/settings.json.
# =============================================================================

# Returns 0 iff `claude` has been logged in at least once on this machine,
# detected by the presence of a non-empty OAuth credentials file. Pure read-only
# check -- no subprocess, no network -- added in #273 to prevent first-run
# `claude plugin ...` calls from tripping `set -e` in post.sh.
is_claude_authenticated() {
    [[ -s "$HOME/.claude/.credentials.json" ]]
}

# Register a marketplace with Claude Code when it is not registered yet. The
# source comes from extraKnownMarketplaces; the official marketplace falls back
# to its well-known repository when settings.json does not declare it.
# Returns 0 when the marketplace is registered afterwards, 1 otherwise.
_setup_plugins_ensure_marketplace() {
    local settings_file="$1"
    local marketplace="$2"

    if claude plugin marketplace list 2>/dev/null | grep -qw -- "$marketplace"; then
        echo "  - Marketplace ${marketplace} already registered"
        return 0
    fi

    local source_kind="" repo="" url="" target=""
    source_kind="$(jq -r --arg m "$marketplace" '.extraKnownMarketplaces[$m].source.source // empty' "$settings_file" 2>/dev/null || true)"
    case "$source_kind" in
        github)
            repo="$(jq -r --arg m "$marketplace" '.extraKnownMarketplaces[$m].source.repo // empty' "$settings_file" 2>/dev/null || true)"
            if [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+$ ]]; then
                target="$repo"
            fi
            ;;
        git)
            url="$(jq -r --arg m "$marketplace" '.extraKnownMarketplaces[$m].source.url // empty' "$settings_file" 2>/dev/null || true)"
            if [[ -n "$url" ]] && [[ "$url" != -* ]]; then
                target="$url"
            fi
            ;;
        "")
            if [[ "$marketplace" == "claude-plugins-official" ]]; then
                target="anthropics/claude-plugins-official"
            fi
            ;;
    esac

    if [[ -z "$target" ]]; then
        echo "  [WARN] Marketplace ${marketplace} has no usable source in extraKnownMarketplaces; skipping its plugins"
        return 1
    fi

    echo "  - Registering marketplace ${marketplace} (${target})..."
    if claude plugin marketplace add "$target"; then
        return 0
    fi
    echo "  [WARN] Failed to register marketplace ${marketplace}; try: claude plugin marketplace add ${target}"
    return 1
}

setup_plugins() {
    echo "Setting up Claude Code plugins..."

    if ! command -v claude &> /dev/null; then
        echo "  [WARN] Claude Code CLI is not installed; skipping plugin setup"
        return 0
    fi

    if ! command -v jq &> /dev/null; then
        echo "  [WARN] jq not found; skipping plugin setup (install jq, then re-run this script)"
        return 0
    fi

    local project_root settings_file
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    settings_file="${SETUP_PLUGINS_SETTINGS_FILE:-${project_root}/.claude/settings.json}"

    if [[ ! -f "$settings_file" ]]; then
        echo "  [WARN] ${settings_file} not found; skipping plugin setup"
        return 0
    fi

    local enabled=""
    if ! enabled="$(jq -r '(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key' "$settings_file" 2>/dev/null)"; then
        echo "  [WARN] ${settings_file} is not valid JSON (or enabledPlugins is malformed); skipping plugin setup"
        return 0
    fi

    if [[ -z "$enabled" ]]; then
        echo "  [WARN] no enabledPlugins in .claude/settings.json; nothing to install"
        return 0
    fi

    # Pre-flight: skip cleanly when `claude` has never been logged in (#273).
    # Without this gate every `claude plugin ...` call would fail on first-run
    # containers.
    if ! is_claude_authenticated; then
        echo "  - Claude Code CLI detected, but not yet authenticated"
        echo "  - To install Claude plugins, run \`claude\` to log in,"
        echo "    then re-run: source .devcontainer/scripts/setup_plugins.sh && setup_plugins"
        echo "  - Skipping plugin setup"
        return 0
    fi

    echo "  - Claude Code CLI detected"

    # Expected `claude plugin list --json` shape: an array of objects, each with
    # an `id` field of the form `<name>@<marketplace>`. Written against Claude
    # Code 2.1.x. If the shape changes, jq fails or matches nothing and every
    # enabled plugin is re-installed, which is idempotent and therefore benign.
    # An unreadable list means "assume nothing is installed": install is idempotent.
    local installed="" list_json=""
    if list_json="$(claude plugin list --json 2>/dev/null)" \
        && installed="$(printf '%s' "$list_json" | jq -r '.[].id' 2>/dev/null)"; then
        :
    else
        installed=""
        echo "  - Note: could not query installed plugins; attempting every enabled plugin"
    fi

    local handled_marketplaces=" " failed_marketplaces=" "
    local plugin_id marketplace
    while IFS= read -r plugin_id; do
        [[ -n "$plugin_id" ]] || continue

        if [[ ! "$plugin_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
            echo "  [WARN] Skipping malformed plugin id '${plugin_id}' (expected <name>@<marketplace>)"
            continue
        fi

        if printf '%s\n' "$installed" | grep -qxF -- "$plugin_id"; then
            echo "  - ${plugin_id} already installed, skipping"
            continue
        fi

        marketplace="${plugin_id#*@}"
        if [[ "$failed_marketplaces" == *" ${marketplace} "* ]]; then
            continue
        fi
        if [[ "$handled_marketplaces" != *" ${marketplace} "* ]]; then
            if _setup_plugins_ensure_marketplace "$settings_file" "$marketplace"; then
                handled_marketplaces+="${marketplace} "
            else
                failed_marketplaces+="${marketplace} "
                continue
            fi
        fi

        echo "  - Installing ${plugin_id}..."
        if claude plugin install "$plugin_id" --scope project; then
            echo "  - ${plugin_id} installed"
        else
            echo "  [WARN] Failed to install ${plugin_id}; try: claude plugin install ${plugin_id} --scope project"
        fi
    done <<< "$enabled"

    echo "  - Plugin setup complete"
    return 0
}
