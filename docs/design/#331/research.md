# Research: #331 Godot (GDScript + C#) language flavor

Issue-specific research for the Godot flavor. The mise facts that other flavors
can reuse (the `github` / `pypi` backends and `[tool_alias]`) are promoted to
[`../shared/research/mise.md`](../shared/research/mise.md) (findings 10–12).
Sources were read, and the installs below were run, on 2026-11-03.

## Executive Summary

- **OQ-1: mise can install the Godot .NET build, but not through the registry
  shorthand.** `godot` resolves to `aqua:godotengine/godot`, and that aqua
  package hard-codes the standard asset name (`Godot_v<ver>_linux.x86_64.zip`),
  so it can only fetch the non-.NET build. mise's `github` backend can fetch the
  `_mono_` asset with `asset_pattern`, and with `rename_exe` the executable
  installs as `godot` next to its `GodotSharp/` directory. A `[tool_alias]`
  entry keeps the user-facing key `tools.godot`. This was installed and run
  with mise 2026.10.25, the version pinned in the core `Dockerfile.dev`:
  `godot --headless --version` printed `4.7.2.stable.mono.official.ed1daf0bf`
  both through `mise exec` and through the shim directory. Godot itself does not
  need to be installed by `plugin_dockerfile`.
- **OQ-2: Godot `4.7.2-stable` and .NET SDK `10.0.403`.** 4.7.2 is the newest
  4.x stable release. Godot 4.7 needs .NET 8 or later. .NET 8 reaches end of
  life on 2026-11-10, so .NET 10, the active LTS, is the newest LTS that Godot's
  .NET build supports. Godot's editor host is built with
  `RollForward=LatestMajor`, so it runs on the .NET 10 runtime alone.
- **OQ-3: `dotnet format`.** It ships with the .NET SDK, so it needs no extra
  global tool, and it reads `.editorconfig`, which this flavor distributes per
  module. CSharpier has no mise registry entry, would need a `dotnet:` backend
  entry, and would ignore most of `.editorconfig`.
- **gdtoolkit without the python flavor.** `pypi:gdtoolkit` (alias `pipx:`)
  installs through `uv tool install`. It needs `uv` in `mise.toml`, but not a
  `python` tool. The per-tool option `python = "3.12"` makes mise install
  CPython 3.12 privately for the tool, without making `python` an active tool.
  Without the option, uv downloaded the newest CPython (3.15.2), which had no
  PyYAML wheel, so PyYAML was built from source.
- **Finding dotnet:** Godot's editor looks for hostfxr through `DOTNET_ROOT`,
  then the default install directories, then `dotnet --list-sdks` on `PATH`.
  mise exports `DOTNET_ROOT` for dotnet. The `PATH` fallback works through the
  mise shim because `--list-sdks` prints the real SDK paths. No `[env]` entry is
  needed for Godot to find .NET.
- **WSLg:** Microsoft's container guidance needs `/tmp/.X11-unix` and
  `/mnt/wslg` bind mounts, `DISPLAY` / `WAYLAND_DISPLAY` / `XDG_RUNTIME_DIR` /
  `PULSE_SERVER`, and, for the vGPU, `/dev/dxg`, a `/usr/lib/wsl` mount and
  `LD_LIBRARY_PATH=/usr/lib/wsl/lib`. Debian trixie's Mesa (25.0.7) ships the
  Gallium `d3d12` OpenGL driver but no Dozen (`dzn`) Vulkan driver. On WSLg,
  GPU-accelerated rendering therefore means Godot's Compatibility renderer
  (`--rendering-driver opengl3`). Vulkan still works through `lavapipe`, on the
  CPU.

## Findings

### 1. aqua `godotengine/godot` cannot select the .NET build (OQ-1)

- **Details**: `mise registry` lists only one backend for `godot`:
  `aqua:godotengine/godot`. The aqua package (`pkgs/godotengine/godot/registry.yaml`)
  ends with a catch-all override (`version_constraint: "true"`) whose asset is
  `Godot_v{{.Version}}_{{.OS}}.{{.Arch}}.{{.Format}}`, with `amd64` replaced by
  `x86_64` on Linux. The file contains no `mono` asset at all, so the shorthand
  always installs the standard (GDScript-only) editor.
