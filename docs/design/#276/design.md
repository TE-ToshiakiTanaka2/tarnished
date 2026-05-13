# Design: #276 fix(setup): suppress spurious curl:(23) from remote bootstrap and ensure GitHub Project detection always prompts

## Context

`setup.sh` is the top-level template installer. It supports two distribution
paths (see `shared/api-spec.md :: "Curl pipe (primary distribution path)"`):

- **Local**: `./setup.sh` from a cloned repo.
- **Remote**: `curl -fsSL .../setup.sh | bash`.

When invoked remotely (`BASH_SOURCE[0]` empty / `"-"` / not a regular file),
the bootstrap block (`setup.sh:29-69`) creates a temp dir, `git clone`s the
repo, and `exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"` to continue
execution from the local copy.

Inside the script, the GitHub Project Integration step is wired through
`templates/github-actions/project-integration/plugin.sh::plugin_interactive_setup()`
(lines 845-1115). That function:

1. Prompts for `ERD_REF` via `/dev/tty`.
2. Tries to auto-detect projects via `gh` CLI helpers (`check_gh_available`,
   `get_current_user`, `get_owner_projects`, `get_project_fields_detailed`).
   Each helper currently runs `gh ... </dev/null 2>/dev/null` — stderr is
   silenced, exit code is captured by `$(...)`.
3. On auto-detect success → shows a project selection list + field-config
   prompts.
4. On auto-detect failure → falls through to `prompt_manual_project_config`
   and `prompt_manual_field_defaults` at line 1102-1106 ("else" branch).

Two behavioral invariants from `shared/architecture.md :: "Cross-cutting
Concerns"` apply:

- **Plugin failures wrapped per-plugin** so one failure does not abort
  the whole setup (`#255`).
- **Idempotency / non-fatal warnings**: setup helpers under `set -e` must
  `return 0` on non-fatal failures so `post.sh` / `setup.sh` continue.

The gh helpers today violate the second invariant: `var=$(gh ... 2>/dev/null)`
under `set -e` propagates `gh`'s non-zero exit, and the bootstrap leaks an
EPIPE-shaped `curl: (23)` message into the user's terminal at a moment that
falsely implicates the gh-detection step.

## Architecture Overview (delta)

Two surgical fixes in two files. No new module, no new template, no Rust
changes.

1. **`setup.sh:69`** — detach the outer-curl pipe from the new process
   before `exec`, eliminating the EPIPE from curl's residual write.
2. **`templates/github-actions/project-integration/plugin.sh`** — restructure
   the gh-detection helpers so:
   - gh's stderr is captured (not silenced) into a process-wide tempfile
     `GH_LAST_ERROR_FILE` (first line only). A file rather than a shell
     variable is required because helpers are invoked via `$(...)`
     command substitution; subshell mutations to a plain variable do
     not survive. The path comes from `mktemp` (unpredictable name,
     0600 perms) — a predictable `/tmp/...$$` path would expose a
     symlink-clobber primitive.
   - The helpers always `return 0`; failure is communicated via empty
     stdout + non-empty `GH_LAST_ERROR_FILE`.
   - Callers emit a `print_warning` that includes the captured cause.
   - The "always reach an interactive prompt" invariant is restored
     (broken today by `set -e` abort inside `var=$(...)`).
   - No `EXIT` trap is installed: this plugin is sourced inside
     `setup.sh`'s plugin dispatch (after the `--upgrade` flow may have
     already registered `cleanup_upstream_dir EXIT`), and an
     unconditional trap would stomp the caller's trap and leak the
     upstream clone directory. The per-PID tempfile is left in TMPDIR.

Tests added under `tests/`.

## Module Structure (delta)

```
.
├── setup.sh                              # Modified: bootstrap exec gains `< /dev/null`
├── templates/github-actions/
│   └── project-integration/plugin.sh     # Modified: _gh_run wrapper + helper rewrite + warning surfacing
└── tests/
    ├── setup_remote_bootstrap.bats       # NEW: stderr has no `curl:` substring across modes
    └── project_integration_gh.bats       # NEW: gh failure paths surface cause + reach manual prompt
```

## Interface Design (delta)

### Bootstrap exec contract (`setup.sh`)

```bash
# Before
exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@"

# After
exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null
```

The redirection severs the outer curl write pipe; the new bash reads the
script from disk, not stdin. curl finishes (or aborts on close-from-reader)
without emitting EPIPE to the user terminal.

### `_gh_run` wrapper (NEW, private to `plugin.sh`)

