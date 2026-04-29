# Design: #265 feat(setup): support manifest-based upgrade for previously scaffolded projects

## Context

The shell side of `tarnished` (see `../shared/architecture.md`) is layered as `setup.sh` (orchestrator) → `scripts/lib/common.sh` (shared helpers) → `templates/<flavor>/plugin.sh` (per-flavor copy/post-copy hooks). `setup.sh` exposes three operating modes today (#263): **single**, **monorepo init**, **add-module**. In all three modes file copying happens through the `copy_with_confirm` / `copy_dir_with_confirm` helpers, which are responsible for the only existing safety net for "destination already exists" — an interactive y/N prompt or a non-TTY skip. There is currently **no record** of which version of tarnished produced a downstream project's files, and `copy_with_confirm` cannot tell an unedited template file apart from a file the user has deliberately customized.

The plugin contract — `plugin_name`, `plugin_description`, `plugin_copy`, `plugin_post_copy` (plus the language-plugin split into `_shared` + `_module` from #263) — is consumed by 14 plugin scripts under `templates/`. NFR-1 of this issue forbids changing that contract; all new behavior must be added without breaking existing plugins.

The relevant pieces of the data model for this issue:

- **Tracked-file model** is *new*. Per FR-3 the manifest covers only "verbatim copy" files (the category that flows through `copy_with_confirm`). Merge-targets (`.gitignore`, `devcontainer.json`, `.claude/settings.json`), dynamically-generated files (`docker-compose.yml`, `modules.json`), and user-owned files (`CLAUDE.md`, `AGENTS.md`, `README.md`) are deliberately **out of scope** for hash tracking.
- **Idempotency** is already an explicit cross-cutting concern (`../shared/architecture.md` :: "Cross-cutting Concerns"). `plugin_post_copy` re-runs are safe in flavors that follow the existing line-/block-/JSON-merge idempotency contract; this issue depends on that guarantee for FR-5.
- **Monorepo registry** (`modules.json`, `../shared/data-model.md` :: "modules.json schema") is the source of truth for which modules a target carries. Per FR-6, the manifest model must mirror that two-tier shape: one root manifest for shared assets plus one per-module manifest for module-specific assets.

## Architecture Overview (delta)

This issue introduces a new artifact and three new top-level operating modes for `setup.sh`:

1. **`.tarnished-manifest.json`** — a hash manifest written at scaffold time and consumed at upgrade time. Records sha256 of every "verbatim copy" file, plus the originating tarnished version, commit, and scaffold options. In monorepo targets a root manifest sits beside `modules.json`, and each module directory carries its own per-module manifest.
2. **`setup.sh --upgrade`** — refresh an existing scaffolded project to the latest (or `--target-version`-specified) tarnished version. File-by-file decisions follow an 8-case lifecycle (FR-4) keyed by the manifest hash; user-edited files are always skipped.
3. **`setup.sh --create-manifest`** — bootstrap mode for projects that were scaffolded before this feature existed. Generates a manifest from the current state of files; required as a one-shot before the first `--upgrade` on a legacy project.

The implementation strategy keeps the plugin contract unchanged by **wrapping `copy_with_confirm`** to opportunistically record `(dest_path, sha256)` into a global tracking set whenever recording is enabled. Plugins that use `copy_with_confirm` (the convention enforced by `.claude/rules/shell.md`) automatically participate. Plugins that bypass it with raw `cp` are migrated as part of this issue (Phase 1 cleanup).

The `--upgrade` flow uses a **staging area** so plugins continue to operate on `target_dir`-rooted paths exactly as they do today: tarnished is cloned at the target version into a temp dir, plugins are loaded from there and run with their copy destination redirected into a staging directory, then the lifecycle decision engine compares (manifest hash old) × (current file hash) × (staging file hash) per FR-4 and applies decisions to the real target. This isolates the upgrade computation from the user's working tree until the decisions are settled.

## Module Structure (delta)

```
.
├── setup.sh                                    # MODIFIED:
│                                               #   - parse_arguments(): new flags
│                                               #     --upgrade, --create-manifest, --shared-only,
│                                               #     --module <name> (repeatable), --target-version <tag>,
│                                               #     --prune, --from-version <tag>, --force
│                                               #   - resolve_setup_mode(): adds UPGRADE_MODE,
│                                               #     CREATE_MANIFEST_MODE branches alongside the existing
│                                               #     single / monorepo-init / add-module branches
│                                               #   - main(): top-level dispatch on mode
│                                               #   - new helpers: resolve_target_version,
│                                               #     check_git_clean, run_upgrade, run_create_manifest
├── scripts/lib/
│   ├── common.sh                               # MODIFIED:
│   │                                           #   - sha256_file(<path>) → "sha256:<hex>" wrapper
│   │                                           #   - copy_with_confirm() / copy_dir_with_confirm()
│   │                                           #     extended to append (dest_relative, sha) to a global
│   │                                           #     associative array MANIFEST_TRACKED when
│   │                                           #     MANIFEST_RECORDING == true
│   │                                           #   - new: manifest_recording_start / _stop / _flush
│   └── manifest.sh                             # NEW: pure manifest module — read/write,
│                                               #   compute hashes from a directory tree,
│                                               #   diff old vs new vs current, lifecycle decision
│                                               #   engine, summary printer, diff-summary helper
├── templates/
│   ├── core/plugin.sh                          # MODIFIED: replace `cp "$template" .../modules.json`
│   │                                           #   at line 93 with copy_with_confirm so the modules.json
│   │                                           #   template seed participates in tracking (verbatim
│   │                                           #   case; modules.json is then *mutated* by add_module_entry
│   │                                           #   which is excluded from tracking — see Implementation
│   │                                           #   Notes below).
│   └── languages/{rust,python,node,deno,latex}/plugin.sh
│                                               # MODIFIED: audit and replace direct `cp` (currently rust:71,
│                                               #   plus any in python/node/deno/latex) with copy_with_confirm
│                                               #   so language-specific verbatim files are tracked.
└── tests/
    ├── manifest.bats                           # NEW: unit tests for manifest.sh helpers
    │                                           #   (sha256_file, read/write/compare round-trip,
    │                                           #   lifecycle decision matrix for all 8 FR-4 cases)
    ├── setup_create_manifest.bats              # NEW: bootstrap flow (single + monorepo)
    └── setup_upgrade.bats                      # NEW: end-to-end upgrade flow including
                                                #   --shared-only, --module, --prune, --target-version,
                                                #   --dry-run, dirty-tree abort, --force bypass
```

`README.md` and `AGENTS.md` get small additions documenting `--upgrade` / `--create-manifest`. They are **not** tracked by the manifest (FR-3: user-owned).

## Interface Design (delta)

### New CLI flags on `setup.sh`

The full canonical surface lives in `api-spec.md` :: "setup.sh — new flags". Brief overview:

| Flag | Mode | Notes |
| --- | --- | --- |
| `--upgrade` | upgrade | Mode selector. Mutually exclusive with `--monorepo`, `--module <n>:<l>`, `--add-module`, `--create-manifest`. |
| `--create-manifest` | create-manifest | Mode selector. Mutually exclusive with the above. |
| `--target-version <tag>` | upgrade | Defaults to `${REMOTE_BRANCH}` HEAD (currently `develop`). Accepts a tag (e.g. `v0.0.76`) or branch name. |
| `--from-version <tag>` | create-manifest | Defaults to `unknown`. Optional declaration of the version that originally produced the project. |
| `--module <name>` | upgrade | **Different semantics from #263's `--module <name>:<lang>`**: in upgrade context this is a scope filter naming an existing module, repeatable. Disambiguated at parse time by the absence of a `:lang` suffix, but to remove ambiguity the parser also rejects `--module foo:bar` when `--upgrade` is set. |
| `--shared-only` | upgrade | Restrict to the root manifest (shared assets only). |
| `--prune` | upgrade | Opt in to deleting tracked files that have been removed upstream and are still unedited locally (FR-4 case 6). Without `--prune` the default is leave + warn. |
| `--force` | upgrade | Bypass the FR-9 git-clean precondition. |

Existing `--dry-run` (`-d`) and `--yes` (`-y`) apply to upgrade mode unchanged.

### New shell-library functions

Full signatures in `api-spec.md`. Summary:

**`scripts/lib/common.sh`**:

| Function | Signature | Purpose |
| --- | --- | --- |
| `sha256_file` | `<path> → "sha256:<hex>"` | Cross-platform sha256 wrapper. Picks `sha256sum` (Linux) or `shasum -a 256` (macOS). |
| `manifest_recording_start` | (none) | Sets `MANIFEST_RECORDING=true` and clears the `MANIFEST_TRACKED` global associative array. Called by `setup.sh` before plugins run. |
| `manifest_recording_stop` | (none) | Sets `MANIFEST_RECORDING=false`. |
| `_record_tracked_copy` (internal) | `<rel_path> <abs_dest>` | Called from inside `copy_with_confirm` only when recording is on. Computes sha256 and writes to `MANIFEST_TRACKED[<rel_path>]="sha256:<hex>"`. |

**`scripts/lib/manifest.sh`** (new file):

| Function | Signature | Purpose |
| --- | --- | --- |
| `manifest_path` | `<scope_root>` → stdout | Returns `${scope_root}/.tarnished-manifest.json`. |
| `manifest_exists` | `<scope_root>` → exit code | 0 iff manifest file present. |
| `manifest_read` | `<scope_root>` → stdout (jq) | Reads, validates `manifest_version`, streams JSON. |
| `manifest_supported_version` | (constant) | `MANIFEST_SUPPORTED_VERSION=1`. |
| `manifest_write` | `<scope_root> <tarnished_version> <tarnished_commit> <scaffold_options_json>` | Writes from the global `MANIFEST_TRACKED` snapshot. Atomic replace via `tmp + mv`. |
| `manifest_decide` | `<old_hash_or_-> <current_hash_or_-> <new_hash_or_->` → emits one of `NOOP / UPDATE / SKIP_EDITED / NEW / SKIP_NEW_CONFLICT / LEAVE_REMOVED / PRUNE / SKIP_USER_DELETED` | Pure decision function — the FR-4 lifecycle as a state-table lookup. |
| `manifest_apply` | `<decision> <staging_path> <target_path>` | Mutates the target tree per decision. Honors `DRY_RUN`. |
| `manifest_diff_summary` | `<staging_path> <target_path>` → stdout | Short `+N -M ~K` style line for skipped-edited files. |
| `manifest_summary_print` | (reads tally globals) | End-of-run summary table (FR-11). |
| `manifest_walk_directory` | `<root> <include_globs_or_->` → emits `<rel_path> <hash>` lines | Used by `--create-manifest` to compute hashes from current state. |

### Type Definitions (delta)

**`.tarnished-manifest.json` schema (new, FR-2)**:

```json
{
  "manifest_version": 1,
  "tarnished_version": "v0.0.76",
  "tarnished_commit": "<sha-or-empty>",
  "created_at": "2026-04-29T12:34:56Z",
  "scaffold_options": {
    "languages": ["rust"],
    "services": ["postgresql"],
    "github_actions_enabled": true,
    "auto_tag_enabled": false,
    "codex_enabled": true,
    "monorepo": false
  },
  "files": {
    ".devcontainer/devcontainer.json": "sha256:abc...",
    ".claude/commands/erd/build.md": "sha256:def..."
  }
}
```

| Field | Type | Required | Constraints |
| --- | --- | --- | --- |
| `manifest_version` | integer | yes | Currently `1`. Readers MUST reject unknown majors with a clear error. |
| `tarnished_version` | string | yes | git tag (e.g. `v0.0.76`), branch HEAD ref name, or `unknown` (legacy bootstrap). |
| `tarnished_commit` | string | yes | 40-char SHA, may be `""` if `git describe` was unavailable in the bootstrap path. |
| `created_at` | string | yes | ISO-8601 UTC, second precision (`%Y-%m-%dT%H:%M:%SZ`). |
| `scaffold_options` | object | yes | Snapshot of the option flags that produced the file set. Used informationally. Forward-compat: readers ignore unknown keys. |
| `scaffold_options.languages` | array | yes | Language ids selected at scaffold time. |
| `scaffold_options.services` | array | yes | Service ids selected at scaffold time. |
| `scaffold_options.github_actions_enabled` | boolean | yes | |
| `scaffold_options.auto_tag_enabled` | boolean | yes | |
| `scaffold_options.codex_enabled` | boolean | yes | |
| `scaffold_options.monorepo` | boolean | yes | true for root manifests in monorepo targets; false for single-mode and per-module manifests. |
| `files` | object | yes | Map of repo-root-relative path → `"sha256:<hex>"`. Empty `{}` is valid (e.g. a per-module manifest with no verbatim files). |

**Per-module manifest** uses the same schema and lives at `<module>/.tarnished-manifest.json`. The `scaffold_options.monorepo` field is `false` (the per-module manifest describes a single language scaffold; the *root* manifest carries `monorepo: true`). `scaffold_options.languages` is a single-element array on per-module manifests.

**Decision enum** (internal, no JSON form):

```
NOOP                  unchanged & unedited
UPDATE                upstream changed; user file matches old → overwrite
SKIP_EDITED           upstream changed; user file diverged from old → skip + diff summary
NEW                   not in old manifest; not in current target → copy
SKIP_NEW_CONFLICT     not in old manifest; user already has the path → warn + skip
LEAVE_REMOVED         in old manifest; absent from new manifest; user file matches old → leave + warn (default)
PRUNE                 LEAVE_REMOVED + --prune flag → delete target file
SKIP_USER_DELETED     in old & new; user file absent → respect deletion
```

The `LEAVE_REMOVED` + edited subcase (FR-4 row 7) and `SKIP_USER_DELETED` (FR-4 row 8) reduce into the table by checking `current_hash` before the upstream-removed branch.

### `manifest_decide` state table

| `old_hash` | `current_hash` | `new_hash` | Decision | FR-4 row |
| --- | --- | --- | --- | --- |
| present | == old | == old | NOOP | (1) unchanged & unedited |
| present | == old | != old | UPDATE | (2) updated upstream, unedited |
| present | != old | != old | SKIP_EDITED | (3) updated upstream, edited |
| absent  | absent | present | NEW | (4) newly added upstream |
| absent  | present | present | SKIP_NEW_CONFLICT | (5) collision with user file |
| present | == old | absent | LEAVE_REMOVED *(or PRUNE if `--prune`)* | (6) removed upstream, unedited |
| present | != old | absent | LEAVE_REMOVED *(always)* | (7) removed upstream, edited |
| present | absent | present | SKIP_USER_DELETED | (8) deleted by user |
| absent  | absent | absent | NOOP | impossible in practice; included for total-function safety |

`current_hash == old_hash` is the "unedited" predicate; this is the ONE place that interprets the manifest's record. Everything else flows from that comparison.

## Data Flow

### `--upgrade` (single-mode, `--shared-only` not set)

```
setup.sh
  ├── parse_arguments               → UPGRADE_MODE=true, TARGET_VERSION, PRUNE, FORCE, DRY_RUN, ...
  ├── resolve_setup_mode (extended) → confirms manifest exists; reads MONOREPO via manifest's
  │                                    scaffold_options.monorepo OR target's modules.json
  ├── check_git_clean               → unless --force, abort if `git diff-index --quiet HEAD --` fails
  ├── resolve_target_version        → maps --target-version <tag> | --target-branch | default to a
  │                                    git ref; clones tarnished@ref into TMP_DIR
  ├── manifest_read TARGET_DIR      → OLD_MANIFEST (in memory)
  ├── prepare staging               → STAGING_DIR := mktemp -d
  ├── load TMP_DIR/templates/<flavors-from-OLD_MANIFEST.scaffold_options>
  ├── manifest_recording_start
  ├── execute_plugin_copies STAGING_DIR
  ├── execute_plugin_dockerfiles STAGING_DIR
  ├── execute_plugin_post_copies STAGING_DIR     (FR-5 re-run, idempotent)
  ├── manifest_recording_stop      → NEW_MANIFEST_FILES := MANIFEST_TRACKED snapshot
  ├── for each path in OLD ∪ NEW :
  │       old_h     := OLD.files[path]
  │       new_h     := NEW_MANIFEST_FILES[path]   (sha256 of staging file)
  │       current_h := sha256_file(TARGET_DIR/path) || ""
  │       decision  := manifest_decide(old_h, current_h, new_h)
  │       manifest_apply(decision, STAGING_DIR/path, TARGET_DIR/path)
  │       tally per decision; collect skip-edited list
  ├── manifest_apply also re-runs the merge-mutation post-copy steps directly on TARGET_DIR
  │   for plugins whose plugin_post_copy contains gitignore/JSON-merge work (re-running these
  │   on TARGET_DIR is safe because of existing idempotency invariants — Cross-cutting Concerns
  │   in shared/architecture.md). To keep the staging-area model clean, we run these merge
  │   steps on TARGET_DIR *after* the verbatim-file decisions have been applied.
  ├── manifest_write TARGET_DIR <target_version> <commit> <scaffold_options>  (skipped if --dry-run)
  └── manifest_summary_print
```

### `--upgrade --module foo --module bar` (monorepo, selective)

Same flow as above, but before applying decisions the iteration narrows:

- Root manifest (`<root>/.tarnished-manifest.json`) is **only** processed if `--shared-only` is set or `--module` is not given (i.e. the default is "all").
- Per-module manifest (`<root>/foo/.tarnished-manifest.json`) is processed iff `foo ∈ --module` arguments OR no `--module` was given.
- Plugins are loaded from `OLD_MANIFEST.scaffold_options.languages` (root) and per-module `OLD_MANIFEST.scaffold_options.languages[0]` (module).

Implementation detail: `execute_plugin_post_copies` already knows how to dispatch language plugins per `(MONOREPO_MODE, MODULES)` (from #263). Upgrade mode reuses that dispatch by repopulating `MODULES` from the target's `modules.json` and filtering it down to the `--module` subset, so the per-language `_shared` + `_module` calls just work.

### `--create-manifest`

```
setup.sh --create-manifest [--from-version v0.0.74]
  ├── parse_arguments → CREATE_MANIFEST_MODE=true, FROM_VERSION (defaults "unknown")
  ├── resolve_setup_mode → detect monorepo via target's modules.json
  ├── manifest_walk_directory TARGET_DIR <include_set> → emits (rel_path, sha) lines
  │       where <include_set> is computed from the categories tracked by FR-3:
  │         - Exclude: .gitignore, devcontainer.json, .claude/settings.json,
  │           docker-compose.yml, modules.json, CLAUDE.md, AGENTS.md, README.md
  │         - Exclude: .tarnished-manifest.json itself
  │         - Include: everything else under tracked roots
  │           (.devcontainer/, .claude/, .codex/, docker/, .github/)
  ├── manifest_write TARGET_DIR FROM_VERSION "" <inferred_options>
  └── if monorepo:
        for each module in modules.json:
          manifest_walk_directory <root>/<module>/ → emit per-module manifest
```

The category-based include set is derived from a constant table inside `manifest.sh` (`MANIFEST_EXCLUDE_GLOBS`). It is the same table used by `manifest_walk_directory` in upgrade-mode debugging and by the bats tests for FR-3 coverage.

## Error Handling

| Error | Mode | Type | Recovery |
| --- | --- | --- | --- |
| Manifest absent | `--upgrade` | shell error, exit 1 | "Run `setup.sh --create-manifest` first" guidance message |
| `manifest_version` unsupported | any | shell error, exit 1 | "Upgrade setup.sh; this manifest needs a newer version" |
| Manifest JSON malformed | any | shell error, exit 1 | direct jq error surfaced via `print_error` |
| Dirty git tree | `--upgrade` | shell error, exit 1 | "Commit or stash changes, or pass `--force`" |
| Not a git repo | `--upgrade` | shell warning | clean check skipped; treated as `--force`-equivalent |
| Mutually-exclusive flags (e.g. `--upgrade --monorepo`, `--upgrade --add-module`, `--upgrade --create-manifest`) | parsing | shell error, exit 1 | per existing #263 mutex pattern in `parse_arguments` |
| `--module foo` with `:lang` suffix in upgrade mode | parsing | shell error, exit 1 | "In upgrade mode, --module takes a name only" |
| `--module foo` referencing missing module | `--upgrade` | shell error, exit 1 | "Module 'foo' not found in modules.json" |
| `--shared-only` against non-monorepo target | `--upgrade` | shell warning | downgrades to plain `--upgrade` |
| `--target-version` that does not resolve in upstream tarnished | `--upgrade` | shell error, exit 1 | git fetch / checkout error surfaced |
| Plugin failure during staging-area copy | `--upgrade` | per-plugin warning, continue | same isolation pattern as #255 |
| sha256 mismatch when `--from-version` was wrong (impossible to detect at create time, but `--upgrade` then sees every file as "edited") | runtime | informational | first `--upgrade` from a bootstrap reports a high SKIP_EDITED count; this is acceptable per Q5-b discussion in #265 brainstorm — the safety-first default is to skip rather than overwrite |

The pre-flight clean check uses `git diff-index --quiet HEAD --` (already-committed convention used by other setup.sh helpers); untracked files are ignored by this check, matching the user's expectation of "edits I haven't committed yet should not block an upgrade unless they are tracked-and-modified".

## Implementation Notes

### Why a staging area instead of running plugins directly on the target

Running `plugin_copy(target_dir)` directly on the user's tree would entangle the lifecycle decision engine with `copy_with_confirm`'s own y/N logic, and would write upgrade content **before** the decision is made. The staging area lets us:

1. Run plugins exactly as today — they just write to a different directory.
2. Compute the new hash set cleanly via `MANIFEST_TRACKED` collected during the staged run.
3. Compare three hashes per file (`old`, `current`, `new`) and apply the FR-4 decision *atomically* per file.
4. Cleanly support `--dry-run` by short-circuiting `manifest_apply`'s mutation phase.

### Why `copy_with_confirm` extension instead of a new `plugin_manifest_files` function

The brainstorm in #265 considered three ways to record tracked files (option A: wrap copy helper, option B: new plugin function, option C: hybrid). Option A was chosen because:

- The plugin contract stays unchanged (NFR-1).
- The `.claude/rules/shell.md` rule already mandates `copy_with_confirm` for any plugin that may overwrite files. Most plugins already comply.
- The rare direct-`cp` callers are easy to migrate (Phase 1 cleanup; six suspect plugins identified from `grep -l "cp " templates/*/plugin.sh templates/*/*/plugin.sh`).

Direct-`cp` calls outside `copy_with_confirm` will silently fail to be tracked, which would manifest as a "ghost" file in the upgrade — present on disk but not in the manifest, hence treated as user-owned and never updated. This is a soft failure mode (no data loss) but degrades the upgrade UX. The Phase 1 audit + the new bats test that loads each plugin and asserts every emitted file ends up in `MANIFEST_TRACKED` is the mitigation.

### Why `modules.json` is excluded from the manifest

`templates/core/plugin.sh:93` seeds an *empty template* `modules.json` via `cp`. After that, `modules.json` is mutated by `add_module_entry` / `replace_module_entry` (#263). The seed is a verbatim file but the live file is dynamic — the same path holds different roles at different lifecycle stages. Tracking the seed would produce false `SKIP_EDITED` results on every upgrade.

The cleanest resolution is to migrate line 93 to `copy_with_confirm` so the **seed-write call** still uses the standard helper (consistency), but to add `modules.json` to `MANIFEST_EXCLUDE_GLOBS` so the recording wrapper *does not* persist it into the manifest. The same exclusion already applies to `.gitignore`, `docker-compose.yml`, etc.

### Cross-platform sha256

`sha256sum` (GNU coreutils, present on Linux and devcontainers) and `shasum -a 256` (BSD-style, default on macOS) emit slightly different output formats but the leading hex digest matches. `sha256_file` extracts the first 64 hex chars and prepends the `sha256:` algorithm tag so future migrations to a different algorithm (e.g. `blake3:` for performance) can be done without rewriting old manifests:

```bash
sha256_file() {
    local path="$1"
    local hex
    if command -v sha256sum &> /dev/null; then
        hex=$(sha256sum "$path" | cut -d' ' -f1)
    elif command -v shasum &> /dev/null; then
        hex=$(shasum -a 256 "$path" | cut -d' ' -f1)
    else
        print_error "Neither sha256sum nor shasum available"
        return 1
    fi
    [[ ${#hex} -eq 64 ]] || { print_error "sha256 output malformed for $path"; return 1; }
    printf 'sha256:%s' "$hex"
}
```

### Edge case: upstream-renamed file

A file rename in the tarnished templates (e.g. `commands/erd/build.md` → `commands/erd/verify.md`) is observed by the manifest as one `LEAVE_REMOVED` and one `NEW`. If the user has not edited the old file, default behavior leaves it on disk and creates the new one — both files coexist. With `--prune`, the old one is removed. There is no rename-detection layer; this is consistent with the FR-2 manifest model (path is the key) and with the brainstorm's explicit Constraint that "renames are treated as delete + add". Releases that perform renames should call this out in their release notes.

### Edge case: monorepo without per-module manifests (mixed legacy state)

If a target's root has a `.tarnished-manifest.json` but a module directory does not, `--upgrade` (without `--shared-only` and without `--module foo`) treats the module as un-managed and skips it (warn). To bring it into management, the user runs `setup.sh --create-manifest` again — `manifest_walk_directory` is idempotent and re-creates any missing per-module manifests in place without rewriting existing ones (`manifest_write` is unconditional but only runs once per scope per invocation).

### Edge case: `--target-version` < current

Downgrades are permitted by the data model (the manifest is symmetric in old/new) but explicitly **out of scope** for this issue. Implementation: at `resolve_target_version`, if the target version's `git rev-list --count` is lower than the manifest's `tarnished_commit`, emit a warning ("Downgrade detected — proceeding"). No special handling, but the user is informed.

### Performance

A single sha256 over the typical scaffold footprint (~400 verbatim files, ~3 MB total) finishes well under one second on commodity hardware. The expensive step in `--upgrade` is the git clone of upstream tarnished into TMP_DIR (already done by the existing remote-execution bootstrap in `setup.sh:42-67`); this issue piggybacks on the same clone path. No new network operations are introduced.

### Test strategy

Bats tests (the project already uses bats — `tests/setup_language_selection.bats`, `setup_service_selection.bats`):

- **`tests/manifest.bats`** — pure unit tests of `manifest.sh`. The decision-table test parameterizes all 8 FR-4 rows; the round-trip test writes a fixture manifest, reads it back, and asserts equality.
- **`tests/setup_create_manifest.bats`** — black-box: scaffold a target, run `setup.sh --create-manifest`, assert manifest contents (file paths, sha values, scaffold_options).
- **`tests/setup_upgrade.bats`** — black-box: scaffold target at version A, simulate an upstream change to one file (mutate the staging-area template), run `setup.sh --upgrade`, assert each lifecycle outcome. Includes:
  - Edited-file is preserved (SKIP_EDITED row 3)
  - Pruning behavior (default vs `--prune`; rows 6 & 7)
  - Dirty-tree abort (FR-9)
  - `--dry-run` writes nothing
  - Monorepo `--module foo` only touches `foo/`
- **Plugin coverage test** (in `manifest.bats`): for each `templates/*/plugin.sh` and `templates/*/*/plugin.sh`, invoke `plugin_copy` against a temp dir with `MANIFEST_RECORDING=true` and assert every file in the temp dir has a corresponding entry in `MANIFEST_TRACKED`. This is the regression net for the "direct `cp` audit" Phase 1 task.

Tests run on Ubuntu (CI default) and macOS (developer laptops). The `sha256_file` cross-platform path is exercised by the round-trip test.
