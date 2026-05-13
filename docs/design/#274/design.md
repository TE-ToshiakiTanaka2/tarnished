# Design: #274 feat(templates): add Go language template

## Context

`tarnished` ships language scaffolds for downstream projects via
`templates/languages/<lang>/`. Today five languages are supported (`rust`,
`python`, `node`, `deno`, `latex`). Each plugin implements the contract
documented in `../shared/api-spec.md` :: "Language plugin contract":

```
plugin_name()                  # echo "<id>"
plugin_description()           # echo "<desc>"
plugin_copy(target_dir)        # root-scoped: e.g. .github/workflows/<lang>-quality-check.yml
plugin_dockerfile(target_dir)  # OPTIONAL: append marker-guarded ENV/RUN block
plugin_post_copy_shared(root)             # root-only edits: devcontainer.json, .claude, post.sh
plugin_post_copy_module(root, module)     # per-module config files
plugin_post_copy(root)                    # backward-compat shim
```

`setup.sh` registers languages via two arrays (`AVAILABLE_LANGUAGES` +
`LANGUAGE_DISPLAY_NAMES`) and dispatches `plugin_post_copy` per the monorepo
rules in `../shared/architecture.md` :: "Cross-cutting Concerns / `setup.sh`
operating mode". Shared toolchain edits (`Dockerfile.dev`, `post.sh`) are
guarded by per-language markers (`# >>> <lang> ... >>>`) so `--add-module`
re-runs are no-ops at the root level.

This issue adds **Go** as a sixth language, following the same minimal-footprint
policy applied to Rust: no `go mod init` is run, no `src/` scaffold is written.
The user retains full control over project initialization.

## Architecture Overview (delta)

The change is additive and pattern-following. No layer boundary moves and no
existing plugin behavior changes. The Go plugin slots into the existing
language-plugin orchestration without requiring new dispatch paths.

Two `setup.sh` registration sites gain a `go` entry; the rest of the change is
new files under `templates/languages/go/`. Monorepo split follows the Rust
shape exactly: `.golangci.yml` is per-module (`plugin_post_copy_module`); the
devcontainer feature merge, Claude settings/rules copy, and `post.sh`
`gotestsum` install are shared (`plugin_post_copy_shared`). A `post.sh` marker
(`# >>> go (toolchain) post-create >>>`) guards block-level idempotency.

`plugin_dockerfile` is intentionally **omitted** (same as Rust). The Go
devcontainer feature exports `GOPATH`/`GOROOT`/`PATH` automatically and adds
`/go/bin` (where `go install` lands) to `PATH`, so no extra `ENV` block is
needed in `Dockerfile.dev`. If a future need arises (e.g., `GOTOOLCHAIN=auto`,
`GOPROXY` pinning), it can be added in a follow-up — the contract permits it.

## Module Structure (delta)

```
templates/languages/go/                       # NEW
├── plugin.sh                                 # NEW: plugin_name/description/copy/post_copy_*
├── .devcontainer/
│   └── devcontainer.json                     # NEW: ghcr.io/devcontainers/features/go:1 + VS Code extensions
├── .github/workflows/
│   └── go-quality-check.yml                  # NEW: build / vet / fmt / lint / test jobs
├── .claude/
│   ├── settings.json                         # NEW: PostToolUse hooks for gofmt + go vet
│   └── rules/
│       └── go.md                             # NEW: Go coding rules (mirrors rust.md)
└── .golangci.yml                             # NEW: per-module lint config
```

Touched files in `setup.sh`:

| Line region (current) | Change |
| --- | --- |
| `AVAILABLE_LANGUAGES=(...)` (`setup.sh:91`) | append `"go"` |
| `LANGUAGE_DISPLAY_NAMES=(...)` (`setup.sh:92-`) | add `["go"]="Go"` |
| Usage / `--lang` help block (around `setup.sh:206`–`238`) | add a `go` row + one example line |
| Header comment examples (`setup.sh:12`) | optional — add `--lang go` example |

