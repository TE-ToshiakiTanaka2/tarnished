# Maintenance reference

Run maintenance from the downstream project directory, using the **current Tarnished checkout's** `setup.sh` or the remote commands in the [README](../README.md). The current setup supplies the trusted updater, including when you select an older distribution. Maintenance requires Bash 4.4+, Git, jq, and `sha256sum` or `shasum`; ordinary BSD utilities are supported without GNU `realpath` or `mv -T`.

## Commands and scope

```bash
# Preview and update distributed AI assets and settings.
bash /path/to/tarnished/setup.sh --refresh --dry-run
bash /path/to/tarnished/setup.sh --refresh -y

# Update AI assets/settings plus eligible runtime helpers.
bash /path/to/tarnished/setup.sh --upgrade --dry-run
bash /path/to/tarnished/setup.sh --upgrade -y --prune
bash /path/to/tarnished/setup.sh --upgrade --target-version <ref> -y

# Monorepo root/shared update, including AI assets/settings.
bash /path/to/tarnished/setup.sh --upgrade --shared-only -y
# A module-only update does not refresh root AI assets/settings.
bash /path/to/tarnished/setup.sh --upgrade --module backend -y
```

Root upgrades resolve the selected distribution once for both AI updates and runtime helpers. `--target-version` selects candidate bytes and catalog from that ref; the updater implementation still comes from the current invoked setup. Invalid module scopes fail before mutation. `--prune` permits removal of proven unchanged obsolete runtime helpers; AI upstream removals have their own provenance checks.

A bare setup rerun in an existing Tarnished project performs AI refresh. Explicit scaffold options are rejected there; use `--add-module <name> --lang <language>` for a new monorepo module. `--overwrite` does not authorize re-scaffolding an existing project.

Helper upgrades require a manifest and a clean working tree. Eligibility is checked before AI writes, so the AI update itself does not invalidate that check. If a missing manifest or dirty tree blocks helpers, the root AI update can still proceed, but the combined upgrade returns a nonzero status and explains the skipped helper work. Address that reported condition and rerun. `--force` bypasses only the helper clean-tree guard, never provenance or path checks.

## Ownership and replacement

| Asset | Maintenance behavior |
| --- | --- |
| Currently distributed Claude assets, applicable Codex skills, shared workflow contracts and erd projection | Install the effective upstream/sidecar content; verify a backup before replacing differing existing bytes; restore missing distributed files |
| `.claude/settings.json` and applicable `.codex/config.toml` | Replace the complete file from the selected distribution after backing up differing existing bytes, including custom keys; no JSON/TOML merge |
| Application source, tests, docs, build/package files, Docker/CI files, root instructions and `post.sh` | Developer-owned scaffold seeds; maintenance never overwrites or prunes them |
| `.devcontainer/scripts/*.sh` helpers other than `post.sh` | Upgrade only with proven installed provenance and unchanged content; updater migration has the additional rules below |
| `.tarnished/agent-profile.json`, `refresh.json`, native local settings, extra sibling files and configured `.local` sidecars | Project-owned; preserve |
| Manifest and refresh state | Record successful installation/adoption; never inventory the entire project as owned |
| `.tarnished/backups/` | Private recovery storage; excluded from refresh and manifest/prune ownership, including custom broad mappings |

Distribution candidates are enumerated upstream, never by recursively replacing destination directories. Edited or unknown legacy files at a currently distributed AI destination are backed up and replaced. Matching bytes are an idempotent no-op. Previous user deletion does not suppress installation of a currently distributed AI file. Unsafe paths, failed backups and detected concurrent changes preserve the live file and prior baseline and are reported.

Only a proven unchanged upstream-origin file may be removed after verified upstream disappearance. Unknown/custom obsolete files and overlay-origin files are preserved. Removed or reconfigured mappings preserve former files. Project-added sibling files are preserved even inside managed directories. `.tarnished/refresh-state.json` records successful installed/adopted hashes; it does not grant ownership over unrelated files. Repeated runs reconcile content even when the upstream commit is unchanged.

Settings use the selected distribution's existing values, without introducing new model IDs. Because replacement covers the entire settings file, a project-specific model or other key inside that file is backed up and replaced. Profile selection and role/model overrides in `.tarnished/agent-profile.json` remain unchanged.

## Backups and restoration

Before replacing differing existing content, refresh prepares the candidate, copies the original bytes into a unique private `.tarnished/backups/refresh.XXXXXX/` directory and verifies the backup. The original relative path is retained: a settings backup ends in `.codex/config.toml` or `.claude/settings.json`. The updater rechecks file/path boundaries and content before replacement. A failed backup or detected in-flight edit prevents replacement; prior backups survive retries and later failures.

Use the exact backup and restore command reported by the update. For example, a reported `.tarnished/backups/refresh.A1b2C3/.claude/settings.json` can be restored from the project root with:

```bash
cp .tarnished/backups/refresh.A1b2C3/.claude/settings.json .claude/settings.json
```

Substitute your actual reported path. The next refresh, including container start, may replace the restored live file again. Save lasting changes through the customization mechanisms below before refreshing again. Backups are never automatically pruned. They may contain sensitive settings; keep them out of version control and manage retention yourself. Maintenance does not rewrite an existing project's `.gitignore`.

## Customization

Configured whole-file `.local` sidecars remain effective. For example:

```bash
mkdir -p .claude/commands.local/erd
cp .claude/commands/erd/brainstorm.md .claude/commands.local/erd/brainstorm.md
$EDITOR .claude/commands.local/erd/brainstorm.md
bash /path/to/tarnished/setup.sh --refresh -y
```

