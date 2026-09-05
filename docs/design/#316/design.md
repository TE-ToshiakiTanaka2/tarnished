# Design: #316 Preserve project ownership during AI foundation updates

## Context

Tarnished supplies Bash template plugins and the `erd` Rust CLI. `setup.sh` currently scaffolds a single project or monorepo, bootstraps `.tarnished-manifest.json`, and upgrades staged template files. `scripts/lib/common.sh` supplies copy/merge helpers and recording; `scripts/lib/manifest.sh` compares old/current/new hashes. Container-start `refresh-assets.sh` independently distributes AI assets from a cached Tarnished checkout. This change leaves the Rust crate and plugin interface intact.

The existing ownership inference is unsafe: `run_create_manifest` walks downstream files, skipped copies are recorded as owned, upgrade replays arbitrary post-copy hooks against the project, and runtime refresh uses directory `rsync --delete`. The manifest also advances to desired upstream hashes on skipped edits. Claude assets refresh while Codex skills and shared workflow contracts retain older copies. The resulting system does not reliably distinguish a scaffold seed, an installed foundation asset, and developer work.

## Personas and ontology

| Persona | Goal | Responsibility |
| --- | --- | --- |
| Downstream developer | Introduce and maintain an AI-agent development foundation for a new or ongoing software project | Own application behavior, settings, model/profile choices, and explicit customizations; resolve conflicts that require a project decision |
| Tarnished maintainer | Adapt centrally distributed skills and harnesses as supported models and vendor behavior evolve | Publish compatible defaults, tests, and migrations once; avoid requiring each developer to optimize copies manually |

| Entity | Owner | Creation/update/deletion authority |
| --- | --- | --- |
| Downstream project | Developer | Tarnished never claims the whole repository or a directory merely because setup ran there |
| Initial scaffold seed | Developer after creation | Language source/tests, package/build/lint files, docs, Docker/compose definitions, CI, root instructions, `post.sh`, and settings are initial seeds; maintenance does not overwrite or prune them |
| Distributed AI asset | Tarnished upstream; developer controls local changes | Claude commands/skills/scripts/agents/shared shell rule, Codex skills, and shared workflow contracts/projection update only through per-file provenance checks |
| Runtime helper | Tarnished upstream; developer controls local changes | Explicit template-delivered `.devcontainer/scripts/*.sh` helpers other than `post.sh` may receive manifest upgrades if ownership and unchanged bytes are proven |
| Project configuration/customization | Developer | `.tarnished/agent-profile.json`, `.tarnished/refresh.json`, `.codex/config.toml`, `.claude/settings.json`, `.local` sidecars and extra files remain under developer control |
| Provenance record | Updater metadata | Stores only an installed baseline or a baseline established by an exact distribution match; never records arbitrary observed project bytes as installed |
| Conflict | Developer decision pending | Existing unknown/edited file differs from desired distribution. Preserve it, report both paths and how to compare/adopt or move an override to `.local`; never automatically resolve it |

Preservation takes priority over convergence. Matching a template path is not ownership proof. The project retains ownership of scaffold seeds even when they are byte-identical to the seed.

## Architecture overview (delta)

Separate initial scaffold from two maintenance operations: `setup.sh --refresh` for AI assets, and `setup.sh --upgrade` for tracked runtime helpers. A bare rerun in an identified Tarnished project routes to refresh before any scaffold prompts/hooks. Maintenance always uses the current updater distributed with the invoked setup checkout, never executes a potentially unsafe old downstream refresh script.

Both update mechanisms use the same ownership rules and independent state because their managed sets are disjoint. Keep the runtime script deployable as its existing standalone template asset; do not require downstream copies of `scripts/lib/common.sh`. Share implementation helpers only if deployment/mirror wiring remains explicit; the requirement is one behavioral contract, not a new abstraction hierarchy.

### Changed modules