- **Source**: https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/godotengine/godot/registry.yaml ;
  `mise registry` (mise 2026.10.25).
- **Relevance**: FR-2 needs the .NET build. The shorthand cannot provide it.

### 2. Godot release assets (OQ-1, OQ-2)

- **Details**: GitHub release `4.7.2-stable` (2026-08-18) is the newest 4.x
  release. 3.6.3 was published later, on 2026-08-22, but it is a 3.x
  maintenance release. The tag has no `v` prefix. The .NET Linux assets are
  `Godot_v4.7.2-stable_mono_linux_x86_64.zip` (107,698,034 bytes) and
  `..._mono_linux_arm64.zip` (plus arm32 and x86_32). Export templates are
  `Godot_v4.7.2-stable_mono_export_templates.tpz` (about 1.2 GB). The release
  publishes `SHA512-SUMS.txt`, and the GitHub API reports a `sha256:` digest
  for each asset. The zip holds one top-level directory with the editor binary
  `Godot_v4.7.2-stable_mono_linux.x86_64` and a sibling `GodotSharp/`
  directory (94 entries). The DLLs under `GodotSharp/Tools/` carry executable
  bits.
- **Source**: `https://api.github.com/repos/godotengine/godot/releases`; the
  zip's central directory, read with an HTTP range request and `unzip -Z`.
- **Relevance**: The `asset_pattern` must name the `mono_linux_<arch>` asset
  explicitly. The broad pattern `mono_linux_*` would pick `arm32`, the shortest
  name. `rename_exe` must use the table form keyed on the editor binary,
  because the string form falls back to "the first executable", which could be
  a DLL.

### 3. mise `github` backend installs the .NET build (OQ-1)

- **Details**: The options that matter are `asset_pattern`, a Tera template
  with `{{ version }}` and `{{ arch(x64=..., arm64=...) }}` that names the
  asset; automatic stripping of a single top-level directory; `rename_exe` as a
  table `{ "<glob>" = "<name>" }`; and PATH rule 3, under which the install
  directory goes on `PATH` when it directly contains an executable. The
  download is checked against the digest GitHub reports. Verified install
  (isolated `MISE_DATA_DIR`, mise 2026.10.25):

  ```toml
  [tool_alias]
  godot = "github:godotengine/godot"

  [tools]
  godot = { version = "4.7.2-stable", asset_pattern = 'Godot_v{{ version }}_mono_linux_{{ arch(x64="x86_64", arm64="arm64") }}.zip', rename_exe = { "Godot_v*_mono_linux.*" = "godot" } }
  ```

  Result: `installs/godot/4.7.2-stable/{godot, GodotSharp/}`, a `godot` shim,
  and `godot --headless --version` printing `4.7.2.stable.mono.official.ed1daf0bf`
  through both `mise exec` and the shim directory. Godot finds `GodotSharp/`
  next to the real executable, and the shim execs the real path.
- **Source**: https://mise.jdx.dev/dev-tools/backends/github.html (sections
  `asset_pattern`, `strip_components`, `bin_path`, `rename_exe`, Templates,
  Verification); https://mise.jdx.dev/dev-tools/aliases.html.
- **Relevance**: This resolves OQ-1. Both runtimes live in `mise.toml`, and
  `plugin_dockerfile` stays OS-packages-only.
- **Observed side note**: headless `godot --version` printed
  `libfontconfig.so.1: cannot open shared object file` on a host without
  fontconfig, so even headless runs need `libfontconfig1`.

### 4. `.NET` version support (OQ-2)

- **Details**: Godot docs (4.7 branch, `c_sharp_basics.rst`): "Godot 4.5
  requires .NET 8 or later, but exporting to Android requires .NET 9 or later."
  The master branch says "Godot 4.8 requires .NET 10 or later". In the 4.7.2
  source, `GodotSharp.csproj` and `GodotTools.csproj` target `net8.0`, and
  `GodotPlugins.csproj` sets `<RollForward>LatestMajor</RollForward>`.
  Microsoft's release index: 10.0 `lts` / `active` (latest SDK `10.0.403`,
  EOL 2028-11-14); 8.0 `lts` / `maintenance` (EOL 2026-11-10); 9.0 `sts`
  (EOL 2026-11-10); 11.0 `go-live` (RC). `mise ls-remote dotnet` lists
  `10.0.403`. mise's core `dotnet` plugin installs SDKs into a shared
  `DOTNET_ROOT` (default `~/.local/share/mise/dotnet-root`) and exports
  `DOTNET_ROOT` and `DOTNET_MULTILEVEL_LOOKUP=0`.
