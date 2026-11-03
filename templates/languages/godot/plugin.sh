#!/bin/bash
# =============================================================================
# Template Plugin: godot
# This file is meant to be sourced by setup.sh, not executed directly.
# =============================================================================
# This plugin provides a tooling-only Godot 4 (.NET) environment:
# - Godot .NET editor, .NET SDK, uv and gdtoolkit (gdlint / gdformat), all
#   declared in mise.toml (no devcontainer feature)
# - OS libraries for the editor (X11 / Wayland / Mesa / audio) through
#   plugin_dockerfile
# - Claude Code hooks (gdformat for *.gd, dotnet format whitespace for *.cs)
#   and GDScript / C# coding rules
# - VS Code and Zed editor integration
# - GitHub Actions workflow: gdlint / gdformat, GUT, headless export
# - An opt-in WSLg overlay (docker-compose.godot-gui.yml). It is a separate
#   Compose file, activated by listing it in devcontainer.json
#   "dockerComposeFile" (prompt, or GODOT_GUI=true). Headless is the default.
#
# Monorepo split (#263): gdlintrc + .editorconfig are per-module
# (plugin_post_copy_module); everything else (mise.toml, devcontainer, hooks,
# rules, gitignore, post.sh, GUI activation) is shared at the root
# (plugin_post_copy_shared). The plugin never creates project.godot,
# export_presets.cfg or addons/: that stays the developer's choice.
# =============================================================================

# Get the directory where this plugin is located
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Constants are plain assignments: plugins are sourced once per pass, so
# `readonly` would fail on the second source.
GODOT_POSTSH_MARKER="# Godot Engine Setup"
GODOT_GITIGNORE_MARKER="# Godot (engine caches and export output)"
GODOT_GUI_COMPOSE_FILE="docker-compose.godot-gui.yml"
GODOT_GUI_COMPOSE_REF="../docker-compose.godot-gui.yml"

# The Godot .NET editor comes from the mise github backend (the registry
# shorthand only fetches the standard build). Mise Tera templates, not
# Tarnished placeholders.
GODOT_MISE_TOOL_VALUE="{ version = \"4.7.2-stable\", asset_pattern = 'Godot_v{{ version }}_mono_linux_{{ arch(x64=\"x86_64\", arm64=\"arm64\") }}.zip', rename_exe = { \"Godot_v*_mono_linux.*\" = \"godot\" } }"
GODOT_MISE_GDTOOLKIT_VALUE='{ version = "4.5.0", python = "3.12" }'

# GUI choice: "true", "false" or empty (undecided). Reset on every source so a
# value from an earlier pass never leaks in; setup.sh sources the plugin
# immediately before plugin_interactive_setup and the post-copy hooks.
GODOT_GUI_ENABLED=""

# =============================================================================
# Required Functions
# =============================================================================

# Return plugin identifier
plugin_name() {
    echo "godot"
}

# Return plugin description
plugin_description() {
    echo "Godot 4 (.NET) game development with GDScript and C#"
}

# =============================================================================
# Private Helpers
# =============================================================================

# Copy the CI workflow with the rust-style overwrite prompt (#265).
# Declining only skips the workflow; the caller keeps copying other files.
_godot_copy_workflow() {
    local target_dir="$1"
    local workflow="${PLUGIN_DIR}/.github/workflows/godot-quality-check.yml"

    [[ -f "$workflow" ]] || return 0

    print_info "Copying Godot quality check workflow..."
    mkdir -p "${target_dir}/.github/workflows"

    local target_file="${target_dir}/.github/workflows/godot-quality-check.yml"
    if [[ -f "$target_file" ]]; then
        local overwrite="n"
        echo -n "  godot-quality-check.yml already exists. Overwrite? (y/n) [n]: "
        if check_tty_available; then
            read -r overwrite < /dev/tty
        fi
        if [[ "$overwrite" != "y" ]]; then
            print_info "Skipping godot-quality-check.yml"
            return 0
        fi
    fi

    # The prompt above is the source of truth; bypass copy_with_confirm's own.
    OVERWRITE_ALL=true copy_with_confirm "$workflow" "$target_file"
    print_success "Created godot-quality-check.yml"
}