| Files | Change |
| --- | --- |
| `setup.sh` | Early existing-project routing, `--refresh`, safe bootstrap and upgrades, current-script invocation with explicit project root, no real-target post-copy during maintenance |
| `scripts/lib/common.sh` | Positive runtime-helper eligibility plus exclusions; copied-file provenance; excluded AI trees/configuration/state/sidecars |
| `scripts/lib/manifest.sh` | Validated version-2 baselines, conservative legacy migration, last-installed state retention, safe apply paths |
| `templates/core/.devcontainer/scripts/refresh-assets.sh` and workspace mirror | Per-file inventory/state/overlay decisions, safe configuration/cache/path handling, meaningful dry-run |
| `templates/agent-workflows/.tarnished/refresh.json` and workspace mirror | Claude/Codex/shared distribution defaults and opt-in centrally evolving default mappings |
| Affected lifecycle skills/contracts and mirrors | Remove statements that Codex/shared contracts cannot refresh; retain fallback compatibility for old installs |
| `README.md`, user-facing maintenance documentation, affected Bats tests | Ownership, migration, conflict recovery, CLI changes, behavioral regressions |

## CLI and routing

1. Explicit `--create-manifest`, `--upgrade`, `--refresh`, and `--add-module` retain separate modes; reject incompatible combinations before mutation. `--refresh` accepts `--dry-run` and `--yes`; scaffold selections and upgrade-only flags are rejected. Add `--project-root` to the refresh script so invoking it from the source checkout targets the intended downstream repository.
2. Before scaffold work, resolve the actual target using existing project-name/CWD rules and inspect markers (`.tarnished-manifest.json`, `.tarnished/refresh.json`, `.tarnished/agent-profile.json`, or `modules.json`). Malformed or symlink markers still identify an existing project and produce a safe diagnostic, not a fallback into scaffolding.
3. Bare existing-project reruns select refresh, including monorepo roots. Explicit `--add-module <name> --lang <lang>` remains available. Explicit scaffold flags against an existing Tarnished target fail with refresh/add-module guidance; `--overwrite` is not permission to re-scaffold it.
4. A repository without Tarnished markers can still receive initial scaffolding. Honor copy confirmation and only record successful template copies; a declined/skipped copy provides no provenance. Do not turn existing source or settings into maintenance assets. Explicit add-module retains its existing intended extension behavior and module collision checks.
5. `--upgrade` intentionally narrows to runtime helpers. It retains target refs, clean-tree/`--force`, root/module filters and opt-in `--prune`. It does not call real-target `plugin_post_copy` or mutate project settings/merge seeds. Plugin execution is allowed only in private staging. `--force` only bypasses the git precondition, never ownership checks.

## Manifest ownership and migration

Use `manifest_version: 2` with the existing metadata/options and `files: {relative_path: sha256}` shape. Version 2 means each hash is the last successfully installed/explicitly matched distribution baseline. Validate schema, hash syntax, paths, and scopes before reading any target or mutating state. Only positive runtime-helper destinations are eligible: `.devcontainer/scripts/*.sh` (including nested helpers when actually delivered by a selected plugin), except `post.sh`; reject `.local` and symlink paths. Other template files remain scaffold-only. A prior trusted eligible helper may remain a removal candidate even after it disappears from the new inventory.

Fresh scaffolding records only files successfully written through copy helpers and rehashes those recorded paths after rendering/post-copy. Do not replace this with a project-wide walk. An alternative bootstrap inventory may walk an isolated template staging tree, then inspect only candidate paths in the downstream project. Directory walking is allowed for upstream/private staging, never to infer downstream ownership.

For `--create-manifest`, stage the selected/inferred plugin distribution and compare only eligible candidates. Existing exact matches may establish a baseline without changing bytes. Differing/missing candidates are not adopted. `--from-version` selects the distribution reference used for comparison; a ref string is not proof by itself. Without a supplied ref, use the invoked source checkout and record its actual identity. A repeated bootstrap must retain existing version-2 baselines for edited/deleted files rather than reset them.

Every version-1 hash is untrusted because prior bootstrap could record arbitrary files. Never use it as an overwrite/prune precondition, even if it equals current bytes. Preserve/report all legacy entries that cannot be corroborated; drop their ownership claims from the new version-2 map. Eligible candidates identical to the selected distribution may be adopted without mutation. Unknown obsolete legacy files remain untouched. Unavailable historical content does not justify assuming ownership. A legacy file that differs from today's upstream needs one-time review/adoption; automatic recovery of already deleted files is out of scope.

For trusted files, update state only after successful installation or a verified current==desired match. Retain the old baseline on conflict/failure, user deletion, or an upstream removal not pruned. Keep removed-file baselines so a later `--prune` can still make a safe decision. A successfully pruned file loses its entry. Never advance skipped files to desired upstream hashes.