A shell variable cannot carry the captured stderr across the `$(...)`
command substitution used by callers (subshell mutations are lost), so
the channel is a process-wide tempfile whose path is obtained via
`mktemp` at plugin source time. `mktemp` gives an unpredictable name
and 0600 perms, eliminating the symlink-clobber risk a predictable
`/tmp/foo.$$` path would expose.

```bash
# Path established once when the plugin is sourced.
# Empty if mktemp fails — _gh_run degrades to no-capture mode but the
# helpers still work; callers just lose the captured-cause suffix.
GH_LAST_ERROR_FILE="$(mktemp -t tarnished-gh-last-error.XXXXXX 2>/dev/null || true)"

# Run a gh command, capture first-line stderr to GH_LAST_ERROR_FILE,
# swallow the exit code. Stdout is emitted verbatim. Always returns 0.
#
# Usage: _gh_run gh api user --jq '.login'
_gh_run() {
    local err_file
    err_file=$(mktemp 2>/dev/null) || err_file=""
    [[ -n "$GH_LAST_ERROR_FILE" ]] && : > "$GH_LAST_ERROR_FILE"
    if [[ -n "$err_file" ]]; then
        "$@" </dev/null 2>"$err_file" || true
        if [[ -n "$GH_LAST_ERROR_FILE" ]]; then
            head -n1 "$err_file" > "$GH_LAST_ERROR_FILE" 2>/dev/null || true
        fi
        rm -f "$err_file"
    else
        "$@" </dev/null 2>/dev/null || true
    fi
    return 0
}
```

No `EXIT` trap is installed. This plugin is sourced inside `setup.sh`'s
plugin dispatch (after the `--upgrade` flow may have already registered
`trap cleanup_upstream_dir EXIT` at `setup.sh:2077`); an unconditional
`trap … EXIT` here would replace that handler and leak the upstream
clone. The per-PID tempfile is left for the OS to clean.

### Helper output contract (revised)

| Function | stdout on success | stdout on failure | Exit code | `GH_LAST_ERROR_FILE` |
| --- | --- | --- | --- | --- |
| `check_gh_available` | (empty) | (empty) | 0 / 1 | unchanged |
| `get_current_repo` | `owner/repo` | (empty) | 0 (always) | first-line gh stderr (or empty) |
| `get_current_user` | `<login>` | (empty) | 0 (always) | first-line gh stderr |
| `get_owner_projects` | `<JSON>` | (empty) | 0 (always) | first-line gh stderr |
| `get_project_fields` | `<JSON>` | (empty) | 0 (always) | first-line gh stderr |
| `get_project_fields_detailed` | `<JSON>` | (empty) | 0 (always) | first-line gh stderr (last gh attempt) |

Callers continue to use the `$(...)` capture pattern they use today; only
the implementation behind each helper changes.

### Caller pattern at lines 881-904 (revised)

```bash
if check_gh_available; then
    print_info "Detected gh CLI, attempting to fetch projects..."
    current_user=$(get_current_user)

    if [[ -n "$current_user" ]]; then
        owner_projects=$(get_owner_projects "$current_user")
        if [[ -n "$owner_projects" ]]; then
            ...  # unchanged auto-detect happy path
        else
            _print_gh_warning "Could not fetch projects for $current_user"
        fi
    else
        _print_gh_warning "Could not determine current user"
    fi
else
    print_info "gh CLI not found, using manual configuration"
fi
```

Where `_print_gh_warning` is a small private helper:

```bash
_print_gh_warning() {
    local prefix="$1"
    local err=""
    if [[ -n "$GH_LAST_ERROR_FILE" ]] && [[ -f "$GH_LAST_ERROR_FILE" ]]; then
        err=$(cat "$GH_LAST_ERROR_FILE" 2>/dev/null || true)
    fi
    if [[ -n "$err" ]]; then
        print_warning "$prefix (gh: $err)"
    else
        print_warning "$prefix"
    fi
}
```

### Type Definitions (delta)

None. The new state is a process-wide path string `GH_LAST_ERROR_FILE`
(set once at plugin source time) and the file it points to. No schema,
no struct, no Rust type.

## Data Flow

1. User invokes `curl -fsSL .../setup.sh | bash`.
2. Outer `curl` streams the script into `bash`'s stdin.
3. Bootstrap block detects pipe execution, clones tarnished, and runs
   **`exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null`** —
   stdin of the new process is `/dev/null`, no inheritance of curl's pipe.
