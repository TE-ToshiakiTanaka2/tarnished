# Workflow: #323 feat: optional Zed editor support in the generator and this repository's devcontainer

Implementation order, dependencies and the test plan. Exact signatures, jq
programs and file contents are in [api-spec.md](./api-spec.md); the decisions
behind them are in [design.md](./design.md).

## Dependency graph

```
Step 1 (common.sh merge helpers)
   ├──> Step 2 (template .zed/ assets)
   │       └──> Step 3 (plugin call sites)
   │               └──> Step 5 (setup.sh wiring: needs assets to exist to be observable)
   └──> Step 4 (manifest.sh + provenance)
Step 6 (docs)            — independent, but needs Step 5's final flag/prompt strings
Step 7 (repo dogfooding) — needs Steps 1-3 to know what the generator produces
Step 8 (tests)           — written alongside each step; gate for the whole issue
```

Steps 1-5 must land together to be coherent, but each is independently
verifiable with the tests named below.

## Step 1 — `scripts/lib/common.sh` merge layer

1. Replace the jq program inside `merge_devcontainer_json` with the
   presence-gated version (api-spec :: "merge_devcontainer_json (modified)").
   Signature, JSONC normalization, temp handling and all failure paths stay as
   they are.
2. Add `merge_zed_settings` immediately after `merge_claude_settings_hooks`,
   following that family's style: `print_error` + `return 1` on missing base,
   `cp` when the overlay is absent, `_jsonc_to_json_file` normalization for
   both inputs, strict-JSON output, temp cleanup on every failure path.
3. Add `apply_zed_assets` after `merge_zed_settings`. It is the only function
   in the repository that reads `ZED_ENABLED`, and it reads it as
   `${ZED_ENABLED:-false}`.

Conventions to honor (`.claude/rules/shell.md`, `AGENTS.md` §2): 4-space
indent, `local` for every variable, quoted expansions, `[[ ]]`, comment header
per function, `print_*` instead of `echo`.

**Verify**: `tests/common_json.bats`, `tests/common_zed.bats` (both below),
plus `bash -n scripts/lib/common.sh` and shellcheck if available.

## Step 2 — Template `.zed/` assets

Create, with the exact contents in api-spec :: "Input/Output Schemas":

```
templates/core/.zed/devcontainer.json
templates/core/.zed/settings.json
templates/languages/rust/.zed/{devcontainer.json,settings.json}
templates/languages/python/.zed/{devcontainer.json,settings.json}
templates/languages/node/.zed/{devcontainer.json,settings.json}
templates/languages/deno/.zed/{devcontainer.json,settings.json}
templates/languages/go/.zed/settings.json          # no extensions — see research.md
templates/languages/latex/.zed/{devcontainer.json,settings.json}
templates/services/postgresql/.zed/devcontainer.json
templates/services/mysql/.zed/devcontainer.json
```

`templates/services/redis/` gets **no** `.zed/` directory (no verified
extension, and its VS Code overlay ships none either).

File modes 644, consistent with the `plugin.sh` normalization from #301.

**Do not** add any extension ID that is not in
[research.md](./research.md) §2. Re-verify before merging, both ways:

```bash
curl -fsSL https://raw.githubusercontent.com/zed-industries/extensions/main/extensions.toml | grep -n '^\[\(dockerfile\|toml\|biome\|deno\|latex\|sql\)\]$'
curl -fsSL 'https://api.zed.dev/extensions?filter=dockerfile'
```

**Verify**: every new JSON file parses — `for f in $(git ls-files -o --exclude-standard 'templates/**/.zed/*.json'); do jq empty "$f"; done`.

## Step 3 — Plugin call sites

Add one line to each plugin, at the position in api-spec :: "Plugin call
sites":

```bash
    # Zed editor assets (no-op unless --zed was selected)
    apply_zed_assets "$target_dir" "$PLUGIN_DIR"
```

- `templates/core/plugin.sh::plugin_post_copy`
- `templates/languages/{rust,python,node,deno,go,latex}/plugin.sh::plugin_post_copy_shared`
  — **immediately after the existing `merge_devcontainer_json` block**, because
  all six functions can `return` early from their `post.sh` marker branch.
