# Workflow: #265 feat(setup): support manifest-based upgrade for previously scaffolded projects

The 4-phase split from the issue brainstorm is preserved as the PR boundary. Each phase ends in a separately-mergeable PR. Within a phase the steps are ordered by dependency; "can run in parallel" notes call out where order doesn't matter.

## Implementation Steps

### Phase 1 — Foundation

#### Step 1.1: Add `sha256_file` cross-platform wrapper

- **Action**: Implement `sha256_file <path>` in `scripts/lib/common.sh`. Prefer `sha256sum`; fall back to `shasum -a 256`; error if neither exists. Output format: `sha256:<64 lowercase hex>`.
- **Files**: `scripts/lib/common.sh`
- **Depends on**: none
- **Done when**: `sha256_file ./README.md` emits `sha256:<hex>` on both Linux and macOS; missing-file path returns 1 with a clear `print_error`.

#### Step 1.2: Create `scripts/lib/manifest.sh` skeleton

- **Action**: New file with the source-guard, constants (`MANIFEST_FILENAME`, `MANIFEST_SUPPORTED_VERSION`, `MANIFEST_EXCLUDE_GLOBS`), and stub functions for the public API listed in `api-spec.md` :: "scripts/lib/manifest.sh — new module". `manifest_path`, `manifest_exists` are full implementations; the rest are stubs that `print_error "not implemented"; return 1` so later phases can fill them in.
- **Files**: `scripts/lib/manifest.sh` (new)
- **Depends on**: 1.1
- **Done when**: `source scripts/lib/manifest.sh` is idempotent (guard works); `manifest_path /tmp/x` returns `/tmp/x/.tarnished-manifest.json`; `MANIFEST_EXCLUDE_GLOBS` array is exported.

#### Step 1.3: Extend `copy_with_confirm` for manifest recording

- **Action**: Add `MANIFEST_RECORDING`, `MANIFEST_RECORDING_ROOT`, `MANIFEST_TRACKED` globals (default off) plus `manifest_recording_start <root>` and `manifest_recording_stop`. Inside `copy_with_confirm` (and `copy_dir_with_confirm` indirectly), after a successful `cp`, call `_record_tracked_copy <relative_dest> <abs_dest>` when recording is on. The recorder skips paths matching `MANIFEST_EXCLUDE_GLOBS` and skips paths outside `MANIFEST_RECORDING_ROOT`.
- **Files**: `scripts/lib/common.sh`
- **Depends on**: 1.1, 1.2
- **Done when**: With recording off, behavior is byte-equivalent to pre-#265 (NFR-1). With recording on, after a `copy_with_confirm src /root/.foo`, `MANIFEST_TRACKED[".foo"]=="sha256:..."`. Excluded paths (e.g. `modules.json`) do not appear.

#### Step 1.4: Audit plugins for direct `cp` and migrate to `copy_with_confirm`

- **Action**: Inventory direct `cp` calls in `templates/*/plugin.sh` and `templates/*/*/plugin.sh`. Confirmed targets: `templates/core/plugin.sh:93` (modules.json template seed), `templates/languages/rust/plugin.sh:71` (workflow file copy). Audit `python/node/deno/latex` for any others (`grep -nE '(^|[^_])\bcp +' templates/.../plugin.sh`). Replace each with `copy_with_confirm` keeping behavior identical (same source/dest, same overwrite semantics — `copy_with_confirm` already covers the existing-vs-not-existing branches).
- **Files**: `templates/core/plugin.sh`, `templates/languages/rust/plugin.sh`, plus any flagged by audit.
- **Depends on**: none (independent of 1.1–1.3, but landing it in this phase keeps the invariant aligned with the new tracking)
- **Done when**: Every plugin's file copy goes through `copy_with_confirm` or `copy_dir_with_confirm`. `grep -E '\bcp +' templates/*/plugin.sh templates/*/*/plugin.sh` returns nothing or only flag-style usage (e.g. `cp -r` is also banned per the rule — but rare/none today).

