# Design: #318 Distributed AI updates with backups

## Context

Root `--upgrade` currently updates proven runtime helpers only. AI refresh separately preserves differing live assets, and excludes CLI settings. This prevents existing installations adopting new skills/settings. The user explicitly selected backing up and replacing distributed targets on every maintenance run. Project-only siblings, application files and explicit sidecars remain protected.

## Architecture and ownership

Keep reconciliation in the standalone, mirrored `refresh-assets.sh`. Enumerate upstream files, configured sidecars and previous state only. A currently distributed destination can be installed without historical ownership; differing existing bytes require a verified backup first. Unknown/edited live skills are no longer conflicts. Restore deleted currently distributed files. Matching bytes need no backup. Mapping identity changes remain conservative (preserve and report rather than authorize removal). Removed upstream files retain the previous provenance/unchanged-content conditions; edited obsolete files and overlay-origin files survive.

Add `.claude/settings.json` and `.codex/config.toml` to the default catalog. The selected distribution's complete file is the candidate, with no TOML/JSON merging and no new model IDs. Custom keys inside these files are therefore backed up and replaced. Claude assets remain shipped for every existing profile; Codex settings/skills require Codex profile, manifest capability or ordinary installed Codex settings/skills. Keep `.tarnished/agent-profile.json` and refresh configuration project-owned. Retain configured skill/workflow overlays. Do not use CLI-native local settings as replacement-file sidecars: those files have their own partial-configuration semantics. Users can explicitly configure a whole-file sidecar through refresh.json; native local settings remain untouched.

## Backup transaction

Reserve `.tarnished/backups/` and all descendants against refresh installation/removal and manifest ownership, including custom broad mappings. Lazily create a private unique run directory using `mktemp -d` beneath that ordinary directory. Store each replaced file at its original relative path inside the run directory. Do not prune or automatically delete backups. A run's content is created only when a differing existing target needs replacement.

1. Validate source, target and every backup path component (no symlinks or non-regular leaves).
2. Read current and desired hashes. In dry-run, report planned backup and installation without creating anything in the target.
3. Prepare a temporary candidate beside the target and verify its desired hash.
4. Copy the existing target to a new backup path, verify exact original bytes, and recheck the target's original hash. Failure preserves the target and baseline.
5. Immediately before atomic replacement, recheck target, candidate and backup path/content. Replace using the existing portable rename pattern; verify installed bytes before advancing state.
6. Report the backup path even if later installation fails, so recovery remains possible. Preserve all earlier backups across retries.

This retains the repository's per-call boundary checks rather than claiming filesystem-wide atomicity against arbitrary hostile races. Deterministic in-flight edits must abort replacement. Backup directories are private because settings can contain sensitive values. Summaries count installed, unchanged/adopted, backed-up, preserved/unsafe and failed results.

## Setup integration and compatibility

`run_refresh(root, source)` accepts an optional selected distribution source, defaulting to the invoked checkout. Use the current trusted updater implementation even with an explicit older `--target-version`; use selected source bytes/catalog for candidates. With default mappings enabled, augment older catalogs with the two mandatory settings projections when no existing destination mapping covers them; candidate bytes still come from the selected source. Explicit custom/empty catalogs remain authoritative. Do not execute an old updater that implements a different replacement policy. Upgrade staging substitutes the current refresher before helper application, so later helper/module failures cannot leave a historical updater installed; historical manifest bootstrap still compares the selected release bytes. Root manifests retain selected distribution version/commit metadata, with the current refresher identified by its installed file hash. Retain current conservative installed-helper migration, adding the preceding shipped helper digest to recognized legacy hashes.

Root-inclusive `--upgrade` (single/root and `--shared-only`) resolves its source once and runs AI refresh once as well as helper maintenance. Validate explicit module scopes before mutation; module-only upgrade never refreshes root AI settings. Capture helper clean-tree eligibility before AI writes. If missing manifest or dirty tree blocks helper work, root AI refresh can still run, with explicit helper-skipped guidance and a nonzero overall upgrade result. Invalid markers/scopes/source still fail without writes. Do not mask arbitrary dirty files to make upgrades pass. Existing `--force` only bypasses the helper clean-tree guard.

Newly installed recognized pre-opt-in catalogs enable default mappings immediately; existing explicit custom/false catalogs retain their choices. Dry-run uses a temporary migrated config outside the target. Explicit custom or empty managed mappings stay authoritative. Extend recognized previous default catalogs as necessary; default opt-in adopts current mappings. The invoked setup safely updates recognized old installed refresh helpers, making subsequent container-start runs adopt this policy. Unknown/edited installed helpers still require the documented explicit migration. Container-start failures warn and return 0; only unknown CLI flags return 1.

## Documentation

Rewrite README.md as a short Tarnished introduction plus initial setup, existing-project AI/all maintenance and backup recovery. Link advanced profile/monorepo/ownership/migration details from `docs/maintenance.md` and setup/reference documentation. Preserve erd CLI installation/usage in a linked reference. Restore examples use a real reported backup path, explain that refresh may replace a restored live file again, and describe durable customizations through sidecars/native local settings without inventing CLI behavior.

## Requirement coverage and verification

FR-1/7: root upgrade source/ref/migration/scope; FR-2/5: transaction and backups; FR-3: settings catalog/capability; FR-4: upstream enumeration, guarded removals, sidecars; FR-6: dry-run and summaries/nonfatal runtime; FR-8: behavioral fixtures; FR-9: entry-page rewrite. Shell, catalog/exclusion and mirror checks cover cross-cutting invariants. Tests must replace now-obsolete live-edit preservation expectations while retaining helper/application safety checks.