# Add a tool to mise.toml together with the tool_alias that backs it. The pair
# is written only when tools.<key> is absent, so a developer's own entry (for
# example the aqua build of godot) is never retargeted.
# Usage: _godot_ensure_aliased_tool <mise_toml> <key> <alias_target> <tool_value> <label>
_godot_ensure_aliased_tool() {
    local mise_toml="$1"
    local key="$2"
    local alias_target="$3"
    local tool_value="$4"
    local label="$5"
    local rc=0

    mise_toml_has_key "$mise_toml" tools "$key" || rc=$?
    case "$rc" in
        0)
            print_info "Kept existing ${label} in mise.toml"
            return 0
            ;;
        1) ;;
        *)
            print_warning "Could not add ${label} to mise.toml"
            return 0
            ;;
    esac

    mise_toml_ensure "$mise_toml" tool_alias "$key" "\"${alias_target}\"" \
        || { print_warning "Could not add tool_alias.${key} to mise.toml"; return 0; }
    mise_toml_ensure "$mise_toml" tools "$key" "$tool_value" \
        || print_warning "Could not add ${label} to mise.toml"
    return 0
}

# Whether devcontainer.json already lists the GUI overlay in dockerComposeFile.
# Returns 1 for a missing file or a jq failure.
_godot_gui_entry_present() {
    local devcontainer_json="$1"

    [[ -f "$devcontainer_json" ]] || return 1
    command -v jq &> /dev/null || return 1
    jq -e --arg f "$GODOT_GUI_COMPOSE_REF" \
        '(.dockerComposeFile // []) | (if type == "string" then [.] else . end) | index($f) != null' \
        "$devcontainer_json" &> /dev/null
}

# Whether the setup host looks like WSLg (prompt default only).
_godot_wslg_detected() {
    [[ -d /mnt/wslg ]] && [[ -e /dev/dxg ]]
}

# Decide the GUI choice without prompting. Sets GODOT_GUI_ENABLED to true or
# false when GODOT_GUI, an already-listed entry, or a non-interactive context
# decides; leaves it empty when only a prompt can decide.
# Usage: _godot_resolve_gui_choice [target_dir]
_godot_resolve_gui_choice() {
    local target_dir="${1:-${TARGET_DIR:-}}"

    # 1. Explicit environment variable.
    if [[ -n "${GODOT_GUI:-}" ]]; then
        case "$GODOT_GUI" in
            true|1|yes) GODOT_GUI_ENABLED="true" ;;
            *) GODOT_GUI_ENABLED="false" ;;
        esac
        return 0
    fi

    # 2. Overlay already listed: nothing to ask.
    if [[ -n "$target_dir" ]] \
        && _godot_gui_entry_present "${target_dir}/.devcontainer/devcontainer.json"; then
        GODOT_GUI_ENABLED="true"
        return 0
    fi

    # 3. Staging runs, -y and runs without a terminal never prompt.
    if [[ "${UPGRADE_MODE:-false}" == true ]] \
        || [[ "${CREATE_MANIFEST_MODE:-false}" == true ]] \
        || [[ "${SKIP_CONFIRM:-false}" == true ]] \
        || ! check_tty_available; then
        GODOT_GUI_ENABLED="false"
        return 0
    fi

    # 4. Undecided: only the interactive prompt can answer.
    return 0
}

