# Design: #279 feat(setup): always-latest sync for shared Claude/Codex assets via DevContainer postStart

## Context

This issue adds a complementary distribution mode to the existing
`setup.sh` template-installer ecosystem. The shared truth lives in:

- `shared/architecture.md :: "Module Structure"` — `templates/{claude,codex,core,agent-workflows}/`
  is copied into downstream projects by `setup.sh` at scaffold time.
- `shared/architecture.md :: "Cross-cutting Concerns / Manifest-driven upgrades (#265)"`
  — `setup.sh --upgrade` already exists with three-hash lifecycle decisions
  (`manifest_decide` 8 cases). It is opt-in and rarely run.
- `shared/api-spec.md :: "setup.sh"` and `:: "scripts/lib/manifest.sh"`
  — `MANIFEST_EXCLUDE_GLOBS` (defined once in `scripts/lib/common.sh:125-139`,
  re-exported by `manifest.sh`) governs which paths participate in
  manifest-tracked upgrades.
- `shared/api-spec.md :: "templates/codex/plugin.sh::plugin_post_copy"`
  and `templates/claude/plugin.sh::plugin_post_copy` — both already use a
  marker-guarded `cat >> post.sh` block to wire their own `setup_*.sh` into
  the post-create hook. Same pattern works for `refresh_assets`.
- `shared/sequence.md :: "Codex CLI: install in devcontainer"` and
  `:: "devcontainer plugin install"` — both flows are sourced into
  `templates/core/.devcontainer/scripts/post.sh` (which runs under `set -e`
  but contractually `return 0`s on non-fatal failure).
- `shared/architecture.md :: "Cross-cutting Concerns / Workspace Codex
  dogfooding (#261)"` — workspace and template are kept in sync; same
  pattern applies to the refresh script.

