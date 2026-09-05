# Workflow: #316 Preserve project ownership during AI foundation updates

## Implementation steps

### 1. Establish ownership and manifest provenance

- **Files**: `scripts/lib/common.sh`, `scripts/lib/manifest.sh`, `setup.sh`; `tests/manifest.bats`, `plugin_tracking.bats`, `setup_create_manifest.bats`.
- **Action**: Add positive maintenance eligibility, v2 validation/migration, successful-write recording and finite-path rehashing; replace downstream bootstrap walks with staged candidates. Preserve baseline on skip/conflict/deletion/removal.
- **Done when**: A developer's source/test/doc/custom configuration cannot enter a new manifest or become a legacy overwrite/prune candidate, including dirty/committed files and paths containing spaces.

### 2. Build safe per-file refresh

- **Files**: template/workspace `refresh-assets.sh`; `tests/refresh_assets.bats`.
- **Depends on**: Ownership contract in step 1.
- **Action**: Add explicit root/source options, strict config/state/path/cache checks, hash inventory, effective overlay candidates, per-file state/apply, same-SHA reconciliation, nonfatal warnings and target-free dry-run.
- **Done when**: Unknown and edited files survive, proven unchanged assets advance/remove, sidecars remain usable, failed writes retain baseline, and repeat runs converge without target changes.

### 3. Integrate setup maintenance and distribution migration

- **Files**: `setup.sh`, refresh configs/mirrors, relevant workflow ownership text/mirrors; setup upgrade/rerun/profile Bats coverage.
- **Depends on**: Steps 1–2.
- **Action**: Add early existing-project refresh dispatch and conflict checks. Invoke the current updater/source. Narrow upgrade to runtime helpers and remove real-target post-copy. Extend defaults to Codex/shared contracts and migrate only recognized default catalogs. Preserve explicit config/profile. Report outdated installed updater migration clearly.
- **Done when**: Ordinary rerun leaves application/settings snapshots identical; explicit add-module still works; Claude-only, Claude+Codex, codex-main and dual receive applicable assets while profile/settings hashes stay unchanged.

### 4. Document and verify

- **Files**: `README.md`, user-facing ownership/migration documentation, `AGENTS.md` and template counterpart as applicable, affected lifecycle ownership statements and mirrors, `scripts/verify-mirrors.sh` only if adding new pairs.
- **Depends on**: Steps 1–3.
- **Action**: Explain personas/ontology, initial vs ongoing use, narrowed upgrade, unknown legacy ownership, concrete conflict/config/updater migration. Replace current mandatory-overwrite/`rsync --delete` guidance with the preservation contract; retain sidecars as explicit overrides. Do not alter model IDs or unrelated prompts.
- **Done when**: Review can map FR-1–8 to behavior/docs and every affected mirror is identical.

## Behavioral validation matrix

| Surface | Necessary cases |
| --- | --- |
| Bootstrap/scaffold | Preexisting `src/work.py`, tests, docs and custom assets absent from ownership; skipped copy not owned; rendered actual copies only; repeated bootstrap keeps edited/deleted trusted baseline; explicit historical ref cannot certify arbitrary content |
| Upgrade/legacy | v1 arbitrary path unchanged and edited never overwritten/pruned; safe exact-match adoption; trusted helper update/obsolete prune; removed baseline retained for later prune; no real-target JSON/compose/post-copy mutation; root/module scope isolation |
| Refresh first/repeat | Missing state with matching/differing existing files; new file; upstream changed content with same size/mtime; unchanged repeat; missing state on second target sharing cache; config/overlay changes with unchanged SHA |
| Refresh ownership | Custom file under managed directory; edited upstream asset; removed unchanged/edited asset; removed last file/source directory with verified upstream disappearance; disappeared/changed mapping preserved; user-deleted file not resurrected |
| Overlays | New overlay-only file; changed sidecar; unknown collision; edited live projection; sidecar removal with and without upstream; upstream removal with retained sidecar; overlay-origin files never automatically pruned |
| Dry-run | Snapshot target files, directory entries, state/config/summary, and persistent cache before/after; both with source/cache and without cache; exact action preview when source available |
| Boundaries/failures | Traversal/absolute/control-character paths; source/target/overlay/parent/state/manifest/cache symlinks; directory collisions; overlapping mappings; corrupt state/config; hostile module path; cache overlap/wrong origin/dirty cache; clone/fetch/copy/state-write failures; missing option arguments |
| Profiles/migration | claude-main with/without Codex, codex-main, dual; existing profile/model overrides/settings byte-preserved; recognized legacy default mappings updated; custom/empty catalog retained; safe current updater used instead of legacy installed destructive script |

Use local git/temp fixtures and mocked failures; no production repository execution. Run affected Bats suites, Bash syntax checks and ShellCheck at the project's accepted severity, and `scripts/verify-mirrors.sh`. Broaden testing only for affected plugin/add-module integration. No Rust behavior changes require new Rust tests. Record any unavailable checks and preexisting failures separately. Review independently against both this design and the raw issue before PR creation.