#### Step 1.5: Plugin coverage test (regression net for 1.4)

- **Action**: New bats test that, for each plugin under `templates/`, sources the plugin in a temp dir with `MANIFEST_RECORDING=true` and `MANIFEST_RECORDING_ROOT=$tmp`, runs `plugin_copy "$tmp"`, walks `$tmp` for the resulting files, and asserts every non-excluded file has a corresponding entry in `MANIFEST_TRACKED`. Files matching `MANIFEST_EXCLUDE_GLOBS` are *expected* to be missing from `MANIFEST_TRACKED`.
- **Files**: `tests/plugin_tracking.bats` (new)
- **Depends on**: 1.3, 1.4
- **Done when**: Test passes for all 14 plugins. Adding a new direct-`cp` regression to any plugin breaks this test.

#### Step 1.6: Phase 1 PR

- **Action**: Open PR titled `feat(setup): foundation for manifest-based upgrade (#265 phase 1)`. Reference `Refs #265`. Body lists the four foundation pieces and notes that `--upgrade` / `--create-manifest` flags arrive in subsequent phases.
- **Depends on**: 1.1–1.5

---

### Phase 2 — Bootstrap (`--create-manifest`)

#### Step 2.1: Argument parsing for `--create-manifest` and `--from-version`

- **Action**: Extend `parse_arguments` to recognize the two flags. Add `CREATE_MANIFEST_MODE`, `FROM_VERSION` globals (with defaults). Add to the help text. Mutex check: reject combinations with `--monorepo`, `--add-module`, `--upgrade` (the last is added in Phase 3 — leave the rejection in place so we don't have to revisit this code path).
- **Files**: `setup.sh`
- **Depends on**: Phase 1 merged
- **Done when**: `setup.sh --create-manifest --from-version v0.0.74 --monorepo` exits 1 with a clear message; `--help` shows the new flags.

#### Step 2.2: Implement `manifest_walk_directory`

- **Action**: Walk the directory tree under `<root>`, filter out paths matching `MANIFEST_EXCLUDE_GLOBS`, hash each file via `sha256_file`, emit `<rel_path>\t<hash>` lines. Use `find` with the standard `-print0 | while IFS= read -r -d ''` idiom (consistent with `copy_dir_with_confirm`). Symlinks are followed (`find -L`) — current scaffolds do not include symlinks, but this matches `cp` behavior.
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 2.1
- **Done when**: Unit test (`tests/manifest.bats::manifest_walk_directory`) walks a fixture dir and verifies every non-excluded file is present, every excluded file is absent.

#### Step 2.3: Implement `manifest_write` and `manifest_read`

- **Action**: `manifest_write <root> <version> <commit> <scaffold_options_json>` builds the JSON object from the in-memory `MANIFEST_TRACKED` array and writes atomically (`tmp + mv`). `manifest_read <root>` validates `manifest_version <= MANIFEST_SUPPORTED_VERSION` and streams the JSON to stdout. `created_at` is `date -u +"%Y-%m-%dT%H:%M:%SZ"`.
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 2.2
- **Done when**: Round-trip test passes — `manifest_write` then `manifest_read` returns equivalent JSON; unsupported `manifest_version` returns exit-1 with `print_error`.

#### Step 2.4: Implement `run_create_manifest`

- **Action**: New top-level helper in `setup.sh`. Detects single vs monorepo via the target's `modules.json`. For single mode: walk root, write root manifest. For monorepo: walk root with module dirs excluded, write root manifest with `scaffold_options.monorepo=true`; for each module entry in `modules.json`, walk `<module>/`, write per-module manifest. Inferred `scaffold_options` come from filesystem evidence (presence of `.codex/config.toml` → codex enabled; presence of `.github/workflows/auto-tag.yml` → auto-tag enabled; etc.).
- **Files**: `setup.sh`
- **Depends on**: 2.2, 2.3
- **Done when**: Bats test scaffolds a project (single or monorepo), runs `--create-manifest`, asserts manifest file(s) exist with expected `tarnished_version`, expected `files` set, expected `scaffold_options`.

#### Step 2.5: Bats tests for create-manifest

- **Action**: `tests/setup_create_manifest.bats` covering single-mode, monorepo, `--from-version` propagation, idempotency (running twice produces an equivalent manifest — `created_at` will differ but everything else equal), and rejection of mutex violations.
- **Files**: `tests/setup_create_manifest.bats` (new)
- **Depends on**: 2.4
- **Done when**: All cases green on Linux + macOS CI matrix.

#### Step 2.6: Phase 2 PR

- **Action**: Open PR titled `feat(setup): --create-manifest bootstrap mode (#265 phase 2)`. Reference `Refs #265`. Body summarizes the bootstrap surface and the safety boundary (only generates manifest, does not modify any other file).

---

### Phase 3 — Upgrade core (`--upgrade`)

#### Step 3.1: Argument parsing for `--upgrade`, `--target-version`, `--force`

- **Action**: Extend `parse_arguments`. Add `UPGRADE_MODE`, `TARGET_VERSION` (default empty → resolves to `${REMOTE_BRANCH}` HEAD), `FORCE` globals. Mutex matrix per `api-spec.md`. Help-text update.
- **Files**: `setup.sh`
- **Depends on**: Phase 2 merged
- **Done when**: All mutex cases exit-1 with clear messages; `--help` shows the new flags.

#### Step 3.2: Implement `check_git_clean`

- **Action**: New helper in `setup.sh`. Returns 0 if `git diff-index --quiet HEAD --` succeeds, OR if `--force` is set, OR if the target is not a git repo (with a `print_warning` in the latter case). Returns 1 otherwise with the "commit/stash or use --force" guidance.
- **Files**: `setup.sh`
- **Depends on**: 3.1
- **Done when**: Unit test covers (a) clean repo → 0, (b) dirty repo without force → 1, (c) dirty repo with force → 0, (d) not-a-repo → 0 with warning.

#### Step 3.3: Implement `resolve_target_version`

- **Action**: Map `TARGET_VERSION` (tag, branch, commit) to a clone-able ref against the upstream tarnished repo. Reuse the existing remote-execution clone path (`setup.sh:42-67`) — extract the clone-into-tmp helper if it isn't already a function. Default value is `${REMOTE_BRANCH}` (currently `develop`). On failure, surface git's own error.
- **Files**: `setup.sh`
- **Depends on**: 3.1
- **Done when**: A tag (`v0.0.76`), branch (`develop`), and bad ref are exercised; bad ref exits 1.

#### Step 3.4: Implement `manifest_decide`

- **Action**: Pure function emitting one of the 8 decision symbols based on the three-hash state table in `design.md` :: "manifest_decide state table". `LEAVE_REMOVED` vs `PRUNE` is decided by reading the global `PRUNE_ENABLED` (set from `--prune`, lands in Phase 4 — for now read it as `false`).
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 3.1
- **Done when**: `tests/manifest.bats::manifest_decide` parameterizes all 8 rows and asserts the emitted decision; rows are referenced by FR-4 row number in the test name for easy debugging.

#### Step 3.5: Implement `manifest_apply`

- **Action**: Per decision: `NOOP`/`SKIP_*`/`LEAVE_REMOVED` → no filesystem writes; `UPDATE`/`NEW` → `cp` from staging to target; `PRUNE` → `rm` (Phase 4 ramps this up). Increments tally globals; appends to per-decision file-list arrays. Honors `DRY_RUN`.
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 3.4
- **Done when**: Unit test runs each decision against a temp directory and asserts target state + tally counters + file-list arrays.

#### Step 3.6: Implement `manifest_diff_summary`

- **Action**: One-line `(~K +N -M)` summary. `K` = lines that differ; `N` = lines added in staging vs target; `M` = lines removed. Computed via `diff` line counts: `diff <(cat staging) <(cat target) | awk` etc. Bounded to ~80 cols.
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 3.5
- **Done when**: Unit test asserts the format on simple fixtures.

#### Step 3.7: Implement `manifest_summary_print`

- **Action**: Emits the FR-11 summary block per `api-spec.md` :: "End-of-run summary format". Always called at the end of `run_upgrade`. In `--dry-run`, the trailing line is "Dry-run; no files were modified." instead of "Manifest updated: ...".
- **Files**: `scripts/lib/manifest.sh`
- **Depends on**: 3.5
- **Done when**: Bats test snapshots the output of a fixture upgrade and matches it byte-for-byte.

#### Step 3.8: Implement `run_upgrade` (single-mode only in this step)

- **Action**: Top-level orchestrator: `check_git_clean` → `manifest_read` → `resolve_target_version` (clone) → `prepare staging dir` → `manifest_recording_start` → `execute_plugin_copies STAGING_DIR` + dockerfile + post_copy → `manifest_recording_stop` → iterate paths in (OLD ∪ NEW), compute three hashes, dispatch `manifest_decide`, call `manifest_apply` → `rerun_post_copy_on_target TARGET_DIR` (FR-5) → `manifest_write` → `manifest_summary_print`. In this step we only handle single-mode targets; monorepo dispatch is Phase 4.
- **Files**: `setup.sh`, `scripts/lib/manifest.sh` (for `rerun_post_copy_on_target` if it lives in `manifest.sh`)
- **Depends on**: 3.2, 3.3, 3.4, 3.5, 3.6, 3.7
- **Done when**: Bats test scaffolds a project, simulates an upstream change to a tracked file (mutate the staged template), runs `--upgrade`, observes the file is overwritten and tally is `Updated: 1`. Edited-file fixture asserts `SKIP_EDITED`. Dry-run fixture asserts no writes.

#### Step 3.9: Implement FR-9 dirty-tree check + `--dry-run` integration

- **Action**: Wire `check_git_clean` into the front of `run_upgrade`. Wire `DRY_RUN` into `manifest_apply` (already done in 3.5) and `manifest_write` (skip the write).
- **Files**: `setup.sh`, `scripts/lib/manifest.sh`
- **Depends on**: 3.8
- **Done when**: `--upgrade` against a dirty tree exits 1 (without `--force`) and 0 (with `--force`); `--upgrade --dry-run` is a true no-op on disk and prints the dry-run summary line.

#### Step 3.10: Bats tests for upgrade core

- **Action**: `tests/setup_upgrade.bats` covering each FR-4 lifecycle row end-to-end; FR-9 dirty/clean/forced; FR-10 dry-run; FR-11 summary.
- **Files**: `tests/setup_upgrade.bats` (new)
- **Depends on**: 3.8, 3.9
- **Done when**: All cases green.

#### Step 3.11: Phase 3 PR

- **Action**: Open PR titled `feat(setup): --upgrade single-mode + lifecycle (#265 phase 3)`. Reference `Refs #265`. Body summarizes single-mode upgrade behavior and notes that monorepo / `--prune` / `--shared-only` / `--module` arrive in Phase 4.

---

### Phase 4 — Monorepo + extras

#### Step 4.1: `--shared-only` and `--module <name>` (repeatable) parsing

- **Action**: Parse `--shared-only` and `--module <name>` (no `:lang` suffix in upgrade context). Reject `--module foo:bar` with the disambiguation error. Reject `--module foo` against single-mode targets.
- **Files**: `setup.sh`
- **Depends on**: Phase 3 merged
- **Done when**: Mutex matrix is fully exercised by tests.

#### Step 4.2: Implement `compute_upgrade_scopes`

- **Action**: Helper that returns the list of (scope_root, scope_name) pairs to process. Logic: if single-mode, return `[(target_root, "shared")]`. If monorepo: always include shared (unless `--module foo` given without `--shared-only`); include each `<root>/<module>` for each `--module <name>`, or all modules if `--module` is empty and `--shared-only` is not set.
- **Files**: `setup.sh`
- **Depends on**: 4.1
- **Done when**: Unit test exercises every combination (`(single, no flags)`, `(monorepo, no flags)`, `(monorepo, --shared-only)`, `(monorepo, --module a)`, `(monorepo, --module a --module b)`, `(monorepo, --shared-only --module a)`).

#### Step 4.3: Adapt `run_upgrade` for monorepo dispatch

- **Action**: After `compute_upgrade_scopes`, loop over scopes. For each scope: read scope's manifest, stage scope-specific plugin output (using existing #263 dispatch for language plugins by setting `MONOREPO_MODE=true`, `MODULES` from the target's `modules.json` filtered to the scopes being processed), apply per-scope decisions, write per-scope manifest. `manifest_summary_print` becomes scope-sectioned per `api-spec.md` :: "End-of-run summary format".
- **Files**: `setup.sh`, `scripts/lib/manifest.sh`
- **Depends on**: 4.2
- **Done when**: Bats test scaffolds a monorepo (`--monorepo --module a:python --module b:node`), runs `--upgrade`, observes shared + per-module sections in the summary; `--module a` only touches `a/`.