The relevant slice of `data-model.md` is the `.tarnished-manifest.json`
schema (`shared/data-model.md :: ".tarnished-manifest.json schema"`).
This issue introduces a sibling artifact, `.tarnished/refresh.json`,
that complements the manifest by declaring the always-latest path
whitelist; the two are mutually exclusive per path (FR-7 of #279).

The current state of `templates/agent-workflows/.tarnished/` is
`{agent-profile.json, workflows/}`. Adding `refresh.json` there is
natural: `.tarnished/` is already the project-local container for
tarnished-managed metadata.

The existing `templates/claude/plugin.sh` copies four directories
(`commands/`, `skills/`, `scripts/`, plus the top-level `CLAUDE.md`) into
`<target>/.claude/`. There is currently **no** `templates/claude/.claude/rules/`
directory, so `shell.md` (today only at `/workspace/.claude/rules/shell.md`)
is not distributed. This is the gap FR-6 addresses.

## Architecture Overview (delta)

One new bash script (`templates/core/.devcontainer/scripts/refresh-assets.sh`,
~250 lines), one new declarative whitelist
(`templates/agent-workflows/.tarnished/refresh.json`), one new
distributed rule file (`templates/claude/.claude/rules/shell.md` — moved
from this repo's own `.claude/rules/`), and small targeted edits in
three existing files (`setup.sh`, `templates/core/.devcontainer/scripts/post.sh`
or — more likely — `templates/core/plugin.sh::plugin_post_copy`,
`templates/claude/plugin.sh`).

The runtime model:

```
DevContainer onCreate           DevContainer onStart (every container start)
─────────────────────           ────────────────────────────────────────────
  postCreateCommand                postStartCommand
       │                               │
       └─→ post.sh                     └─→ refresh-assets.sh
            │                                │
            ├─→ setup_plugins                ├─→ git ls-remote upstream HEAD
            ├─→ setup_codex                  ├─→ if SHA changed → git pull
            └─→ refresh_assets (FIRST RUN)   ├─→ rsync --delete  upstream → base
                  │                          ├─→ rsync (no-del)  *.local/ → base
                  └─→ git clone /opt/...     └─→ summary print
```

Two invocation paths:

1. **First container boot after scaffold** — `post.sh` calls
   `refresh_assets` to perform the initial `git clone` of upstream into
   `/opt/tarnished` and the first synchronization pass. (We piggyback on
   `post.sh` rather than relying solely on `postStartCommand` because
   `postCreateCommand` runs before `postStartCommand` on the very first
   boot, and we want the first user-facing Claude Code session to already
   see the latest assets.)
2. **Every subsequent container start** — `postStartCommand` invokes
   `refresh-assets.sh` directly (no `post.sh`), which detects the existing
   clone in `/opt/tarnished`, performs the lightweight `git ls-remote`
   SHA check, and only `git pull`s + syncs when upstream changed.

The two paths converge on the same `refresh-assets.sh` entry point;
the script is idempotent on first run vs. nth run.

### Mutual exclusivity with manifest tracking

`shared/architecture.md :: "Manifest-driven upgrades (#265)"` documents
that `--upgrade` resolves a per-file three-hash decision. For files
governed by always-latest, that decision is irrelevant — they are
unconditionally overwritten on every container start. To prevent the
two mechanisms from fighting, the always-latest path whitelist is
appended to `MANIFEST_EXCLUDE_GLOBS` (in `scripts/lib/common.sh`); this
keeps `--create-manifest` from hashing them and keeps `--upgrade` from
recording them as new.

The exclusion is one-way: a path becomes always-latest by being listed
in `refresh.json`, and is then automatically excluded from the manifest.
Plugin authors do not need to know about this invariant — `copy_with_confirm`
already consults `MANIFEST_EXCLUDE_GLOBS` (at `scripts/lib/common.sh:163-174`).

### Override mechanism (`.local/` overlay)

Per FR-4, users override an upstream skill or command by creating a
sidecar file at `.claude/commands.local/<path>` mirroring the upstream
layout under `.claude/commands/<path>`. `refresh-assets.sh` performs a
two-pass rsync per managed directory:

```
  pass 1:  rsync --delete  /opt/tarnished/<src>/   <project>/<dst>/
  pass 2:  rsync           <project>/<dst>.local/  <project>/<dst>/
```

Pass 2 omits `--delete`, so files in `<dst>.local/` overlay the base.
A user who wants to fully replace `commands/erd/brainstorm.md` writes
`.claude/commands.local/erd/brainstorm.md`; everything else in
`commands/` keeps tracking upstream.

`.local/` directories are user-owned and are added to
`MANIFEST_EXCLUDE_GLOBS` as well (so `--upgrade` never touches them).

## Module Structure (delta)

```
templates/
├── agent-workflows/
│   └── .tarnished/
│       └── refresh.json                                # NEW — whitelist + overlay declaration
├── claude/
│   └── .claude/
│       └── rules/                                      # NEW dir (was missing in templates)
│           └── shell.md                                # NEW — moved from /workspace/.claude/rules/shell.md
└── core/
    └── .devcontainer/
        └── scripts/
            └── refresh-assets.sh                       # NEW — ~250 LoC bash; the entry point
```

Modified files:

| File | Change |
| --- | --- |
| `templates/core/.devcontainer/devcontainer.json` | Add `postStartCommand` invoking `refresh-assets.sh`. Single-line JSON addition. |
| `templates/agent-workflows/plugin.sh` | Copy `.tarnished/refresh.json` into target `.tarnished/` (the directory is already copied verbatim today). |
| `templates/claude/plugin.sh` | (a) Copy new `templates/claude/.claude/rules/` into `<target>/.claude/rules/`. (b) Wire `refresh_assets` into `post.sh` via marker-guarded block (same pattern as Codex's `# Codex CLI Setup` integration at `templates/codex/plugin.sh:111-128`). |
| `scripts/lib/common.sh` | Extend `MANIFEST_EXCLUDE_GLOBS` (lines 126-138) with always-latest paths from `refresh.json` plus all `*.local/` siblings. |
| `setup.sh` | (a) On scaffold, ensure `refresh-assets.sh` is executable and the marker block is in `post.sh`. (b) `--upgrade` excludes always-latest paths from manifest tracking automatically via the extended `MANIFEST_EXCLUDE_GLOBS` — no further `--upgrade` change needed. |
| `/workspace/.claude/rules/shell.md` | Moved → `templates/claude/.claude/rules/shell.md`. The workspace one becomes a *copy* of the template (workspace dogfooding, mirroring `#261`). |
| `tests/refresh_assets.bats` (new) | Unit tests for refresh-assets.sh: SHA cache hit/miss, overlay precedence, offline fallback, whitelist enforcement. |
| `tests/setup_upgrade.bats` (existing) | Add cases asserting always-latest paths are excluded from manifest after upgrade. |
| `README.md`, `templates/claude/CLAUDE.md` | Document `.local/` override directories. |

## Interface Design (delta)

### `refresh.json` schema

`templates/agent-workflows/.tarnished/refresh.json`:

```json
{
  "schema_version": 1,
  "upstream": {
    "repo_url": "https://github.com/TE-ToshiakiTanaka2/tarnished.git",
    "branch": "develop"
  },
  "clone_dir": "/opt/tarnished",
  "managed_paths": [
    { "src": ".claude/commands",   "dst": ".claude/commands",   "overlay": ".claude/commands.local" },
    { "src": ".claude/skills",     "dst": ".claude/skills",     "overlay": ".claude/skills.local" },
    { "src": ".claude/scripts",    "dst": ".claude/scripts",    "overlay": ".claude/scripts.local" },
    { "src": ".claude/rules",      "dst": ".claude/rules",      "overlay": ".claude/rules.local" }
  ]
}
```

`upstream.repo_url` and `upstream.branch` default to the same constants
`setup.sh` uses (`REMOTE_REPO_URL`, `REMOTE_BRANCH`); environment
variables `DEVCONTAINER_REPO_URL` and `DEVCONTAINER_BRANCH` continue to
override (consistent with `setup.sh:25-26`).

`managed_paths[].src` is relative to the upstream clone root. For Claude
assets, `src == dst` (path-symmetric). The schema accepts asymmetry for
future flexibility (e.g., promoting a workspace-only asset into a
template path during distribution).

`managed_paths[].overlay` is the user-owned sidecar directory. Set to
`null` (or omit the key) to disable overlay for a particular path.

`.codex/config.toml` is **not** in the initial whitelist. Codex config
is currently a single file that downstream projects may legitimately
customize (e.g., to lock a model). Including it would force users to
adopt `.codex/config.local.toml` as the only safe override. We surface
this as an Open Question (below) — including it can be a fast-follow
once the override convention is socialized.

### `refresh-assets.sh` contract

```
Usage: refresh-assets.sh [--config <path>] [--dry-run] [--force-pull] [--quiet]

Options:
  --config <path>   Path to refresh.json. Default: <repo_root>/.tarnished/refresh.json
  --dry-run         Print actions; don't pull or rsync.
  --force-pull      Skip the `git ls-remote` SHA cache check; always pull.
  --quiet           Suppress per-path "no change" messages; warnings still print.
```

Behavior (full decision tree in `flowchart.md`):

1. Locate `refresh.json` (CLI arg, then `.tarnished/refresh.json`, then
   skip with a single `print_warning` if absent).
2. Read `upstream.repo_url`, `upstream.branch`, `clone_dir`.
3. If `<clone_dir>/.git` does not exist:
   - First-boot path: `git clone --depth 1 --branch <branch> <repo_url>
     <clone_dir>`. On failure (no network, repo unreachable), print a
     clear warning and exit 0. The project keeps the bytes already
     installed by `setup.sh`.
4. Else (cache exists):
   - Run `git -C <clone_dir> ls-remote origin <branch>` → upstream SHA.
   - Read `git -C <clone_dir> rev-parse HEAD` → local SHA.
   - If equal AND `--force-pull` not set: print one-line "no change"
     summary and exit 0.
   - Else: `git -C <clone_dir> fetch origin <branch>` then
     `git -C <clone_dir> reset --hard origin/<branch>`. (We use `reset --hard`
     because `/opt/tarnished` is treated as an immutable mirror — local
     edits are never expected and would silently shadow upstream.)
5. For each `managed_paths[]` entry:
   - `rsync -a --delete <clone_dir>/<src>/ <project_root>/<dst>/`
   - If `<project_root>/<overlay>/` exists:
     `rsync -a <project_root>/<overlay>/ <project_root>/<dst>/`
6. Emit a structured summary line: `[OK] refresh-assets: 4 paths
   synced (123 files added, 5 removed); 2 overlay files preserved`.

All failures (clone, pull, rsync) → `print_warning` and exit 0.
Container start MUST NOT block on this script (FR-5).

Output convention follows `shared/architecture.md :: "Cross-cutting
Concerns / Plugin failures"`: `print_info`, `print_success`,
`print_warning`, `print_error`, sourced from
`scripts/lib/common.sh` when sourced by `post.sh`. When invoked
standalone via `postStartCommand`, the script defines minimal local
fallbacks (so it can run before `scripts/lib/common.sh` is available
on a downstream project).

### `MANIFEST_EXCLUDE_GLOBS` extension

`scripts/lib/common.sh:126-138`:

```bash
MANIFEST_EXCLUDE_GLOBS=(
    # ... existing entries unchanged ...
    # Always-latest paths (managed by refresh-assets.sh, #279):
    ".claude/commands"
    ".claude/commands/*"
    ".claude/skills"
    ".claude/skills/*"
    ".claude/scripts"
    ".claude/scripts/*"
    ".claude/rules"
    ".claude/rules/*"
    # User-owned overlay sidecars (never tracked):
    ".claude/commands.local"
    ".claude/commands.local/*"
    ".claude/skills.local"
    ".claude/skills.local/*"
    ".claude/scripts.local"
    ".claude/scripts.local/*"
    ".claude/rules.local"
    ".claude/rules.local/*"
)
```

Both the directory and `dir/*` forms are included so `_manifest_path_excluded`
(which uses bash glob match at `scripts/lib/common.sh:166-174`) catches
both the directory itself and every file under it.

### `templates/claude/plugin.sh` post.sh wiring

Insert a new marker-guarded block after the existing setup_plugins
block (mirrors the Codex pattern at `templates/codex/plugin.sh:113-129`):

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

The trailing `|| true` is required because `post.sh` runs under
`set -e`; the script itself returns 0 on all non-fatal paths, but the
extra guard is consistent with how `setup_plugins` and `setup_codex`
are invoked (`source` inside an `if [[ -f ... ]]` shell, with each
inner function `return 0`-ing).

Choice: integrate via `templates/core/plugin.sh` rather than
`templates/claude/plugin.sh`. Rationale: `refresh-assets.sh` and
`refresh.json` distribute *core* infrastructure that benefits *every*
scaffolded project, not just ones that selected the Claude flavor.
However, the actual `managed_paths` today all live under `.claude/`, so
moving the integration into `templates/claude/plugin.sh` is also
defensible. Decision: ship via `templates/core/plugin.sh::plugin_post_copy`
so the mechanism is universal even if the initial whitelist happens to
be Claude-only. The `refresh.json` whitelist can be empty (or absent) for
non-Claude scaffolds — `refresh-assets.sh` is a no-op in that case.

### `devcontainer.json` postStart wiring

`templates/core/.devcontainer/devcontainer.json:38` currently has only
`postCreateCommand`. Add:

```json
"postStartCommand": "bash .devcontainer/scripts/refresh-assets.sh || true"
```

The `|| true` is defense in depth — `refresh-assets.sh` already always
returns 0, but a missing-script case (e.g., manifest skipped the file)
should not turn the container yellow in the VS Code Dev Containers UI.

## Data Flow

System-wide flow added to `shared/sequence.md` (Phase 7, see
`Always-Latest Asset Refresh` section). Issue-local decision tree in
`flowchart.md`.

Three-state lifecycle of `/opt/tarnished`:

```
absent ──first refresh──> cloned@<sha>
                              │
                              ├─upstream unchanged──> cloned@<sha>      (no-op)
                              │
                              ├─upstream advanced───> cloned@<new_sha>  (pull + sync)
                              │
                              └─network offline────> cloned@<old_sha>   (warning, use cache)
```

## Error Handling

| Condition | Action | Severity |
| --- | --- | --- |
| `refresh.json` missing or unparseable | `print_warning` once, exit 0 | warning |
| `git clone` fails on first boot (network unreachable, DNS) | `print_warning`, exit 0; project keeps original scaffolded bytes | warning |
| `git ls-remote` fails (transient network) | `print_warning`, fall through to use cached `/opt/tarnished` as-is | warning |
| `git fetch` / `git reset --hard` fails | `print_warning`, exit 0 (cache untouched) | warning |
| `rsync` fails for a managed path | `print_warning` for that path; continue with siblings; exit 0 | warning |
| `<clone_dir>` exists but is not a git repo | `print_error`, exit 0 (do not silently nuke). Message tells user to delete manually. | error-but-non-blocking |
| Overlay path collides with sync that writes the same file (rsync no-delete pass overlays cleanly) | not an error — overlay always wins | n/a |
| `jq` not installed | `print_error`, exit 0; suggest install | error-but-non-blocking |

All paths preserve container start. `post.sh` and `postStartCommand`
both treat `refresh-assets.sh` as informational. This matches the
design principle for `setup_plugins` and `setup_codex`: container
boot must be robust to an offline / degraded upstream.

## Implementation Notes

- **Permissions**: `/opt/tarnished` is owned by the `vscode` user
  inside the devcontainer (default `remoteUser` in
  `templates/core/.devcontainer/devcontainer.json:37`). The script's
  first-clone code does `mkdir -p "$(dirname "$clone_dir")"` only when
  `$clone_dir` is under `$HOME` or `/tmp`; for `/opt/tarnished` it
  expects the parent to exist (the Dockerfile-base image provides
  `/opt`). On `mkdir` permission failure the script falls back to
  `${HOME}/.cache/tarnished` and proceeds. This is announced via
  `print_warning` so users can adjust their image.

- **`reset --hard` rationale**: We treat `/opt/tarnished` as an
  immutable mirror. Users who want to test a local upstream patch
  should set `DEVCONTAINER_REPO_URL=file:///path/to/their/clone`.
  This avoids the complexity of merging local commits into the cache.

- **First-boot ordering**: On the very first container boot,
  `postCreateCommand` (which runs `post.sh` → `refresh_assets`)
  executes *before* `postStartCommand`. So the first `refresh-assets.sh`
  call comes from `post.sh` — this is desirable because the first
  Claude Code session sees the latest assets immediately. On all
  subsequent starts, only `postStartCommand` runs.

- **Idempotency**: `refresh-assets.sh` is fully idempotent. Running
  it twice in a row with no upstream change is a no-op.
  Running it after `setup.sh --upgrade` is also a no-op for tracked
  paths because `--upgrade` excludes always-latest paths from manifest
  application.

- **Single-source-of-truth for `MANIFEST_EXCLUDE_GLOBS`**: Today the
  exclusion list is hardcoded in `scripts/lib/common.sh`. We do *not*
  read it from `refresh.json` at runtime — keeping the list static
  preserves the property that `setup.sh` from any version of tarnished
  knows what to exclude without parsing project-local JSON. The
  `refresh.json` whitelist is the runtime contract for `refresh-assets.sh`;
  the `MANIFEST_EXCLUDE_GLOBS` extension is the build-time contract
  for `--upgrade`. They are kept in sync by code review (and by a
  test that asserts the `refresh.json` defaults are a subset of
  `MANIFEST_EXCLUDE_GLOBS`).

- **Workspace dogfooding**: Per #261's pattern, the workspace itself
  carries `/workspace/.devcontainer/scripts/refresh-assets.sh` and
  `/workspace/.tarnished/refresh.json`. Updates to the template MUST
  be applied to the workspace copy in the same commit. The workspace's
  `devcontainer.json` adds the same `postStartCommand`.

- **Test harness**: `tests/refresh_assets.bats` will use a local
  bare-repo as the "upstream" so SHA progression and offline fallback
  can be exercised deterministically without network. The harness
  pattern from `tests/setup_upgrade.bats` (clone-and-stage) is reused.

- **No `pinned-version` support in this issue**: Per the issue's open
  question, we ship always-`develop`. The `refresh.json` schema's
  `upstream.branch` field is the natural extension point — a future
  issue can add `upstream.pinned_commit` without breaking the
  schema.
