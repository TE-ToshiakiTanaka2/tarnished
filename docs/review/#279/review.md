# Code Review: #279

- **Branch**: feature/TE-ToshiakiTanaka2/#279/always-latest-sync-for-claude-codex-assets
- **Base**: develop (merge base: 3efdc55)
- **Review scope**: Large (24 files, 2669 insertions)
- **Reviewed at**: 2026-05-14T03:05:16Z
- **Reviewer**: Codex CLI (codex-cli 0.128.0, codex exec --sandbox read-only)

---

### Critical (must fix)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:282] The first successful run never performs the initial sync. `ensure_clone()` clones the cache, then `pull_if_changed()` immediately compares local `HEAD` to `ls-remote`, sees them equal, returns `1`, and `main()` exits at line 412 before `sync_paths()` runs. That violates the design’s “first boot performs the first synchronization pass” requirement and breaks pre-#279 upgrades that rely on refresh to add missing assets such as `.claude/rules/`. Suggested fix: track whether `ensure_clone()` created a fresh clone and force one sync pass in that case, instead of treating “remote SHA == local SHA” as a no-op.

### Warnings (should fix)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:337] `dst`/`overlay` values from `.tarnished/refresh.json` are concatenated directly into filesystem paths with no normalization or prefix check. A value like `../../.ssh` or an absolute path would let the auto-run `postStartCommand` write outside the project root. The same applies to `src`, which is not constrained to stay under `CLONE_DIR`. Suggested fix: canonicalize joined paths and reject anything that escapes `PROJECT_ROOT`/`CLONE_DIR` before `mkdir` or `rsync`.
- [templates/core/.devcontainer/scripts/refresh-assets.sh:86] `--config` does not validate that an argument is present. `shift 2` on a lone `--config` leaves the parser stuck rather than producing a clean CLI error; I reproduced this as a hanging process with `bash .../refresh-assets.sh --config`. Suggested fix: check `[[ $# -ge 2 ]]` before consuming the flag and treat a missing operand as an explicit argument error.
- [tests/refresh_assets.bats:321] The invariant test only checks that each `dst` and `overlay` appears literally in `MANIFEST_EXCLUDE_GLOBS`; it does not assert the required `dir/*` entries. That means the test still passes if `.claude/commands/*` or another child glob is accidentally removed, even though manifest exclusion would then fail for files under that directory. Suggested fix: assert both `${path}` and `${path}/*` for every managed path and overlay.

### Suggestions (nice to have)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:171] Several non-fatal branches use `print_error` (`jq` missing, non-git clone dir) even though the stated FR-5 review criterion says failure paths should warn and exit `0`. Behavior is still non-blocking, but aligning the log level with the contract would reduce ambiguity.
- [tests/refresh_assets.bats:305] Add a bats case for `--config` without a value. The parser bug above is easy to regress because the current suite only covers unknown flags and `--help`.

### Positive
- [templates/core/plugin.sh:76] The post-create wiring is clean and idempotent, and the workspace/template dogfood copies are in sync.
- [scripts/lib/common.sh:138] The manifest exclusion list correctly includes both directory and `dir/*` forms for the always-latest paths and their `.local` overlays.

`bats` is not installed in this environment, so I could not execute the test suites locally.

REQUEST_CHANGES
### Critical (must fix)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:282] The first successful run never performs the initial sync. `ensure_clone()` clones the cache, then `pull_if_changed()` immediately compares local `HEAD` to `ls-remote`, sees them equal, returns `1`, and `main()` exits at line 412 before `sync_paths()` runs. That violates the design’s “first boot performs the first synchronization pass” requirement and breaks pre-#279 upgrades that rely on refresh to add missing assets such as `.claude/rules/`. Suggested fix: track whether `ensure_clone()` created a fresh clone and force one sync pass in that case, instead of treating “remote SHA == local SHA” as a no-op.