# Append the GUI overlay to devcontainer.json "dockerComposeFile" (order kept,
# never duplicated). Warns and leaves the file untouched on any failure.
_godot_enable_gui_overlay() {
    local target_dir="$1"
    local devcontainer_json="${target_dir}/.devcontainer/devcontainer.json"
    local overlay="${target_dir}/${GODOT_GUI_COMPOSE_FILE}"
    local hint="add \"${GODOT_GUI_COMPOSE_REF}\" after \"../docker-compose.yml\" in \"dockerComposeFile\" of .devcontainer/devcontainer.json"

    if [[ ! -f "$overlay" ]]; then
        print_warning "${GODOT_GUI_COMPOSE_FILE} is missing; not enabling the Godot GUI (restore it, then ${hint})"
        return 0
    fi
    if [[ ! -f "$devcontainer_json" ]]; then
        print_warning "devcontainer.json not found; to enable the Godot GUI, ${hint}"
        return 0
    fi
    if _godot_gui_entry_present "$devcontainer_json"; then
        print_info "Godot GUI (WSLg) overlay already enabled"
        return 0
    fi
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found; to enable the Godot GUI, ${hint}"
        return 0
    fi

    local temp_file
    if ! temp_file="$(mktemp "${devcontainer_json}.XXXXXX")"; then
        print_warning "Could not enable the Godot GUI; ${hint}"
        return 0
    fi

    if jq --arg f "$GODOT_GUI_COMPOSE_REF" '
            .dockerComposeFile = (
                (.dockerComposeFile // ["../docker-compose.yml"])
                | (if type == "string" then [.] else . end)
                | . + [$f]
            )' "$devcontainer_json" > "$temp_file" 2> /dev/null \
        && chmod 644 "$temp_file" && mv "$temp_file" "$devcontainer_json"; then
        print_success "Godot GUI (WSLg) overlay enabled"
    else
        rm -f "$temp_file"
        print_warning "Could not enable the Godot GUI (devcontainer.json may contain comments); ${hint}"
    fi
    return 0
}

# =============================================================================
# Hook Functions
# =============================================================================

# Interactive setup: called by setup.sh only when a TTY is available. Resolves
# the choice without prompting first, then asks only when it is still open.
plugin_interactive_setup() {
    _godot_resolve_gui_choice "${TARGET_DIR:-}"

    if [[ -n "${GODOT_GUI_ENABLED:-}" ]]; then
        return 0
    fi

    local default="n"
    if _godot_wslg_detected; then
        default="y"
    fi

    if confirm "Enable the Godot GUI editor through WSLg?" "$default"; then
        GODOT_GUI_ENABLED="true"
    else
        GODOT_GUI_ENABLED="false"
    fi
    return 0
}

# Copy the CI workflow and the (inert until listed) GUI overlay.
plugin_copy() {
    local target_dir="$1"

    _godot_copy_workflow "$target_dir"

    local overlay="${PLUGIN_DIR}/${GODOT_GUI_COMPOSE_FILE}"
    if [[ -f "$overlay" ]]; then
        print_info "Copying Godot GUI (WSLg) overlay..."
        copy_with_confirm "$overlay" "${target_dir}/${GODOT_GUI_COMPOSE_FILE}"
    fi
}

# OS libraries for the editor, GUI and .NET. Runtimes live in mise.toml.
plugin_dockerfile() {
    local target_dir="$1"

    dockerfile_add_os_packages "${target_dir}/docker/Dockerfile.dev" godot \
        libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 libxrender1 \
        libwayland-client0 libwayland-cursor0 libwayland-egl1 libxkbcommon0 libdecor-0-0 \
        libgl1 libegl1 libglx-mesa0 libgl1-mesa-dri libvulkan1 mesa-vulkan-drivers \
        libasound2t64 libpulse0 \
        libfontconfig1 libudev1 libdbus-1-3 \
        libicu76 libssl3t64 \
        netcat-openbsd unzip
}

# Shared root post-copy work: mise.toml, devcontainer, hooks, rules, gitignore,
# post.sh and GUI activation. Every step is idempotent and there is no early
# return, so re-runs and --add-module stay safe.
plugin_post_copy_shared() {
    local target_dir="$1"

    # 1. Runtime versions live in mise.toml (#325). Existing entries are never
    # changed.
    local mise_toml="${target_dir}/mise.toml"
    _godot_ensure_aliased_tool "$mise_toml" godot "github:godotengine/godot" \
        "$GODOT_MISE_TOOL_VALUE" "tools.godot"
    mise_toml_ensure "$mise_toml" tools dotnet '"10.0.403"' \
        || print_warning "Could not add tools.dotnet to mise.toml"
    # Same literal as the python plugin so the first writer cannot pick another uv.
    mise_toml_ensure "$mise_toml" tools uv '"0.13.6"' \
        || print_warning "Could not add tools.uv to mise.toml"
    _godot_ensure_aliased_tool "$mise_toml" gdtoolkit "pypi:gdtoolkit" \
        "$GODOT_MISE_GDTOOLKIT_VALUE" "tools.gdtoolkit"
    mise_toml_ensure "$mise_toml" env DOTNET_CLI_TELEMETRY_OPTOUT '"1"' \
        || print_warning "Could not add env.DOTNET_CLI_TELEMETRY_OPTOUT to mise.toml"
    mise_toml_ensure "$mise_toml" env DOTNET_NOLOGO '"1"' \
        || print_warning "Could not add env.DOTNET_NOLOGO to mise.toml"

    # 2. Merge devcontainer.json customizations (extensions and settings)
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local plugin_devcontainer="${PLUGIN_DIR}/.devcontainer/devcontainer.json"

    if [[ -f "$plugin_devcontainer" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Godot devcontainer customizations..."
        local temp_file="${target_dir}/.devcontainer/devcontainer.json.tmp"

        merge_devcontainer_json "$target_devcontainer" "$plugin_devcontainer" "$temp_file"
        mv "$temp_file" "$target_devcontainer"

        print_success "Godot devcontainer customizations merged"
    fi

    # 3. Zed editor assets (no-op unless --zed was selected)
    apply_zed_assets "$target_dir" "$PLUGIN_DIR"

    # 4. WSLg GUI overlay. Non-TTY runs never reach plugin_interactive_setup,
    # so the non-prompting resolver runs here. Still empty afterwards means off:
    # this step never prompts.
    if [[ -z "${GODOT_GUI_ENABLED:-}" ]]; then
        _godot_resolve_gui_choice "$target_dir"
    fi
    if [[ "${GODOT_GUI_ENABLED:-}" == true ]]; then
        _godot_enable_gui_overlay "$target_dir"
    fi

    # 5. Merge Claude settings hooks
    local target_settings="${target_dir}/.claude/settings.json"
    local plugin_settings="${PLUGIN_DIR}/.claude/settings.json"

    if [[ -f "$plugin_settings" ]] && [[ -f "$target_settings" ]]; then
        print_info "Merging Godot Claude settings..."
        local temp_settings="${target_dir}/.claude/settings.json.tmp"

        merge_claude_settings_hooks "$target_settings" "$plugin_settings" "$temp_settings"
        mv "$temp_settings" "$target_settings"

        print_success "Godot Claude settings merged"
    fi

    # 6. Copy Claude rules files
    local plugin_rules_dir="${PLUGIN_DIR}/.claude/rules"
    local target_rules_dir="${target_dir}/.claude/rules"

    if [[ -d "$plugin_rules_dir" ]]; then
        print_info "Copying Godot Claude rules..."
        copy_dir_with_confirm "$plugin_rules_dir" "$target_rules_dir"
        print_success "Godot Claude rules copied"
    fi

    # 7. .gitignore block (exact-line marker, append only)
    local gitignore="${target_dir}/.gitignore"
    touch "$gitignore"
    if [[ -s "$gitignore" ]] && [[ -n "$(tail -c 1 "$gitignore")" ]]; then
        echo "" >> "$gitignore"
    fi
    if ! grep -q "^${GODOT_GITIGNORE_MARKER}$" "$gitignore" 2> /dev/null; then
        {
            echo ""
            echo "$GODOT_GITIGNORE_MARKER"
            echo ".godot/"
            echo ".mono/"
            echo "data_*/"
            echo "mono_crash.*.json"
            echo "*.translation"
            echo "export_credentials.cfg"
            echo "build/"
            echo "export/"
        } >> "$gitignore"
    fi

    # 8. post.sh informational block, before the Codex / plugin blocks (#325).
    local target_post_sh="${target_dir}/.devcontainer/scripts/post.sh"
    if [[ -f "$target_post_sh" ]]; then
        print_info "Adding Godot setup to post.sh..."
        post_sh_add_block "$target_post_sh" "$GODOT_POSTSH_MARKER" \
            "# Codex CLI Setup" "# Claude Code Plugin Setup" << 'EOF' \
            || print_warning "Could not add the Godot block to post.sh"
if command -v godot &> /dev/null; then
    echo "Godot development environment:"
    godot_version="$(godot --headless --version 2> /dev/null | tail -n 1 || true)"
    echo "  - godot: ${godot_version:-not runnable yet (run: mise install)}"
    if command -v dotnet &> /dev/null; then
        echo "  - dotnet: $(dotnet --version 2> /dev/null || echo 'not runnable yet')"
    fi
    if [[ -n "$godot_version" ]]; then
        godot_templates="${HOME}/.local/share/godot/export_templates/$(echo "$godot_version" | sed -E 's/\.(official|custom_build)(\..*)?$//')"
        if [[ ! -d "$godot_templates" ]]; then
            echo "  - Export templates not installed (needed only for exporting); see docs/setup.md \"Godot\""
        fi
    fi
    if [[ -d /mnt/wslg ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        echo "  - GUI: WSLg available. Start the editor with: godot -e  (GPU: add --rendering-driver opengl3)"
    else
        echo "  - GUI: headless. WSL2 hosts can opt in via docker-compose.godot-gui.yml"
    fi
else
    echo "[WARN] godot not found; run 'mise install' in the project root (see mise.toml)"
fi
EOF
    fi
    return 0
}

# Module-scoped post-copy work: per-module lint and editor configuration.
plugin_post_copy_module() {
    local target_dir="$1"
    local _module_name="${2:-}"   # currently unused; kept for contract symmetry

    local config_file
    for config_file in gdlintrc .editorconfig; do
        local source_config="${PLUGIN_DIR}/${config_file}"
        local target_config="${target_dir}/${config_file}"

        if [[ -f "$source_config" ]]; then
            print_info "Copying ${config_file} to ${target_dir}..."
            copy_with_confirm "$source_config" "$target_config"
        fi
    done
}

# Backward-compat shim.
plugin_post_copy() {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}
