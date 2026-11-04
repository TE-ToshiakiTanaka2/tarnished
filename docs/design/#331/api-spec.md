# API Specification: #331 Add Godot (GDScript + C#) language flavor with WSLg GUI overlay and headless CI

The interfaces this issue introduces or changes. The decisions behind them are
in [`design.md`](./design.md); the cumulative surface is in
[`../shared/api-spec.md`](../shared/api-spec.md).

## Endpoints / Functions (delta)

### `templates/languages/godot/plugin.sh`

The file is sourced by `setup.sh`, never executed, and has mode 644. Constants
are plain assignments: plugins can be sourced several times, so `readonly`
would fail.

| Name | Signature | Description |
| --- | --- | --- |
| `PLUGIN_DIR` | constant | `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` |
| `GODOT_POSTSH_MARKER` | constant | `# Godot Engine Setup` |
| `GODOT_GITIGNORE_MARKER` | constant | `# Godot (engine caches and export output)` |
| `GODOT_GUI_COMPOSE_FILE` | constant | `docker-compose.godot-gui.yml` |
| `GODOT_GUI_COMPOSE_REF` | constant | `../docker-compose.godot-gui.yml` (the path relative to `.devcontainer/`) |
| `GODOT_GUI_ENABLED` | global, `true` / `false` / empty | Reset to `""` at source time. Set only by `_godot_resolve_gui_choice` (steps 1–3) or by the prompt in `plugin_interactive_setup` (step 4). Read by `plugin_post_copy_shared`, which first calls the resolver when the value is empty, because non-TTY runs never invoke `plugin_interactive_setup`. Still empty after that call ⇒ treated as `false`. |
| `plugin_name` | `()` → stdout `godot` | Contract |
| `plugin_description` | `()` → stdout `Godot 4 (.NET) game development with GDScript and C#` | Contract |
| `plugin_interactive_setup` | `()` → 0 | Invoked by `setup.sh` only when `check_tty_available` succeeds. Calls `_godot_resolve_gui_choice "${TARGET_DIR:-}"`. If `GODOT_GUI_ENABLED` is still empty, prompts `confirm "Enable the Godot GUI editor through WSLg?" <default>` (default `y` iff `_godot_wslg_detected`) and stores `true` / `false`. See design.md "GUI choice resolution". |
| `_godot_resolve_gui_choice` | `([target_dir])` → 0 | Never prompts and never reads `/dev/tty`. (1) `GODOT_GUI` non-empty: `true` / `1` / `yes` → `true`, else `false`. (2) Else, if `_godot_gui_entry_present "<target_dir or $TARGET_DIR>/.devcontainer/devcontainer.json"` → `true`; step skipped when no directory is known. (3) Else, if `UPGRADE_MODE`, `CREATE_MANIFEST_MODE` or `SKIP_CONFIRM` is `true`, or `! check_tty_available` → `false`. (4) Else leave empty. |
| `plugin_copy` | `(target_dir)` → 0 | `_godot_copy_workflow target_dir`, then `copy_with_confirm "${PLUGIN_DIR}/docker-compose.godot-gui.yml" "${target_dir}/docker-compose.godot-gui.yml"` |
| `plugin_dockerfile` | `(target_dir)` → 0 | `dockerfile_add_os_packages "${target_dir}/docker/Dockerfile.dev" godot <28 packages>` (design.md "OS-package block") |
| `plugin_post_copy_shared` | `(target_dir)` → 0 | Steps 1–8 below. No early `return`. |
| `plugin_post_copy_module` | `(target_dir, module_name)` → 0 | For each of `gdlintrc` and `.editorconfig`: `copy_with_confirm "${PLUGIN_DIR}/<f>" "${target_dir}/<f>"` |
| `plugin_post_copy` | `(target_dir)` → 0 | `plugin_post_copy_shared "$1"; plugin_post_copy_module "$1" "${PROJECT_NAME}"` |
| `_godot_copy_workflow` | `(target_dir)` → 0 | `mkdir -p .github/workflows`. If the target file exists, prompt `godot-quality-check.yml already exists. Overwrite? (y/n) [n]: ` (reads `/dev/tty` only when `check_tty_available`; otherwise `n`). On `y` or a missing file: `OVERWRITE_ALL=true copy_with_confirm`. |
| `_godot_ensure_aliased_tool` | `(mise_toml, key, alias_target, tool_value, label)` → 0 | `mise_toml_has_key "$mise_toml" tools "$key"`. Exit 0: `print_info` "Kept existing tools.<key>". Exit 1: `mise_toml_ensure … tool_alias "$key" "\"$alias_target\""` then `mise_toml_ensure … tools "$key" "$tool_value"`. Any non-zero from the helpers becomes `print_warning "Could not add <label> to mise.toml"`. |
| `_godot_gui_entry_present` | `(devcontainer_json)` → 0 \| 1 | `jq -e --arg f "$GODOT_GUI_COMPOSE_REF" '(.dockerComposeFile // []) \| (if type == "string" then [.] else . end) \| index($f) != null'`. Returns 1 on a missing file or a jq failure. |
| `_godot_enable_gui_overlay` | `(target_dir)` → 0 | See "GUI activation" below |
| `_godot_wslg_detected` | `()` → 0 \| 1 | `[[ -d /mnt/wslg ]] && [[ -e /dev/dxg ]]` |