4. Outer curl's residual write fails (EPIPE) at most once, but quietly —
   the user's stderr is no longer connected to the path that was getting
   the curl message. (See "Implementation Notes" for the precise reason.)
5. The new bash reads `setup.sh` from disk. Existing behavior from here on.
6. Eventually `plugin_interactive_setup` runs:
   - For each gh helper call, on failure `GH_LAST_ERROR_FILE` holds the
     first line of gh's stderr (e.g. `gh: To get started with GitHub CLI,
     please run: gh auth login`). The file persists across the `$(...)`
     subshell because its path was established once in the parent shell.
   - Callers always emit a `print_warning` with that line (read by
     `_print_gh_warning` from the file).
   - `use_gh_detection` stays `false` and the manual fallback at line
     1102 runs deterministically.

This restores the per-issue Functional Requirements (#276 FR-1/FR-2/FR-3):
no curl noise, always-visible prompt, always-visible cause.

## Error Handling

Error policy delta (merged into `shared/api-spec.md :: "Error Responses"`):

| Error | Type | When | Behavior |
| --- | --- | --- | --- |
| `curl: (23)` from remote bootstrap | (eliminated) | Outer curl pipe inherited by exec | Suppressed by `< /dev/null` on exec |
| gh helper failure (auth / API / empty result) | shell warning, non-fatal | gh unauthenticated, network error, or empty data | `print_warning` includes captured `GH_LAST_ERROR_FILE` line; flow falls through to manual prompt |

Notably:

- We do NOT add a pre-flight `gh auth status` check. The helpers ARE the
  diagnostic — letting them run and capturing their failure message is
  more truthful than guessing the cause.
- We do NOT change exit codes or fail-fast behavior. The script still
  completes successfully on the failure path; the user simply enters
  Project config manually.

## Implementation Notes

- **Why `< /dev/null` over draining stdin**: `cat > /dev/null` before
  `exec` requires knowing how much of the script remains buffered by
  bash and curl, and is sensitive to bash version and pipe-buffer
  sizing. `< /dev/null` on `exec` is one token, has no timing
  dependency, and matches the established practice for severing
  inherited pipes (see `gh ... </dev/null` already used throughout
  plugin.sh).
- **`set -e` interaction**: Today's `var=$(gh ... 2>/dev/null)` under
  `set -e` aborts the script when gh exits non-zero. This is the most
  likely cause of "the manual prompt never appeared" reported by the
  user, because the abort happens BEFORE the `else` branch at line
  1102 is reached. The new `_gh_run` always returns 0; the failure
  signal is the empty stdout assigned to the caller's variable. This
  matches the non-fatal-warning pattern documented in
  `shared/architecture.md :: "Cross-cutting Concerns / Plugin
  failures"` (`#255`).
- **Why a tempfile instead of a shell variable**: bash functions cannot
  return multiple values without out-of-band mechanisms (globals, named
  pipes, JSON-encoded stdout). Existing callers wrap helpers in
  `$(...)` command substitution, which runs them in a subshell — a
  plain variable mutated there is invisible to the parent. A tempfile
  bridges the subshell because the FS state outlives the subshell. The
  path is mktemp'd once at sourcing time (parent scope) and inherited
  by every subshell that runs a helper. Each `_gh_run` truncates and
  rewrites the file, so cross-call leakage is bounded.
- **Why no `EXIT` trap on the tempfile**: this plugin is sourced by
  `setup.sh` *after* the `--upgrade` flow may have set its own
  `trap cleanup_upstream_dir EXIT` (`setup.sh:2077`). A bare
  `trap … EXIT` here replaces (does not append to) that handler, which
  would leak the upstream clone. The per-PID tempfile is tiny and
  named uniquely by `mktemp`; we accept the small TMPDIR leftover.
- **Stderr first line only**: gh sometimes prints multi-line stderr
  (e.g., 1 line of error + 1 line of recovery hint + 1 line about
  `gh auth login`). Surfacing all of it in a `print_warning` would
  clutter the terminal. Capturing `head -n1` gives a one-line summary;
  motivated users can re-run `gh auth status` themselves for full
  detail.
- **Test isolation**: the bats tests stub `gh` via a PATH-prepended
  shim. We never call the real GitHub API in CI.
- **Backwards compatibility**: a previously-successful auto-detect
  is byte-identical post-fix (the success path of `_gh_run` is
  indistinguishable from today's `$(gh ...)`). Only failure paths
  change visible output.
- **Non-goals**:
  - No change to the manual prompt UX.
  - No new CLI flags.
  - No retry logic on gh failure.
  - No telemetry / log file.
