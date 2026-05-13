# Workflow: #276 fix(setup) bootstrap + gh helper error surfacing

## Implementation Steps

### Step 1: Add bootstrap stdin detach
- **Action**: Modify the `exec` line in `setup.sh`'s remote-execution
  bootstrap so the new process's stdin is `/dev/null`, severing the outer
  curl write pipe.
- **Files**: `setup.sh:69`
- **Depends on**: nothing
- **Done when**: line reads `exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null`;
  a manual `curl -fsSL <served-setup>/setup.sh | bash -s -- --help` prints
  no `curl:` substring on stderr.

### Step 2: Introduce `_gh_run` wrapper + `GH_LAST_ERROR`
- **Action**: Add a private function `_gh_run` near the top of
  `templates/github-actions/project-integration/plugin.sh` (just below
  `check_gh_available` is the natural spot). The function captures gh's
  first-line stderr into the global `GH_LAST_ERROR` and always returns 0.
- **Files**: `templates/github-actions/project-integration/plugin.sh`
  (additions around line 40)
- **Depends on**: nothing (independent of Step 1)
- **Done when**: the function exists, has the documented signature, and
  is unit-friendly under a PATH-stubbed `gh`.

### Step 3: Refactor gh helpers to use `_gh_run`
- **Action**: Rewrite `get_current_repo`, `get_current_user`,
  `get_owner_projects`, `get_project_fields`, and
  `get_project_fields_detailed` to delegate every `gh` invocation through
  `_gh_run`. Every helper always exits 0; failure is signaled by empty
  stdout + non-empty `GH_LAST_ERROR`.
- **Files**: `templates/github-actions/project-integration/plugin.sh`
  (lines 37-180; existing helpers replaced in place)
- **Depends on**: Step 2
- **Done when**:
  - All existing call sites compile.
  - Stubbed-gh test (Step 7) covers success / auth-error / empty paths
    and observes the expected behavior.

### Step 4: Surface captured warnings at call sites
- **Action**: Add a private `_print_gh_warning` helper, and replace each
  `print_warning "Could not ..."` in `plugin_interactive_setup` (and any
  other call sites discovered during Step 3) with a call to
  `_print_gh_warning` that includes `GH_LAST_ERROR` when present.
- **Files**: `templates/github-actions/project-integration/plugin.sh`
  (lines 881-904 plus a few inside the detailed-fields fallback near
  lines 1092-1100)
- **Depends on**: Step 3
- **Done when**: under a stubbed gh that prints `gh: not authenticated`
  on stderr, the user sees `[WARN] Could not determine current user
  (gh: gh: not authenticated)`.

### Step 5: Verify the always-prompt invariant
- **Action**: Walk the control flow in `plugin_interactive_setup` and
  confirm that every failure branch in lines 877-904 sets
  `use_gh_detection=false` (or leaves it false) and reaches the `else`
  branch at line 1102. Since helpers now always exit 0, no `set -e`
  abort can sneak in. If a missing transition is discovered, patch it.
- **Files**: `templates/github-actions/project-integration/plugin.sh`
  (audit; minimal code changes only if needed)
- **Depends on**: Step 4
- **Done when**: audit memo recorded in the implementation commit;
  bats test from Step 7 passes the "reaches manual prompt" assertion.

### Step 6: Add bats test — remote bootstrap stderr quietness
- **Action**: Create `tests/setup_remote_bootstrap.bats`. Serve a local
  copy of `setup.sh` over `python3 -m http.server` (or feed the script
  through a pipe + `bash`), run several non-interactive invocations
  (`--help`, `--lang rust -y --overwrite`), and assert stderr contains
  no `curl:` substring.
- **Files**: `tests/setup_remote_bootstrap.bats` (NEW)
- **Depends on**: Step 1
- **Done when**: `bats tests/setup_remote_bootstrap.bats` passes.

### Step 7: Add bats test — gh failure surfacing + manual fallback
- **Action**: Create `tests/project_integration_gh.bats`. Stub `gh` via
  a PATH-prepended bin that responds based on its args:
  - `gh api user --jq '.login'` → exit 1, stderr `gh: not logged in` →
    expect `[WARN] Could not determine current user (gh: gh: not logged in)`,
    then manual project prompt is reached.
  - `gh api user --jq '.login'` → exit 0, stdout `someuser`;
    `gh project list --owner someuser --format json` → stdout
    `{"projects":[]}` → expect `[WARN] No projects found for someuser`,
    then manual prompt reached.
  - `gh api user` succeeds, `gh project list` returns a single project →
    expect `[OK] Auto-selected project: ...`, no warnings.
- **Files**: `tests/project_integration_gh.bats` (NEW), plus a fixtures
  directory under `tests/fixtures/gh-stubs/`
- **Depends on**: Steps 3 and 4
- **Done when**: all three sub-cases pass.

### Step 8: Smoke-test end-to-end
- **Action**: From a fresh scratch directory, run
  `curl -fsSL https://raw.githubusercontent.com/TE-ToshiakiTanaka2/tarnished/{branch}/setup.sh | bash`
  with the branch from this issue. Visually confirm:
  - Zero `curl:` lines on stderr.
  - The project selection / manual prompt is reached.
  - When gh is intentionally logged out (`gh auth logout`), the warning
    explicitly mentions the gh stderr line.
- **Files**: none (manual)
- **Depends on**: all prior
- **Done when**: confirmation captured in the PR description.

## Task Dependencies

```
Step 1 ─────────────────────────────┐
                                    │
Step 2 ──► Step 3 ──► Step 4 ──► Step 5
                                    │
                                    ├──► Step 6 (depends only on Step 1)
                                    │
                                    └──► Step 7 (depends on Steps 3, 4)
                                                                │
                                                                ▼
                                                             Step 8 (manual)
```

- Steps 1 and 2 can be committed as separate atomic changes (different files).
- Steps 6 and 7 can be authored in parallel by the same developer once their
  dependencies have landed.

## Test Strategy

### Unit Tests
- `_gh_run` deterministic behavior under a PATH-stubbed `gh`:
  - success path → stdout pass-through, `GH_LAST_ERROR=""`, exit 0
  - exit-1-with-stderr → empty stdout, `GH_LAST_ERROR=<first line>`, exit 0
  - exit-0-empty → empty stdout, `GH_LAST_ERROR=""`, exit 0

### Integration Tests
- `setup_remote_bootstrap.bats` — stderr quietness across the remote
  bootstrap path for `--help`, `--lang rust -y`, and `--github-actions`
  non-interactive permutations.
- `project_integration_gh.bats` — auth-error, empty-list, and happy-path
  permutations of `plugin_interactive_setup`.

### Edge Cases
- gh returns valid JSON with `.projects: []` (empty array).
- gh exits 0 with empty stdout (rare; treated as "no data").
- gh prints multi-line stderr (only first line is surfaced).
- gh is installed but pointed at an unreachable enterprise host (network
  error → captured into `GH_LAST_ERROR`).
- `--overwrite -y` non-interactive mode bypasses TTY checks and uses
  defaults — must not regress.
- `gh` available but not on PATH at `command -v` time mid-script
  (PATH change after `check_gh_available`): out of scope; not addressed.
- Outer curl's EPIPE timing is non-deterministic; the bootstrap test
  asserts absence over multiple runs to reduce flakiness risk.