Auto-detect fallback at `setup.sh:1458–1464` (used by `--add-module` to infer
the module's language from filesystem evidence) currently keys on
`Cargo.toml` / `pyproject.toml` / `package.json` / `deno.json[c]` /
`build-pdf.yml`. For Go, the closest equivalent is `go.mod`. Since this plugin
intentionally does **not** create `go.mod`, an auto-detect rule
`[[ -f "$target_dir/go.mod" ]] && langs+=(go)` only fires after the user has
run `go mod init`. That is acceptable — `--add-module` users who skip
`go mod init` can pass `--lang go` explicitly, matching the Rust experience.

## Interface Design (delta)

### Public API / Functions (Go plugin)

| Name | Signature | Description |
| --- | --- | --- |
| `plugin_name` | `() -> "go"` | Plugin identifier |
| `plugin_description` | `() -> string` | "Go development environment with golangci-lint and gotestsum" |
| `plugin_copy` | `(target_dir)` | Copy `go-quality-check.yml` to `target_dir/.github/workflows/` with overwrite prompt |
| `plugin_post_copy_shared` | `(target_dir)` | Merge devcontainer.json features+extensions, merge `.claude/settings.json` hooks, copy `.claude/rules/go.md`, append marker-guarded `post.sh` block that installs `gotestsum` (and optionally `golangci-lint`) |
| `plugin_post_copy_module` | `(target_dir, module_name)` | Copy `.golangci.yml` into the module root via `copy_with_confirm` |
| `plugin_post_copy` | `(target_dir)` | Shim: calls `plugin_post_copy_shared` then `plugin_post_copy_module(target_dir, "$PROJECT_NAME")` |

### Type Definitions (delta)

No Rust types change. Shell-level constants introduced:

- `GO_POSTSH_MARKER="# >>> go (toolchain) post-create >>>"` — block-level
  idempotency key for the `post.sh` append done in `plugin_post_copy_shared`.
  Companion close marker: `# <<< go (toolchain) post-create <<<`.

`modules.json` schema (`../shared/data-model.md` :: "modules.json schema")
gains `go` as a valid value for `modules[].language`. The schema is unchanged;
only the enumerated set widens. Forward-compatible per NFR-2.

## Data Flow

The Go plugin participates in the existing `setup.sh` post-copy flow with no
new control paths. Concretely, on a single-mode `setup.sh --lang go`:

1. `setup.sh` parses `--lang go`, appends to `SELECTED_LANGUAGES`.
2. `load_selected_plugins` sources `templates/languages/go/plugin.sh`.
3. `execute_plugin_copies(root)` calls `plugin_copy(root)` → writes
   `.github/workflows/go-quality-check.yml`.
4. `execute_plugin_dockerfiles(root)` finds no `plugin_dockerfile` for Go and
   skips (no `Dockerfile.dev` change).
5. `execute_plugin_post_copies(root)` takes the legacy branch (single mode)
   and calls `plugin_post_copy(root)`, which delegates to
   `plugin_post_copy_shared` (merge devcontainer.json + .claude/settings.json,
   copy rules, append `post.sh` Go block) and
   `plugin_post_copy_module(root, $PROJECT_NAME)` (copy `.golangci.yml` to
   root).

On a monorepo `setup.sh --monorepo --module svc:go`:

1. `MONOREPO_MODE=true`, `MODULES+=("svc:go")`.
2. `execute_plugin_post_copies` takes the monorepo branch for the Go plugin
   because the plugin path matches `*/templates/languages/*` and the plugin
   exposes `plugin_post_copy_module`.
3. `plugin_post_copy_shared(root)` runs once. The `post.sh` append is
   marker-guarded (`use_marker=true`) and skipped on re-runs.
4. For every module whose language is `go`, `plugin_post_copy_module(root/<m>,
   <m>)` writes `.golangci.yml` to that module subdirectory.

The full sequence is identical in shape to the Rust path documented in
`../shared/sequence.md` :: "`setup.sh --monorepo` — one-shot monorepo init",
substituting `python`/`node` participants with `go`.

## Error Handling

The Go plugin inherits the existing error-handling conventions:

- **Missing `Dockerfile.dev` on `--lang go`**: irrelevant — no
  `plugin_dockerfile` is defined.
- **Missing `post.sh` in `plugin_post_copy_shared`**: skip silently (Rust
  precedent — `[[ -f "$target_post_sh" ]]` guard).
- **Marker already present in `post.sh`** (monorepo / add-module re-run):
  log `print_info` and `return`. Same as Rust.
- **Overwrite confirmation for `go-quality-check.yml`**: explicit `(y/n)`
  prompt with `[n]` default, via `check_tty_available`. Matches the Rust
  `plugin_copy` UX exactly (`copy_with_confirm`'s built-in prompt is bypassed
  via `OVERWRITE_ALL=true` so the per-plugin message is the source of truth —
  the #265 contract).
- **`copy_with_confirm` failures** (e.g., destination not writable): propagate
  per the standard `set -euo pipefail` contract; this is a fatal scaffold
  error, not a Go-specific case.

No new error variants surface to `erd` (the Rust crate). The Rust binary does
not consume Go-specific configuration.

## Implementation Notes

### Tooling choices (research-derived)

- **`gofmt`** — Go-standard formatter, included with the toolchain. No extra
  install. Hook command: `gofmt -w "$CLAUDE_FILE_PATH"`.
- **`go vet`** — Standard static analyzer, included with the toolchain. Hook
  command: `go vet ./...` (project-wide rather than per-file, since `vet`
  works on packages not files).
- **`golangci-lint`** — Aggregator that wraps `staticcheck`, `errcheck`,
  `gosimple`, `govet`, `ineffassign`, `unused`, plus 50+ optional linters.
  Install in CI via the official action `golangci/golangci-lint-action@v6`
  (Node-24 native — fits the #267 pin policy). Install in devcontainer via
  `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`
  inside the `post.sh` block.
- **`gotestsum`** — Wraps `go test`, adds readable formatting + JUnit XML
  output. Install: `go install gotest.tools/gotestsum@latest`. Run command:
  `gotestsum --format pkgname -- ./...`.

### devcontainer feature

```jsonc
{
  "features": {
    "ghcr.io/devcontainers/features/go:1": {
      "version": "latest"
    }
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "golang.go"           // includes gopls, go-debug, go-test integration
      ]
    }
  }
}
```

The Go feature auto-configures `GOPATH=/go`, `GOROOT`, and prepends
`$GOPATH/bin` to `PATH`. `go install` lands binaries in `$GOPATH/bin`, so
`gotestsum` and `golangci-lint` are reachable from the shell and from VS Code
tasks without further configuration.

### Claude `settings.json` hooks

```jsonc
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write(*.go)",
        "hooks": [
          { "type": "command", "command": "gofmt -w \"$CLAUDE_FILE_PATH\" && go vet ./..." }
        ]
      },
      {
        "matcher": "Edit(*.go)",
        "hooks": [
          { "type": "command", "command": "gofmt -w \"$CLAUDE_FILE_PATH\" && go vet ./..." }
        ]
      }
    ]
  }
}
```

`merge_claude_settings_hooks` (existing `scripts/lib/common.sh` helper) merges
these into the target's `.claude/settings.json` without clobbering existing
hooks. Idempotent by construction.

### `go-quality-check.yml` shape (CI)

Five parallel jobs on `pull_request: [develop]` + `push: [develop]`, matching
the structure of `rust-quality-check.yml`:

| Job | Steps | Notes |
| --- | --- | --- |
| `build` | `actions/checkout@v5` → `actions/setup-go@v6` → `go build ./...` | Cache key off `go.sum` |
| `vet` | checkout → setup-go → `go vet ./...` | |
| `fmt` | checkout → setup-go → `test -z "$(gofmt -l .)"` | Fails if any file differs |
| `lint` | checkout → setup-go → `golangci/golangci-lint-action@v6` | Action pulls version from `.golangci.yml`, falls back to latest |
| `unit-test` | checkout → setup-go → `go install gotest.tools/gotestsum@latest` → `gotestsum --format pkgname -- ./...` | Cache `~/go/pkg/mod` |

`integration-test` job is **deferred** — the Rust precedent splits
`unit-test` and `integration-test` via `cargo test --bins` vs.
`cargo test --test '*'`. Go has no equivalent file-path convention (build
tags `//go:build integration` are the closest, but they require user opt-in).
Add a single `unit-test` job for now; integration tests can be a follow-up.

Action pins follow `../shared/architecture.md` :: "Cross-cutting Concerns /
GitHub Actions JS runtime" (#267):

- `actions/checkout@v5` — earliest Node-24 native major.
- `actions/cache@v5` — earliest Node-24 native major.
- `actions/setup-go@v6` — first major declaring `runs.using: node24` in
  `action.yml`. (`@v5` is Node-20; per the selection rule, use the earliest
  Node-24 major.)
- `golangci/golangci-lint-action@v6` — Node-24 native; `@v7` reserves
  `version: latest` semantics differently and is needlessly newer.

These pins propagate to downstream consumers verbatim (the file is copied
into target projects unchanged). Tarnished's own root `.github/workflows/`
remains unaffected by this issue.

### `.golangci.yml` baseline

Minimal, opinionated default — downstream projects can edit freely:

```yaml
run:
  timeout: 5m
linters:
  disable-all: true
  enable:
    - errcheck
    - gosimple
    - govet
    - ineffassign
    - staticcheck
    - unused
    - gofmt
    - goimports
issues:
  exclude-use-default: false
```

The default linter set above is what `golangci-lint` enables when nothing is
configured; making it explicit prevents surprises when upstream defaults
shift. `goimports` is enabled in addition because Go's import-ordering rules
are stricter than `gofmt`'s.

### `post.sh` `gotestsum` block

```bash
# >>> go (toolchain) post-create >>>
# -----------------------------------------------------------------------------
# Go Development Tools Setup
# -----------------------------------------------------------------------------
if command -v go &> /dev/null; then
    echo "Installing Go development tools..."

    if ! command -v gotestsum &> /dev/null; then
        echo "  - Installing gotestsum..."
        go install gotest.tools/gotestsum@latest
    fi

    if ! command -v golangci-lint &> /dev/null; then
        echo "  - Installing golangci-lint..."
        go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    fi

    echo "Go development tools installed."
fi
# <<< go (toolchain) post-create <<<
```

Block-level idempotency follows the Rust pattern: in monorepo / add-module
mode the markers are present and `grep -qF "$GO_POSTSH_MARKER"` short-circuits
re-runs. In single mode the markers are still emitted (this is the only
deviation from the Rust precedent, which uses an unmarkered block in single
mode for NFR-1 byte-equality with the pre-#263 baseline). Since Go is a new
language with no pre-#263 baseline to preserve, **markers are emitted in
both single and monorepo modes** — simpler invariant, no compatibility cost.

### Manifest tracking (#265)

The Go plugin's verbatim-copy outputs participate in `--upgrade` tracking
automatically because they go through `copy_with_confirm`:

- `.github/workflows/go-quality-check.yml`
- `.claude/rules/go.md`
- `.golangci.yml` (per module)

Merge outputs (`.devcontainer/devcontainer.json`, `.claude/settings.json`) and
dynamically appended blocks (`post.sh`, `Dockerfile.dev`) are excluded from
manifest tracking — same as every other plugin, per `MANIFEST_EXCLUDE_GLOBS`
and the merge-vs-verbatim distinction. No `scripts/lib/manifest.sh` change is
needed.

### Edge cases

1. **User runs `--lang go` then later runs `--upgrade --target-version <new>`
   without first `--create-manifest`** — same error as every other language:
   "run `--create-manifest` first" (existing flow, no Go-specific change).
2. **User runs `--add-module svc --lang go` against a monorepo where Go is
   already registered** — `plugin_post_copy_shared` finds the marker in
   `post.sh` and skips; `plugin_post_copy_module` writes the new module's
   `.golangci.yml`. No conflict.
3. **User edits `.golangci.yml` post-scaffold then runs `--upgrade`** —
   `manifest_decide` returns `SKIP_EDITED` (current_h ≠ old_h), preserving
   the edit. Standard behavior.
4. **`gofmt -w` hook fires on a file that fails to parse** — `gofmt` exits
   non-zero; the hook command fails. Claude surfaces the failure but the
   edit is not rolled back. Identical UX to Rust's `cargo fmt` hook.
5. **`go vet ./...` hook fires before `go.mod` exists** — `go vet` requires
   a module. Hook fails with "go.mod file not found". Acceptable for a
   pre-init repo; user runs `go mod init` once and the hook starts working.
   Same pattern as Rust requiring `Cargo.toml` for `cargo fmt`.

### Out of scope

- `go mod init` auto-scaffold (intentional, per requirement)
- `main.go` template (intentional)
- `go.work` workspaces (deferred; only matters for monorepo + Go and adds
  a non-trivial dimension; can be a follow-up)
- Cross-compile matrix in CI (defer to user)
- `gosec` / `govulncheck` security linters (defer; can be added to
  `.golangci.yml` linter list later without touching the plugin)
