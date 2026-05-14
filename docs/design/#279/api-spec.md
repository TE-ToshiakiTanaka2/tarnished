# API Specification: #279 always-latest sync for shared Claude/Codex assets

## Endpoints / Functions (delta)

### CLI: `refresh-assets.sh`

```
Usage: refresh-assets.sh [--config <path>] [--dry-run] [--force-pull] [--quiet]
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `--config <path>` | path | `$(repo_root)/.tarnished/refresh.json` | Override the whitelist config location. |
| `--dry-run` | flag | off | Print intended actions; perform no `git pull` or `rsync`. |
| `--force-pull` | flag | off | Skip the `git ls-remote` SHA cache check; always fetch + reset. |
| `--quiet` | flag | off | Suppress per-path "no change" lines; warnings still print. |

Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Always returned for non-fatal paths (success, skipped, warnings, network failure with cache hit). |
| 1 | Reserved — only used if invoked with an unknown flag (CLI argument error). |

### Bash function (when sourced into `post.sh`)

```bash
refresh_assets()
```

| Aspect | Detail |
| --- | --- |
| Args | none |
| Returns | always `0` (FR-5 invariant; container start MUST NOT block). |
| Side effects | clones / pulls `<clone_dir>`; `rsync`s into `<project>/<dst>` paths; emits `print_*` to stderr. |
| Reads env | `DEVCONTAINER_REPO_URL`, `DEVCONTAINER_BRANCH` (override `refresh.json` defaults). |
| Reads file | `.tarnished/refresh.json`. |

When invoked standalone (`postStartCommand`), the script wires up the
same logic without depending on `scripts/lib/common.sh` being sourced
(it defines minimal `print_*` fallbacks).

### `MANIFEST_EXCLUDE_GLOBS` extension (`scripts/lib/common.sh`)

The constant gains 16 additional patterns (8 always-latest paths + 8
`*.local/` overlay sidecars). The patterns are documented in
`design.md :: "MANIFEST_EXCLUDE_GLOBS extension"`. Plugin authors do
not interact with this list directly — `copy_with_confirm` consults it
transparently.

The list extension is invariant-preserving:

- A path matched by the new entries was previously eligible for
  `--upgrade` tracking. After this issue, it is not. Any user who has
  edited `.claude/commands/erd/foo.md` in a project scaffolded before
  #279 will find the file overwritten on first container start
  post-upgrade. This is intentional and documented in the migration
  notes.

### `templates/agent-workflows/.tarnished/refresh.json` (new file, distributed)

Schema version 1. Distributed verbatim by `templates/agent-workflows/plugin.sh`
into `<target>/.tarnished/refresh.json`.

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `schema_version` | integer | yes | Currently `1`. Readers MUST reject unknown majors. |
| `upstream.repo_url` | string | yes | git URL of upstream tarnished. Default: `https://github.com/TE-ToshiakiTanaka2/tarnished.git`. Env-overridable via `DEVCONTAINER_REPO_URL`. |
| `upstream.branch` | string | yes | Branch ref. Default: `develop`. Env-overridable via `DEVCONTAINER_BRANCH`. |
| `clone_dir` | string | yes | Absolute path. Default: `/opt/tarnished`. Falls back to `${HOME}/.cache/tarnished` if the parent is not writable. |
| `managed_paths` | array | yes | List of `{src, dst, overlay}` triples. May be empty (script becomes a no-op). |
| `managed_paths[].src` | string | yes | Path within the upstream clone, relative to clone root. |
| `managed_paths[].dst` | string | yes | Path within the project, relative to project root. |
| `managed_paths[].overlay` | string \| null | yes | Path within the project for the user-owned sidecar. `null` disables overlay for that path. |

Default `managed_paths`:

| `src` | `dst` | `overlay` |
| --- | --- | --- |
| `.claude/commands` | `.claude/commands` | `.claude/commands.local` |
| `.claude/skills`   | `.claude/skills`   | `.claude/skills.local`   |
| `.claude/scripts`  | `.claude/scripts`  | `.claude/scripts.local`  |
| `.claude/rules`    | `.claude/rules`    | `.claude/rules.local`    |

Forward compatibility: unknown top-level keys ignored; `schema_version`
is the breaking-change escape hatch. Per-path additions (e.g.,
`exclude_globs`) are non-breaking.

### `templates/core/.devcontainer/devcontainer.json` (modified)

Adds one key:

```json
"postStartCommand": "bash .devcontainer/scripts/refresh-assets.sh || true"
```

Pre-existing `postCreateCommand` unchanged.

### `templates/claude/plugin.sh` — new responsibilities

`plugin_copy(target_dir)` gains:

```bash
if [[ -d "${PLUGIN_DIR}/.claude/rules" ]]; then
    copy_dir_with_confirm "${PLUGIN_DIR}/.claude/rules" "${target_dir}/.claude/rules"
fi
```

`plugin_post_copy(target_dir)` is unchanged (the post.sh wiring lives
in `templates/core/plugin.sh::plugin_post_copy` because the refresh
mechanism is core, not Claude-specific).

### `templates/core/plugin.sh::plugin_post_copy` — new responsibility

Append a marker-guarded block to `<target>/.devcontainer/scripts/post.sh`:

```bash
local refresh_marker="# Tarnished Asset Refresh"
if [[ -f "$post_sh" ]] && ! grep -q "$refresh_marker" "$post_sh"; then
    cat >> "$post_sh" << 'EOF'

# -----------------------------------------------------------------------------
# Tarnished Asset Refresh
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "${SCRIPT_DIR}/refresh-assets.sh" ]]; then
    "${SCRIPT_DIR}/refresh-assets.sh" || true
fi
EOF
fi
```

Idempotency contract: same line-anchored marker pattern as `# Codex CLI Setup`
(`templates/codex/plugin.sh:113-128`) and `# Claude Code Plugin Setup`
(`templates/claude/plugin.sh:113-129`). Block-level idempotency per
`shared/architecture.md :: "Cross-cutting Concerns / Idempotency"`.

### `templates/agent-workflows/plugin.sh` — extended copy

Already copies `.tarnished/{agent-profile.json, workflows/}`. Add
`refresh.json` to the verbatim copy set. The plugin's existing
`copy_dir_with_confirm "${PLUGIN_DIR}/.tarnished" "${target_dir}/.tarnished"`
already picks it up since it's a recursive directory copy — no plugin
code change required, only the new file in `templates/agent-workflows/.tarnished/refresh.json`.

## Input/Output Schemas

### `refresh-assets.sh` summary line (stdout, success)

Format: `[OK] refresh-assets: <N> paths synced (<A> files added, <R> removed); <O> overlay files preserved`

Example: `[OK] refresh-assets: 4 paths synced (12 files added, 3 removed); 2 overlay files preserved`

When upstream is unchanged: `[OK] refresh-assets: upstream unchanged (sha=<short>)`

### `refresh-assets.sh` warning line (stderr)

Format follows `print_warning`: `[WARN] refresh-assets: <reason>`

Examples:
- `[WARN] refresh-assets: ls-remote failed (network unreachable); using cached upstream@<short>`
- `[WARN] refresh-assets: rsync of .claude/commands failed (exit 23); skipping`
- `[WARN] refresh-assets: refresh.json missing at .tarnished/refresh.json; nothing to sync`

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| `refresh.json` missing | `print_warning`, exit 0 | One-time guidance line; downstream may not have opted in |
| `refresh.json` malformed | `print_warning`, exit 0 | jq parse failure; no sync performed this run |
| `refresh.json` `schema_version > 1` | `print_warning`, exit 0 | Reader rejects; downstream must update tarnished |
| `git clone` fails | `print_warning`, exit 0 | Network unreachable on first boot; project keeps original scaffolded bytes |
| `git ls-remote` fails | `print_warning`, exit 0 | Transient; cached `<clone_dir>` used as-is |
| `git fetch` / `git reset --hard` fails | `print_warning`, exit 0 | Cache untouched (fetch is atomic; reset only runs after successful fetch) |
| `rsync` fails for a managed path | `print_warning` (per path), exit 0 | Sibling paths still attempted |
| `<clone_dir>` exists but not a git repo | `print_error`, exit 0 | Manual intervention required; do not silently delete |
| `<clone_dir>` parent directory not writable | `print_warning`, fall back to `${HOME}/.cache/tarnished` | One-line guidance to adjust container image if `/opt` is preferred |
| `jq` not on `$PATH` | `print_error`, exit 0 | Suggest `apt-get install jq`; the devcontainer's base image normally provides it |
| Unknown CLI flag | `print_error`, exit 1 | Strict — programmer error |

## Versioning Policy

`refresh.json` carries its own `schema_version` field, current value
`1`. Bumps follow a major-only convention: field additions are
non-breaking by tolerant readers, structural reshapes require a major
bump. Backward compatibility is the responsibility of `refresh-assets.sh`
itself — older scripts running against a newer manifest MUST refuse
gracefully (`print_warning` + exit 0) rather than crash.

The constants `REMOTE_REPO_URL` and `REMOTE_BRANCH` in `setup.sh:25-26`
remain authoritative for the bootstrap `setup.sh | bash` flow. The
identical defaults appear in `refresh.json` so `refresh-assets.sh` is
self-contained and works without sourcing `setup.sh`.