#### Step 4.4: `--prune` flag

- **Action**: Parse `--prune`. Set `PRUNE_ENABLED=true`. `manifest_decide` already returns `PRUNE` when this is on; `manifest_apply` handles `PRUNE` by `rm` against the target file (and increments `TALLY_PRUNED`). Without the flag, `LEAVE_REMOVED` is the result and `manifest_summary_print` shows the "Removed (would prune)" section.
- **Files**: `setup.sh`, `scripts/lib/manifest.sh`
- **Depends on**: 4.1
- **Done when**: Bats test asserts that without `--prune`, removed-upstream files are left + counted as `Removed (would prune)`; with `--prune`, they are deleted + counted as `Pruned`.

#### Step 4.5: `--target-version` end-to-end exercise

- **Action**: Add a bats test that pins `--target-version` to a specific git tag in a fixture upstream, runs `--upgrade`, and asserts the new manifest's `tarnished_version` matches.
- **Files**: `tests/setup_upgrade.bats`
- **Depends on**: 3.3, 4.3
- **Done when**: Test green; failure mode for bad ref is also covered.

#### Step 4.6: README + AGENTS docs

- **Action**: Update `README.md` with a new "Upgrading an existing project" section showing `--create-manifest` then `--upgrade`. Update `AGENTS.md` :: "Project-Specific Checks" to mention manifest tracking as part of the plugin contract review (so reviewers flag direct-`cp` regressions).
- **Files**: `README.md`, `AGENTS.md`
- **Depends on**: 4.5
- **Done when**: Docs accurately reflect every flag from `api-spec.md`.