#### `plugin_post_copy_shared` steps

1. **mise** (`m="${target_dir}/mise.toml"`):
   - `_godot_ensure_aliased_tool "$m" godot github:godotengine/godot '<godot inline table>' tools.godot`
   - `mise_toml_ensure "$m" tools dotnet '"10.0.403"'`
   - `mise_toml_ensure "$m" tools uv '"0.13.6"'` (same literal as the python plugin)
   - `_godot_ensure_aliased_tool "$m" gdtoolkit pypi:gdtoolkit '{ version = "4.5.0", python = "3.12" }' tools.gdtoolkit`
   - `mise_toml_ensure "$m" env DOTNET_CLI_TELEMETRY_OPTOUT '"1"'`
   - `mise_toml_ensure "$m" env DOTNET_NOLOGO '"1"'`

   Each `mise_toml_ensure` call is followed by `|| print_warning "Could not add <section>.<key> to mise.toml"`.
2. **Devcontainer**: when both files exist, run
   `merge_devcontainer_json target overlay target.tmp`, then `mv`. Log text:
   "Merging Godot devcontainer customizations...".
3. **Zed**: `apply_zed_assets "$target_dir" "$PLUGIN_DIR"`.
4. **GUI**: if `[[ -z "${GODOT_GUI_ENABLED:-}" ]]`, run
   `_godot_resolve_gui_choice "$target_dir"`. This is the path every non-TTY
   run takes, including `GODOT_GUI=true ./setup.sh --lang godot -y` under CI
   or `curl … | bash`. Then, if `[[ "${GODOT_GUI_ENABLED:-}" == true ]]`, run
   `_godot_enable_gui_overlay "$target_dir"`. An empty value at this point
   means off, because this step never prompts.
5. **Claude hooks**: when both files exist, run
   `merge_claude_settings_hooks target overlay target.tmp`, then `mv`.
6. **Claude rules**: `copy_dir_with_confirm "${PLUGIN_DIR}/.claude/rules" "${target_dir}/.claude/rules"`.
7. **gitignore**: `touch "${target_dir}/.gitignore"`. If the file does not end
   in a newline, add one. Then, if `! grep -q "^${GODOT_GITIGNORE_MARKER}$"`,
   append a blank line, the marker and the lines from design.md.
8. **`post.sh`**: `post_sh_add_block "${target_dir}/.devcontainer/scripts/post.sh" "$GODOT_POSTSH_MARKER" "# Codex CLI Setup" "# Claude Code Plugin Setup" <<'EOF' … EOF`,
   with the body from design.md. The call is followed by
   `|| print_warning "Could not add the Godot block to post.sh"`.

#### GUI activation (`_godot_enable_gui_overlay`)

