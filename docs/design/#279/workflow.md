# Workflow: #279 always-latest sync for shared Claude/Codex assets

## Implementation Steps

### Step 1 — Move `shell.md` into the Claude template

1. `mkdir -p templates/claude/.claude/rules`
2. `git mv .claude/rules/shell.md templates/claude/.claude/rules/shell.md`
3. Recreate the workspace symlink/copy: keep `/workspace/.claude/rules/shell.md`
   identical to the template (workspace dogfooding per `shared/architecture.md ::
   "Cross-cutting Concerns / Workspace Codex dogfooding"`). The simplest
   approach is `cp templates/claude/.claude/rules/shell.md .claude/rules/shell.md`
   (preserving as a regular file — symlinks confuse rsync `--delete` later).

### Step 2 — Distribute `.claude/rules/` from the Claude plugin

1. In `templates/claude/plugin.sh::plugin_copy`, after the existing
   `commands/`, `skills/`, `scripts/` blocks, add:
   ```bash
   if [[ -d "${PLUGIN_DIR}/.claude/rules" ]]; then
       copy_dir_with_confirm "${PLUGIN_DIR}/.claude/rules" "${target_dir}/.claude/rules"
   fi
   ```
2. No `plugin_post_copy` change here — `.claude/rules/` is plain text,
   no merge logic needed.

### Step 3 — Author `templates/agent-workflows/.tarnished/refresh.json`

Create the file with the schema documented in `api-spec.md`. The
existing `templates/agent-workflows/plugin.sh` already does
`copy_dir_with_confirm "${PLUGIN_DIR}/.tarnished" "${target_dir}/.tarnished"`
(verbatim recursive copy), so the new file is picked up automatically.

### Step 4 — Author `templates/core/.devcontainer/scripts/refresh-assets.sh`

The full ~250-line script. Breakdown:

1. Header: shebang `#!/bin/bash`, `set -euo pipefail`, comment block.
2. Local `print_*` helpers (so the script works when sourced from
   `post.sh` *or* invoked standalone by `postStartCommand`).
3. Argument parsing: `--config`, `--dry-run`, `--force-pull`, `--quiet`.
4. `load_config`: locate and parse `refresh.json` via `jq`.
5. `ensure_clone`: clone-if-missing logic; permission fallback to
   `${HOME}/.cache/tarnished`.
6. `check_upstream`: `git ls-remote` SHA cache check.
7. `fetch_upstream`: `git fetch` + `git reset --hard origin/<branch>`.
8. `sync_paths`: per-`managed_paths[]` entry, two-pass `rsync`
   (base `--delete`, then overlay no-delete).
9. `print_summary`: structured one-line report.
10. `main`: orchestration with the FR-5 always-return-0 invariant.

### Step 5 — Wire `refresh_assets` into `post.sh`

In `templates/core/plugin.sh::plugin_post_copy`, append the
marker-guarded block per `api-spec.md :: "templates/core/plugin.sh::plugin_post_copy"`.

Justification for placing in `core` (not `claude`): the refresh
mechanism is universal infrastructure. A non-Claude scaffold gets the
script + an empty `managed_paths` and the script is a no-op.

### Step 6 — Add `postStartCommand` to `devcontainer.json`

`templates/core/.devcontainer/devcontainer.json:38` — append the new
key. Use `|| true` defense-in-depth even though the script returns 0.

### Step 7 — Extend `MANIFEST_EXCLUDE_GLOBS`

`scripts/lib/common.sh:126-138` — add the 16 new entries documented in
`design.md :: "MANIFEST_EXCLUDE_GLOBS extension"`.

This makes `--upgrade` automatically exclude always-latest paths from
manifest tracking. No further `--upgrade` change needed.

### Step 8 — Workspace dogfooding

Mirror the template into the workspace:

1. Copy `templates/core/.devcontainer/scripts/refresh-assets.sh` →
   `/workspace/.devcontainer/scripts/refresh-assets.sh` (with executable bit).
2. Copy `templates/agent-workflows/.tarnished/refresh.json` →
   `/workspace/.tarnished/refresh.json` (creating `/workspace/.tarnished/`
   if absent).
3. Add `postStartCommand` to `/workspace/.devcontainer/devcontainer.json`.
4. Append the marker-guarded block to `/workspace/.devcontainer/scripts/post.sh`.

The workspace and the template MUST stay byte-identical (modulo
absolute paths). Mirrors the `setup_codex.sh` dogfooding pattern from
#261.

### Step 9 — Tests