#### Step 4.7: Cross-cutting — verify `plugin_post_copy()` idempotency across all plugins

- **Action**: Audit each plugin's `plugin_post_copy` (and language plugins' `plugin_post_copy_shared` / `_module`) for FR-5 idempotency. Existing #263 invariant is "must be idempotent" — this step is the verification. For each plugin: write a short bats fixture that runs `plugin_post_copy` twice on the same fresh target dir and asserts the second run produces zero filesystem changes (`diff -r` between snapshots). Any plugin that fails this gets a fix-up PR before Phase 4 merges.
- **Files**: `tests/plugin_idempotency.bats` (new), and any plugin scripts that need fixes
- **Depends on**: Phase 1 (plugin coverage test scaffolding can be reused)
- **Done when**: Every plugin passes the double-run test.

#### Step 4.8: Phase 4 PR

- **Action**: Open PR titled `feat(setup): monorepo upgrade + --prune + docs (#265 phase 4)`. Reference `Closes #265` (or leave it as `Refs #265` and let the PR body close it explicitly). This is the final PR for the issue.

---

## Task Dependencies

Within a phase, dependencies are noted per step. Across phases:

- Phase 2 depends on Phase 1 merging (so 2.1 starts only after 1.6 lands).
- Phase 3 depends on Phase 2 merging.
- Phase 4 depends on Phase 3 merging.

