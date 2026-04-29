# API Specification: #265 feat(setup): support manifest-based upgrade for previously scaffolded projects

## setup.sh — new flags (delta over `../shared/api-spec.md` :: "CLI Surface :: setup.sh")

```
Modes (mutually exclusive — only one of these may appear in a single invocation):

  (no mode flag)        Single mode (existing behavior)
  --monorepo            Monorepo init (#263)
  --add-module <name>   Add a module to an existing monorepo (#263)
  --upgrade             [#265] Refresh tracked files of an existing scaffolded project
  --create-manifest     [#265] Bootstrap a manifest from a project's current state

Upgrade-mode flags (only meaningful with --upgrade):

  --target-version <ref>      [#265] Target git ref (tag or branch) of upstream tarnished.
                                     Defaults to ${REMOTE_BRANCH} HEAD (currently 'develop').
  --shared-only               [#265] Restrict to the root-level (shared) manifest.
                                     Has no effect on single-mode targets.
  --module <name>             [#265] (repeatable) Restrict to the named monorepo module.
                                     `<name>` is the module id from modules.json (no `:lang` suffix).
  --prune                     [#265] Delete tracked files that have been removed upstream
                                     and remain unedited locally. Without this flag, such
                                     files are left in place and reported as a warning.
  --force                     [#265] Bypass the FR-9 git-clean precondition (treat dirty tree
                                     as ok). Use with care — the upgrade may overwrite uncommitted
                                     work in unedited files.

Create-manifest flags (only meaningful with --create-manifest):

  --from-version <ref>        [#265] Recorded as `tarnished_version` in the produced manifest.
                                     Defaults to "unknown".

Inherited flags (apply to all modes; behavior unchanged):

  -h, --help
  -d, --dry-run
  -y, --yes
  --overwrite                 (single mode only)
```

### Mutual-exclusion matrix (additions for #265)

| Combination | Result |
| --- | --- |
| `--upgrade --monorepo` | exit 1 — "modes are exclusive" |
| `--upgrade --module foo:python` | exit 1 — "in upgrade mode, --module takes a name only" |
| `--upgrade --add-module foo` | exit 1 — "modes are exclusive" |
| `--upgrade --create-manifest` | exit 1 — "modes are exclusive" |
| `--create-manifest --monorepo` | exit 1 — "modes are exclusive" |
| `--create-manifest --add-module foo` | exit 1 — "modes are exclusive" |
| `--upgrade --shared-only` against single-mode target | warning, downgrades to `--upgrade` |
| `--upgrade --module foo` against single-mode target | exit 1 — "--module is monorepo-only" |
| `--upgrade --module unknown` (not in `modules.json`) | exit 1 — "module 'unknown' not found" |
| `--upgrade --target-version <bad-ref>` | exit 1 with git's error |
| `--upgrade` against project with no manifest | exit 1 — "run `setup.sh --create-manifest` first" |
| `--upgrade` against dirty git tree (no `--force`) | exit 1 — "commit/stash or use --force" |
| `--upgrade --prune` (no other flags) | normal upgrade with prune enabled |

### Examples

```bash
# Bootstrap an existing legacy project
./setup.sh --create-manifest --from-version v0.0.74 -y

# Upgrade to latest develop
./setup.sh --upgrade -y

# Upgrade to a pinned version
./setup.sh --upgrade --target-version v0.0.76 -y

# Preview an upgrade without writing anything
./setup.sh --upgrade --dry-run

# Monorepo: only refresh shared assets
./setup.sh --upgrade --shared-only -y

# Monorepo: only refresh selected modules
./setup.sh --upgrade --module backend --module worker -y

# Aggressive: also delete files that were removed upstream
./setup.sh --upgrade --prune -y

# Bypass the clean-tree check (advanced)
./setup.sh --upgrade --force -y

# Curl pipe (primary distribution path)
curl -fsSL .../setup.sh | bash -s -- --upgrade --target-version v0.0.76 -y
```

### Exit codes (additions)

| Code | Meaning |
| --- | --- |
| 0 | Success (including dry-run, including upgrades that decided NOOP for everything) |
| 1 | User error (bad flags, missing manifest, dirty tree without `--force`) |
| 2 | Reserved for partial-success scenarios; **not used** by #265 (matches existing convention) |

## End-of-run summary format (FR-11)

Single output block at the end of `--upgrade`. Always printed (even when there is nothing to update — confirms the no-op).

```
Tarnished upgrade summary (v0.0.74 → v0.0.76)
─────────────────────────────────────────────
  Updated:                    12 file(s)
  Skipped (edited):            3 file(s)
    .claude/skills/issue/SKILL.md           (~5 +12 -2)
    .claude/commands/erd/build.md           (~3 +0 -8)
    .devcontainer/devcontainer.json         (~1 +1 -0)
  New:                         5 file(s)
    .claude/rules/python.md
    .claude/skills/erd/cleanup/SKILL.md
    ...
  Removed (would prune):       2 file(s)
    .claude/legacy-rule.md
    templates/old-helper.sh
  Skipped (deleted by user):   1 file(s)
    .claude/commands/erd/old-helper.md
─────────────────────────────────────────────
  Manifest updated: .tarnished-manifest.json
  (or: Dry-run; no files were modified.)
```