```text
dc = <target>/.devcontainer/devcontainer.json
overlay = <target>/docker-compose.godot-gui.yml
if overlay missing         → print_warning "GUI overlay file missing; not enabling", return 0
if dc missing              → print_warning "<manual edit hint>", return 0
if _godot_gui_entry_present dc → print_info "already enabled", return 0
jq --arg f "../docker-compose.godot-gui.yml" '
    .dockerComposeFile = (
        (.dockerComposeFile // ["../docker-compose.yml"])
        | (if type == "string" then [.] else . end)
        | . + [$f]
    )' dc > tmp            (tmp = mktemp next to dc)
  success → mv tmp dc, print_success "Godot GUI (WSLg) overlay enabled"
  failure → rm tmp, print_warning "<manual edit hint>", return 0
```

The manual edit hint reads:
`add "../docker-compose.godot-gui.yml" after "../docker-compose.yml" in "dockerComposeFile"`.
Order is preserved: append only, never `unique`, which would sort the
overlay ahead of the base.

### `scripts/lib/common.sh`

| Name | Signature | Change |
| --- | --- | --- |
| `mise_toml_ensure` | `<mise_toml> <section> <key> <toml_value>` | `section` ∈ {`tools`, `env`, `settings`, `tool_alias`}. The error text lists all four. Behavior is otherwise unchanged. |
| `mise_toml_has_key` | `<mise_toml> <section> <key>` | **New.** Read-only. Exit 0 when the key is present (same rule as `mise_toml_ensure`: bare or `"…"` / `'…'`-quoted key under `[section]`, a `[section.key]` header, or a top-level `section.key =`). Exit 1 when absent or the file is missing. Exit 2 (plus `print_error`) for a bad section or key. Prints nothing on 0 or 1. |
| `replace_placeholders` | unchanged | File list gains `${target_dir}/docker-compose.godot-gui.yml` |
| `show_interactive_mode_error` | unchanged | `--lang` line lists `godot` |

### `setup.sh`

| Item | Change |
| --- | --- |
| `AVAILABLE_LANGUAGES` | `("rust" "python" "node" "deno" "latex" "go" "godot")` |
| `LANGUAGE_DISPLAY_NAMES` | `["godot"]="Godot (GDScript + C#)"` |
| `show_help` | Language line, `GODOT_GUI` note, two examples (design.md) |
| `infer_scaffold_options` (single mode) | `[[ -f gdlintrc \|\| -f .github/workflows/godot-quality-check.yml ]] && langs+=(godot)` |
| Flags | **none added** |

### Environment variables (inputs)

| Variable | Read by | Values | Effect |
| --- | --- | --- | --- |
| `GODOT_GUI` | `_godot_resolve_gui_choice` (called from `plugin_interactive_setup` on a TTY and from `plugin_post_copy_shared` otherwise) | `true` / `1` / `yes` → on; any other non-empty value → off; unset → prompt (TTY, no `-y`, not staging, not already enabled) or off | Enables or disables the WSLg overlay without prompting, in TTY and non-TTY runs alike |
| `WSLG_X11_DIR`, `WSLG_DIR`, `WSL_LIB_DIR` | Docker Compose (interpolation in the overlay) | host paths | Override WSLg source paths (Docker Desktop) |

### Generated files

