# Workflow: #318 Distributed AI updates with backups

1. Implement reserved backup paths and verified per-file backup/install transaction in both runtime script mirrors. Add targeted tests for edited/unknown/deleted assets, exact backups, repeated runs, failure and in-flight edit guards.
2. Add settings catalog entries, Codex installed-settings detection and mirror/exclusion updates. Adapt synthetic catalog fixtures to handle JSON/TOML files. Verify settings replacement, native local-file preservation, profile behavior and custom catalog/sidecar behavior.
3. Integrate root upgrade with selected-source refresh and current updater policy, while retaining module validation, helper ownership and helper clean-tree checks. Register the previous shipped helper as recognized migration input. Test target refs, missing manifest, dirty tree, module-only scope and dry-run.
4. Simplify README; move useful advanced/CLI material into linked docs. Align shared ownership descriptions and AGENTS guidance with the explicitly accepted replacement policy.
5. Run affected Bats suites (refresh_assets, setup_maintenance, setup_upgrade, setup_remote_bootstrap, manifest/create-manifest as affected), Bash syntax, shellcheck where available, mirror verification, diff whitespace and local Markdown links. No Rust behavior changes; normal PR Rust CI still applies.
6. Orchestrator reviews against issue and design; independent external review, fixes and a PR to develop. Do not merge.

## Behavior matrix

- Unknown old, edited known, deleted known, matching and new distributed skill/settings destinations.
- Exact backup content and path, unique later-run backup, no redundant unchanged backup.
- Backup creation/copy/hash failures and symlinked backup/source/target paths preserve live bytes/baselines.
- Target edits during candidate/backup preparation do not get overwritten.
- Default and custom/empty catalogs, Codex profile and existing capability, explicit sidecars and project siblings.
- Proven unchanged upstream removal only; edited/unknown obsolete files preserved.
- Dry-run leaves target tree/config/state/backups unchanged, including missing config/helper migration.
- Root upgrade uses selected version for settings/skills; module-only never writes root; helper skipping has explicit outcome.
