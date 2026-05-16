# Workflow: #286 setup.sh --upgrade: exclude `.github/` from manifest tracking

## Implementation Steps

1. **Extend `MANIFEST_EXCLUDE_GLOBS`** (`scripts/lib/common.sh:126`)
   - Append `".github"` and `".github/*"` entries with a rationale comment block referencing #286.
   - Place them adjacent to the `.claude/commands{,/*}` entries to keep "directory-managed user-owned" entries grouped.

2. **Add defensive filter to `apply_decisions_for_scope`** (`setup.sh:1939`)
   - In the OLD_HASHES population loop (currently at `setup.sh:1956`), call `_manifest_path_excluded` and `continue` for excluded paths. Add an inline comment pointing to FR-2 / #286.

3. **Update `tests/manifest.bats`**
   - Add a regression case under the existing `@test "MANIFEST_EXCLUDE_GLOBS paths are not recorded"` group asserting that `.github/project.yml` and `.github/workflows/auto-tag.yml` are not recorded after `copy_with_confirm` with recording on.
   - Add a regression case under `@test "manifest_walk_directory hashes every non-excluded file"` asserting both paths are skipped by the walker.

4. **Update `tests/setup_upgrade.bats`**
   - Add a test that scaffolds, hand-edits `.github/workflows/auto-tag.yml`, runs `setup.sh --upgrade -y`, and asserts the edited content survives (decision should not even fire).
   - Add a test that constructs a pre-#286 manifest containing `.github/workflows/auto-tag.yml`, runs `setup.sh --upgrade --prune -y`, and asserts the file is still present afterward and the new manifest no longer lists `.github/*`.

5. **Verify shared snapshot consistency**
   - `/design` Phase 7 regenerates `docs/design/shared/{architecture,data-model,api-spec,sequence}.md` to reflect the new exclusion. Confirm the `MANIFEST_EXCLUDE_GLOBS` row in `data-model.md` mentions #286 and the inline-value list in `api-spec.md` reflects the new entries.

6. **Manual verification** (developer machine)
   - Run `bats tests/manifest.bats tests/setup_upgrade.bats`. All cases must pass.
   - Optionally run a smoke `./setup.sh --upgrade --dry-run` on the workspace's own `.tarnished-manifest.json` to confirm the summary no longer mentions `.github/*` after the change.

## Task Dependencies

- Step 1 unblocks Steps 2 and 3 (without it, recording-side tests cannot pass).
- Step 2 unblocks Step 4's `--prune` regression (without the OLD_HASHES filter, the prune test will incorrectly delete the file).
- Steps 3 and 4 can be authored in parallel after Steps 1 and 2 are in place.
- Step 5 must run last; it consumes the merged source-tree state.

## Test Strategy

### Unit tests (`tests/manifest.bats`)

| What | How | Why |
| --- | --- | --- |
| `.github/*` not recorded | Call `copy_with_confirm` with `MANIFEST_RECORDING=true` for `.github/project.yml` and `.github/workflows/auto-tag.yml`; assert `MANIFEST_TRACKED` does not contain either key. | Confirms FR-1 recording-side. |
| `.github/*` not walked | Pre-populate a scratch directory with the same two files plus a non-excluded file; assert `manifest_walk_directory` emits only the non-excluded file. | Confirms FR-1 walk-side. |
| Pattern crosses `/` | The walk-side test already exercises a nested path (`.github/workflows/auto-tag.yml`); no separate test needed. | Locks the bash-glob `*`-across-`/` assumption against future regression (e.g., a code refactor that switches to `find -path` could break this silently). |

### Integration tests (`tests/setup_upgrade.bats`)

| What | How | Why |
| --- | --- | --- |
| User edits to `.github/workflows/*.yml` survive `--upgrade` | Scaffold, edit `.github/workflows/auto-tag.yml`, run `setup.sh --upgrade -y`, diff the file against the edited copy. | Confirms FR-3 + FR-1 end-to-end. |
| `--upgrade --prune` does not delete `.github/*` even when OLD manifest lists them | Construct a pre-#286 manifest (manually inject `.github/workflows/auto-tag.yml` hash), run `setup.sh --upgrade --prune -y`, assert file still present. | Confirms FR-2 (the defensive OLD_HASHES filter). |
| Post-upgrade manifest no longer tracks `.github/*` | Same scenario as above; `jq '.files | keys[]'` on the new manifest must contain no path starting with `.github/`. | Confirms FR-4 (auto-migration). |

### Edge cases to cover

- **Empty `.github/`**: walker must not synthesize phantom entries (already covered by existing `manifest_walk_directory` invariants).
- **`.github.local/` or similar**: out of scope. We do not introduce overlay semantics for `.github/`. No need to test absence of overlay behavior — the change does not add it.
- **`docker-compose.yml`** and other already-excluded paths: untouched by this change; existing tests for them must continue to pass.

## Quality Checks

Standard repo quality gates apply:

- `bats tests/manifest.bats tests/setup_upgrade.bats tests/plugin_tracking.bats` — the three test files that interact with `MANIFEST_EXCLUDE_GLOBS` or the upgrade flow. All must pass.
- `shellcheck scripts/lib/common.sh setup.sh` — the two production files touched. No new warnings.
- `bash -n scripts/lib/common.sh setup.sh` — syntactic sanity, fast.

The Rust crate (`cargo test`, `cargo clippy`) is unaffected by this issue; no Rust files are changed.