The `(~K +N -M)` next to each skipped-edited entry is from `manifest_diff_summary` and reflects the line counts between the staged template content and the user's current file. It is intentionally compact — the user can pull a full diff with their normal tooling.

In monorepo mode, when more than one manifest scope was touched, the summary is sectioned:

```
Tarnished upgrade summary (v0.0.74 → v0.0.76)
─────────────────────────────────────────────
[shared]
  Updated: ...
[backend]
  Updated: ...
[worker]
  Updated: ...
```

## scripts/lib/common.sh — new public API

### `sha256_file <path>`

Cross-platform sha256 wrapper. Stdout: `sha256:<64 lowercase hex chars>`.

| Input | Output | Exit |
| --- | --- | --- |
| Existing file | `sha256:abc...` | 0 |
| Missing file | (stderr error) | 1 |
| No sha256 tool found | (stderr error) | 1 |

### Manifest recording globals

| Global | Type | Purpose |
| --- | --- | --- |
| `MANIFEST_RECORDING` | `bool` (string `"true"` / `"false"`) | Gate flag. False unless `manifest_recording_start` was called. |
| `MANIFEST_TRACKED` | `declare -gA` (associative) | Map: `<repo-relative-path> → "sha256:<hex>"`. Cleared by `_start`. |
| `MANIFEST_RECORDING_ROOT` | `string` | Absolute path used to compute repo-relative paths from absolute destinations. |

### `manifest_recording_start <root_dir>`

Sets `MANIFEST_RECORDING=true`, `MANIFEST_RECORDING_ROOT=<root_dir>`, clears `MANIFEST_TRACKED`. Idempotent.

### `manifest_recording_stop`

Sets `MANIFEST_RECORDING=false`. Does **not** clear `MANIFEST_TRACKED` (the snapshot is still readable).

### Wrapper behavior on `copy_with_confirm`

When `MANIFEST_RECORDING=true`, after a successful copy (whether the destination existed or not), `copy_with_confirm` calls an internal:

```bash
_record_tracked_copy <relative_dest> <abs_dest>
```

`<relative_dest>` is computed as `${abs_dest#${MANIFEST_RECORDING_ROOT}/}`. If the destination is outside the root (e.g. plugin writes to `/tmp/...` for unrelated reasons), the call is a no-op. If the destination matches `MANIFEST_EXCLUDE_GLOBS`, the call is a no-op (this is how `modules.json`, `docker-compose.yml`, `.gitignore`, etc. stay out of the manifest even though they flow through `copy_with_confirm`).

`MANIFEST_EXCLUDE_GLOBS` is defined in `manifest.sh` (see below) and exported into `common.sh`'s scope at source time.

When `MANIFEST_RECORDING=false` (the default), `copy_with_confirm` is byte-equivalent to its pre-#265 behavior — NFR-1 over the existing semantics.

## scripts/lib/manifest.sh — new module

```bash
#!/bin/bash
# scripts/lib/manifest.sh — manifest read/write, lifecycle decisions,
# and summary formatting for `setup.sh --create-manifest` / `--upgrade`.
[[ -n "${_MANIFEST_SH_LOADED:-}" ]] && return
_MANIFEST_SH_LOADED=1

readonly MANIFEST_FILENAME=".tarnished-manifest.json"
readonly MANIFEST_SUPPORTED_VERSION=1

# Globs (relative to the manifest scope root) that are deliberately not tracked.
# Per FR-3: merge files, dynamic files, user-owned files.
MANIFEST_EXCLUDE_GLOBS=(
    ".gitignore"
    ".tarnished-manifest.json"
    "modules.json"
    "docker-compose.yml"
    "CLAUDE.md"
    "AGENTS.md"
    "README.md"
    ".claude/settings.json"
    ".claude/settings.local.json"
    ".devcontainer/devcontainer.json"
    ".codex/config.local.toml"
)
```

### Read/write functions

| Function | Signature | Behavior |
| --- | --- | --- |
| `manifest_path` | `<root> → stdout` | echoes `${root}/${MANIFEST_FILENAME}` |
| `manifest_exists` | `<root> → exit` | 0 iff the file exists |
| `manifest_read` | `<root> → stdout (jq)` | reads + validates `manifest_version`; rejects unknown majors with `print_error` and exit-1; on success streams the parsed JSON |
| `manifest_write` | `<root> <version> <commit> <scaffold_options_json> → exit` | builds the manifest from `MANIFEST_TRACKED` and writes atomically via tmp+mv |
| `manifest_walk_directory` | `<root> → stdout (lines: <rel_path> <hash>)` | walks the directory tree applying `MANIFEST_EXCLUDE_GLOBS`, hashes each file. Used only by `--create-manifest`. |

