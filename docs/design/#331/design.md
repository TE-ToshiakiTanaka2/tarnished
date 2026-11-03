# Design: #331 Add Godot (GDScript + C#) language flavor with WSLg GUI overlay and headless CI

## Context

Tarnished generates devcontainer boilerplates. `setup.sh` loads plugins in a
fixed order: `core` → `agent-workflows` → selected `languages/*` → selected
`services/*` → `claude` → `codex` (if `--codex`) → `github-actions/*`. It then
runs three hook passes over them:

1. `plugin_copy`: verbatim copies.
2. `plugin_dockerfile`: OS-package blocks inserted above the single `SHELL`
   line of `docker/Dockerfile.dev`.
3. `plugin_post_copy`: merges and marker-guarded appends.

Language plugins split the third pass into `plugin_post_copy_shared(root)` and
`plugin_post_copy_module(dir, name)`. Single mode calls them through a
`plugin_post_copy` shim (#263). `plugin_interactive_setup`, when a plugin
defines it, runs at the start of that plugin's post-copy pass whenever a TTY
is available. Add-module mode skips `core`, `claude`, `codex` and
`github-actions`. `--upgrade` replays the whole pipeline into a private
staging tree, but applies decisions only to manifest-eligible files:
`.devcontainer/scripts/*.sh` other than `post.sh`.

Since #325 the generated environment has a three-layer install contract and no
devcontainer `features` anywhere:

| Layer | Declared in | Helper |
| --- | --- | --- |
| OS packages | `docker/Dockerfile.dev` | `common.sh::dockerfile_add_os_packages` from `plugin_dockerfile` |
| Runtimes | developer-owned `mise.toml` | `common.sh::mise_toml_ensure` from `plugin_post_copy_shared` (an existing key is never changed) |
| AI CLIs / plugins | `post.sh` blocks | `common.sh::post_sh_add_block`, with the load-bearing order `# mise Runtime Setup` → `# Claude Code Setup` → language/service blocks → `# Codex CLI Setup` → `# Claude Code Plugin Setup` |

Other shared truth this delta acts on:

- **Devcontainer merges.** `merge_devcontainer_json` deep-merges with jq `*`,
  which replaces arrays. `merge_docker_compose_services` merges service
  overlays: through yq `*` when yq is present (arrays are replaced), otherwise
  through a text fallback that can only append new top-level services and
  volumes. Service plugins mutate `runServices` with a direct jq `+=`.
- **Zed.** Zed assets go through `apply_zed_assets`, called once from
  `plugin_post_copy_shared`.
- **Hooks.** Claude hooks are merged by `merge_claude_settings_hooks`.
- **Language list.** `setup.sh::AVAILABLE_LANGUAGES` is
  `("rust" "python" "node" "deno" "latex" "go")`, and the same ids are the
  accepted values of `modules.json :: modules[].language`.
- **Placeholders.** `replace_placeholders` renders `{{PROJECT_NAME}}` only in a
  hard-coded list of files.

See `../shared/architecture.md` ("Install contract", "Editor flavors",
"Idempotency"), `../shared/api-spec.md` ("Language plugin contract",
"Generated install contract", `mise_toml_ensure`) and
`../shared/data-model.md` ("mise.toml schema"). External facts are in
[`research.md`](./research.md) and `../shared/research/mise.md`.

## Architecture Overview (delta)

A seventh language flavor, `templates/languages/godot/`, scaffolds tooling
only, for Godot 4 .NET projects with both GDScript and C#. It does not create
`project.godot`, `export_presets.cfg` or a GUT addon. It follows the rust
plugin's shape: a root-scoped CI workflow with the #265 overwrite prompt, a
shared/module split, and a backward-compatible `plugin_post_copy` shim. It
uses only the #325 install contract:

- **Runtimes in `mise.toml`.** `dotnet` (.NET 10 LTS SDK), the Godot .NET
  editor, `uv` and gdtoolkit. The registry shorthand `godot` can only fetch
  the non-.NET build, so `tools.godot` is backed by
  `tool_alias.godot = "github:godotengine/godot"` with an `asset_pattern` for
  the `_mono_` asset. gdtoolkit is backed by `pypi:gdtoolkit` with a private
  CPython, so it never needs the python flavor. `common.sh::mise_toml_ensure`
  learns the `tool_alias` section, and a new read-only
  `mise_toml_has_key` lets the plugin add an alias only together with the tool
  entry it backs.
- **OS packages through `plugin_dockerfile`.** One `godot` block carries the
  X11/Wayland, Mesa (including the WSLg `d3d12` GL driver), Vulkan, ALSA,
  PulseAudio, fontconfig, udev and dbus libraries; the .NET prerequisites
  (`libicu76`, `libssl3t64`); `netcat-openbsd` for Zed's GDScript LSP bridge;
  and `unzip` for export templates.
- **`post.sh`.** One informational `# Godot Engine Setup` block, placed by
  `post_sh_add_block` before the Codex and Claude-plugin blocks.

The **WSLg GUI** is an opt-in, separate Compose file,
`docker-compose.godot-gui.yml`. The plugin always copies it to the project
root, where it does nothing until it is listed in
`.devcontainer/devcontainer.json :: dockerComposeFile`. Compose's own
multi-file merge then appends the WSLg mounts and `/dev/dxg` to the dev
service and adds the WSLg environment. The plugin adds that list entry only
when the developer opts in, either through a `plugin_interactive_setup` prompt
whose default comes from WSLg detection on the setup host, or through
`GODOT_GUI=true`. Without the entry the container is headless, and that is the
default everywhere.

A new **`godot-quality-check.yml`** CI workflow installs the same pinned tools
from `mise.toml` through `jdx/mise-action@v4`. It discovers every
`project.godot`, so a monorepo module also works, and runs three jobs:

1. gdlint and `gdformat --check`.
2. `dotnet build` when a `.csproj` exists, then headless GUT. GUT is skipped
   with a notice when `addons/gut` is absent.
3. Headless export, skipped with a notice when `export_presets.cfg` is absent.

## Decisions Not Settled by the Issue

| # | Topic | Decision | Reasoning |
| --- | --- | --- | --- |
| D1 | **OQ-1**: Godot .NET source | Godot stays in `mise.toml`: `[tool_alias] godot = "github:godotengine/godot"` plus `tools.godot = { version = "4.7.2-stable", asset_pattern = 'Godot_v{{ version }}_mono_linux_{{ arch(x64="x86_64", arm64="arm64") }}.zip', rename_exe = { "Godot_v*_mono_linux.*" = "godot" } }` | The aqua package hard-codes the standard asset name. The github backend with this exact entry was installed and run with the pinned mise 2026.10.25: `godot --headless --version` → `4.7.2.stable.mono.official.ed1daf0bf` (research §1, §3). The alias keeps the issue's key `tools.godot`. A `plugin_dockerfile` install would put a runtime pin in the Dockerfile, which #325 forbids. |
| D2 | **OQ-2**: pins | `godot` `4.7.2-stable`; `dotnet` `10.0.403` (newest 10.0 SDK); `gdtoolkit` `4.5.0`; `uv` = the python flavor's pin (`0.13.6` today) | 4.7.2 is the newest 4.x stable. Godot 4.7 needs .NET ≥ 8; .NET 8 reaches end of life on 2026-11-10, and 10.0 is the active LTS (Godot 4.8 will require it). The editor host rolls forward to the latest major (research §4). Sharing uv's pin with the python flavor avoids the first writer deciding a different uv in a godot+python monorepo. Like #325, implementation re-checks for newer patch releases (godot 4.7.x, dotnet 10.0.x, gdtoolkit) and uses whatever is newest then. |
| D3 | **OQ-3**: C# formatter | `dotnet format whitespace <dir> --folder --include <file>` in the `*.cs` hook | It ships with the SDK (no extra tool), runs without loading a project, and reads the module `.editorconfig` (FR-12). CSharpier would need a `dotnet:` alias entry and ignores most of `.editorconfig` (research §8). The style/analyzer passes need a project load, which is too slow for a hook; `godot.md` documents `dotnet format <csproj>` for a full pass. |
| D4 | gdtoolkit install (FR-3, Constraint) | `tools.uv`, `[tool_alias] gdtoolkit = "pypi:gdtoolkit"`, `tools.gdtoolkit = { version = "4.5.0", python = "3.12" }` | Verified: installs with uv and a mise-managed private CPython 3.12, and `python` is not activated (research §6). Without `python = …`, uv downloads the newest CPython and builds PyYAML from source. 3.12 matches the python flavor's default, so a godot+python project shares one interpreter install. |
| D5 | Writing alias entries safely | (a) `mise_toml_ensure` accepts the section `tool_alias`. (b) New `mise_toml_has_key <file> <section> <key>` (exit 0 = present) uses exactly `mise_toml_ensure`'s presence rule. (c) The plugin writes `tool_alias.<k>` only when `tools.<k>` was absent before this run, then writes `tools.<k>`. | An unconditional alias would retarget a developer's own `godot = "…"` (aqua, standard build) to the github backend without `asset_pattern` / `rename_exe`, so `godot` would vanish from `PATH`. That violates FR-2 ("existing developer entries are never changed"). A developer who already has `tool_alias.godot` but no `tools.godot` keeps their alias (`mise_toml_ensure` skips it), and only the tool entry is added. Keys with `:` or `/` (`"github:…"`) stay unsupported by design: an alias keeps keys bare. |
| D6 | `[env]` | `DOTNET_CLI_TELEMETRY_OPTOUT = "1"`, `DOTNET_NOLOGO = "1"`. **No** `DOTNET_ROOT`. | Godot finds hostfxr through `DOTNET_ROOT` (exported by mise for dotnet), and otherwise through `dotnet --list-sdks` on `PATH`, which works through the shim (research §5). Pinning `DOTNET_ROOT` by hand would break mise's isolated mode. Telemetry opt-out and no first-run banner are container defaults that keep CI logs and post-create output clean; both are ordinary developer-owned entries. |
| D7 | OS packages (FR-7) | Block id `godot`, unconditional (list in "Type Definitions") | `plugin_dockerfile` runs before the post-copy pass, so it cannot know the GUI choice. Installing the GUI libraries always also means a later opt-in needs no Dockerfile edit. Debian trixie has no Dozen Vulkan driver, so `mesa-vulkan-drivers` gives CPU Vulkan (lavapipe), and `libgl1-mesa-dri` gives GPU OpenGL through `d3d12_dri.so` on WSLg (research §10). |
| D8 | **FR-8 "merged the same way service plugins merge compose files"** | The overlay is **not** merged into `docker-compose.yml`. It stays a separate file, and Compose's native multi-file merge applies it once it is listed in `dockerComposeFile`. The plugin appends the entry with a direct jq edit (the `runServices` precedent) that keeps order and never duplicates. | `merge_docker_compose_services` cannot add mounts to the existing dev service: with yq, `*` replaces the service's `volumes` array (dropping the `/workspace` mount); without yq, the fallback re-emits the service key (duplicate YAML key). A merged block would also make `/dev/dxg` mandatory, and Docker refuses to start a container whose device is missing, which breaks FR-8's own acceptance and NFR-4. Compose's multi-file merge appends `volumes` / `devices` by target path and merges `environment` by key (research §9). The Implementation Approach ("Keep the GUI overlay a separate file so headless remains the default path") supports this reading. **Flagged for orchestrator review** as a deviation from the literal FR-8 wording. |
| D9 | Opt-in trigger | A non-prompting resolver, `_godot_resolve_gui_choice`, decides from `GODOT_GUI=true\|false`, from an already-listed entry, and from staging / `-y` / no-TTY (⇒ off). It runs from `plugin_post_copy_shared` whenever the choice is still undecided, so it works in non-TTY runs, where `setup.sh` never calls `plugin_interactive_setup`. `plugin_interactive_setup` calls the same resolver and adds only the prompt `Enable the Godot GUI editor through WSLg? (y/n) [<default>]` when the choice is still open and a TTY exists. The default is `y` when the setup host has `/mnt/wslg` and `/dev/dxg`, otherwise `n`. Full order in "GUI choice resolution". **No new `setup.sh` flag.** | The issue scopes `setup.sh` edits to the language list, help and examples. A flag would also touch argument parsing, `scaffold_flags_supplied`, add-module handling and manifest options. The env var keeps `-y` and `curl \| bash` runs scriptable, and `setup.sh --help` documents it. `setup.sh` gates `plugin_interactive_setup` on a TTY (not on `-y`), so the env var must be read outside that hook. Skipping the prompt in staging modes keeps `--upgrade` non-interactive. |
| D10 | Overlay file lifecycle | `plugin_copy` always copies `docker-compose.godot-gui.yml` to the root with `copy_with_confirm`. `replace_placeholders` gains it in its file list. The file is developer-owned. | An inert file costs nothing and lets a teammate opt in later with a one-line edit (documented). It needs `{{PROJECT_NAME}}` as the service key, and only listed files are rendered. It is outside `_manifest_path_eligible`, so `--upgrade` never touches it and no `MANIFEST_EXCLUDE_GLOBS` entry is needed. |
| D11 | Overlay content | Fixed container-side values (`WAYLAND_DISPLAY=wayland-0`, `XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir`, `PULSE_SERVER=unix:/mnt/wslg/PulseServer`, `DISPLAY=${DISPLAY:-:0}`), plus the vGPU pieces (`/usr/lib/wsl:ro`, `LD_LIBRARY_PATH=/usr/lib/wsl/lib`). Host source paths are overridable: `${WSLG_X11_DIR:-/tmp/.X11-unix}`, `${WSLG_DIR:-/mnt/wslg}`, `${WSL_LIB_DIR:-/usr/lib/wsl}`. | With systemd enabled, the host `XDG_RUNTIME_DIR` is `/run/user/<uid>`, which does not exist in the container. The `/mnt/wslg` paths are stable. FR-8's list lacks `/usr/lib/wsl` and `LD_LIBRARY_PATH`, but Microsoft documents both as required for `/dev/dxg` to be usable. The overrides cover Docker Desktop, whose WSLg paths differ; that path is unverified (Risks). |
| D12 | `post.sh` block | Marker `# Godot Engine Setup`, placed by `post_sh_add_block` before `# Codex CLI Setup` / `# Claude Code Plugin Setup`, in every mode. Informational only: `godot` / `dotnet` versions, a missing-export-templates hint with exact commands, and GUI vs headless mode. | Runtimes are installed by `setup_mise`, so there is nothing to install here. The block exists to tell the developer which mode they are in and what to download. A new flavor has no pre-#263 single-mode bytes to preserve, so it needs no unmarked legacy variant. `post_sh_add_block` gives exact-line idempotency in all modes and keeps the #325 order whatever the load order. Export templates are about 1.2 GB, which is too heavy for post-create. |
| D13 | gitignore (FR-10) | Root `.gitignore` block `# Godot (engine caches and export output)` (lines in "Type Definitions"), appended by `plugin_post_copy_shared` after `grep -q "^<marker>$"` | Root scope, like the codex blocks. The patterns are unanchored, so they also match inside monorepo modules. Export output directories: `build/` and `export/`. CI writes to `build/ci-export/`. Godot 4 `.import` sidecars and `export_presets.cfg` must stay tracked, so they are not listed. |
| D14 | CI tool installation | `jdx/mise-action@v4` (first `node24` major, #267 rule) with `install_args` per job; versions come only from `mise.toml` | One source of versions for container and CI, which avoids the drift #325 recorded for the other language workflows. `github_token` is passed by the action, which avoids GitHub API throttling for the github backend. |
| D15 | CI project discovery | Every directory containing `project.godot`, excluding `.godot/` and `addons/` | Works in single mode (repo root) and in monorepo modules without configuration. No project means each job prints `::notice::` and succeeds. |
| D16 | Where `dotnet build` runs | First step of job 2 (tests), per discovered project with a `*.csproj`, before GUT | FR-9 fixes three jobs. Godot must have compiled C# assemblies before it can load C# scripts headless, so the build has to precede GUT anyway. It runs even when GUT is absent, so C# compile errors fail CI. Export (job 3) builds C# itself. |
| D17 | Export templates in CI | Derive the template dir from `godot --version` and the release tag from `mise current godot`. Cache `~/.local/share/godot/export_templates` with `actions/cache@v5` keyed on the version. On a miss, download the `.tpz`, check it against `SHA512-SUMS.txt`, and unzip it. | Templates are required by `--export-release`. The SHA-512 check keeps the download verifiable. Caching avoids 1.2 GB per run. |
| D18 | Export presets in CI | Export every `[preset.N]` whose `export_path` is non-empty to `build/ci-export/<preset index>/<basename of export_path>`. Presets without `export_path` get a `::notice::` and are skipped. | It needs no configuration, keeps the platform file extension the developer chose, and never writes over the developer's own export path. |
| D19 | Editor integration (FR-6) | VS Code: `geequlim.godot-tools`, `ms-dotnettools.csharp`. Settings: `godotTools.editorPath.godot4 = "godot"`, `godotTools.lsp.headless = true`, plus `.godot` in `search.exclude` / `files.watcherExclude`. Zed: extensions `gdscript`, `csharp`; GDScript formatted on save by `gdformat -`; `**/.godot` in `file_scan_exclusions`. | The headless LSP gives completion on hosts without WSLg. `ms-dotnettools.csharp` is the MIT-licensed C# extension (C# Dev Kit needs a license). Zed's gdscript extension needs `nc`, which is installed by D7. |
| D20 | Shared/module split (FR-12) | Module: `gdlintrc`, `.editorconfig`. Shared: `mise.toml`, devcontainer + Zed, GUI overlay activation, Claude hooks + rules, gitignore, `post.sh`. Root `plugin_copy`: CI workflow, GUI overlay file. | Lint and format configuration is per project, and `gdlint` / `dotnet format` read it from the file's ancestors. Everything else is per container. |
| D21 | Single-mode scaffold inference | `setup.sh::infer_scaffold_options` adds `godot` when `gdlintrc` or `.github/workflows/godot-quality-check.yml` exists | A tooling-only scaffold has no `project.godot` to probe. Like latex's `build-pdf.yml`, the probe uses files the plugin emits, so the upgrade staging run rebuilds the same tree. |
| D22 | Automated FR-8 / NFR-4 acceptance | Add a `godot` entry to `scaffold-build.yml` (args `--lang godot`, tools `godot dotnet gdformat gdlint`), and teach `scripts/ci/smoke-runtimes.sh` these four tools | It checks "`godot --headless --version` works in the container" on a non-WSLg runner for every change to the templates. It costs one more matrix leg (larger image: about 300 MB of SDK, Godot and Mesa). |
| D23 | Mirrors | None. `scripts/verify-mirrors.sh` is unchanged. | The workspace does not dogfood Godot, and no new asset is mirrored. |

## Module Structure (delta)

```
templates/languages/godot/                         NEW flavor
├── plugin.sh                                      plugin_name, plugin_description, plugin_interactive_setup,
│                                                  plugin_copy, plugin_dockerfile, plugin_post_copy_shared,
│                                                  plugin_post_copy_module, plugin_post_copy (shim);
│                                                  private _godot_* helpers
├── docker-compose.godot-gui.yml                   WSLg overlay (copied to project root, inert until listed)
├── gdlintrc                                       per-module gdlint config (4.5.0 defaults + excludes)
├── .editorconfig                                  per-module editor/formatter config (GDScript tabs, C# spaces)
├── .claude/
│   ├── settings.json                              PostToolUse hooks: *.gd → gdformat, *.cs → dotnet format whitespace
│   └── rules/godot.md                             GDScript/C# conventions, scenes, signals, pitfalls
├── .devcontainer/devcontainer.json                customizations.vscode only (extensions + settings)
├── .zed/
│   ├── devcontainer.json                          customizations.zed.extensions: gdscript, csharp
│   └── settings.json                              file_scan_exclusions + GDScript external formatter
└── .github/workflows/godot-quality-check.yml      lint / test (dotnet build + GUT) / export
scripts/lib/common.sh                              EDIT  mise_toml_ensure accepts `tool_alias`;
                                                         NEW mise_toml_has_key; replace_placeholders list
                                                         + docker-compose.godot-gui.yml;
                                                         show_interactive_mode_error lists godot
setup.sh                                           EDIT  AVAILABLE_LANGUAGES + LANGUAGE_DISPLAY_NAMES (godot),
                                                         help (language line, GODOT_GUI, example),
                                                         infer_scaffold_options godot probe (D21)
.github/workflows/scaffold-build.yml               EDIT  + godot matrix entry (D22)
scripts/ci/smoke-runtimes.sh                       EDIT  + godot, dotnet, gdformat, gdlint checks (D22)
tests/                                             see workflow.md "Test Strategy"
README.md, docs/setup.md, AGENTS.md                EDIT  NFR-5 / contributor docs
```

No file is added outside `templates/languages/godot/`'s permitted
subdirectories (`AGENTS.md` §4). The project-root distributables it ships are
the CI workflow (`.github/`), and the Compose overlay, which follows the
`templates/services/<svc>/docker-compose.<svc>.yml` precedent of a
root-level Compose file.

## Interface Design (delta)

Full signatures, schemas and error tables: [`api-spec.md`](./api-spec.md).

### Public API / Functions

| Name | Signature | Description |
| --- | --- | --- |
| `plugin_name` | `() -> stdout "godot"` | Stable id; equals the directory name and the `AVAILABLE_LANGUAGES` entry. |
| `plugin_description` | `() -> stdout` | `Godot 4 (.NET) game development with GDScript and C#` |
| `plugin_interactive_setup` | `() -> 0` | Called by `setup.sh` only when a TTY is available. Calls `_godot_resolve_gui_choice`; prompts only if the choice is still empty (D9). Never prompts with `-y`, in upgrade / create-manifest mode, with `GODOT_GUI` set, or when already enabled. |
| `plugin_copy` | `(target_dir) -> 0` | Root: `godot-quality-check.yml` (#265 prompt) and `docker-compose.godot-gui.yml` (`copy_with_confirm`). Each copy is independent: declining one does not skip the other. |
| `plugin_dockerfile` | `(target_dir) -> 0` | `dockerfile_add_os_packages "<target>/docker/Dockerfile.dev" godot <packages…>` |
| `plugin_post_copy_shared` | `(target_dir) -> 0` | Root: mise entries (D1–D6) → devcontainer merge → `apply_zed_assets` → GUI choice (`_godot_resolve_gui_choice` when `GODOT_GUI_ENABLED` is empty; empty afterwards ⇒ off) and activation when `true` → hooks merge → rules copy → gitignore block → `post.sh` block. No early return. |
| `plugin_post_copy_module` | `(target_dir, module_name) -> 0` | `copy_with_confirm` of `gdlintrc` and `.editorconfig` into `target_dir`. |
| `plugin_post_copy` | `(target_dir) -> 0` | Shim: shared(root) + module(root, `PROJECT_NAME`). |
| `_godot_copy_workflow` | `(target_dir) -> 0` | Private: the rust-style overwrite prompt, then `OVERWRITE_ALL=true copy_with_confirm`. |
| `_godot_enable_gui_overlay` | `(target_dir) -> 0` | Private: appends `"../docker-compose.godot-gui.yml"` to `dockerComposeFile` when absent (D8). Warns and leaves the file untouched on failure. |
| `_godot_resolve_gui_choice` | `([target_dir]) -> 0` | Private, never prompts. Sets `GODOT_GUI_ENABLED` to `true` / `false` from steps 1–3 of "GUI choice resolution" (`GODOT_GUI` → already-listed entry → staging / `SKIP_CONFIRM` / no TTY ⇒ `false`), else leaves it empty. Called by `plugin_interactive_setup` and by `plugin_post_copy_shared`. |
| `_godot_gui_entry_present` | `(devcontainer_json) -> 0\|1` | Private: whether the entry is already listed. Used by the resolver (step 2) and by activation. |
| `_godot_wslg_detected` | `() -> 0\|1` | Private: `[[ -d /mnt/wslg ]] && [[ -e /dev/dxg ]]` on the setup host (prompt default only). |
| `_godot_ensure_aliased_tool` | `(mise_toml, key, alias_target, tool_value, label) -> 0` | Private: D5(c): `mise_toml_has_key tools <key>` → if absent, `mise_toml_ensure tool_alias` then `mise_toml_ensure tools`. Failures become `print_warning`. |
| `mise_toml_has_key` | `(mise_toml, section, key) -> 0 present \| 1 absent \| 2 bad args` | NEW in `common.sh`. Read-only. Same presence rule as `mise_toml_ensure`. Missing file → 1. |
| `mise_toml_ensure` | unchanged signature | `section` ∈ {`tools`, `env`, `settings`, **`tool_alias`**}. |

Private helpers carry the `_godot_` prefix. `setup.sh::unset_plugin_functions`
unsets only the contract names, so plugin-private functions must be uniquely
prefixed to avoid colliding with another plugin's leftovers.

### Type Definitions (delta)

#### `mise.toml` entries written by `plugin_post_copy_shared`

Writes happen in this order. "If absent" means the whole pair is skipped when
`tools.<key>` already exists (D5).

| Section | Key | Value | Condition |
| --- | --- | --- | --- |
| `[tool_alias]` | `godot` | `"github:godotengine/godot"` | `tools.godot` absent |
| `[tools]` | `godot` | `{ version = "4.7.2-stable", asset_pattern = 'Godot_v{{ version }}_mono_linux_{{ arch(x64="x86_64", arm64="arm64") }}.zip', rename_exe = { "Godot_v*_mono_linux.*" = "godot" } }` | `tools.godot` absent |
| `[tools]` | `dotnet` | `"10.0.403"` | `mise_toml_ensure` rule |
| `[tools]` | `uv` | python flavor's pin (`"0.13.6"`) | `mise_toml_ensure` rule (no-op when python already wrote it) |
| `[tool_alias]` | `gdtoolkit` | `"pypi:gdtoolkit"` | `tools.gdtoolkit` absent |
| `[tools]` | `gdtoolkit` | `{ version = "4.5.0", python = "3.12" }` | `tools.gdtoolkit` absent |
| `[env]` | `DOTNET_CLI_TELEMETRY_OPTOUT` | `"1"` | `mise_toml_ensure` rule |
| `[env]` | `DOTNET_NOLOGO` | `"1"` | `mise_toml_ensure` rule |

`{{ version }}` and `{{ arch(…) }}` are mise Tera templates, not Tarnished
placeholders (`replace_placeholders` matches only `{{[A-Za-z0-9_]+}}` with no
spaces, and never processes `mise.toml`). The non-string tool options need
mise trust, which `MISE_TRUSTED_CONFIG_PATHS=/workspace` and `mise install`'s
self-trust already provide.

Resulting fresh single-mode file (core + godot):

```toml
# Runtime versions for this project, managed by mise (https://mise.jdx.dev).
# ...core header...

[tools]
node = "22"
godot = { version = "4.7.2-stable", asset_pattern = 'Godot_v{{ version }}_mono_linux_{{ arch(x64="x86_64", arm64="arm64") }}.zip', rename_exe = { "Godot_v*_mono_linux.*" = "godot" } }
dotnet = "10.0.403"
uv = "0.13.6"
gdtoolkit = { version = "4.5.0", python = "3.12" }

[tool_alias]
godot = "github:godotengine/godot"
gdtoolkit = "pypi:gdtoolkit"

[env]
DOTNET_CLI_TELEMETRY_OPTOUT = "1"
DOTNET_NOLOGO = "1"
```

The alias for `godot` is written before `tools.godot`, so the `[tool_alias]`
header is created first and lands after `[tools]` (which core already
created). Section order is irrelevant to TOML and mise.

#### OS-package block (`plugin_dockerfile`)

`dockerfile_add_os_packages "${target_dir}/docker/Dockerfile.dev" godot` with,
in this order:

| Group | Packages |
| --- | --- |
| X11 | `libx11-6 libxcursor1 libxext6 libxi6 libxinerama1 libxrandr2 libxrender1` |
| Wayland | `libwayland-client0 libwayland-cursor0 libwayland-egl1 libxkbcommon0 libdecor-0-0` |
| OpenGL / Vulkan / Mesa (incl. WSLg `d3d12`) | `libgl1 libegl1 libglx-mesa0 libgl1-mesa-dri libvulkan1 mesa-vulkan-drivers` |
| Audio | `libasound2t64 libpulse0` |
| Fonts, input, IPC | `libfontconfig1 libudev1 libdbus-1-3` |
| .NET SDK prerequisites | `libicu76 libssl3t64` |
| Tooling | `netcat-openbsd unzip` |

Markers: `# >>> godot os-packages >>>` / `# <<< godot os-packages <<<`. The
Debian package names are trixie-specific (`*t64`, `libicu76`), which matches
the core base image `debian:trixie-slim`.

#### `docker-compose.godot-gui.yml` (template; rendered at the project root)

```yaml
# Godot GUI editor through WSLg (Windows 11 + WSL2 only).
# Opt-in: active only while ".devcontainer/devcontainer.json" lists
# "../docker-compose.godot-gui.yml" in "dockerComposeFile". Remove that entry
# and rebuild on hosts without WSLg: the container then runs headless.
# Docker Desktop users may need to override WSLG_X11_DIR / WSLG_DIR / WSL_LIB_DIR.
services:
  {{PROJECT_NAME}}:
    volumes:
      - ${WSLG_X11_DIR:-/tmp/.X11-unix}:/tmp/.X11-unix
      - ${WSLG_DIR:-/mnt/wslg}:/mnt/wslg
      - ${WSL_LIB_DIR:-/usr/lib/wsl}:/usr/lib/wsl:ro
    devices:
      - /dev/dxg:/dev/dxg
    environment:
      DISPLAY: ${DISPLAY:-:0}
      WAYLAND_DISPLAY: wayland-0
      XDG_RUNTIME_DIR: /mnt/wslg/runtime-dir
      PULSE_SERVER: unix:/mnt/wslg/PulseServer
      LD_LIBRARY_PATH: /usr/lib/wsl/lib
```

Activated `devcontainer.json`: `"dockerComposeFile": ["../docker-compose.yml",
"../docker-compose.godot-gui.yml"]`. Base first, so the overlay's keys win on
conflict. A string-valued `dockerComposeFile` is normalized to a one-element
array before appending.

#### Root `.gitignore` block

```gitignore

# Godot (engine caches and export output)
.godot/
.mono/
data_*/
mono_crash.*.json
*.translation
export_credentials.cfg
build/
export/
```

#### `.claude/settings.json` (flavor overlay)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "if": "Write(*.gd)", "command": "f=\"$(jq -r '.tool_input.file_path')\" && gdformat \"$f\"" },
          { "type": "command", "if": "Edit(*.gd)",  "command": "f=\"$(jq -r '.tool_input.file_path')\" && gdformat \"$f\"" },
          { "type": "command", "if": "Write(*.cs)", "command": "f=\"$(jq -r '.tool_input.file_path')\" && cd \"$(dirname \"$f\")\" && dotnet format whitespace . --folder --include \"$(basename \"$f\")\"" },
          { "type": "command", "if": "Edit(*.cs)",  "command": "f=\"$(jq -r '.tool_input.file_path')\" && cd \"$(dirname \"$f\")\" && dotnet format whitespace . --folder --include \"$(basename \"$f\")\"" }
        ]
      }
    ]
  }
}
```

The shape follows the #299 convention: `matcher` names tools only, the file
pattern goes in a per-handler `if`, and the path is read from stdin JSON and
quoted.

#### `.devcontainer/devcontainer.json` (flavor overlay)

```json
{
  "customizations": {
    "vscode": {
      "extensions": ["geequlim.godot-tools", "ms-dotnettools.csharp"],
      "settings": {
        "godotTools.editorPath.godot4": "godot",
        "godotTools.lsp.headless": true,
        "search.exclude": { "**/.godot": true },
        "files.watcherExclude": { "**/.godot/**": true }
      }
    }
  }
}
```

No `features`, `mounts` or `runArgs` (Constraint).

#### `.zed/devcontainer.json` / `.zed/settings.json`

```json
{ "customizations": { "zed": { "extensions": ["gdscript", "csharp"] } } }
```

```json
{
  "file_scan_exclusions": ["**/.godot"],
  "languages": {
    "GDScript": {
      "format_on_save": "on",
      "formatter": { "external": { "command": "gdformat", "arguments": ["-"] } }
    }
  }
}
```

#### `gdlintrc` and `.editorconfig` (per module)

- `gdlintrc`: the verbatim output of `gdlint --dump-default-config` from the
  pinned gdtoolkit (4.5.0), with `excluded_directories` extended to
  `{.git, .godot, addons}`. All other keys, including `max-line-length: 100`
  and `tab-characters: 1`, keep gdtoolkit's defaults so `gdformat` and
  `gdlint` agree.
- `.editorconfig`:

  ```ini
  root = true

  [*]
  charset = utf-8
  end_of_line = lf
  insert_final_newline = true
  trim_trailing_whitespace = true

  [*.gd]
  indent_style = tab
  indent_size = 4

  [*.cs]
  indent_style = space
  indent_size = 4

  [*.{json,yml,yaml}]
  indent_style = space
  indent_size = 2

  # Godot rewrites these files itself; editors must not reformat them.
  [*.{tscn,tres,godot,import,cfg}]
  trim_trailing_whitespace = false
  insert_final_newline = false
  ```

#### `post.sh` block (body passed on stdin to `post_sh_add_block`)

```bash
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
            echo "  - Export templates not installed (needed only for exporting); see docs/setup.md \"Godot\" or:"
            echo "      mise exec -- godot --headless --version  # then download Godot_v<tag>_mono_export_templates.tpz"
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
```

Implementation may refine the hint wording. Fixed: no `exit`, no `sudo`,
every command guarded so `set -e` cannot abort `post.sh`, and no network
download.

#### `.github/workflows/godot-quality-check.yml` (job matrix)

| Job | Tools (`install_args`) | Skip conditions (each prints `::notice::` and succeeds) | Steps |
| --- | --- | --- | --- |
| `lint` (`GDScript Lint & Format`) | `uv gdtoolkit` | no `*.gd` outside `.godot/` / `addons/` | `gdlint <files>`; `gdformat --check <files>` |
| `test` (`Unit Tests (GUT, headless)`) | `godot dotnet` | no `project.godot` → whole job no-op. Per project: no `*.csproj` → skip build; no `addons/gut` → skip GUT; neither `.gutconfig.json` nor `test/` / `tests/` → skip GUT | per project: `dotnet build <csproj>`; `godot --headless --path <dir> --import`; `godot --headless --path <dir> -s addons/gut/gut_cmdln.gd -gexit [-gdir=res://test,res://tests -ginclude_subdirs]` |
| `export` (`Export (headless)`) | `godot dotnet` | no project with `export_presets.cfg` → job no-op; preset without `export_path` → skip that preset | resolve versions; `actions/cache@v5` on templates; on miss download + SHA-512 check + unzip; per preset `godot --headless --path <dir> --export-release "<name>" "build/ci-export/<n>/<basename>"` |

Shared conventions: `on` / branch filters copied from
`rust-quality-check.yml` (`pull_request` and `push` on `develop`);
`permissions: contents: read`; `actions/checkout@v5`; a cheap detection step
runs before `jdx/mise-action@v4` and gates it with `if:`, so skipped jobs
install nothing; `timeout-minutes` 15 / 20 / 30.

## Data Flow

1. **Scaffold** (`./setup.sh demo --lang godot -y`; the branching is in
   [`flowchart.md`](./flowchart.md)):
   1. `plugin_copy` writes the workflow and the inert GUI overlay.
   2. `plugin_dockerfile` inserts the `godot` apt block above `SHELL`.
   3. In the post-copy pass, the GUI choice is resolved: by
      `plugin_interactive_setup` when a TTY exists (prompt only if still
      open), otherwise by `_godot_resolve_gui_choice` inside
      `plugin_post_copy_shared`. `GODOT_GUI=true` enables it in both cases;
      unset with `-y` or without a TTY means off.
   4. `plugin_post_copy_shared` writes `mise.toml` entries, merges the
      devcontainer and Zed overlays, appends `dockerComposeFile` only when
      enabled, merges hooks, copies rules, appends the gitignore block, and
      places the `post.sh` block.
   5. `plugin_post_copy_module` copies `gdlintrc` and `.editorconfig`.
   6. `replace_placeholders` renders the overlay's service key.
2. **Image build**: root apt (core + `godot` block), then as `vscode`
   `mise install`, which brings `node`, `godot` (github `_mono_` zip), `dotnet`
   (dotnet-install), `uv`, a private CPython 3.12 and `gdtoolkit`.
3. **Container start**: with the overlay listed, Compose merges the WSLg
   mounts, device and env into the dev service. Without it the service is
   unchanged.
4. **Post-create**: `setup_mise` → `setup_claude` → `# Godot Engine Setup`
   (report) → codex → plugins. See the updated
   `../shared/sequence.md` "Godot flavor: GUI opt-in and container launch".
5. **CI**: each job detects inputs, installs only its tools from `mise.toml`,
   and runs the checks or emits notices.

## Error Handling

Shared policy (architecture.md "Plugin failures"): scaffold helpers return
non-zero only for programming errors, and plugins downgrade those to
`print_warning`. `post.sh` code never aborts.

| Condition | Where | Behavior |
| --- | --- | --- |
| `mise_toml_ensure` / `mise_toml_has_key` invalid args or write failure | `_godot_ensure_aliased_tool`, shared hook | `print_warning "Could not add …"`; scaffold continues; `mise.toml` untouched |
| `tools.godot` / `tools.gdtoolkit` already present | `_godot_ensure_aliased_tool` | `print_info "Kept existing tools.<k>"`; no alias written |
| `tool_alias.<k>` present but `tools.<k>` absent | same | alias kept as the developer wrote it; tool entry added |
| `devcontainer.json` missing, unparseable for jq (e.g. hand-added comments), or the write fails during GUI activation | `_godot_enable_gui_overlay` | `print_warning` with the manual one-line edit; file untouched (temp + `mv` only on success); return 0 |
| `docker-compose.godot-gui.yml` declined at the copy prompt but GUI enabled | `_godot_enable_gui_overlay` | Activation is still performed only if the overlay file exists at the root; otherwise `print_warning` and no entry is added (an entry pointing at a missing file would break `docker compose`) |
| No `SHELL` anchor / no Dockerfile | `dockerfile_add_os_packages` | existing behavior: warning listing the packages |
| CI workflow exists and the user declines | `_godot_copy_workflow` | `print_info "Skipping godot-quality-check.yml"`; other copies continue |
| GUI enabled on a host without WSLg | Docker at container start | Container start fails ("error gathering device information … /dev/dxg"). Documented recovery: remove the `dockerComposeFile` entry and rebuild. Prevented by default `n` off-WSLg (D9). |
| `godot` / `dotnet` not runnable at post-create | `post.sh` block | informational line / `[WARN]` with `mise install` hint; continues |
| Export templates download / SHA-512 mismatch | CI `export` job | job fails (integrity is not negotiable); cache is not saved |
| GUT failures | CI `test` job | `-gexit` returns non-zero; job fails |

## Implementation Notes

### Requirement traceability

| Req | Carried by |
| --- | --- |
| FR-1 | `templates/languages/godot/plugin.sh` (functions table); `AVAILABLE_LANGUAGES` / display name / help; `tests/setup_language_selection.bats` new cases; D22 CI leg runs `./setup.sh … --lang godot -y` |
| FR-2 | D1, D2, D5 (`mise_toml_has_key`, alias guard); bats: hand-edited `godot` / `dotnet` kept byte-identical, no alias added |
| FR-3 | D4 (`pypi:gdtoolkit`, private CPython, no python flavor); `gdlintrc` per module |
| FR-4 | `.claude/settings.json` overlay merged by `merge_claude_settings_hooks`; D3 |
| FR-5 | `.claude/rules/godot.md` via `copy_dir_with_confirm` (outline below) |
| FR-6 | devcontainer overlay (D19); `.zed/` assets through `apply_zed_assets` |
| FR-7 | `plugin_dockerfile` block `godot` (D7) |
| FR-8 | `docker-compose.godot-gui.yml` + activation (D8–D11); headless default; D22 acceptance |
| FR-9 | workflow job matrix (D14–D18); `_godot_copy_workflow` = #265 prompt |
| FR-10 | gitignore block (D13), exact-line marker guard |
| FR-11 | the plugin creates no `project.godot`, `export_presets.cfg` or `addons/`; every distributed file goes through `copy_with_confirm` / `copy_dir_with_confirm` / the #265 prompt; bats asserts their absence |
| FR-12 | D20; monorepo + `--add-module … --lang godot` bats |
| NFR-1 | Only `common.sh` helpers (plus the two small `common.sh` extensions); `post_sh_add_block`; shell rules |
| NFR-2 | `plugin_idempotency.bats` godot cases (single, monorepo, add-module, ZED) |
| NFR-3 | The `common.sh` changes are additive (new section value, new function, one more list entry that does not exist in other flavors' trees); workflow.md step 9 diffs every existing flavor's scaffold against `develop` |
| NFR-4 | GUI off by default; overlay inert; D22 CI on a non-WSLg runner; CI jobs skip cleanly |
| NFR-5 | Docs plan below |

### `mise_toml_has_key` and the `tool_alias` section

- Extract the presence predicate of `mise_toml_ensure`'s awk program (the
  `present` computation: bare or quoted key in `[section]`, a
  `[section.key]` header, or a top-level `section.key =`) so both functions
  share it. `mise_toml_ensure`'s output must stay byte-identical. The existing
  `tests/common_mise.bats` cases guard this.
- `mise_toml_has_key` validates arguments the same way (section in the
  allowed set, key regex) and returns 2 on bad input. It never creates the
  file, and returns 1 for a missing one.
- `tool_alias` joins the allowed `case` list. Nothing else in
  `mise_toml_ensure` is section-specific.

### GUI choice resolution (`_godot_resolve_gui_choice` + `plugin_interactive_setup`)

`setup.sh` calls `plugin_interactive_setup` only when a TTY is available
(`execute_plugin_post_copies`: `declare -f plugin_interactive_setup &&
check_tty_available`). It is not gated on `SKIP_CONFIRM`. In every non-TTY run
(CI, the `curl … | bash` bootstrap, the D22 scaffold-build leg, bats) the hook
never runs. The decision therefore cannot live only in that hook. It is split
in two:

**Resolver.** `_godot_resolve_gui_choice [target_dir]` never prompts. It sets
the global `GODOT_GUI_ENABLED` to `true` or `false` when one of steps 1–3
decides, and leaves it empty ("open") otherwise:

1. If `GODOT_GUI` is set and non-empty: `true` / `1` / `yes` → `true`,
   anything else → `false`.
2. Else, if `<target_dir>/.devcontainer/devcontainer.json` already lists the
   overlay (`_godot_gui_entry_present`) → `true`. There is nothing to ask, and
   activation is a no-op.
3. Else, if `UPGRADE_MODE`, `CREATE_MANIFEST_MODE` or `SKIP_CONFIRM` is true,
   or `check_tty_available` fails → `false`.
4. Otherwise it stays empty: only an interactive prompt can decide.

`target_dir` defaults to `TARGET_DIR`, which `setup.sh` sets before the
post-copy pass. When neither is available (isolated sourcing), step 2 is
skipped.

**Hook.** `plugin_interactive_setup` calls the resolver. Only if the choice is
still empty does it prompt with `confirm "Enable the Godot GUI editor through
WSLg?" <y|n>` (default `y` iff `_godot_wslg_detected`), and it stores the
answer.

**Consumer.** `plugin_post_copy_shared` step 4 calls
`_godot_resolve_gui_choice "$target_dir"` whenever `GODOT_GUI_ENABLED` is
empty, which is always the case in non-TTY runs. It then enables the overlay
only if the value is `true`. A value still empty after that call (an
interactive context where the hook did not run, e.g. a test calling
`plugin_post_copy` directly with a TTY) is treated as `false`, because the
consumer never prompts.

**Reset.** The plugin file sets `GODOT_GUI_ENABLED=""` at source time.
`setup.sh` sources the plugin once per pass, immediately before
`plugin_interactive_setup` and the post-copy hooks, so every post-copy pass
starts undecided and an earlier run's value can never leak in.

Resulting behavior:

| Context | `GODOT_GUI` | Hook runs? | Result |
| --- | --- | --- | --- |
| non-TTY (CI, bootstrap, bats), with or without `-y` | `true` | no | enabled (resolver step 1, from the shared hook) |
| non-TTY | unset | no | disabled (step 3), no prompt |
| TTY + `-y` | unset | yes | disabled (step 3), no prompt |
| TTY, no `-y` | unset | yes | prompt (step 4) |
| TTY or not | `false` | either | disabled, no prompt |
| any, overlay already listed | unset | either | enabled (step 2), no prompt |
| `--upgrade` / `--create-manifest` staging | unset | maybe | disabled (step 3), no prompt |

### Rules file outline (`.claude/rules/godot.md`)

Sections, in the style of the existing `rust.md` / `python.md`:

1. Project layout. `project.godot` is the root, `res://` paths, `.godot/` is a
   cache (never edit or commit it), `.import` files are committed, and
   `addons/` holds third-party code (never reformat it).
2. GDScript. Static typing (`var x: int`, typed arrays, `-> void`), `@export`
   / `@onready`, `class_name`, `snake_case` members, `PascalCase` classes,
   tabs, and `gdformat` / `gdlint` as the authority.
3. C#. `partial` classes deriving from Godot types, `[Export]` and
   `[Signal]` delegates ending in `EventHandler`, keeping the class name equal
   to the file name, preferring `GodotObject.IsInstanceValid` over null checks
   for freed nodes, `dotnet format` / `.editorconfig`, and rebuilding before
   running the editor after C# changes.
4. Scenes and nodes. Composition over deep inheritance, one script per scene
   root where possible, `%UniqueName` and `get_node` paths, avoiding
   hard-coded absolute paths, and `PackedScene` instantiation.
5. Signals. Declare at the top, past-tense names, connect in code or the
   editor but not both, disconnect on free, call down and signal up.
6. Pitfalls. Editing `.tscn` / `.tres` by hand (keep the UIDs), `_process`
   vs `_physics_process`, `await` on freed nodes, autoload overuse, mixing
   GDScript and C# across the same class, export templates per Godot version,
   and headless runs (`--headless`) in CI.
7. Testing. GUT layout (`res://test`, `test_*.gd`, `extends GutTest`) and
   running GUT headless.

### Monorepo, add-module, upgrade

- **Monorepo init** (`--module game:godot`). The shared hook runs once at the
  root: `mise.toml`, devcontainer, Zed, hooks, rules, gitignore, `post.sh` and
  GUI activation. The module hook runs for `game/`: `gdlintrc` and
  `.editorconfig`. CI discovers `game/project.godot` once the developer
  creates it.
- **`--add-module level2 --lang godot`.** All shared steps are idempotent, so
  re-running only copies the module files. The GUI prompt reappears only when
  the overlay is still not listed and the run is interactive without `-y`.
- **`--upgrade`.** Staging re-runs the hooks without prompting (D9 step 3).
  None of the godot files are manifest-eligible, so nothing in the target
  changes. D21 lets the staging run reproduce the same language set.

### `setup.sh` text changes

- `AVAILABLE_LANGUAGES=("rust" "python" "node" "deno" "latex" "go" "godot")`
  and `LANGUAGE_DISPLAY_NAMES["godot"]="Godot (GDScript + C#)"`. Appending at
  the end keeps the existing menu numbers stable.
- Help "Available Languages":
  `godot  Godot 4 .NET (GDScript + C#, gdtoolkit, GUT/export CI; WSLg GUI opt-in: GODOT_GUI=true)`.
- Examples: `./setup.sh --lang godot` and
  `GODOT_GUI=true ./setup.sh --lang godot -y   # WSL2: also run the Godot editor GUI`.
- `common.sh::show_interactive_mode_error`: the language list gains `godot`.

### Documentation (NFR-5)

- `README.md` "First-time setup": the runtime sentence names Godot and .NET.
  Add one line saying Godot projects can run the editor GUI in the container
  on WSL2 (link to docs/setup.md).
- `docs/setup.md`, new section "Godot (GDScript + C#)":
  - What is generated (tooling only).
  - `mise.toml` entries and why `godot` is aliased (the .NET build).
  - Bumping Godot: edit `tools.godot.version`, run `mise install`, then
    **re-download export templates** for the new version (exact commands:
    derive the tag, download `Godot_v<tag>_mono_export_templates.tpz`, check
    `SHA512-SUMS.txt`, unzip into
    `~/.local/share/godot/export_templates/<x.y.z>.stable.mono/`). The
    templates live in the container home and are lost on rebuild unless a
    volume is added.
  - The WSLg GUI opt-in: the prompt / `GODOT_GUI=true` / adding the
    `dockerComposeFile` entry by hand, and how to turn it off for teammates
    on macOS / Linux.
  - GPU note: Compatibility renderer `--rendering-driver opengl3` for
    `d3d12`; Vulkan runs on lavapipe (CPU).
  - Docker Desktop overrides (`WSLG_*`, unverified).
  - CI behavior and the skip notices.
  - `dotnet format` for a full C# style pass.
  - The runtime-layer table gains `godot`, `dotnet`, `gdtoolkit` and the OS
    row gains the Godot libraries.
  - The CI note lists godot in `scaffold-build.yml`.
- `AGENTS.md`: §1 lists `mise_toml_has_key` among the helpers, and notes that
  `tool_alias` is the sanctioned way to give a non-registry tool a bare key.
  §4 notes `templates/languages/godot/docker-compose.godot-gui.yml` as a
  root-level Compose file that is *not* merged into `docker-compose.yml`.

### Risks and follow-ups

- **Docker Desktop paths.** Docker Desktop's WSLg mounts are unverified, so
  the overlay is overridable but tested only against Docker Engine inside the
  WSL2 distro.
- **WSLg Vulkan is CPU-only on Debian trixie** (no Dozen). Forward+ works but
  slowly; documented. A future Debian/Mesa with `dzn` would fix it without a
  template change.
- **Image size.** The .NET SDK, Godot (≈145 MB unpacked) and Mesa/LLVM add
  roughly 0.8–1 GB. The scaffold-build leg (D22) runs longer.
- **CI export-template cache** is about 1.2 GB per Godot version, against
  GitHub's 10 GB repository cache limit.
- **Root AI refresh replaces `.claude/settings.json`** with the distributed
  claude template on container start. That template carries no language
  hooks, the same as for the other six languages today. This flavor inherits
  that pre-existing behavior; it is not changed here.
- **`python` shim in godot-only projects.** mise creates a `python` shim for
  gdtoolkit's private interpreter. In a godot-only project the shim reports
  "not active" instead of "command not found". This is harmless and
  documented.
- **A developer-deleted entry** comes back on the next `--add-module` for
  godot (#325's documented `mise_toml_ensure` limit). The alias pair is
  restored together.