## Per-file refresh and provenance

Persist `.tarnished/refresh-state.json` atomically. Its versioned entries bind a project-relative destination to the upstream repository and source mapping, the last installed SHA-256, and whether effective bytes came from upstream or a local overlay. Include the upstream commit for diagnostics. Configuration/state files and their ancestors must be ordinary files/directories, not symlinks. State is generated local metadata, excluded from both manifests and distribution; document ignore handling without rewriting user gitignore content.

For each validated active mapping, enumerate regular upstream files and regular overlay files without following symlinks, then union those destinations with prior state entries for that exact mapping. Never enumerate destination files as owned. Unknown destination siblings are consequently untouched. A missing source root authorizes removal only when the current valid upstream checkout and prior state for that unchanged mapping prove the previously distributed root disappeared upstream (for example verified git tree absence at the resolved commit). A failed/unavailable checkout, malformed catalog, or changed mapping is not removal proof. When a source root exists, a missing individual previously owned file is a verifiable upstream removal. If an entire mapping is retired or reconfigured, preserve its former destinations/state rather than interpreting its absence as deletion.

The effective desired file is the corresponding `.local` file when present, otherwise upstream. A local sidecar is never mutated. Apply this decision table after path/type validation:

| Prior trusted baseline | Current destination | Desired bytes | Action/state |
| --- | --- | --- | --- |
| None | Missing | Present | Create; record bytes only after success |
| None | Exactly desired or exactly current upstream base | Present | Adopt identical base without mutation; an explicit overlay may then replace that proven base |
| None | Other existing content | Present/absent | Preserve unknown collision; no ownership claim |
| Present | Exactly desired | Present | No byte write; acknowledge desired installed baseline |
| Present | Matches last installed hash | Changed desired | Update; record successful effective bytes |
| Present | Differs from installed and desired | Any | Preserve conflict and old baseline |
| Present | Missing | Present | Preserve user's deletion and baseline; do not resurrect |
| Upstream-owned | Matches installed | Absent upstream and no overlay | Remove this file only; drop entry after success |
| Overlay-owned | Matches installed | Upstream and overlay both absent | Preserve projected customization; report; never prune overlay-origin content |

Removing a sidecar while its upstream file still exists restores upstream only if the live projection still matches the previously installed overlay. A further edit to the live file conflicts and is preserved. Removing an upstream file while a sidecar remains keeps or safely updates the overlay projection. Overlay-only added files are supported with the same collision rules. The two erd projections remain separate: `.claude/commands.local/erd` and `.tarnished/workflows/erd.local` must contain matching overrides when shared behavior is desired.

Serialize only successful/adopted entries plus preserved prior entries. A failed copy/delete does not advance that entry. Use per-file atomic replacement to avoid truncated files. On state persistence failure, warn and retain old state; a subsequent current==desired comparison can recover completed copies safely. Do not rewrite unchanged state merely to update a timestamp. A same-upstream SHA may avoid fetching but must not skip reconciliation: missing state, a different target, changed configuration/overlays, and retryable conflicts still need evaluation.

## Distribution and profiles

Keep `refresh.json` schema 1 compatible, adding an optional boolean `use_default_managed_paths` (absent means false). New defaults set it true and carry the full mapping snapshot in `managed_paths` for compatibility and documentation. In default mode, load only the validated `managed_paths` from the cached upstream `templates/agent-workflows/.tarnished/refresh.json`; retain project upstream URL/branch, clone location, and all profile/settings. If that upstream default catalog cannot be read/validated, warn and use the valid project snapshot. This allows a maintainer to add future default mappings without editing every downstream project. Explicit custom whitelists keep false/absent and remain authoritative, including an intentionally empty list.

The default catalog contains existing Claude mappings, Codex `.agents/skills` with `.agents/skills.local`, shared workflow `.md` file mappings with `.tarnished/workflows.local/<file>`, and the existing separate erd directory mapping. Using file mappings for shared contracts avoids an overlapping parent-directory mapping and its generated erd projection. Add every default destination/overlay and required directory-plus-`/*` exclusions to `MANIFEST_EXCLUDE_GLOBS`. Exclude profile/config/state explicitly; none is fetched as a workflow.