This is the safest sequencing for a feature with shared-state risk. Phases 1+2 *could* be one PR if reviewer bandwidth permits, but the four-phase split keeps individual diffs small and reviewable.

Within Phase 1: 1.4 can run in parallel with 1.1–1.3 (independent file sets); 1.5 depends on both. Within Phase 3: 3.4–3.7 are mostly independent (decision/apply/diff/summary) but all depend on 3.1; 3.8 stitches them together. Within Phase 4: 4.4 (`--prune`) is independent of 4.2/4.3 (monorepo) and can land in either order.

## Test Strategy

### Unit Tests (bats)

- **`manifest.bats`** — pure helpers in `scripts/lib/manifest.sh`:
  - `sha256_file` round-trip and missing-file error path
  - `manifest_walk_directory` excludes correct paths
  - `manifest_write` + `manifest_read` round-trip
  - `manifest_read` rejects unsupported `manifest_version`
  - `manifest_decide` 8-row state table (one parameterized test per FR-4 row)
  - `manifest_apply` per decision (with and without `DRY_RUN`)
  - `manifest_diff_summary` format on canned fixtures
  - `manifest_summary_print` snapshot

- **`plugin_tracking.bats`** — every plugin's emitted files are tracked (regression net for direct-`cp` audit).

- **`plugin_idempotency.bats`** — every `plugin_post_copy` is a no-op on its second run (FR-5 verification).