- `templates/services/{postgresql,mysql,redis}/plugin.sh::plugin_post_copy`
  — after the existing `merge_devcontainer_json` block (postgresql/mysql) or
  after the devcontainer merge (redis), where it is a documented no-op.

No plugin gains a conditional, a new function, or a file outside
`templates/<flavor>/.zed/`. The four-function interface is unchanged.

**Verify**: `tests/plugin_idempotency.bats` (existing tests must stay green
with `ZED_ENABLED` unset, new variants green with it set).

## Step 4 — Provenance

1. `scripts/lib/manifest.sh::manifest_options_valid`: add `"zed_enabled"` to
   the boolean key list.
2. `setup.sh::infer_scaffold_options`: derive `zed=false` /
   `[[ -f "$target_dir/.zed/settings.json" ]] && zed=true`, pass
   `--argjson zed "$zed"`, emit `zed_enabled: $zed`.
3. `setup.sh::populate_setup_state_from_manifest`: add `ZED_ENABLED=false` to
   the reset block and read `.scaffold_options.zed_enabled // false`.

**Verify**: `tests/setup_zed.bats` provenance cases; existing
`tests/manifest.bats`, `tests/setup_create_manifest.bats` and
`tests/setup_upgrade.bats` must stay green (a pre-#323 manifest with no
`zed_enabled` key still validates).

## Step 5 — `setup.sh` CLI and UX

In file order:

1. `ZED_ENABLED=false` in the feature-flag block, directly after
   `CODEX_ENABLED=false`.
2. `show_help`: `--zed` option line after `--codex`, and the example line.
3. `parse_arguments`: `--zed` case after `--codex`.
4. `scaffold_flags_supplied`: add `|| "$ZED_ENABLED" == true`.
5. Interactive prompt in the TTY block, after the auto-tag prompt.
6. Add-module warning + reset, after the `--codex` warning.
7. `Zed:` line in the Setup Configuration summary, after `Codex CLI:`.
8. Zed block in the "Next steps" completion output.

All strings verbatim from api-spec :: "CLI surface".

**Verify**: `tests/setup_zed.bats` CLI cases; `bash -n setup.sh`.

## Step 6 — Documentation

1. `AGENTS.md` §4 ("Template directory contract"): add `.zed/` to the
   permitted subdirectories, with the note that it is **not** copied verbatim
   — `devcontainer.json` inside it is a merge overlay and only `settings.json`
   is installed, by `apply_zed_assets`.
2. `README.md` → "First-time setup": one sentence that the generated project
   can be opened in VS Code or, with `--zed`, in Zed's dev container mode,
   linking to `docs/setup.md`.
3. `docs/setup.md`: a new `## Zed editor support` section covering
   - `--zed` (and the interactive prompt) and what it adds:
     `customizations.zed.extensions`, `.zed/settings.json`, per-language
     LSP/formatter settings; `customizations.vscode` is always kept;
   - how to open: `zed .` then the "Open in Container" prompt, or
     "Project: Open Remote" from the command palette;
   - prerequisites: Docker or Podman on `PATH` (`"use_podman": true` for
     Podman);
   - caveats, each as its own bullet: **no automatic rebuild** after editing
     `devcontainer.json` (stop the container and reopen); **do not run VS Code
     and Zed on the same project at once** (the two derive different Compose
     project names while `docker-compose.yml` pins `container_name`, so the
     second editor collides); **`forwardPorts` is ignored by Zed** (no
     generated file sets it today); extensions declared for the project are
     also installed into the developer's local Zed;
   - that `.zed/settings.json` is developer-owned — not refreshed by
     `refresh-assets.sh`, not touched by `--upgrade`.

Downstream-facing docs must not promise CI parity enforcement for these files
(`shared/architecture.md` :: "Lifecycle asset altitudes").

## Step 7 — Dogfooding this repository (FR-7)

1. `/.devcontainer/devcontainer.json`: add `customizations.zed.extensions` =
   `["dockerfile", "toml"]` after the existing `vscode` object. Leave
   `customizations.vscode` untouched.
