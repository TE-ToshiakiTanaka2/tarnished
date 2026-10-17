# Design: #323 feat: optional Zed editor support in the generator and this repository's devcontainer

## Context

`setup.sh` is the template installer. It parses flags, resolves one of five
operating modes, loads an ordered list of `templates/<flavor>/plugin.sh`
scripts and drives them through three phases:

```
execute_plugin_copies      → every plugin's plugin_copy(target_dir)
execute_plugin_dockerfiles → every plugin's plugin_dockerfile(target_dir)
execute_plugin_post_copies → every plugin's plugin_post_copy(target_dir)
                             (language plugins: plugin_post_copy_shared + _module)
```

Load order is fixed: `core` → `agent-workflows` → languages → services →
`claude` → `codex` → github-actions (`setup.sh::load_selected_plugins`). All
`plugin_copy` calls run before any `plugin_post_copy`.

Two shapes of devcontainer asset exist today, and the difference is the single
most important constraint on this design:

- `templates/core/.devcontainer/` is **copied verbatim** into the target by
  `copy_dir_with_confirm`. Every file in it lands in the generated project.
- `templates/languages/*/.devcontainer/devcontainer.json` and
  `templates/services/*/.devcontainer/devcontainer.json` are **never copied**.
  They are merge overlays, passed to
  `scripts/lib/common.sh::merge_devcontainer_json` against the target's
  devcontainer.

`merge_devcontainer_json` normalizes JSONC to strict JSON in temp files and
then runs one jq program that deep-merges top-level keys, object-merges
`features`, and rebuilds `customizations` as exactly
`{vscode: {extensions, settings}}` — `extensions` as a `unique` union,
`settings` as an object merge. Anything else under `customizations`,
including `customizations.zed`, is silently dropped.

Provenance: `<scope>/.tarnished-manifest.json` records `scaffold_options`
(which flavors were selected) plus hashes of *maintenance-eligible* files.
Eligibility is a **positive** allow-list — `_manifest_path_eligible` admits
only `.devcontainer/scripts/*.sh` other than `post.sh`. Scaffold-time
`scaffold_options` is produced by `infer_scaffold_options`, which reads the
generated tree rather than the in-memory flags.

Separately, `refresh-assets.sh` + `.tarnished/refresh.json` keep AI assets
(Claude/Codex skills, settings, workflow contracts) always-latest on every
container start. That channel is deliberately **untouched** here.

## Architecture Overview (delta)

This issue adds a fourth optional flavor dimension — editor — to a generator
that previously assumed VS Code. It is expressed as one boolean
(`ZED_ENABLED`, set by `--zed` or an interactive prompt) and four artifact
groups: `customizations.zed.extensions` inside the generated
`.devcontainer/devcontainer.json`, a project-level `.zed/settings.json`,
per-language Zed LSP/formatter fragments merged into that file, and
documentation. `customizations.vscode` is always kept, so a generated project
opens in either editor.

The delta is deliberately **additive and presence-gated** rather than
flag-threaded through the plugins. Two new pieces of shared machinery carry
all of it:

1. `merge_devcontainer_json` learns to carry `customizations.zed` through the
   merge, emitting the key **only when the base or the overlay has it**. It
   reads no environment variable — it stays a pure function of its three
   arguments. With no Zed inputs anywhere, its output is byte-for-byte what it
   is today (NFR-1).
2. One new shared helper, `apply_zed_assets <target_dir> <plugin_dir>`,
   installs a flavor's Zed contributions. It is the only place that reads
   `ZED_ENABLED`, and it returns immediately when Zed is off or when the
   flavor ships no `.zed/` directory. Every plugin that participates gains
   exactly one call to it; no plugin gains a conditional.

A flavor's Zed contributions live in a new per-flavor directory
`templates/<flavor>/.zed/` holding at most two files: `devcontainer.json`
(a devcontainer overlay containing only `customizations.zed`) and
`settings.json` (a `.zed/settings.json` fragment). `apply_zed_assets` merges
the first into the target devcontainer and installs/merges the second into
`<target>/.zed/settings.json`.