- **Source**: https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/c_sharp/c_sharp_basics.rst ;
  `modules/mono/glue/GodotSharp/*/*.csproj` at tag `4.7.2-stable`;
  https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json ;
  https://mise.jdx.dev/lang/dotnet.html.
- **Relevance**: Pin `dotnet = "10.0.403"`. It satisfies 4.7 (≥ 8), already
  satisfies 4.8 (≥ 10), and remains supported for two years.

### 5. How Godot's editor finds .NET

- **Details**: `modules/mono/editor/hostfxr_resolver.cpp::try_get_path` checks
  `DOTNET_ROOT[_<arch>]`, then the self-registered directory, then
  `/usr/local/share/dotnet` and `/usr/share/dotnet`.
  `mono_gd/gd_mono.cpp::find_hostfxr` then falls back to running
  `dotnet --list-sdks` from `PATH` and derives the root from the newest SDK
  path. mise's dotnet `exec_env` sets `DOTNET_ROOT`.
- **Source**: Godot source at `4.7.2-stable`; `src/plugins/core/dotnet.rs` in
  jdx/mise.
- **Relevance**: The flavor needs no `DOTNET_ROOT` entry in `[env]`. In an
  activated shell `DOTNET_ROOT` is exported. Through shims or an editor
  extension, the `PATH` fallback still finds the real SDK.

### 6. gdtoolkit through the mise `pypi` backend (FR-3)

- **Details**: `pypi:` (alias `pipx:`) installs a PyPI application with
  `uv tool install`, or with pipx when uv is absent. It needs uv or pipx;
  "When `uv`, `pipx` or `python` is in your config, mise installs it before
  your Python tools." The per-tool `python` option makes mise install that
  CPython "as a private dependency of the tool; it does not add Python to the
  shell's active tools". gdtoolkit's latest release is 4.5.0
  (`requires_python >=3.7`). It installs `gdformat`, `gdlint`, `gdparse`,
  `gdradon` and `gd2py`. Verified: with only `uv = "0.13.6"` in `[tools]`,
  `gdtoolkit = { version = "4.5.0", python = "3.12" }` installed into a venv
  whose `home` is mise's `installs/python/3.12/bin`. `gdformat --version` and
  `gdlint --version` printed `4.5.0` through the shims, and no `python` tool
  became active. Without the option, uv downloaded CPython 3.15.2 into
  `~/.local/share/uv/python` and built PyYAML from source.
- **Source**: https://mise.jdx.dev/dev-tools/backends/pypi.html (Requirements,
  Choosing Python); https://pypi.org/pypi/gdtoolkit/json.
- **Relevance**: FR-3 and the Constraint: gdtoolkit does not depend on the
  python flavor. The python option avoids an unpinned interpreter and source
  builds. One caveat: mise still creates a `python` shim, which errors with
  "not active" instead of "command not found" in a godot-only project.

### 7. gdtoolkit configuration

- **Details**: `gdlint` reads `gdlintrc` / `.gdlintrc` from the working
  directory or its parents, and `gdlint --dump-default-config` writes the
  defaults (4.5.0: `max-line-length: 100`, `tab-characters: 1`,
  `excluded_directories: !!set {.git: null}`, the naming regexes, and
  `class-definitions-order`). `gdformat` is not configurable beyond line
  length and spaces/tabs, and it formats stdin with `gdformat -` (verified:
  tab-indented output).
- **Source**: `gdlint --dump-default-config`, `gdformat --help` (gdtoolkit 4.5.0).
- **Relevance**: The distributed `gdlintrc` is the 4.5.0 dump with `.godot`
  and `addons` added to `excluded_directories`. `gdformat` cannot exclude
  directories, so CI excludes them when it lists files.

### 8. C# formatter choice (OQ-3)

