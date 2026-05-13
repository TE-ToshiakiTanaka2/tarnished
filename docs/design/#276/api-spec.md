# API Specification: #276 fix(setup) bootstrap + gh helper error surfacing

## Modified Surface (delta)

### `setup.sh` — bootstrap exec contract

```bash
# Before (setup.sh:69)
exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"

# After
exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null
```

| Aspect | Before | After |
| --- | --- | --- |
| stdin of exec'd bash | inherited from caller (outer curl pipe when `curl \| bash`) | `/dev/null` |
| Effect on `./setup.sh` (local) | stdin = terminal / inherited | stdin = `/dev/null` (the bootstrap branch only fires on pipe input, so local invocations are unaffected) |
| Effect on `curl \| bash` | curl's residual writes hit a process that has exec'd, race-prone EPIPE printed | curl's writes are not inherited; no terminal noise |

No CLI flag change. No new env var.

### `templates/github-actions/project-integration/plugin.sh` — gh helper contract

| Function | Existing signature | Existing behavior | New behavior |
| --- | --- | --- | --- |
| `check_gh_available` | `() -> 0\|1` | `command -v gh` | unchanged |
| `get_current_repo` | `() -> stdout(owner/repo)` | `gh repo view ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + populated `GH_LAST_ERROR_FILE` |
| `get_current_user` | `() -> stdout(login)` | `gh api user ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + populated `GH_LAST_ERROR_FILE` |
| `get_owner_projects` | `(owner) -> stdout(JSON)` | `gh project list ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + populated `GH_LAST_ERROR_FILE` |
| `get_project_fields` | `(owner, number) -> stdout(JSON)` | `gh project field-list ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + populated `GH_LAST_ERROR_FILE` |
| `get_project_fields_detailed` | `(owner, number) -> stdout(JSON)` | GraphQL via `gh api graphql ... 2>/dev/null`; falls back to `get_project_fields` | delegates to `_gh_run` at each gh invocation; always exits 0; falls back to `get_project_fields`; `GH_LAST_ERROR_FILE` holds the last gh attempt's stderr |

### `_gh_run` (NEW, private)

```bash
# Signature
_gh_run <cmd> [args...]

# Effect
#   - Runs the gh command with stdin from /dev/null and stderr captured
#     to a temp file.
#   - Writes the first line of captured stderr to GH_LAST_ERROR_FILE
#     (truncates first so a success run clears the prior error).
#   - Emits the command's stdout to its own stdout.
#   - Always returns 0.
#   - Degrades gracefully if mktemp is unavailable / GH_LAST_ERROR_FILE
#     is empty: stderr is discarded instead, helpers still run.
```

### `_print_gh_warning` (NEW, private)

```bash
# Signature
_print_gh_warning <prefix>

# Effect
#   - If GH_LAST_ERROR_FILE exists and is non-empty:
#       print_warning "<prefix> (gh: <first-line>)"
#   - Otherwise:
#       print_warning "<prefix>"
```

### Globals (NEW)

| Name | Type | Lifetime | Description |
| --- | --- | --- | --- |
| `GH_LAST_ERROR_FILE` | string (file path) | per-process; established once at plugin source via `mktemp` | Path to a tempfile whose contents are the first line of the most recent gh helper's stderr (empty on success). Empty string if mktemp failed at source time, in which case stderr capture is disabled but helpers still work. |

A tempfile is required because helpers are invoked inside `$(...)`
command substitution and a plain variable mutated in the subshell would
not survive. The path comes from `mktemp` (unpredictable name, 0600
perms) to avoid the symlink-clobber risk of a predictable
`/tmp/foo.$$` path. The plugin does NOT register a `trap … EXIT` for
this file — sourcing happens inside `setup.sh`'s plugin dispatch, where
the parent script may have already registered its own EXIT handler
(`cleanup_upstream_dir` for the `--upgrade` flow at `setup.sh:2077`).
The per-PID tempfile is left for the OS to clean.

No other plugin globals are introduced; no existing globals are renamed.

## Error Responses (delta — to be merged into `shared/api-spec.md :: Error Responses`)

| Error | Type | When | Behavior |
| --- | --- | --- | --- |
| `curl: (23) Failure writing output to destination` from remote bootstrap | (eliminated) | Outer curl pipe inherited across `exec bash`, race against the new process's read | Suppressed by `< /dev/null` on the `exec` line; never printed |
| gh helper API/auth failure | shell warning, non-fatal | gh unauthenticated, network error, or empty result | `print_warning` includes captured first-line stderr (from `GH_LAST_ERROR_FILE`); control flow falls through to manual prompt |

## Out of Scope (non-goals)

- Pre-flight `gh auth status` check (helpers themselves are the diagnostic).
- Retry logic on gh failure.
- Multi-line stderr surfacing (first line only — by design).
- Changing the manual prompt UX.
- New CLI flags or env vars.