### Why a separate `templates/<flavor>/.zed/` directory

The issue leaves this open ("Decide in design how the vscode/zed split is
represented so the non-`--zed` path stays byte-identical"). Three options were
considered.

| Option | Verdict |
| --- | --- |
| **(a)** `customizations.zed` inside each existing overlay `devcontainer.json`, stripped by `merge_devcontainer_json` unless `ZED_ENABLED=true`. | Works for languages/services, **fails for core**: core's devcontainer.json is copied verbatim, so the key would appear in every generated project. Fixing that would mean rewriting the copied file with jq when Zed is off, which reformats it and breaks byte-identity. It also couples the merge helper to a global, making it untestable in isolation. |
| **(b)** `.devcontainer/devcontainer.zed.json` per flavor, merged only when enabled. | Same core problem from the other direction: the file sits inside the verbatim-copied `templates/core/.devcontainer/`, so an extra file lands in every generated project — a different NFR-1 violation (tree shape, not file bytes). |
| **(c, chosen)** `templates/<flavor>/.zed/{devcontainer.json,settings.json}` + one shared `apply_zed_assets` helper. | No file inside a verbatim-copied directory. Uniform for core, languages and services — the same two filenames, the same single call site. The merge helper stays pure and flag-free: emission is gated by *presence*, and presence is gated by the helper never running when Zed is off. Adding a Zed contribution to a future flavor is "create the directory, add one call". |

Cost of (c): Zed extension IDs for a language no longer sit next to the VS Code
IDs in the same file. That is accepted — the two editors genuinely need
different ID namespaces, and `templates/<flavor>/.zed/` groups each flavor's
Zed story in one place instead.

### Template-directory contract (`AGENTS.md` §4) extension

`AGENTS.md` §4 enumerates the subdirectories a flavor may ship:
`.devcontainer/`, `.claude/`, `.codex/`, `.agents/`, `.tarnished/`,
`.github/`, `docker/`. This design adds `.zed/` to that list, with one
property that distinguishes it from all the others:

> `.zed/` is **not** copied verbatim. `templates/<flavor>/.zed/devcontainer.json`
> is a merge overlay and must never reach the target; only
> `templates/<flavor>/.zed/settings.json` is installed, as
> `<target>/.zed/settings.json`. The sole installer is
> `scripts/lib/common.sh::apply_zed_assets`.

`AGENTS.md` §4 is updated in the same change, because a reviewer reading the
current text would reject `templates/core/.zed/` as a contract violation.

## Module Structure (delta)

```
scripts/lib/common.sh
├── merge_devcontainer_json           # MODIFIED: carry customizations.zed (presence-gated)
├── merge_zed_settings                # NEW: JSONC-tolerant deep merge for .zed/settings.json
└── apply_zed_assets                  # NEW: per-flavor Zed installer; only reader of ZED_ENABLED

scripts/lib/manifest.sh
└── manifest_options_valid            # MODIFIED: "zed_enabled" joins the boolean key list

setup.sh
├── ZED_ENABLED=false                 # NEW global, beside CODEX_ENABLED
├── show_help                         # MODIFIED: --zed option + example
├── parse_arguments                   # MODIFIED: --zed case
├── scaffold_flags_supplied           # MODIFIED: --zed is a scaffold selection
├── main (interactive block)          # MODIFIED: "Enable Zed editor support? (y/n) [n]"
├── main (add-module warnings)        # MODIFIED: --zed ignored + reset
├── main (Setup Configuration)        # MODIFIED: "Zed:" line
├── main (Next steps)                 # MODIFIED: Zed open instructions
├── infer_scaffold_options            # MODIFIED: zed_enabled from .zed/settings.json
└── populate_setup_state_from_manifest# MODIFIED: restore ZED_ENABLED for staged upgrade runs

templates/core/
├── .zed/devcontainer.json            # NEW: customizations.zed.extensions = ["dockerfile"]
├── .zed/settings.json                # NEW: terminal.shell + file_scan_exclusions base
└── plugin.sh                         # MODIFIED: apply_zed_assets call in plugin_post_copy

templates/languages/{rust,python,node,deno,go,latex}/
├── .zed/devcontainer.json            # NEW (except go: settings only)
├── .zed/settings.json                # NEW: per-language LSP/formatter fragment
└── plugin.sh                         # MODIFIED: apply_zed_assets in plugin_post_copy_shared

templates/services/{postgresql,mysql}/
├── .zed/devcontainer.json            # NEW: customizations.zed.extensions = ["sql"]
└── plugin.sh                         # MODIFIED: apply_zed_assets in plugin_post_copy
templates/services/redis/plugin.sh    # MODIFIED: apply_zed_assets (no .zed/ dir → no-op)

.devcontainer/devcontainer.json        # MODIFIED (FR-7): customizations.zed.extensions
.zed/settings.json                     # NEW (FR-7): core base + rust fragment, hand-applied

AGENTS.md                              # MODIFIED: §4 gains .zed/
README.md, docs/setup.md               # MODIFIED: --zed and its caveats

tests/common_json.bats                 # MODIFIED: zed merge cases
tests/common_zed.bats                  # NEW: merge_zed_settings + apply_zed_assets
tests/plugin_idempotency.bats          # MODIFIED: ZED_ENABLED=true variants
tests/setup_zed.bats                   # NEW: end-to-end --zed on/off/dry-run/provenance
```

## Interface Design (delta)

Full signatures, jq semantics, file contracts and exact user-visible strings
are in [api-spec.md](./api-spec.md). Summary:

### Public API / Functions

| Name | Signature | Description |
| --- | --- | --- |
| `merge_devcontainer_json` | `(base_file, overlay_file, output_file) -> 0\|1` | Unchanged signature. Now also merges `customizations.zed`, emitting the key only when base or overlay declares it. Still reads no globals. |
| `merge_zed_settings` | `(base_file, overlay_file, output_file) -> 0\|1` | New. Recursive deep merge for `.zed/settings.json`: objects merge key-wise, arrays become `unique` unions, scalars take the overlay. JSONC inputs accepted; output is strict JSON. Idempotent by construction. |
| `apply_zed_assets` | `(target_dir, plugin_dir) -> 0` | New. No-op unless `ZED_ENABLED == true` and `<plugin_dir>/.zed/` exists. Merges `<plugin_dir>/.zed/devcontainer.json` into the target devcontainer, then installs or merges `<plugin_dir>/.zed/settings.json` into `<target_dir>/.zed/settings.json`. Always returns 0; failures warn and leave the live file untouched. |
| `manifest_options_valid` | `(scaffold_options_json) -> 0\|1` | Unchanged signature; `zed_enabled` added to the validated boolean keys. |
| `infer_scaffold_options` | `(target_dir, monorepo_bool, [single_lang]) -> json` | Unchanged signature; emits `zed_enabled`. |

### Type Definitions (delta)

- **`ZED_ENABLED`** — `setup.sh` global, `"true"` / `"false"`, default `false`.
  Set by `--zed` or the interactive prompt; forced back to `false` in
  add-module mode with a warning. Read by exactly one function
  (`apply_zed_assets`) via `${ZED_ENABLED:-false}`, so plugins and tests that
  never set it behave as if Zed were off.
- **`scaffold_options.zed_enabled`** — boolean, optional (absent in every
  pre-#323 manifest, read with `// false`). Inferred from the existence of
  `<scope>/.zed/settings.json`.
- **`<target>/.zed/settings.json`** — generated project settings file. Strict
  JSON. Developer-owned: not an AI asset (absent from `refresh.json` and
  `refresh-assets.sh`), and not maintenance-eligible, so `--upgrade` and
  `--upgrade --prune` can never rewrite or delete it.
- **`templates/<flavor>/.zed/devcontainer.json`** — devcontainer merge overlay
  whose only top-level key is `customizations.zed`. May carry `//` comments
  (the merge helper strips them).
- **`templates/<flavor>/.zed/settings.json`** — fragment merged into the
  target's `.zed/settings.json`. Strict JSON; arrays are treated as sets.

## Data Flow

Scaffold run with `--zed`, single mode, `--lang rust --postgresql`:

```
parse_arguments            ZED_ENABLED=true
  │
execute_plugin_copies      core: copy .devcontainer/ (verbatim, no zed keys),
  │                              docker/, .claude/, docker-compose.yml
execute_plugin_post_copies
  ├── core.plugin_post_copy
  │     └── apply_zed_assets(target, templates/core)
  │           ├── merge_devcontainer_json(target dc, core/.zed/devcontainer.json)
  │           │     → customizations.zed.extensions = ["dockerfile"]
  │           └── .zed/settings.json absent → copy_with_confirm(core/.zed/settings.json)
  ├── rust.plugin_post_copy_shared
  │     ├── merge_devcontainer_json(target dc, rust/.devcontainer/devcontainer.json)
  │     │     → vscode extensions/settings + features (zed subtree carried through)
  │     ├── ... existing .claude/settings.json + rules + post.sh work ...
  │     └── apply_zed_assets(target, templates/languages/rust)
  │           ├── merge_devcontainer_json → zed.extensions = ["dockerfile","toml"]
  │           └── merge_zed_settings(target .zed/settings.json, rust fragment)
  │                 → + lsp.rust-analyzer.check.command=clippy, + **/target exclusion
  └── postgresql.plugin_post_copy
        ├── ... runServices, compose, vscode merge ...
        └── apply_zed_assets → zed.extensions = ["dockerfile","sql","toml"]
  │
infer_scaffold_options     .zed/settings.json exists → zed_enabled: true
manifest_write             scaffold_options.zed_enabled = true
Next steps                 VS Code steps + Zed steps
```

Without `--zed`, every `apply_zed_assets` call returns at its first guard, no
`.zed/` directory is created, and `merge_devcontainer_json` sees no `zed` key
on either side, so it emits none. The generated tree is byte-identical to
today's (NFR-1).

The ordering `core` → languages → services matters only for aesthetics: core
creates `.zed/settings.json` by copy, later flavors merge. If core is absent
from the run (add-module mode) Zed is off anyway, so the "first contributor
copies, the rest merge" rule never degrades into "a language fragment becomes
the whole file" in practice. The branch is kept for robustness, and
`apply_zed_assets` is correct in either order.

System-wide view: see [shared/sequence.md](../shared/sequence.md) →
"`setup.sh --zed` — optional Zed editor assets". The helper's internal
branching is in [flowchart.md](./flowchart.md).

## Error Handling

Everything in this delta is non-fatal and never leaves a half-written file.

| Situation | Behavior |
| --- | --- |
| `<plugin_dir>/.zed/` missing, or `ZED_ENABLED != true` | `apply_zed_assets` returns 0 immediately. No output, no directory creation. |
| Target `.devcontainer/devcontainer.json` missing | Zed devcontainer step skipped (same guard style as the existing vscode merges, which are all `[[ -f ... ]]`-gated). |
| `merge_devcontainer_json` fails on a Zed overlay (unparseable JSON) | Temp output removed by the helper; `apply_zed_assets` emits `print_warning` and leaves the live devcontainer untouched; returns 0. |
| `merge_zed_settings` fails (developer's `.zed/settings.json` is invalid even after comment stripping) | Temp output removed, `print_warning` with the path, live file untouched, return 0. The developer's file is never clobbered by a failed merge. |
| `copy_with_confirm` declines (file exists, non-interactive) | Existing `copy_with_confirm` semantics: warn and skip. Only reachable if `.zed/settings.json` exists but the merge branch was not taken, which cannot happen (the branch is chosen by the same `[[ -f ]]` test). |
| `--zed` passed in `--add-module` mode | `print_warning "--zed is ignored in add-module mode …"` and `ZED_ENABLED=false`, exactly mirroring `--codex`. |
| `--zed` passed against an existing Tarnished project | `scaffold_flags_supplied` now returns true, so the existing error fires: "Existing Tarnished project: use --refresh …". Same as `--codex`. |
| `--zed --dry-run` | `main` exits in the dry-run branch before `TARGET_DIR` is resolved and before any plugin runs; nothing is written, including `.zed/`. |

Cross-link: the shared error policy table lives in
[shared/api-spec.md](../shared/api-spec.md) :: "Error Responses" and gains the
two new rows above.

## Implementation Notes

### Key decisions and rationale

1. **`merge_devcontainer_json` stays pure.** The gate lives in
   `apply_zed_assets`, not in the jq program. A helper that reads a global
   cannot be unit-tested without arranging the global, and `tests/common_json.bats`
   exercises it directly. Presence-gating also makes NFR-1 a property of the
   program rather than of the caller: with no `zed` key in either input the
   emitted object is unchanged.
2. **Zed emission mirrors vscode emission.** Inside an emitted `zed` object,
   `extensions` is always present as the `unique` union — the same
   unconditional shape the existing program gives `customizations.vscode`.
   This keeps the jq readable. `zed` itself is absent unless one side declares
   it, which is the property NFR-1 needs.
3. **`unique` sorts.** Both `customizations.*.extensions` and the arrays in
   `.zed/settings.json` come out lexicographically sorted. For
   `extensions` this matches the existing vscode behavior. For
   `file_scan_exclusions` the order carries no meaning, and the sentinel
   `"..."` sorts *after* the `**/`-prefixed globs (`*` = 0x2A < `.` = 0x2E),
   so it stays at the end where it was authored. Sorting is also what makes
   repeated merges byte-stable.
4. **`merge_zed_settings` accepts JSONC.** Zed's own settings files are
   canonically comment-bearing, and the repository already has the
   normalization primitives (`_jsonc_to_json_file`) plus tests for them. A
   developer who adds a `//` note to `.zed/settings.json` would otherwise see
   every later merge fail. Output is strict JSON and comments are not
   preserved — the same documented trade-off `merge_devcontainer_json` makes.
5. **`.zed/settings.json` is developer-owned, by policy and by mechanism.**
   The issue's constraint is that it is not an AI asset and is an ordinary
   scaffold artifact. Mechanically, `_manifest_path_eligible` admits only
   `.devcontainer/scripts/*.sh`, so the file is not hashed by
   `--create-manifest`, not decided by `--upgrade`, and not deletable by
   `--prune`, and **no `MANIFEST_EXCLUDE_GLOBS` entry is required or added**.
   See "Assumptions" below.
6. **Provenance by evidence, not by flag.** `zed_enabled` is inferred from
   `.zed/settings.json` (FR-6), which means a developer who removes the file
   is correctly recorded as Zed-off at the next `--create-manifest`, and a
   pre-#323 project is recorded as Zed-off without a migration.
   `populate_setup_state_from_manifest` restores `ZED_ENABLED` so a root
   `--upgrade`'s private staging run reproduces the same tree it would have
   scaffolded; because `.zed/` is not eligible, that only affects staging
   fidelity, never the target.
7. **Extension lists are short on purpose.** Zed installs
   `customizations.zed.extensions` into the developer's *local* Zed, not just
   the container (Zed docs). Every ID is registry-verified and justified in
   [research.md](./research.md), and candidates that would need guessed
   configuration (`golangci-lint`) or a live connection string
   (`postgres-language-server`) are rejected there rather than shipped.
8. **No gitignore change.** `update_gitignore` does not ignore `.zed/`, so
   `.zed/settings.json` is tracked by git in generated projects — correct for
   a shared project setting, and consistent with FR-7 tracking this
   repository's own copy.
9. **No `verify-mirrors.sh` change.** This repository's `.zed/settings.json`
   is the *merged* result (core base + rust fragment), not a copy of any
   single template file, so it is not a mirrored pair. `devcontainer.json` has
   never been one. NFR-3 holds with the script untouched.

### Edge cases

- **`node` + `deno` together.** Their Zed fragments both configure
  `languages.TypeScript`; `formatter` is an object for Biome and the string
  `"language_server"` for Deno, so the later plugin wins for that scalar while
  arrays union. This is the same conflict `load_selected_plugins` already
  warns about for their competing Claude format hooks, and the existing
  warning text covers it. Deterministic (load order), no new warning.
- **Monorepo.** `.zed/` and `.devcontainer/` are root assets, so the Zed call
  belongs in `plugin_post_copy_shared` and must not appear in
  `plugin_post_copy_module` — the contract in
  [shared/api-spec.md](../shared/api-spec.md) :: "Language plugin contract"
  forbids a module hook from touching root paths. One root `.zed/settings.json`
  holds the union of all module languages, matching how `.claude/settings.json`
  and `Dockerfile.dev` already behave.
- **`--add-module` after a `--zed` scaffold.** `--zed` is ignored in
  add-module mode (FR-6), so a module added later does not get its language's
  Zed fragment. Accepted and documented: it mirrors `--codex`, and the
  recovery is a hand-edit of `.zed/settings.json`. Auto-detecting Zed from the
  existing `.zed/settings.json` in add-module mode was considered and
  rejected because FR-6 settles that the flag is *ignored* there.
- **Re-running the scaffold over an existing tree** (`--overwrite`, or the
  `--upgrade` staging run). Both merges are idempotent, so the second run is
  a no-op; `tests/plugin_idempotency.bats` gets `ZED_ENABLED=true` variants to
  prove it.
- **`features` and `remoteUser`.** Unchanged and shared by both editors. Zed
  honors devcontainer `features`, `remoteUser`, `postCreateCommand` and
  `postStartCommand`, so `refresh-assets.sh` still runs on container start
  under Zed. No change is needed for the AI-refresh channel to work there.

### Performance considerations

Per scaffold run the delta adds at most two jq invocations per participating
flavor (≤ 2 × 9 = 18 short-lived `jq` calls in the maximal selection), and
zero when `--zed` is off. Negligible against the existing per-flavor merge
cost.

### Assumptions recorded for review

- The issue's constraint says `.zed/settings.json` is "tracked as an ordinary
  scaffold helper in the manifest". Current ownership policy (#316/#318) made
  eligibility a positive allow-list restricted to `.devcontainer/scripts/*.sh`,
  so **no** scaffold seed of any kind is hashed any more. This design reads the
  constraint as its operative half — *not* an AI asset, *not* excluded by a new
  glob, emitted by the ordinary `copy_with_confirm` scaffold path — and treats
  the file like every other developer-owned seed (`ruff.toml`,
  `rustfmt.toml`, `.claude/settings.json`). Hashing it would require widening
  `_manifest_path_eligible`, which is a change to the ownership model and is
  not in this issue's scope.
- FR-1's "with `-y` the default is off": the new prompt is placed in the same
  `check_tty_available && [[ "$IS_ADD_MODULE_MODE" != true ]]` block as the
  GitHub Project and auto-tag prompts, which that block already runs even under
  `-y`. The default answer is `n`, and with no TTY (the `-y` CI shape, and every
  bats run) Zed stays off. Gating the new prompt on `SKIP_CONFIRM` would make
  `--zed` behave unlike its two siblings, so consistency was chosen; if the
  intent was "`-y` must never prompt", that is a pre-existing property of all
  three prompts and should be changed for all three in a separate issue.