| Criterion | `dotnet format` | CSharpier |
| --- | --- | --- |
| Install | Part of the .NET SDK (since 6) | .NET global/local tool; no mise registry entry, so a `dotnet:csharpier` alias entry would be needed |
| Configuration | `.editorconfig` (whitespace, style, analyzers) | Its own options; reads only a few `.editorconfig` keys |
| Single file without a project | `dotnet format whitespace <folder> --folder --include <file>` | `csharpier format <file>` |
| Speed in a hook | ~1–2 s startup (whitespace pass, no project load) | Faster |
| Godot-generated C# | Neutral | Rewrites layout opinionatedly |

- **Source**: https://learn.microsoft.com/dotnet/core/tools/dotnet-format ;
  https://github.com/belav/csharpier (latest 1.2.6).
- **Relevance**: Choose `dotnet format`. It needs no extra tool, and the
  module `.editorconfig` (FR-12) becomes the single source of C# layout.

### 9. WSLg in containers (FR-8)

- **Details**: X11 needs the `/tmp/.X11-unix` mount and `DISPLAY`. Wayland
  needs the `/mnt/wslg` mount, `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`.
  PulseAudio needs `/mnt/wslg` and `PULSE_SERVER`. The vGPU needs the device
  `/dev/dxg`, the mount `/usr/lib/wsl`, and `LD_LIBRARY_PATH=/usr/lib/wsl/lib`.
  WSLg's fixed values are `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`,
  `XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir` and
  `PULSE_SERVER=unix:/mnt/wslg/PulseServer`. With systemd enabled, the
  distro's own `XDG_RUNTIME_DIR` is `/run/user/<uid>`, which does not exist in
  the container, so the overlay must not forward the host value. Docker
  refuses to start a container whose `devices` entry is missing on the host,
  which is why the overlay must be opt-in.
- **Source**: https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md ;
  https://docs.docker.com/reference/compose-file/merge/ (sequence merge of
  `volumes` / `devices` by target path, mapping merge of `environment`).
- **Relevance**: This sets the overlay content and justifies activating it
  through Compose's own multi-file merge. The paths were verified only for
  Docker Engine running inside the WSL2 distro. Docker Desktop exposes WSLg
  under other paths, so the overlay makes the source paths overridable.

### 10. Debian trixie runtime libraries (FR-7)

- **Details**: All exist in trixie: `libx11-6`, `libxcursor1`, `libxext6`,
  `libxi6`, `libxinerama1`, `libxrandr2`, `libxrender1`, `libwayland-client0`,
  `libwayland-cursor0`, `libwayland-egl1`, `libxkbcommon0`, `libdecor-0-0`,
  `libgl1`, `libegl1`, `libglx-mesa0`, `libgl1-mesa-dri` (contains
  `dri/d3d12_dri.so` on amd64 and arm64), `libvulkan1`, `mesa-vulkan-drivers`
  (contains lavapipe, intel, radeon, nouveau, virtio and gfxstream, but **no
  `dzn`**), `libasound2t64`, `libpulse0`, `libfontconfig1`, `libudev1`,
  `libdbus-1-3`, `libicu76`, `libssl3t64`. Mesa is 25.0.7-2+deb13u1.
- **Source**: https://packages.debian.org/trixie/ (package pages and amd64 /
  arm64 file lists).
- **Relevance**: This is the `godot` OS-package block. `libicu76` and
  `libssl3t64` are .NET SDK prerequisites. Without ICU, `dotnet` aborts unless
  invariant globalization is forced.

### 11. Editor integrations (FR-6)

- **Details**: The VS Code `geequlim.godot-tools` extension (2.7.1) has the
  settings `godotTools.editorPath.godot4` and `godotTools.lsp.headless`. The
  latter starts a headless Godot language server when no editor is running.
  The Zed `gdscript` extension (0.9.0, grndctrl/zed-gdscript) defines the
  language `GDScript`, connects to Godot's LSP on 127.0.0.1:6005, and needs
  `nc` or `ncat` on `PATH`. The Zed `csharp` extension is 1.2.2.
- **Source**: godotengine/godot-vscode-plugin `package.json`;
  zed-industries/extensions `extensions.toml`; `api.zed.dev/extensions`;
  grndctrl/zed-gdscript README and `languages/gdscript/config.toml`.
- **Relevance**: The OS block adds `netcat-openbsd`. The VS Code overlay sets
  the editor path to the `godot` shim and enables the headless LSP. The Zed
  overlay lists `gdscript` and `csharp`.

