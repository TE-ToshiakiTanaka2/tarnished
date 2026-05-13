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
| `get_current_repo` | `() -> stdout(owner/repo)` | `gh repo view ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + `GH_LAST_ERROR` |
| `get_current_user` | `() -> stdout(login)` | `gh api user ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + `GH_LAST_ERROR` |
| `get_owner_projects` | `(owner) -> stdout(JSON)` | `gh project list ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + `GH_LAST_ERROR` |
| `get_project_fields` | `(owner, number) -> stdout(JSON)` | `gh project field-list ... 2>/dev/null` | delegates to `_gh_run`; always exits 0; failure ⇒ empty stdout + `GH_LAST_ERROR` |
| `get_project_fields_detailed` | `(owner, number) -> stdout(JSON)` | GraphQL via `gh api graphql ... 2>/dev/null`; falls back to `get_project_fields` | delegates to `_gh_run` at each gh invocation; always exits 0; falls back to `get_project_fields`; the final `GH_LAST_ERROR` is from the last gh attempt |

### `_gh_run` (NEW, private)

```bash
# Signature
_gh_run <cmd> [args...]

# Effect
#   - Runs the gh command with stdin from /dev/null and stderr captured
#     to a temp file.
#   - Sets GH_LAST_ERROR to the first line of captured stderr (empty
#     if the command succeeded).
#   - Emits the command's stdout to its own stdout.
#   - Always returns 0.
```

### `_print_gh_warning` (NEW, private)

```bash
# Signature
_print_gh_warning <prefix>

# Effect
#   - If GH_LAST_ERROR is non-empty:
#       print_warning "<prefix> (gh: <first-line>)"
#   - Otherwise:
#       print_warning "<prefix>"
```

### Globals (NEW)

| Name | Type | Lifetime | Description |
| --- | --- | --- | --- |
| `GH_LAST_ERROR` | string | per-`_gh_run`-call (overwritten) | First line of the most recent gh helper's stderr; empty on success. |

No other plugin globals are introduced; no existing globals are renamed.

## Error Responses (delta — to be merged into `shared/api-spec.md :: Error Responses`)

| Error | Type | When | Behavior |
| --- | --- | --- | --- |
| `curl: (23) Failure writing output to destination` from remote bootstrap | (eliminated) | Outer curl pipe inherited across `exec bash`, race against the new process's read | Suppressed by `< /dev/null` on the `exec` line; never printed |
| gh helper API/auth failure | shell warning, non-fatal | gh unauthenticated, network error, or empty result | `print_warning` includes captured first-line stderr (`GH_LAST_ERROR`); control flow falls through to manual prompt |

## Out of Scope (non-goals)

- Pre-flight `gh auth status` check (helpers themselves are the diagnostic).
- Retry logic on gh failure.
- Multi-line stderr surfacing (first line only — by design).
- Changing the manual prompt UX.
- New CLI flags or env vars.