The sidecar supplies the desired live file; a differing live file is backed up before replacement. Removing a sidecar restores the upstream candidate on refresh, backing up differing live content first. Overlay-only added files are supported; if both upstream and sidecar disappear, overlay-origin live files are preserved.

Claude erd commands and the Codex-readable erd projection have separate sidecars. Duplicate shared overrides into `.tarnished/workflows/erd.local/`. Codex skills use `.agents/skills.local/`; shared contracts use `.tarnished/workflows.local/<file>.md`. The Codex gitignore whitelist keeps `.agents/skills.local` local and ignored. To share it, append `!.agents/skills.local/` and `!.agents/skills.local/**` after the existing Codex block, leaving block markers unchanged.

Use a CLI's native local configuration mechanism for settings it supports; those files remain project-owned. Native local settings are **not** whole-file replacement sidecars, and refresh does not merge their partial configuration into a distributed file. In particular, `.claude/settings.local.json` is not used as a replacement for `.claude/settings.json`. Do not assume a `.codex/config.local.toml` filename has native CLI support. To override an entire distributed settings file, explicitly configure a separate whole-file `overlay` path in your project's `refresh.json` mapping, keeping it outside the live destination and under a `.local` sidecar path. With a custom catalog, retain any other mappings you still want updated.

## Catalog and profile selection

`.tarnished/refresh.json` selects the upstream repository, branch, cache and managed mappings. The shipped catalog covers Claude assets and settings, applicable Codex skills and settings, shared workflow `.md` contracts, and the separate erd projection. Claude/shared assets are available for every existing profile. Codex updates require a Codex profile, manifest capability or existing ordinary Codex settings/skills installation.

`use_default_managed_paths: true` adopts the validated upstream catalog so new distributed mappings can be added while project settings remain intact. When an older selected distribution catalog lacks the settings mappings, current setup adds those mandatory mappings while keeping candidate file contents from the selected distribution. An absent/false value keeps explicit `managed_paths` authoritative, including an empty list. To use custom overlays, maintain an explicit custom catalog with `use_default_managed_paths: false`; see the [shipped catalog](../templates/agent-workflows/.tarnished/refresh.json) for mapping structure. Runtime refresh never rewrites configuration.

## Existing installations

Run the current `setup.sh --refresh --dry-run`, inspect its plans, then run `--refresh -y` (or root `--upgrade`). Current setup creates missing refresh configuration and migrates only exactly recognized shipped legacy catalogs whose opt-in key is absent. It preserves other fields and explicit `false`, even if the list matches a legacy default. Custom catalogs remain authoritative; explicitly add desired mappings, including settings, or opt into the default catalog.

Current setup also safely migrates a missing helper, an exactly recognized shipped legacy helper, or an unchanged helper with a trusted version-2 installed baseline to its current updater and records that baseline. An edited/unrecognized installed `.devcontainer/scripts/refresh-assets.sh` is preserved and its source/destination paths are reported. **Review and explicitly copy the current helper to the reported destination before the next container start.** A successful one-shot refresh uses the current updater but does not change an unrecognized installed updater's future behavior. Preserve any intended custom helper logic separately before that explicit migration.

A missing helper with a recorded baseline or deletion intent stays absent. Installing a previously missing helper only installs the file: inspect `post.sh` and `devcontainer.json` to establish its invocation if needed. Setup maintenance does not add container-start wiring automatically. Files deleted by older scripts cannot be recovered through provenance migration.

Container starts use the installed updater and configured upstream. For the shipped `/opt/tarnished` cache only, if it is absent and `/opt` is unwritable, refresh uses the validated `~/.cache/tarnished` fallback. Existing unsafe, dirty or unrelated caches are preserved. Runtime failures warn with recovery instructions and return success so the container can start; unknown CLI flags return an error.

Dry-run creates no target files, configuration, state, backups, summary or persistent cache and suppresses Git index refresh writes. It uses a valid local source/cache for exact plans; if none exists, it reports that comparison is unavailable. Actual summaries distinguish installed, unchanged/adopted, backed-up, preserved/unsafe and failed outcomes. Generated refresh state should be ignored if `.tarnished/refresh-state.json` is not already in your ignore rules.

## Runtime-helper provenance

To adopt eligible helpers in a project without a manifest:

```bash
bash /path/to/tarnished/setup.sh --create-manifest -y
# Optionally compare bytes against an available historical distribution.
bash /path/to/tarnished/setup.sh --create-manifest --from-version <ref> -y
```

Manifest upgrades only handle delivered `.devcontainer/scripts/*.sh` helpers other than `post.sh`; AI assets/settings use refresh instead. Plugins stage privately and do not replay post-copy hooks against your project. Version-2 manifests record successful installed or exact distribution matches. Fresh scaffolding records successful copies and rehashes after rendering. Bootstrap compares eligible staged candidates without walking the project to infer ownership.

Version-1 claims are untrusted: source/settings and unknown obsolete files are preserved and their claims dropped; only exact eligible distribution matches can be adopted. A ref name or old manifest hash alone is insufficient. Edited/deleted helpers retain their baseline, and upstream removals remain until explicitly pruned. Missing legacy helpers retain `deleted_paths` tombstones across bootstrap, upgrade and refresh. Restore an exact distribution copy to adopt such a path again. These conservative helper rules do not suppress replacement of currently distributed AI files.
