# Workflow: #331 Add Godot (GDScript + C#) language flavor with WSLg GUI overlay and headless CI

Each step should leave `bats tests/` green before the next starts.
`scripts/verify-mirrors.sh` must stay green throughout. This issue adds no
mirrored asset (D23), so any mirror diff is a regression.

## Implementation Steps

### Step 1: `common.sh` extensions
- **Action**:
  - Add `tool_alias` to `mise_toml_ensure`'s allowed sections.
  - Extract its presence predicate and add `mise_toml_has_key` (contract in
    `api-spec.md`).
  - Add `docker-compose.godot-gui.yml` to `replace_placeholders`' file list.
  - Add `godot` to `show_interactive_mode_error`'s `--lang` line.
- **Files**: `scripts/lib/common.sh`, `tests/common_mise.bats`
- **Depends on**: —
- **Done when**:
  - The existing `common_mise.bats` cases pass unchanged, which proves
    `mise_toml_ensure` output is byte-identical.
  - New cases pass: `tool_alias` accepted; `mise_toml_has_key` returns 0 for
    the bare, `"quoted"`, `'quoted'`, `[tools.godot]` and top-level
    `tools.godot =` forms; it returns 1 for an absent key, the same key in
    another section, a commented-out entry and a missing file; it returns 2
    for a bad section or key; and it never creates the file.

### Step 2: Flavor assets (static files)
- **Action**: Create `templates/languages/godot/` with:
  - `docker-compose.godot-gui.yml`
  - `gdlintrc`: regenerate with the pinned gdtoolkit
    (`gdlint --dump-default-config`), then add `.godot` and `addons` to
    `excluded_directories`.
  - `.editorconfig`
  - `.claude/settings.json`
  - `.claude/rules/godot.md` (outline in design.md)
  - `.devcontainer/devcontainer.json`
  - `.zed/devcontainer.json` and `.zed/settings.json`

  Content is given in design.md "Type Definitions".
- **Files**: the files listed above
- **Depends on**: —
- **Done when**:
  - The JSON files pass `jq empty`.
  - The overlay passes `docker compose -f <core compose rendered> -f <overlay rendered> config`,
    and that output shows the base volumes kept plus the three WSLg mounts,
    the device, and the five env keys.
  - The hook commands, run by hand on a sample `.gd` / `.cs` file inside a
    built image, format the file. Verify the exact
    `dotnet format whitespace . --folder --include <file>` invocation here;
    if the SDK's CLI rejects it, adjust and record the change in the PR.

### Step 3: Workflow template
- **Action**: Write `.github/workflows/godot-quality-check.yml` (job matrix
  and version derivation in design.md / api-spec.md):
  - pins `actions/checkout@v5`, `actions/cache@v5`, `jdx/mise-action@v4`
  - a detection step before mise in every job
  - the `::notice::` skips
  - the GUT default `-gdir=res://test,res://tests -ginclude_subdirs` when
    there is no `.gutconfig.json`, passing only the directories that exist
  - SHA-512 verification of the export templates