2. New `/.zed/settings.json` with the exact content in api-spec :: "FR-7".
   It equals core's base merged with the rust fragment (arrays unioned and
   sorted), which is what the generator would produce for this project.

Hand-applied, like the workspace Codex assets (#261). No `verify-mirrors.sh`
entry: it is a merge result, not a copy of a single template file. No
`.gitignore` change: `.zed/settings.json` is meant to be tracked.

**Verify**: `jq empty .zed/settings.json`, `jq empty .devcontainer/devcontainer.json`,
`bash scripts/verify-mirrors.sh` (must still pass unchanged).

## Step 8 — Tests (NFR-2)

### `tests/common_json.bats` (extend)

| Test name | Asserts |
| --- | --- |
| `merge_devcontainer_json omits customizations.zed when neither input declares it` | `jq 'has("zed")'` on `.customizations` is `false`, and the whole output equals the pre-change expectation for the vscode subtree. Direct NFR-1 guard. |
| `merge_devcontainer_json merges customizations.zed.extensions with unique semantics` | Base `["dockerfile"]` + overlay `["toml","dockerfile"]` → `["dockerfile","toml"]`. |
| `merge_devcontainer_json preserves base customizations.zed when the overlay has none` | A language overlay without Zed data cannot erase core's `zed.extensions`. |
| `merge_devcontainer_json keeps customizations.vscode when only zed is in the overlay` | FR-2's "vscode is always kept". |
| `merge_devcontainer_json remains idempotent with customizations.zed` | Same `jq -S` comparison as the existing idempotency test, with Zed data present. |

### `tests/common_zed.bats` (new)

Harness mirrors `tests/common_json.bats`: `load` bats-support/bats-assert,
`source scripts/lib/common.sh`, `SCRATCH=$(mktemp -d)`, `/tmp/*`-guarded
teardown.

| Test name | Asserts |
| --- | --- |
| `merge_zed_settings deep-merges nested language objects` | `languages.Python` from the overlay lands beside a base `languages.Rust` without replacing it. |
| `merge_zed_settings unions and de-duplicates array values` | `file_scan_exclusions` union is deduplicated, and the `"..."` sentinel survives. |
| `merge_zed_settings prefers the overlay for scalar conflicts` | `format_on_save` overlay value wins; also covers the object-vs-string `formatter` mismatch (node + deno). |
| `merge_zed_settings preserves keys only present in the base` | Developer-authored keys survive a re-merge. |
| `merge_zed_settings is idempotent across repeated merges` | `merge(merge(b,o),o)` is byte-identical to `merge(b,o)`. |
| `merge_zed_settings accepts comment-bearing Zed settings` | A `//`-commented base merges successfully; output is strict JSON. |
| `merge_zed_settings copies the base when the overlay is missing` | Output equals base, exit 0. |
| `merge_zed_settings fails and leaves no output when the base is missing` | Non-zero exit, `output_file` absent. |
| `merge_zed_settings removes the output when the base is invalid JSON` | Non-zero exit, no stale `.tmp`. |
| `apply_zed_assets does nothing when ZED_ENABLED is unset` | No `.zed/` directory, devcontainer byte-identical. |
| `apply_zed_assets does nothing when the flavor ships no .zed directory` | Covers `services/redis`. |
| `apply_zed_assets creates .zed/settings.json for the first contributor` | Core-shaped fragment is copied, parent directory created (FR-3). |
| `apply_zed_assets merges a language fragment into an existing .zed/settings.json` | Second contributor merges rather than overwrites (FR-4). |
| `apply_zed_assets merges customizations.zed into the target devcontainer` | FR-2 through the real call path. |
| `apply_zed_assets leaves the live settings file unchanged when the merge fails` | Invalid live `.zed/settings.json` → warning, original bytes intact, exit 0, no `.tmp` left behind. |
| `apply_zed_assets skips the devcontainer step when the target devcontainer is absent` | No crash, settings step still runs. |

### `tests/plugin_idempotency.bats` (extend)

Add a `ZED_ENABLED=true` variant per participating plugin, reusing
`assert_plugin_post_copy_idempotent` (the existing tests, which never set
`ZED_ENABLED`, prove the Zed-off path is untouched):

- `post_copy idempotent with ZED_ENABLED: core`
- `post_copy idempotent with ZED_ENABLED: languages/rust`
- `post_copy idempotent with ZED_ENABLED: languages/python`
- `post_copy idempotent with ZED_ENABLED: languages/node`
- `post_copy idempotent with ZED_ENABLED: languages/deno`
- `post_copy idempotent with ZED_ENABLED: languages/go`
- `post_copy idempotent with ZED_ENABLED: languages/latex`

The three service plugins are still `skip`ped for the pre-existing
non-idempotency documented in that file; do not add Zed variants that would
fail for an unrelated reason.

Note for the harness: the existing `setup()` seeds `.devcontainer/devcontainer.json`
with `{}`, which is enough for both merges.

### `tests/setup_zed.bats` (new)

End-to-end, driving the real `setup.sh` in a temp directory
(`setup_create_manifest.bats` / `setup_maintenance.bats` style: `SCRATCH=$(mktemp -d)`,
`cd`, run with `-y` so there is no TTY).

| Test name | Asserts |
| --- | --- |
| `--help documents --zed` | `run bash setup.sh --help` output contains `--zed`. |
| `scaffold without --zed creates no .zed directory` | `[[ ! -e .zed ]]` and `jq '.customizations \| has("zed")'` is `false`. |
| `scaffold without --zed leaves the devcontainer customizations unchanged` | NFR-1: `jq -S '.customizations'` of a `--lang rust` run equals the same expression from a run of the pre-change generator — in practice, compare against the committed expectation fixture for the vscode subtree, and assert no `zed` key. |
| `scaffold with --zed writes .zed/settings.json` | File exists, `jq empty` passes, `.terminal.shell.program == "bash"`, `file_scan_exclusions` contains `"..."`. |
| `scaffold with --zed merges the language fragment into .zed/settings.json` | `--lang rust --zed` → `.lsp["rust-analyzer"].initialization_options.check.command == "clippy"` **and** `.terminal.shell.program == "bash"` (both contributors present). |
| `scaffold with --zed writes customizations.zed.extensions` | `--lang rust --zed` → extensions contain `dockerfile` and `toml`. |
| `scaffold with --zed keeps customizations.vscode` | FR-2. |
| `scaffold with --zed and a service adds the service extension` | `--lang rust --postgresql --zed` → extensions contain `sql`. |
| `--zed --dry-run writes nothing` | Target directory still empty, no `.zed/`. |
| `scaffold with --zed records zed_enabled in the manifest` | `jq '.scaffold_options.zed_enabled' .tarnished-manifest.json` is `true`; without `--zed` it is `false`. |
| `scaffold with --zed does not track .zed/settings.json in the manifest` | `jq '.files \| has(".zed/settings.json")'` is `false` — the ownership boundary from design.md decision 5. |
| `--zed is rejected against an existing Tarnished project` | Exit 1 with the "Existing Tarnished project" message (`scaffold_flags_supplied`). |
| `--zed is ignored in add-module mode` | Warning emitted; no `.zed/` appears in a monorepo that was initialized without Zed. |

### Full suite

`bats tests/` must be green, with no change in the skip list.

## Review checklist for this issue

- [ ] No file inside a verbatim-copied template directory gained a Zed key.
- [ ] `merge_devcontainer_json` reads no global and emits no `zed` key when
      neither input has one.
- [ ] Every extension ID appears in [research.md](./research.md) §2.
- [ ] `apply_zed_assets` returns 0 on every path and never overwrites a live
      file after a failed merge.
- [ ] `MANIFEST_EXCLUDE_GLOBS`, `refresh.json`, `refresh-assets.sh`,
      `verify-mirrors.sh` and `update_gitignore` are untouched.
- [ ] The language Zed call is in `plugin_post_copy_shared`, before the
      early-returning `post.sh` branch, and never in `plugin_post_copy_module`.
- [ ] `AGENTS.md` §4 lists `.zed/` with its non-verbatim note.
- [ ] This repository's `.devcontainer/devcontainer.json` and
      `.zed/settings.json` match what the generator would produce.