### Integration Tests (bats)

- **`setup_create_manifest.bats`** — black-box scaffolding + manifest production, single + monorepo, `--from-version`, idempotency.

- **`setup_upgrade.bats`** — black-box upgrade flow:
  - All 8 FR-4 lifecycle rows end-to-end
  - FR-9 dirty/clean/forced
  - FR-10 dry-run is a no-op on disk
  - FR-11 summary output format
  - Monorepo: `--shared-only`, `--module a`, `--module a --module b`, all-default
  - `--prune` deletes upstream-removed unedited files
  - `--target-version` resolves to specified ref
  - Bad ref exits 1
  - Mode mutex matrix (every combination from `api-spec.md`)

### Edge Cases

- File rename upstream (`old.md` → `new.md`) → observed as `LEAVE_REMOVED` + `NEW` (intentional; release notes carry the rename).
- Mixed legacy state: monorepo with root manifest but a missing per-module manifest → that module is skipped with a warning; user re-runs `--create-manifest` to backfill.
- `--upgrade` against a project whose `tarnished_version` is `unknown` (legacy bootstrap) → first upgrade reports a high SKIP_EDITED count; this is acceptable (safety-first default).
- Cross-platform sha256 (Linux + macOS) exercised by every hash-touching test.
- `copy_with_confirm` semantics unchanged when recording is off (NFR-1) — assertion: byte-equivalence test that runs `setup.sh` (no flags, no recording) before and after Phase 1 and diffs the produced project tree.
- `--shared-only --module foo` simultaneously → both scopes processed (no mutex; explicitly allowed).

### Quality Checks

- `bats tests/` passes on Linux (CI) and macOS (developer laptops).
- Shell rules from `.claude/rules/shell.md`: `set -euo pipefail`, `[[ ]]`, quoted expansions, `print_*` helpers, `command -v` checks. Verified by code review (no automated linter today).
- No new top-level dependencies (jq is already required; sha256sum/shasum are standard).