- **Files**: `templates/languages/godot/.github/workflows/godot-quality-check.yml`
- **Depends on**: Step 2
- **Done when**:
  - `actionlint` (if available) and a YAML parse succeed.
  - A throwaway GitHub repository (or `act`), scaffolded with
    `--lang godot -y`, shows all three jobs green with notices when there is
    no project.
  - The same repository with a minimal project (`project.godot`, one `.gd`
    file, GUT copied into `addons/gut`, a `test/test_smoke.gd`, a Linux
    export preset with `export_path`, and a C# script with `.csproj`) passes
    lint, build, GUT and export. A failing GUT test fails the job.

### Step 4: `plugin.sh`
- **Action**: Implement every function in api-spec.md, modelled on
  `languages/rust/plugin.sh`:
  - header comment describing the shared/module split
  - private `_godot_*` helpers
  - the non-prompting `_godot_resolve_gui_choice` (steps 1–3), called both
    from `plugin_interactive_setup` (which adds only the step-4 prompt) and
    from `plugin_post_copy_shared` whenever `GODOT_GUI_ENABLED` is empty;
    `GODOT_GUI_ENABLED=""` reset at source time (design.md "GUI choice
    resolution")
- **Files**: `templates/languages/godot/plugin.sh` (mode 644)
- **Depends on**: Steps 1–3
- **Done when**:
  - `bash -n` passes, and shellcheck is clean if installed.
  - It follows `.claude/rules/shell.md`: 4 spaces, quoted expansions,
    `[[ ]]`, `local`, `print_*`.
  - Step 6 tests pass.

### Step 5: `setup.sh` integration
- **Action**:
  - `AVAILABLE_LANGUAGES` + `LANGUAGE_DISPLAY_NAMES`
  - help text: the language line, the `GODOT_GUI` note and the examples
  - `infer_scaffold_options` godot probe (D21)
- **Files**: `setup.sh`
- **Depends on**: Step 4
- **Done when**:
  - `./setup.sh --help` lists godot.
  - `./setup.sh demo --lang godot -y` in an empty git repo produces the files
    in api-spec.md "Generated files", a `mise.toml` with the entries in
    design.md, the `godot` Dockerfile block, the `post.sh` block before any
    Codex / plugin block (also with `--codex`), and the gitignore block.
  - It produces no `project.godot`, `export_presets.cfg` or `addons/`, and
    `dockerComposeFile` is unchanged.

### Step 6: Tests
- **Action**: See "Test Strategy".
- **Files**: `tests/setup_language_selection.bats`,
  `tests/plugin_idempotency.bats`, `tests/common_mise.bats` (Step 1),
  `tests/godot_plugin.bats` (new), `tests/setup_mise_scaffold.bats`
- **Depends on**: Steps 1–5
- **Done when**: `bats tests/` is green.

### Step 7: Container-level acceptance
- **Action**:
  - Add the `godot` leg to `.github/workflows/scaffold-build.yml`
    (`args: "--lang godot"`, `tools: "godot dotnet gdformat gdlint"`).
  - Extend `scripts/ci/smoke-runtimes.sh`:
    - `godot`: `godot --headless --version` contains `mise current godot`
      with `-` replaced by `.`, plus `.mono`.
    - `dotnet`: `dotnet --version` equals `mise current dotnet`.
    - `gdformat` / `gdlint`: `--version` contains `mise current gdtoolkit`.
    - All are checked under both `bash -c` and `bash -ic`.
- **Files**: `.github/workflows/scaffold-build.yml`, `scripts/ci/smoke-runtimes.sh`
- **Depends on**: Step 5
- **Done when**:
  - A local `docker build` of the godot scaffold succeeds on amd64, and
    `smoke-runtimes.sh godot dotnet gdformat gdlint` passes in it (FR-8 and
    NFR-4 acceptance on a non-WSLg host).
  - The C# path also works: inside the container,
    `godot --headless --path <tmp project with a .csproj> --build-solutions --quit`
    (or `dotnet build`) succeeds, which shows that Godot finds .NET through
    the mise shims.
  - Attempt arm64 once (`buildx --platform linux/arm64`) to exercise the
    `arch(arm64="arm64")` asset mapping.

### Step 8: Manual WSLg verification
- **Action**:
  - On Windows 11 + WSL2, with Docker Engine inside the distro, scaffold
    `--lang godot` interactively and accept the GUI prompt. The default
    should be `y`.
  - Reopen in the container and run `godot -e` (the editor window appears)
    and `godot -e --rendering-driver opengl3`.
  - `glxinfo -B` from `mesa-utils`, installed ad hoc, should report D3D12.
  - Check audio through PulseAudio if possible.
  - Remove the `dockerComposeFile` entry and rebuild: the container should
    start headless.
- **Files**: none (record results in the PR description)
- **Depends on**: Step 7
- **Done when**: Both modes behave as documented. Docker Desktop is optional;
  record what was or was not verified.

### Step 9: NFR-3 byte-identity check
- **Action**: For each existing flavor set:
  - `core`
  - `--lang rust|python|node|deno|latex|go` (each alone)
  - `--lang python --postgresql`, `--redis`, `--mysql`, `--celery`
  - `--zed --lang rust`
  - `--monorepo --module a:python --module b:node`
  - `--codex --lang go`

  scaffold into two temp repos, one with `develop`'s `setup.sh` (a
  `git worktree` of `origin/develop`) and one with this branch, using the
  same project name and `-y`. Then `diff -r` the trees, excluding
  `.tarnished-manifest.json` timestamps and commit fields.
- **Files**: none (a throwaway script in the scratchpad; paste the summary
  into the PR)
- **Depends on**: Step 5
- **Done when**: There are no diffs other than manifest metadata.

### Step 10: Documentation
- **Action**: The README, `docs/setup.md` and `AGENTS.md` edits in
  design.md "Documentation (NFR-5)".
- **Files**: `README.md`, `docs/setup.md`, `AGENTS.md`
- **Depends on**: Steps 5, 7, 8
- **Done when**: The docs name the flavor, the WSLg opt-in (prompt,
  `GODOT_GUI`, manual entry, and how to turn it off), the export-template
  re-download after a Godot bump, the Compatibility-renderer GPU note and CI
  skip behavior. The `mise.toml` runtime table lists godot, dotnet and
  gdtoolkit.

## Dependency Graph

```
1 ──┐
2 ──┼─> 4 ──> 5 ──┬─> 6
3 ──┘             ├─> 7 ──> 8 ──┐
                  ├─> 9         ├─> 10
                  └─────────────┘
```

Steps 1, 2 and 3 are independent. Step 3 only needs Step 2's file layout.

## Test Strategy

### `tests/setup_language_selection.bats`
- `AVAILABLE_LANGUAGES` declared in `setup.sh` contains `godot` (source the
  `declare -a AVAILABLE_LANGUAGES=` line from `setup.sh`, not the local
  fixture).
- `LANGUAGE_DISPLAY_NAMES[godot]` is set in `setup.sh`.
- `validate_language godot` (the `setup.sh` helper at "Verify a language id
  is one of AVAILABLE_LANGUAGES") succeeds.
- `templates/languages/godot/plugin.sh` exists, and sourced in isolation it
  defines `plugin_name` (prints `godot`), `plugin_description`, `plugin_copy`,
  `plugin_dockerfile`, `plugin_post_copy_shared`, `plugin_post_copy_module`
  and `plugin_post_copy`. This is the FR-1 contract check.
- Leave the existing local fixture tests unchanged, so their numbering
  assertions stay valid.

### `tests/common_mise.bats` (Step 1)
- The `tool_alias` section is created and appended to, and an existing
  `tool_alias` key is kept.
- The full `mise_toml_has_key` matrix (Step 1 "Done when").

### `tests/plugin_idempotency.bats`
- `post_copy idempotent: languages/godot`: two runs give byte-identical
  trees (the existing harness).
- `post_copy idempotent with ZED_ENABLED: languages/godot`.
- `mise.toml idempotent: languages/godot`: a second run leaves the file
  byte-identical, and each key appears exactly once.
- `mise.toml: godot never overwrites a developer-changed entry`. Seed
  `godot = "4.6.3-stable"` and `dotnet = "8.0.427"`. After the run both are
  byte-identical, and there is **no** `[tool_alias] godot` (D5). gdtoolkit
  and its alias are still added.
- `mise.toml: godot keeps a developer tool_alias`. Seed only
  `[tool_alias] godot = "aqua:godotengine/godot"`. The alias is kept and
  `tools.godot` is added.
- `mise.toml: godot + python share uv` (either order). There is one `uv`
  line, and python's `python = "3.12"` is untouched.
- `plugin_dockerfile idempotent: languages/godot`. The block is inserted
  once, above `SHELL`, and contains every package in design.md.
- `post_copy idempotent in monorepo mode: godot module`. Root assets are
  written once; `gdlintrc` and `.editorconfig` appear in the module dir and
  not at the root.

### `tests/godot_plugin.bats` (new)
- **FR-11**: after `plugin_copy` + `plugin_post_copy`, there is no
  `project.godot`, `export_presets.cfg` or `addons/` anywhere in the target.
- **Pre-existing files**: a pre-existing `gdlintrc`, `.editorconfig`,
  `docker-compose.godot-gui.yml` or `.claude/rules/godot.md` is kept when the
  copy prompt is declined, using the non-TTY default.
- **Workflow prompt (#265 pattern)**: a pre-existing
  `godot-quality-check.yml` is kept in non-TTY mode, and the overlay file is
  still copied. This is the independence of the two copies.
- **gitignore**:
  - Appended once.
  - User lines before and after it survive a second run.
  - The marker is matched by the exact line.
  - A `.gitignore` without a trailing newline gets one before the block.
- **Hooks**: after merging into the claude template's `settings.json`,
  `PostToolUse` has the `Write|Edit` entry with four handlers whose `if`
  values are `Write(*.gd)`, `Edit(*.gd)`, `Write(*.cs)` and `Edit(*.cs)`. A
  second merge adds nothing (`unique`).
- **`post.sh` order**: with a `post.sh` that already contains
  `# Codex CLI Setup` and `# Claude Code Plugin Setup`, the
  `# Godot Engine Setup` block lands before both. Without them it is
  appended. A second run is a no-op.
- **`post.sh` safety**: the block runs under `bash -e` with a stub `godot`
  that fails, with no `godot` at all, and with no `dotnet`. All three exit 0
  and print the expected `[WARN]` or info lines.
- **GUI choice resolution** (`setup.sh` calls `plugin_interactive_setup`
  only on a TTY, so the non-TTY cases must go through `plugin_post_copy`
  alone, exactly as `execute_plugin_post_copies` does without a TTY):
  - **non-TTY + `GODOT_GUI=true`**: calling only `plugin_copy` +
    `plugin_post_copy` (no `plugin_interactive_setup`) enables the overlay.
    `dockerComposeFile` gains the entry. Repeat with `SKIP_CONFIRM=true`,
    which must give the same result.
  - **non-TTY + `GODOT_GUI` unset**: same calls; the entry is not added and
    no prompt is attempted (`/dev/tty` never read).
  - **TTY + `-y` (`SKIP_CONFIRM=true`) + `GODOT_GUI` unset**, with a TTY
    stub (`check_tty_available` → 0) and a `confirm` stub that fails the
    test if called: run `plugin_interactive_setup` then `plugin_post_copy`.
    No prompt, and the entry is not added.
  - **TTY, no `-y`, `GODOT_GUI` unset**: with a `confirm` stub answering
    `y`, the prompt is shown once and the entry is added. With `n`, it is
    not added.
  - **End-to-end non-TTY**: `GODOT_GUI=true ./setup.sh demo --lang godot -y
    < /dev/null` in a temp git repo produces the entry
    (`tests/setup_mise_scaffold.bats`).
  - **Overlay already listed + `GODOT_GUI` unset, TTY stub**: no prompt, and
    the result is enabled (no duplicate).
  - **Reset**: re-sourcing `plugin.sh` empties `GODOT_GUI_ENABLED`, so a
    value set by an earlier test does not leak.
- **GUI disabled** (default, `GODOT_GUI` unset, non-TTY):
  `devcontainer.json` `dockerComposeFile` is unchanged and the overlay file
  exists.
- **GUI enabled** (`GODOT_GUI=true`, non-TTY, through `plugin_post_copy`):
  - `dockerComposeFile` becomes
    `["../docker-compose.yml","../docker-compose.godot-gui.yml"]` (order
    kept).
  - A second run adds no duplicate.
  - A string-valued `dockerComposeFile` is normalized.
  - With the overlay file absent there is a warning and no entry.
  - A `devcontainer.json` with comments gives a warning, and the file is
    byte-identical afterwards.
- **`GODOT_GUI=false`** with a TTY stub: no prompt and no entry.
- **Staging**: `UPGRADE_MODE=true` gives no prompt, even with a TTY stub.
- **Placeholders**: after `replace_placeholders`, the overlay's service key
  equals the project name and no `{{` remains.
- **`--add-module <name> --lang godot`** against a monorepo fixture: the
  module files are created and the root assets are unchanged (byte-compare
  before and after).
- **`infer_scaffold_options`**: in single mode a tree with `gdlintrc`
  reports `"godot"` in `languages`.

### `tests/setup_mise_scaffold.bats`
- `setup.sh --lang godot -y` (end-to-end, in a temp git repo): `mise.toml`
  holds the godot, dotnet, uv and gdtoolkit tool entries, both aliases and
  both env entries. `docker/Dockerfile.dev` has the `godot` block above
  `SHELL`. No `features` key appears anywhere.
- `GODOT_GUI=true ./setup.sh --lang godot -y < /dev/null` (no TTY, so
  `plugin_interactive_setup` never runs): `devcontainer.json`
  `dockerComposeFile` ends with `"../docker-compose.godot-gui.yml"`. The same
  run without `GODOT_GUI` leaves `dockerComposeFile` as
  `["../docker-compose.yml"]`.

### Container / CI (Step 7)
- The `scaffold-build.yml` `godot` leg: static assertions (no `features`),
  `docker build`, then `smoke-runtimes.sh godot dotnet gdformat gdlint`
  under `bash -c` and `bash -ic`.

### Manual (Step 8)
- WSLg GUI on and off, the GPU renderer note, and audio.

## Notes for the executor

- Re-check the pins at implementation time: the latest 4.7.x stable, the
  latest 10.0.x SDK, gdtoolkit and the python flavor's uv literal. Update
  design.md only if a pin changes the design; otherwise record the new
  values in the PR description.
- Do not add a `setup.sh` flag (D9), and do not touch
  `merge_docker_compose_services` (D8).
- The executor must not commit artifacts outside the issue scope. Mirrors
  are unaffected.