| Path (project) | Scope | Owner after scaffold | Manifest | Refresh |
| --- | --- | --- | --- | --- |
| `.github/workflows/godot-quality-check.yml` | root | developer (`.github/*` excluded, #286) | no | no |
| `docker-compose.godot-gui.yml` | root | developer | no (outside `_manifest_path_eligible`) | no |
| `<module>/gdlintrc`, `<module>/.editorconfig` | module | developer | no | no |
| `.claude/rules/godot.md` | root | developer | no | no (only `shell.md` is refresh-managed) |
| `mise.toml` entries, `.gitignore` block, `post.sh` block, devcontainer / Zed / hooks merges | root | developer | no | `.claude/settings.json` is replaced by the root AI refresh (pre-existing behavior for all languages) |

## Input/Output Schemas

### Input

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `--lang godot` / `--module <name>:godot` / `--add-module <name> --lang godot` | CLI | yes (to select) | Selects the flavor |
| `GODOT_GUI` | env | no | See above |
| TTY answer to `Enable the Godot GUI editor through WSLg? (y/n) [y\|n]` | interactive | no | Default `y` when the setup host has `/mnt/wslg` and `/dev/dxg` |

### Output

| Field | Type | Description |
| --- | --- | --- |
| `mise.toml [tools] godot` | inline table | .NET editor via github backend (`version`, `asset_pattern`, `rename_exe`) |
| `mise.toml [tools] dotnet` | string | `"10.0.403"` |
| `mise.toml [tools] uv` | string | python flavor's pin |
| `mise.toml [tools] gdtoolkit` | inline table | `{ version = "4.5.0", python = "3.12" }` |
| `mise.toml [tool_alias] godot / gdtoolkit` | string | `"github:godotengine/godot"`, `"pypi:gdtoolkit"` (only alongside a newly written tool entry) |
| `mise.toml [env] DOTNET_CLI_TELEMETRY_OPTOUT / DOTNET_NOLOGO` | string | `"1"` |
| `docker/Dockerfile.dev` | text block | `# >>> godot os-packages >>>` … `# <<< godot os-packages <<<` above `SHELL` |
| `.devcontainer/devcontainer.json :: customizations.vscode` | object | + 2 extensions, 4 settings |
| `.devcontainer/devcontainer.json :: dockerComposeFile` | array of string | + `"../docker-compose.godot-gui.yml"` (only when GUI enabled) |
| `.devcontainer/devcontainer.json :: customizations.zed.extensions` | array | + `gdscript`, `csharp` (only with `--zed`) |
| `.zed/settings.json` | object | + `**/.godot`, `languages.GDScript` (only with `--zed`) |
| `.claude/settings.json :: hooks.PostToolUse` | array | + one `Write\|Edit` entry with four `if` handlers |
| `.gitignore` | text block | marker + 8 lines |
| `.devcontainer/scripts/post.sh` | text block | `# Godot Engine Setup`, before Codex / plugin blocks |

### CI workflow contract (`godot-quality-check.yml`)

| Job id | Name | Needs | Outputs / skip notices |
| --- | --- | --- | --- |
| `lint` | GDScript Lint & Format | — | `::notice::No GDScript files found; skipping gdlint/gdformat` |
| `test` | Unit Tests (GUT, headless) | — | `::notice::No project.godot found; skipping`; per project `::notice::<dir>: addons/gut not found; skipping GUT`, `::notice::<dir>: no test directory or .gutconfig.json; skipping GUT` |
| `export` | Export (headless) | — | `::notice::No export_presets.cfg found; skipping export`; per preset `::notice::<dir>: preset "<name>" has no export_path; skipping` |

Exported artifacts land in `build/ci-export/<project slug>/<preset index>/<basename of export_path>`. The slug is the project directory without its leading `./`, with `/` replaced by `_` (`root` for the repository root), so two projects in a monorepo cannot collide on the same preset index.

Version derivation inside `export`:

```bash
tag="$(mise current godot)"                       # 4.7.2-stable
ver="$(godot --headless --version | tail -n 1 | sed -E 's/\.(official|custom_build)(\..*)?$//')"  # 4.7.2.stable.mono
dir="$HOME/.local/share/godot/export_templates/${ver}"
tpz="Godot_v${tag}_mono_export_templates.tpz"
# cache key: godot-export-templates-${ver}
# on miss: curl -fL release/${tag}/${tpz} + SHA512-SUMS.txt; sha512sum -c (matching line); unzip -q; mv templates/* "$dir"/
```

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| Invalid `mise_toml_has_key` arguments | exit 2 + `print_error` | Bad section or key. The plugin treats it like a failure (`print_warning`) and skips the pair. |
| `mise_toml_ensure` failure | exit 1 → `print_warning` | Scaffold continues; file untouched |
| GUI activation impossible (missing or unparseable `devcontainer.json`, missing overlay, write failure) | `print_warning` + manual hint, return 0 | File untouched |
| Copy declined (`copy_with_confirm`, workflow prompt) | `print_info`, continue | Other files still processed |
| `post_sh_add_block` write failure | exit 1 → `print_warning` | `post.sh` untouched |
| Container start with GUI enabled on a non-WSLg host | Docker error (`/dev/dxg` missing) | Documented recovery: remove the `dockerComposeFile` entry and rebuild |
| CI: template checksum mismatch / download failure | job failure | No cache saved |
| CI: GUT test failure | job failure | `-gexit` non-zero |
| CI: `dotnet build` failure | job failure | C# compile errors surface even without GUT |