### 12. CI building blocks (FR-9)

- **Details**: `jdx/mise-action`: v2 and v3 declare `runs.using: node20`, and
  **v4 is the first `node24` major** (latest release v5.2.6). It installs the
  tools from `mise.toml` (`install_args` narrows them), adds shims to `PATH`,
  exports the mise env (`env: true`), and passes `github.token` to mise.
  Godot CLI: `--headless`, `--path`, `--import`,
  `--export-release <preset> <path>` (implies `--import`, needs export
  templates), and `-s <script>`. GUT runs as
  `godot --headless --path <dir> -s addons/gut/gut_cmdln.gd -gexit`. Export
  templates install to
  `~/.local/share/godot/export_templates/<version>.mono/`, where `<version>`
  is the `--version` output without the `.official.<hash>` suffix.
- **Source**: jdx/mise-action `action.yml` at v2/v3/v4 and its releases;
  https://github.com/godotengine/godot-docs/blob/4.7/tutorials/editor/command_line_tutorial.rst.
- **Relevance**: The repository's #267 rule ("earliest Node-24 major") applies,
  so pin `jdx/mise-action@v4`, `actions/checkout@v5` and `actions/cache@v5`.

## Comparison: how to install Godot .NET (OQ-1)

| Option | Gets `_mono_` build | Version source | Verification | Verdict |
| --- | --- | --- | --- | --- |
| `godot = "4.7.2-stable"` (aqua shorthand) | No | mise.toml | SHA512-SUMS | Rejected |
| `github:` backend + `asset_pattern` + `rename_exe`, aliased to `godot` | Yes (verified) | mise.toml | GitHub asset digest | **Chosen** |
| `ubi:` backend | Possible | mise.toml | Weaker | Rejected: deprecated since mise 2026.4.0, removed in 2027.1.0 (`docs/dev-tools/backends/ubi.md`) |
| `plugin_dockerfile` curl + unzip, keep only `dotnet` in mise | Yes | Dockerfile ARG (second place) | Manual sha512 | Rejected: splits runtime pins across two files and breaks the #325 contract (`plugin_dockerfile` is OS packages only) |

## Recommendations

1. Declare `tool_alias.godot = "github:godotengine/godot"` and the `tools.godot`
   inline table above, pinned to `4.7.2-stable`.
2. Declare `tools.dotnet = "10.0.403"`. Do not add `DOTNET_ROOT` to `[env]`.
3. Declare `tools.uv` (same pin as the python flavor),
   `tool_alias.gdtoolkit = "pypi:gdtoolkit"` and
   `tools.gdtoolkit = { version = "4.5.0", python = "3.12" }`.
4. Use `dotnet format whitespace` for the `*.cs` hook.
5. Install the libraries in finding 10, plus `netcat-openbsd` and `unzip`, in a
   `godot` OS-package block.
6. Make the WSLg overlay a separate Compose file that is activated by listing
   it in `dockerComposeFile`. Document that GPU acceleration on WSLg means the
   Compatibility renderer.

## Sources

- https://raw.githubusercontent.com/aquaproj/aqua-registry/main/pkgs/godotengine/godot/registry.yaml
- https://github.com/godotengine/godot/releases/tag/4.7.2-stable
- https://mise.jdx.dev/dev-tools/backends/github.html
- https://mise.jdx.dev/dev-tools/backends/pypi.html
- https://mise.jdx.dev/dev-tools/aliases.html
- https://mise.jdx.dev/lang/dotnet.html
- https://github.com/godotengine/godot-docs/blob/4.7/tutorials/scripting/c_sharp/c_sharp_basics.rst
- https://github.com/godotengine/godot-docs/blob/4.7/tutorials/editor/command_line_tutorial.rst
- https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json
- https://github.com/microsoft/wslg/blob/main/samples/container/Containers.md
- https://docs.docker.com/reference/compose-file/merge/
- https://packages.debian.org/trixie/mesa-vulkan-drivers
- https://packages.debian.org/trixie/libgl1-mesa-dri
- https://pypi.org/project/gdtoolkit/
- https://learn.microsoft.com/dotnet/core/tools/dotnet-format
- https://github.com/godotengine/godot-vscode-plugin
- https://github.com/grndctrl/zed-gdscript
- https://github.com/jdx/mise-action