### Warnings (should fix)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:337] `dst`/`overlay` values from `.tarnished/refresh.json` are concatenated directly into filesystem paths with no normalization or prefix check. A value like `../../.ssh` or an absolute path would let the auto-run `postStartCommand` write outside the project root. The same applies to `src`, which is not constrained to stay under `CLONE_DIR`. Suggested fix: canonicalize joined paths and reject anything that escapes `PROJECT_ROOT`/`CLONE_DIR` before `mkdir` or `rsync`.
- [templates/core/.devcontainer/scripts/refresh-assets.sh:86] `--config` does not validate that an argument is present. `shift 2` on a lone `--config` leaves the parser stuck rather than producing a clean CLI error; I reproduced this as a hanging process with `bash .../refresh-assets.sh --config`. Suggested fix: check `[[ $# -ge 2 ]]` before consuming the flag and treat a missing operand as an explicit argument error.
- [tests/refresh_assets.bats:321] The invariant test only checks that each `dst` and `overlay` appears literally in `MANIFEST_EXCLUDE_GLOBS`; it does not assert the required `dir/*` entries. That means the test still passes if `.claude/commands/*` or another child glob is accidentally removed, even though manifest exclusion would then fail for files under that directory. Suggested fix: assert both `${path}` and `${path}/*` for every managed path and overlay.

### Suggestions (nice to have)
- [templates/core/.devcontainer/scripts/refresh-assets.sh:171] Several non-fatal branches use `print_error` (`jq` missing, non-git clone dir) even though the stated FR-5 review criterion says failure paths should warn and exit `0`. Behavior is still non-blocking, but aligning the log level with the contract would reduce ambiguity.
- [tests/refresh_assets.bats:305] Add a bats case for `--config` without a value. The parser bug above is easy to regress because the current suite only covers unknown flags and `--help`.

### Positive
- [templates/core/plugin.sh:76] The post-create wiring is clean and idempotent, and the workspace/template dogfood copies are in sync.
- [scripts/lib/common.sh:138] The manifest exclusion list correctly includes both directory and `dir/*` forms for the always-latest paths and their `.local` overlays.

`bats` is not installed in this environment, so I could not execute the test suites locally.

REQUEST_CHANGES

**Verdict**: REQUEST_CHANGES

---

## Fixes Applied

- **Critical** — `ensure_clone` now sets `JUST_CLONED=true` on a successful fresh clone; `pull_if_changed` short-circuits to "sync needed" when the flag is set, so first-boot now mirrors assets correctly. Subsequent runs unchanged.
- **Warning (path traversal)** — Added `safe_join()` defending against absolute paths, "..", and any join that escapes `PROJECT_ROOT`/`CLONE_DIR`. Offending entries are skipped with a warning.
- **Warning (--config validation)** — `--config` now requires a non-flag argument; lone `--config` or `--config --dry-run` exits 1 with a clear error.
- **Warning (test invariant)** — Subset test now asserts both `${path}` and `${path}/*` exist in `MANIFEST_EXCLUDE_GLOBS` for every managed_paths entry.
- **Suggestion (log levels)** — `jq missing` and `clone_dir not git repo` downgraded from `print_error` to `print_warning` to match the FR-5 always-return-0 contract.
- **Suggestion (regression tests)** — Added 4 bats cases: `--config` without value, `--config` followed by another flag, absolute-path dst rejection, `..`-bearing dst rejection.

Workspace dogfood copy `/workspace/.devcontainer/scripts/refresh-assets.sh` resynced byte-identical with the template.

- Commit: `e565a3c fix: address review feedback for #279`
- Test status post-fix: `bats tests/*.bats` → 182/182 pass, 0 fail (10 skipped — env has no rsync; CI provides it)
- Lint status post-fix: `shellcheck` clean across `refresh-assets.sh` (template + workspace), `templates/core/plugin.sh`, `templates/claude/plugin.sh`