### Decision and apply functions

| Function | Signature | Behavior |
| --- | --- | --- |
| `manifest_decide` | `<old_hash_or_-> <current_hash_or_-> <new_hash_or_-> → stdout (decision)` | Pure function; the FR-4 lifecycle as a state-table lookup. Emits one of: `NOOP`, `UPDATE`, `SKIP_EDITED`, `NEW`, `SKIP_NEW_CONFLICT`, `LEAVE_REMOVED`, `PRUNE`, `SKIP_USER_DELETED`. The `LEAVE_REMOVED` vs `PRUNE` choice depends on a global `PRUNE_ENABLED` (set from `--prune`). |
| `manifest_apply` | `<decision> <staging_path> <target_path>` | Mutates the target tree per decision. Honors `DRY_RUN`. Increments tally globals (`TALLY_UPDATED`, `TALLY_SKIPPED_EDITED`, ...) for the summary. |
| `manifest_diff_summary` | `<staging_path> <target_path> → stdout` | One-line `(~K +N -M)` summary using `diff` line counts. Used for SKIP_EDITED entries in the summary. |
| `manifest_summary_print` | `<old_version> <new_version>` | Prints the FR-11 summary block to stderr. Reads tally globals + scope tracking. |

### Tally globals (zeroed at start of `--upgrade`)

```
TALLY_UPDATED               counter
TALLY_SKIPPED_EDITED        counter
TALLY_NEW                   counter
TALLY_SKIPPED_NEW_CONFLICT  counter
TALLY_LEAVE_REMOVED         counter (also incremented when --prune is *not* set)
TALLY_PRUNED                counter (--prune deletes)
TALLY_SKIPPED_USER_DELETED  counter

SKIPPED_EDITED_FILES        array of <rel_path>
NEW_FILES                   array
LEAVE_REMOVED_FILES         array
PRUNED_FILES                array
SKIPPED_USER_DELETED_FILES  array
```

In monorepo mode the tallies are per-scope: a leading prefix string identifies the scope (`shared`, `<module>`) and `manifest_summary_print` emits one section per scope.

## setup.sh — new helpers (private)

These are not part of the user-facing API but are documented for review/testability.

| Helper | Purpose |
| --- | --- |
| `resolve_target_version` | Maps `--target-version` into a clone-able git ref; clones tarnished@ref into `TMP_DIR/tarnished-<sha>`. |
| `check_git_clean <target_dir>` | Wraps `git diff-index --quiet HEAD --` with `--force` bypass. Returns 0 if clean OR `--force`. |
| `run_create_manifest <target_dir>` | Top-level entry for `--create-manifest` mode. Walks tree, writes manifest(s). |
| `run_upgrade <target_dir>` | Top-level entry for `--upgrade` mode. Stages plugins, applies decisions, writes new manifest. |
| `compute_upgrade_scopes <target_dir>` | Returns the list of scopes to process based on `--shared-only` / `--module` / target's monorepo state. |
| `apply_decisions_for_scope <scope_root> <staging_root>` | Executes the FR-4 lifecycle per file for one manifest scope. |
| `rerun_post_copy_on_target <target_dir>` | After verbatim-file decisions are applied, re-runs `plugin_post_copy` against `target_dir` for FR-5 (merge logic re-application). |

## Workflow Triggers (no changes)

This issue does not introduce GitHub Actions workflows. The pre-flight git clean check uses local git only.

## Error Responses (additions over `../shared/api-spec.md` :: "Error Responses")

| Error | Type | When |
| --- | --- | --- |
| Manifest absent in `--upgrade` | shell error, exit 1 | `--upgrade` invoked on a project that has never been bootstrapped |
| Manifest `manifest_version` unsupported | shell error, exit 1 | `manifest_read` rejects manifest_version > MANIFEST_SUPPORTED_VERSION |
| Manifest JSON malformed | shell error, exit 1 | `jq` parse error |
| Dirty git tree without `--force` | shell error, exit 1 | `--upgrade` and `git diff-index --quiet HEAD --` non-zero |
| `--upgrade --module unknown` | shell error, exit 1 | named module not in `modules.json` |
| `--upgrade --module foo:python` | shell error, exit 1 | upgrade `--module` does not accept `:lang` suffix |
| `--target-version` ref not resolvable | shell error, exit 1 | git clone error |
| Mode mutex violation | shell error, exit 1 | per the matrix above |
| sha256 tool missing | shell error, exit 1 | `sha256_file` finds neither `sha256sum` nor `shasum` |
| Plugin failure during staging | per-plugin warning | same isolation pattern as `setup_plugins.sh` (#255) |