Retain the existing profile choices (`claude-main`, `codex-main`, `dual`) and role/model overrides byte-for-byte. Claude/shared assets remain available under all profiles because existing Codex skills consume the shared/Claude policy references. Install/update Codex skills when Codex is selected by the valid profile, recorded `codex_enabled`, or an existing `.agents/skills` installation; do not silently install them in Claude-only projects. Invalid profile data warns and preserves installed capability selection rather than replacing it with a new profile. No model IDs, prompt rewriting, model migration, or profile selection UI changes belong to this issue.

## Adoption and recovery

`setup.sh --refresh` invokes the current checkout's runtime script with the downstream root and the checked-out distribution available as a source, bypassing an unsafe installed updater. It may install a missing refresh config from the current defaults. An existing config is automatically opted into current defaults only when its mapping list exactly matches a known shipped legacy default list (compare structured values, not whitespace); preserve its upstream/cache choices and other fields. A custom/empty list is never replaced: report how to add missing mappings or explicitly opt into defaults. Runtime container refresh itself never rewrites the project config.

Document a concrete one-time migration: run current `setup.sh --refresh --dry-run`, inspect conflicts, run `--refresh`, and migrate the installed refresh helper in the same run when exact bytes match a known shipped legacy helper. Establish that proof from available recorded upstream commit/ref content or a shipped legacy digest inventory; a legacy manifest hash alone is insufficient. Only unproven or edited helpers require explicit developer review/copy. Setup refresh must report if the installed container-start helper remains old/conflicting and give the exact current source and target paths. The safe one-shot refresh must not imply that future container starts are safe while an old destructive script remains installed. Preserve custom post-start hooks and settings; do not rewrite them as part of migration.

Conflict recovery is manual and concrete: compare the reported current path to the reported cached/source candidate, keep project edits under the corresponding `.local` sidecar if desired, then explicitly copy the chosen upstream base or remove a conflicting unknown destination before rerunning. Rerunning safely adopts exact matches. Unknown missing-state legacy files cannot automatically receive a differing update; report this limitation. Existing custom whitelists require one-time intentional catalog adoption, not recurring skill optimization.

## Error handling and boundaries

Reject absolute/empty/dot/traversal paths, control characters unsupported by the serialization, directory/file collisions, overlapping destination mappings, and symlink components or leaf files in source, target, overlay, state, manifest, and module scope. Only enumerate regular files; never copy symlinks from upstream or sidecars. Recheck immediately before mutation. Recursive parent cleanup must stop at the managed root; omitting empty-directory cleanup is acceptable and simpler. Never recursively delete destination directories.

Validate clone location before any `fetch/reset/cleanup`: reject a symlinked cache, project/cache overlap in either direction, a cache that resolves to the source/downstream project, and an unrelated preexisting repository. Verify the configured origin; reject dirty/unrecognized caches instead of resetting developer work. Clone into a private temporary directory and rename only after success; cleanup only a temporary directory created by this run, never blindly `rm -rf` the configured location after clone failure.

Dry-run performs no target/config/state/summary writes and no persistent cache mkdir/clone/reset/fetch. Use a valid existing/local distribution to print exact planned file actions; if none is available, report unavailable upstream comparison instead of pretending a complete preview. Private temporary staging outside the target is allowed. Preserve executable modes for installed scripts. Runtime failures print `[WARN]` plus recovery hints and exit 0; only unknown CLI flags retain exit 1. Handle missing option arguments explicitly under `set -u`. Setup's explicit command failures can still return nonzero. Do not add `set -e` to the runtime script.

## Requirements coverage

| Requirement | Design/verification |
| --- | --- |
| FR-1 | Personas/ontology above; user-facing ownership documentation |
| FR-2 | Early rerun routing; scaffold-only project seeds; no target post-copy; source/settings snapshot regression |
| FR-3 | Positive eligibility, successful-write provenance, version-2 migration and staged bootstrap |
| FR-4 | Common refresh engine/default catalog for Claude/Codex/shared workflows; profile preservation |
| FR-5 | Decision table, per-file removal proof, sidecar and conflict rules |
| FR-6 | Exact-match adoption, repeat state retention, dry-run, concrete installation/config migration |
| FR-7 | Explicit nonfatal handling and path/cache validation before all writes/deletes |
| FR-8 | Behavioral matrix in workflow; mirrors and user docs |

No external research is needed: this changes existing Bash/git/jq distribution mechanics and does not make new vendor/model claims.
