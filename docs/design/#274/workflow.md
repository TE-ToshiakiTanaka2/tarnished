# Workflow: #274 feat(templates): add Go language template

## Implementation Steps

### Step 1: Scaffold static asset files

- **Action**: Create the static (non-`plugin.sh`) files that the plugin
  hooks copy/merge into target projects. These are pure content with no
  shell logic.
- **Files**:
  - `templates/languages/go/.devcontainer/devcontainer.json` — Go feature
    + `golang.go` extension (payload documented in api-spec.md)
  - `templates/languages/go/.github/workflows/go-quality-check.yml` —
    5-job workflow (`build` / `vet` / `fmt` / `lint` / `unit-test`),
    Node-24-native action pins
  - `templates/languages/go/.claude/settings.json` — `PostToolUse` hooks
    for `Write(*.go)` and `Edit(*.go)`
  - `templates/languages/go/.claude/rules/go.md` — Go coding rules with
    frontmatter `paths: ["**/*.go"]`
  - `templates/languages/go/.golangci.yml` — baseline lint config
- **Depends on**: nothing (parallelizable with Step 2's research).
- **Done when**: All five files exist with the exact payloads from
  api-spec.md. `yamllint .github/workflows/go-quality-check.yml`,
  `jq . devcontainer.json`, `jq . settings.json` all succeed.

### Step 2: Implement `plugin.sh`

- **Action**: Author `templates/languages/go/plugin.sh` following the
  Rust plugin structure with the deltas documented in design.md.
- **Files**:
  - `templates/languages/go/plugin.sh` (new)
- **Required functions** (in order):
  1. `plugin_name() { echo "go"; }`
  2. `plugin_description() { echo "Go development environment with golangci-lint and gotestsum"; }`
  3. `plugin_copy(target_dir)` — copy workflow with explicit overwrite
     prompt, `OVERWRITE_ALL=true copy_with_confirm`
  4. `plugin_post_copy_shared(target_dir)` — merge devcontainer.json,
     merge `.claude/settings.json`, copy `.claude/rules/`, append
     marker-guarded `post.sh` block
  5. `plugin_post_copy_module(target_dir, module_name)` — copy
     `.golangci.yml` via `copy_with_confirm`
  6. `plugin_post_copy(target_dir)` — backward-compat shim
- **Constants**:
  - `PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
  - `GO_POSTSH_MARKER="# >>> go (toolchain) post-create >>>"`
- **Depends on**: Step 1 (the plugin references those files by path).
- **Done when**:
  - `bash -n plugin.sh` parses without syntax error
  - All six required functions are `declare -f`-discoverable when
    sourced
  - `shellcheck -x plugin.sh` passes with the same allowlist used by the
    rest of the repo (or matches Rust plugin's shellcheck output —
    same warnings/exemptions)

### Step 3: Register `go` in `setup.sh`

- **Action**: Update `setup.sh` to know about the `go` language id.
- **Files**:
  - `setup.sh` (edit only — additive, no refactor)
- **Edits**:
  1. `AVAILABLE_LANGUAGES=("rust" "python" "node" "deno" "latex")` →
     append `"go"`
  2. `LANGUAGE_DISPLAY_NAMES` — add `["go"]="Go"`
  3. Help-text "Available Languages" table — add
     `go                  Go (gofmt, golangci-lint, gotestsum)`
  4. Examples block — add 2 lines:
     - `./setup.sh --lang go                    # Go only`
     - `./setup.sh --lang go --github-actions   # Go with GitHub Project integration`
  5. Auto-detect block (`setup.sh:1458–1464`) — add
     `[[ -f "$target_dir/go.mod" ]] && langs+=(go)`
- **Depends on**: nothing (independent of Step 1/2).
- **Done when**:
  - `./setup.sh --help` prints the new lines without error
  - `bash -n setup.sh` clean
  - No existing language detection (Cargo.toml, pyproject.toml, etc.)
    regresses

### Step 4: Local verification — single-mode

- **Action**: Run `setup.sh --lang go` in a throwaway directory and
  inspect the output.
- **Files**: none (verification only).
- **Steps**:
  1. `mkdir /tmp/test-go && cd /tmp/test-go`
  2. `bash /workspace/setup.sh test-project --lang go -y` (or relevant
     non-interactive invocation)
  3. Confirm:
     - `.devcontainer/devcontainer.json` contains the Go feature + extension
     - `.github/workflows/go-quality-check.yml` exists, byte-equal to the
       template
     - `.claude/settings.json` contains the gofmt/vet hooks
     - `.claude/rules/go.md` exists
     - `.golangci.yml` exists at the project root (single-mode
       `plugin_post_copy_module` target_dir = root)
     - `.devcontainer/scripts/post.sh` contains the marker-guarded Go
       block
- **Depends on**: Steps 1–3.
- **Done when**: all five existence checks pass. Files visually match the
  intent in api-spec.md.

### Step 5: Local verification — monorepo

- **Action**: Run `setup.sh --monorepo --module svc:go` and verify the
  monorepo split.
- **Files**: none (verification only).
- **Steps**:
  1. Fresh dir `/tmp/test-go-mono`
  2. `bash /workspace/setup.sh test-mono --monorepo --module svc:go -y`
  3. Confirm:
     - Root: `.devcontainer/`, `.claude/`, `docker/Dockerfile.dev`,
       `modules.json` (with `go` language entry)
     - `svc/.golangci.yml` exists (per-module config)
     - Root `.devcontainer/scripts/post.sh` contains the marker block
       exactly once
  4. Re-run the same command → confirm idempotency:
     - No double-append in `post.sh`
     - `modules.json` not duplicated
- **Depends on**: Step 4 passing.
- **Done when**: both runs produce identical end states after the second.

### Step 6: Local verification — add-module

- **Action**: From the monorepo created in Step 5, add another Go module.
- **Files**: none (verification only).
- **Steps**:
  1. `cd /tmp/test-go-mono`
  2. `bash /workspace/setup.sh --add-module worker --lang go -y`
  3. Confirm:
     - `worker/.golangci.yml` written
     - `modules.json` now has 2 entries (svc + worker)
     - Root `post.sh` unchanged (block already present, marker check
       short-circuits)
- **Depends on**: Step 5.
- **Done when**: new module's per-module file is present and shared
  assets remain unchanged.

### Step 7: Documentation update

- **Action**: Update README and/or top-of-`setup.sh` comment block to
  list Go as a supported language.
- **Files**:
  - `README.md` (if it has a language table — confirm during
    implementation)
  - `setup.sh` header (`# ./setup.sh --lang rust` example block at
    `setup.sh:12`)
- **Depends on**: Steps 1–3 (semantic correctness only).
- **Done when**: docs match reality.

### Step 8: Shared design layer regeneration

- **Action**: After implementation, regenerate `docs/design/shared/*` to
  reflect that `go` is now a valid language id. (This is **the /design
  step's** Phase 7, executed in this same /design run — captured here so
  /implement does not redo it.)
- **Files**:
  - `docs/design/shared/architecture.md` — add Go to the language list
    in the directory tree comment
  - `docs/design/shared/data-model.md` — update `modules.json` schema
    table: `modules[].language` accepted values
  - `docs/design/shared/api-spec.md` — update "Setup / Plugin Surface"
    workflow list (add `go-quality-check.yml`); update `modules.json`
    schema language enumeration
- **Depends on**: per-issue design files being authored.
- **Done when**: shared/* snapshot reflects post-#274 truth.

### Step 9: Build / quality gate

- **Action**: Run the existing test suite to confirm no regression.
- **Files**: none (test-run only).
- **Steps**:
  1. `cargo check --all-targets` (no Rust code changed, but cheap to
     confirm)
  2. `bash -n setup.sh templates/languages/go/plugin.sh`
  3. `shellcheck -x templates/languages/go/plugin.sh setup.sh` (allow
     existing exemptions)
  4. If repo has integration tests covering `setup.sh`, run them.
- **Depends on**: Steps 1–3.
- **Done when**: all checks pass.

### Step 10: Commit and PR

- **Action**: Stage the new template directory, the `setup.sh` edits,
  and the README/setup.sh-comment doc updates as separate commits
  (or one if small).
- **Depends on**: Steps 1–9.
- **Done when**: branch is push-ready and `gh pr create` workflow can
  be invoked.

## Task Dependencies

```
Step 1 (static files) ─┐
                       ├──► Step 2 (plugin.sh) ──┐
Step 3 (setup.sh)  ────┴───────────────────────┬─┴──► Step 4 (single verify)
                                               │
                                               └────► Step 5 (monorepo verify) ──► Step 6 (add-module verify)

Step 7 (docs)      ────► (parallel with verification)

Step 4 ∧ Step 5 ∧ Step 6 ──► Step 8 (shared/*) ──► Step 9 (build) ──► Step 10 (commit/PR)
```

- Steps 1 and 3 are independent and can be done in parallel.
- Step 2 depends on Step 1 (references file paths).
- Steps 4–6 are sequential (each builds on prior state).
- Step 7 (docs) can run in parallel with Steps 4–6.
- Steps 8–10 are sequential and serve as the wrap-up.

## Test Strategy

### Unit Tests

The shell layer has no formal unit-test harness in this repo; verification
is by direct execution + inspection (Steps 4–6).

Per-function shell sanity:

- `plugin_name`, `plugin_description` — string equality.
- `plugin_copy` — overwrite prompt UX matches Rust (manual visual diff).
- `plugin_post_copy_shared` — three sub-actions (devcontainer merge,
  settings merge, rules copy, post.sh append). Each is observable via
  filesystem inspection after Step 4.
- `plugin_post_copy_module` — single `copy_with_confirm` call. Verified
  by `.golangci.yml` existence in Steps 4 and 5.

### Integration Tests

- **Single mode** (Step 4): `setup.sh --lang go` produces the expected
  6-file output set and a correctly-extended `post.sh`.
- **Monorepo init** (Step 5): `setup.sh --monorepo --module svc:go`
  produces shared + per-module files in the right locations.
- **Add-module** (Step 6): subsequent `setup.sh --add-module ...` is
  idempotent against shared assets.
- **Auto-detect** (regression): existing language detection
  (Cargo.toml, pyproject.toml, etc.) still works after adding the
  `go.mod` line to the auto-detect block. Verifiable by running
  `setup.sh --add-module foo` against a Rust monorepo and confirming
  `langs=(rust)` is inferred.
- **Manifest tracking** (regression): verbatim files
  (`go-quality-check.yml`, `go.md`, `.golangci.yml`) are captured in
  `.tarnished-manifest.json` when `--create-manifest` runs after a Go
  scaffold.

### Edge Cases

1. **Marker collision in `post.sh`** — second run of
   `plugin_post_copy_shared` in monorepo mode short-circuits via
   `grep -qF "$GO_POSTSH_MARKER"`. Validated in Step 5 by re-running
   the same `--monorepo` command.
2. **`golang.go` extension already present** — `merge_devcontainer_json`
   dedupes by string equality in the `extensions` array. Validated by
   confirming a single `golang.go` entry after merge.
3. **`hooks.PostToolUse` matcher collision** —
   `merge_claude_settings_hooks` keys on `matcher`, so re-running won't
   duplicate the `Write(*.go)` / `Edit(*.go)` hooks. Validated by
   inspecting `.claude/settings.json` after two `--lang go` runs.
4. **`post.sh` does not exist** — `[[ -f "$target_post_sh" ]]` guard
   protects against this; the plugin is a no-op for the post.sh step.
   This shouldn't happen in normal flows (post.sh is shipped by the
   `claude` plugin) but the guard is defensive.
5. **`--upgrade` against a Go-scaffolded project where the user edited
   `.golangci.yml`** — `manifest_decide(old_h, current_h, new_h)` with
   `current_h ≠ old_h` returns `SKIP_EDITED`. User edits preserved.
   Regression test: not new behavior, but Go's verbatim files
   automatically participate.
6. **`go vet ./...` runs in a directory without `go.mod`** — the hook
   command fails with a clear Go error. User runs `go mod init` once
   and the hook starts working. Same UX as Rust's
   `cargo fmt`-without-`Cargo.toml`.