Create `tests/refresh_assets.bats`:

1. Set up a local bare-repo as "upstream" (so SHA progression is
   deterministic without network).
2. **Happy path — first run**: `clone_dir` absent → script clones,
   syncs, returns 0.
3. **Happy path — no change**: identical SHA → script returns 0 with
   "upstream unchanged" line, no `rsync` invoked.
4. **Happy path — upstream advanced**: SHA differs → fetch + reset +
   rsync; verify file content updated.
5. **Overlay precedence**: write `<dst>.local/<file>` → after refresh,
   target path contains overlay content even though base path was
   `--delete`d.
6. **Offline first-boot**: clone fails → warning + exit 0; project
   keeps original scaffolded bytes.
7. **Offline subsequent run**: `ls-remote` fails → warning + cache
   used as-is.
8. **`<clone_dir>` not a git repo**: error printed, exit 0, no destructive action.
9. **`refresh.json` malformed**: warning + exit 0.
10. **Permission fallback**: `clone_dir=/opt/...` not writable → falls back
    to `${HOME}/.cache/tarnished`.

Extend `tests/setup_upgrade.bats`:

1. Assert always-latest paths are not present in `.tarnished-manifest.json`
   after `--upgrade`.
2. Assert that user-edited `<dst>.local/` files survive `--upgrade`.

### Step 10 — Documentation

1. `README.md`: add a "Always-latest assets" section explaining the
   override convention (`.local/` sidecars).
2. `templates/claude/CLAUDE.md`: document the `.local/` convention so
   downstream users see it in their first Claude Code session.
3. `AGENTS.md` (the workspace's tarnished-specific one): briefly
   reference the mechanism so review agents understand the
   `.local/` semantics.
4. Inline comments only where the WHY is non-obvious (per CLAUDE.md
   coding rules) — particularly around the `reset --hard` choice and
   the FR-5 always-return-0 invariant.

## Task Dependencies

```
Step 1 (move shell.md) ──────────► Step 2 (distribute .claude/rules)
                              │
                              └──► Step 9 test (overlay smoke)

Step 3 (refresh.json) ──┐
Step 4 (refresh-assets.sh) ──┼─► Step 5 (post.sh wiring)
Step 6 (postStartCommand) ───┘
                                  │
                                  └─► Step 8 (workspace dogfooding)
                                                 │
                                                 └─► Step 9 (tests)
                                                          │
                                                          └─► Step 10 (docs)

Step 7 (MANIFEST_EXCLUDE_GLOBS) is independent of Steps 4-6 but
should land in the same PR for atomicity.
```

Critical path: Step 4 (refresh-assets.sh authoring) is the longest
single piece (~250 LoC bash + tests).

## Test Strategy

### Unit tests (`tests/refresh_assets.bats`)

10 cases enumerated in Step 9 above. Use a local bare repo + temp
project tree for full hermetic execution. Run as part of the existing
`bats` test suite.

### Integration tests

Extend `tests/setup_upgrade.bats` with the always-latest exclusion
assertions. The existing harness already creates a scaffolded project
fixture and runs `--create-manifest` + `--upgrade` against it.

### Manual verification (devcontainer rebuild)

After the PR merges, rebuild the workspace devcontainer and verify:

1. `git -C /opt/tarnished log -1` shows the latest develop commit.
2. Modify a command upstream, restart the container, confirm the change
   is reflected in `.claude/commands/erd/<file>.md`.
3. Create `.claude/commands.local/erd/foo.md`, restart container,
   confirm the file survives and overrides.
4. Disconnect network, restart container, confirm container starts and
   `[WARN]` line appears.

### Edge cases to cover

- Both `postCreateCommand` and `postStartCommand` running on first boot
  (idempotent — second invocation hits the SHA cache).
- `setup.sh --upgrade --target-version v0.0.X` against a project that
  has always-latest enabled — manifest excludes don't regress.
- A project upgraded from a pre-#279 manifest (which contains hashes
  for now-excluded paths). Behavior: those entries become stale; next
  `--create-manifest` will produce a clean manifest. The stale entries
  are inert — `manifest_decide` simply doesn't see them in the new
  staging. Documented in migration notes.
- Monorepo: confirm `postStartCommand` runs once at the root devcontainer
  level (the only devcontainer in the monorepo per FR-8).

### Performance verification

Time the no-change path (`postStartCommand` on a container start where
upstream is unchanged): single `git ls-remote` call. Should complete in
well under 1 second on a normal network. Acceptance criterion in the
issue.
