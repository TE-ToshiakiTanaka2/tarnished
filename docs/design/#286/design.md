# Design: #286 setup.sh --upgrade: exclude `.github/` from manifest tracking

## Context

`setup.sh --upgrade` (#265) drives a per-file lifecycle decision against the user's target tree by comparing three hashes — `(old, current, new)` — where:

- `old` comes from the persisted `.tarnished-manifest.json` (sha256 of every "verbatim copy" file written during scaffold).
- `current` is `sha256_file <target/path>`.
- `new` comes from re-running the plugin pipeline against a staging directory with `MANIFEST_RECORDING=true`.

The set of paths that participate in tracking is filtered through `MANIFEST_EXCLUDE_GLOBS` (defined in `scripts/lib/common.sh:126`, re-exported by `scripts/lib/manifest.sh`). The same array is consulted by:

- `copy_with_confirm` / `manifest_track_file` → `_record_tracked_copy` → `_manifest_path_excluded` (recording side).
- `manifest_walk_directory` (walk-side backstop in `stage_plugin_run`, and `--create-manifest`'s tree walk).

Today `MANIFEST_EXCLUDE_GLOBS` covers the always-latest paths from #279/#281 (`.claude/commands{,/*}`, `.claude/skills{,/*}`, `.claude/scripts{,/*}`, `.claude/rules/shell.md`, and `.claude/*.local{,/*}` sidecars), plus merge-/dynamic-/user-owned files (`.gitignore`, `modules.json`, `docker-compose.yml`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `.claude/settings.json`, `.claude/settings.local.json`, `.devcontainer/devcontainer.json`, `.codex/config.local.toml`, `.tarnished-manifest.json`). It does **not** cover `.github/`.

As a result, the eight files emitted by `templates/github-actions/*` and `templates/languages/<lang>/.github/workflows/*-quality-check.yml` (e.g. `.github/project.yml`, `.github/versioning.yml`, `.github/workflows/auto-tag.yml`, `.github/workflows/project-integration.yml`, `.github/workflows/rust-quality-check.yml`, etc.) are hashed into the manifest at scaffold time and re-evaluated by `manifest_decide` on every `--upgrade`. Workflow YAML is exactly the kind of file downstream consumers customize (project numbers, owners, runner labels, additional jobs); the user-edited copies trip `SKIP_EDITED` at best and are deleted by `--prune` at worst when upstream removes the file.

## Architecture Overview (delta)

Move every path under `.github/` from "tracked by the manifest" to "user-owned, never tracked" — the same category as `CLAUDE.md`, `.claude/settings.json`, and `.devcontainer/devcontainer.json`. The plugin contract is unchanged: `plugin_copy` and `plugin_post_copy` still emit `.github/` files during initial scaffold (`copy_with_confirm` still copies; only the manifest recording is suppressed). The only behavioral changes are:

1. `--create-manifest` no longer hashes `.github/*` into the new manifest.
2. `--upgrade` no longer records or applies decisions to `.github/*`. Combined with item 1, freshly scaffolded projects produce manifests without `.github/` entries.
3. `--upgrade --prune` cannot delete `.github/` files even if the upstream `templates/github-actions/*` plugin is later disabled, because the OLD-manifest entries are filtered out of the decision loop (defensive layer beyond the EXCLUDE_GLOBS check, which only governs the NEW side).

For projects scaffolded before #286, the existing manifest still contains `.github/*` entries. The first post-#286 `--upgrade`:

- Decision-loop filter (item 3) drops the OLD entries before `manifest_decide` runs, so neither `LEAVE_REMOVED` nor `PRUNE` fires on them.
- Manifest rewrite at end-of-scope uses the new `MANIFEST_TRACKED` set, which already excludes `.github/*`, so the regenerated manifest no longer contains them.

Net result: a one-time, silent migration of pre-#286 manifests to the new contract, with no migration code.

## Module Structure (delta)

```
scripts/
└── lib/
    └── common.sh                       # extend MANIFEST_EXCLUDE_GLOBS with .github{,/*}
setup.sh                                # apply_decisions_for_scope: filter excluded paths from OLD_HASHES
tests/
├── manifest.bats                       # +regression: .github/* not recorded / not walked
└── setup_upgrade.bats                  # +regression: .github/* untouched by --upgrade and --upgrade --prune
```

No new files. No template changes — the existing `plugin_copy` implementations in `templates/github-actions/auto-tag/plugin.sh`, `templates/github-actions/project-integration/plugin.sh`, and `templates/languages/<lang>/plugin.sh` already guard against overwriting an existing `.github/workflows/*.yml` interactively and so are safe to re-run during scaffold.

## Interface Design (delta)

### Globals

#### `MANIFEST_EXCLUDE_GLOBS` (`scripts/lib/common.sh:126`)

Append two patterns, mirroring the directory-managed pattern used for `.claude/commands{,/*}` etc.:

```bash
# CI workflow / GitHub-side configuration is routinely customized per project
# (project numbers, owners, runner labels, additional jobs). Treat .github/
# as user-owned: scaffold still emits the templates, but --upgrade never
# touches them. (#286)
".github"
".github/*"
```

Bash glob semantics inside `[[ string == pattern ]]` allow `*` to span `/`, so the single `.github/*` pattern matches `.github/project.yml`, `.github/workflows/auto-tag.yml`, and any deeper nesting. Verified against `/workspace` shell.

#### Effect on existing call sites

| Call site | Effect |
| --- | --- |
| `_record_tracked_copy` (`scripts/lib/common.sh:229`) | Returns early for `.github/*` paths; `MANIFEST_TRACKED` no longer gains `.github/*` entries during a recording-on copy. |
| `manifest_track_file` (`scripts/lib/common.sh:208`) | Same — plugins that emit `.github/workflows/*.yml` via `sed > target` followed by `manifest_track_file` are now no-ops with respect to tracking. |
| `manifest_walk_directory` (`scripts/lib/manifest.sh:188`) | Skips `.github/*` during the backstop walk in `stage_plugin_run` and during `--create-manifest`'s tree walk. |

### Functions

#### `apply_decisions_for_scope` (`setup.sh:1939`)

Defensive filter on OLD_HASHES, ensuring the lifecycle loop never sees a path that the EXCLUDE_GLOBS contract has declared user-owned — even if the previous manifest still lists it. The patch is a single guard inside the existing while-read loop that populates `OLD_HASHES`:

```bash
# Before:
while IFS=$'\t' read -r path hash; do
    [[ -z "$path" ]] && continue
    OLD_HASHES["$path"]="$hash"
done < <(echo "$old_json" | jq -r '.files | to_entries[] | "\(.key)\t\(.value)"')

# After:
while IFS=$'\t' read -r path hash; do
    [[ -z "$path" ]] && continue
    # FR-2 (#286): a path that is now excluded must not enter the lifecycle
    # loop — otherwise --upgrade --prune would delete user-owned files that
    # are still present in pre-#286 manifests.
    if _manifest_path_excluded "$path"; then
        continue
    fi
    OLD_HASHES["$path"]="$hash"
done < <(echo "$old_json" | jq -r '.files | to_entries[] | "\(.key)\t\(.value)"')
```

No new public functions. No signature changes.

### Type Definitions (delta)

None. `MANIFEST_EXCLUDE_GLOBS` remains a bash array of glob patterns.

## Data Flow

The `--upgrade` flow described in `docs/design/shared/sequence.md` is unchanged structurally; only the set of paths that enter the lifecycle loop is narrower. The sequence-diagram annotation `skip MANIFEST_EXCLUDE_GLOBS` at `manifest_walk_directory` is now broadened to also cover `.github/*`. The flowchart for the per-issue control flow is in `docs/design/#286/flowchart.md`.

## Error Handling

No new error paths. The change is purely additive on the exclusion list and defensive on the lifecycle loop. The existing `manifest_walk_directory` / `_record_tracked_copy` / `manifest_apply` error contracts are unchanged.

`apply_decisions_for_scope` continues to propagate `manifest_apply` failures via its `apply_failures` counter; the new filter executes before any apply call, so it cannot introduce a new failure mode. If the old manifest is malformed (so `jq` fails), the existing `manifest_read` error path fires before this loop runs.

## Implementation Notes

- **One-shot migration is silent.** Users on pre-#286 manifests do not need to re-run `--create-manifest`; the first post-#286 `--upgrade` rewrites the manifest minus `.github/*` entries automatically (FR-4).
- **Scaffold parity is preserved.** Initial scaffold still produces the same `.github/` tree because `copy_with_confirm` ignores `MANIFEST_EXCLUDE_GLOBS` for the actual copy operation — the exclusion governs *recording*, not emission. Verified by `templates/github-actions/auto-tag/plugin.sh:88-113` and the corresponding `project-integration/plugin.sh:1357-1404` flows: both `plugin_copy` implementations write to disk and only then call `manifest_track_file`, which is the function whose early-return changes here.
- **`rerun_post_copy_on_target` is unaffected.** That function re-runs `plugin_post_copy` against the real target dir at the tail of `--upgrade`, but `templates/github-actions/auto-tag/plugin.sh::plugin_post_copy` already guards on `[[ -f "$versioning_config" ]]` (skip if exists) and `templates/github-actions/project-integration/plugin.sh::plugin_post_copy` does the same for `project.yml`. Workflow YAML files are written only in `plugin_copy`, which is *not* re-run on the real target — only on the staging dir. So user-edited `.github/workflows/*.yml` remains untouched.
- **Symmetry with #279.** The new entries mirror the directory-managed pattern (`dir` + `dir/*`) already used for `.claude/commands`, `.claude/skills`, and `.claude/scripts`. No need for an overlay sidecar (`.github.local/`) because `.github/` is fully user-owned — there is no upstream-managed-with-overlay model here. If a future issue wants always-latest sync for a *subset* of `.github/` (e.g., a renovate config), that issue can carve out a more specific exception.
- **No new `--exclude` flag.** Pre-emptive flag for "tell `--upgrade` to skip arbitrary paths" was rejected — the EXCLUDE_GLOBS list is the project-wide contract and adding ad-hoc per-invocation overrides would let users disable manifest tracking for paths the contract considers tracked. If a future need arises, it should be a config field, not a flag.
- **Test coverage.** Two layers:
  - **Unit** (`tests/manifest.bats`): `.github/foo.yml` and `.github/workflows/bar.yml` paths must (a) not enter `MANIFEST_TRACKED` after `copy_with_confirm` with recording on, and (b) not appear in `manifest_walk_directory` output.
  - **Integration** (`tests/setup_upgrade.bats`): given a target whose pre-#286 manifest lists `.github/workflows/auto-tag.yml` with the original hash, after `setup.sh --upgrade` the file content is unchanged even when the user has edited it; after `--upgrade --prune`, the file is still present even if upstream removed it; the post-upgrade manifest no longer lists `.github/*`.
