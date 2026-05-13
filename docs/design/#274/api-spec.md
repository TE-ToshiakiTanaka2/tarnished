# API Specification: #274 feat(templates): add Go language template

## CLI Surface (delta)

### `setup.sh` registration

`AVAILABLE_LANGUAGES` and `LANGUAGE_DISPLAY_NAMES` gain a `go` entry.
Downstream effect on the CLI:

```
./setup.sh --lang go [...]
./setup.sh --monorepo --module svc:go [...]
./setup.sh --add-module svc --lang go [...]
```

Help text additions (new rows in the "Available Languages" table around
`setup.sh:206`):

```
go                  Go (gofmt, golangci-lint, gotestsum)
```

Examples block additions (around `setup.sh:223`):

```
./setup.sh --lang go                    # Go only
./setup.sh --lang go --github-actions   # Go with GitHub Project integration
```

No new flags. No mutually-exclusive combination changes. `--upgrade --module
<name>` accepts a Go-language module same as any other.

### Auto-detect (in `--add-module` flow)

`setup.sh:1458–1464` infers a module's language from filesystem evidence.
Add:

```bash
[[ -f "$target_dir/go.mod" ]] && langs+=(go)
```

Detection only succeeds after the user has run `go mod init`, since the Go
plugin does not auto-scaffold `go.mod` (matches the Rust precedent which
keys on `Cargo.toml` — the user-initiated equivalent).

## Plugin Surface (delta)

### Language plugin contract (`templates/languages/go/plugin.sh`)

Implements the contract documented in `../shared/api-spec.md` :: "Language
plugin contract". No contract change — only a new implementor.

| Function | Signature | Behavior |
| --- | --- | --- |
| `plugin_name` | `() -> "go"` | Identifier |
| `plugin_description` | `() -> string` | `"Go development environment with golangci-lint and gotestsum"` |
| `plugin_copy` | `(target_dir)` | Copy `.github/workflows/go-quality-check.yml` with overwrite prompt; `OVERWRITE_ALL=true copy_with_confirm` so the per-plugin prompt is the UX source-of-truth (#265) |
| `plugin_post_copy_shared` | `(target_dir)` | (a) `merge_devcontainer_json` to inject Go feature + `golang.go` extension, (b) `merge_claude_settings_hooks` to inject gofmt/vet hooks, (c) `copy_dir_with_confirm` to copy `.claude/rules/`, (d) append marker-guarded `post.sh` block installing `gotestsum` + `golangci-lint` |
| `plugin_post_copy_module` | `(target_dir, module_name)` | `copy_with_confirm` writes `.golangci.yml` into `target_dir` |
| `plugin_post_copy` | `(target_dir)` | Backward-compat shim: `plugin_post_copy_shared "$target_dir"` then `plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"` |
| `plugin_dockerfile` | (NOT IMPLEMENTED) | Same as Rust — devcontainer feature exports `GOPATH`/`PATH` and `/go/bin` is on `PATH`; no extra ENV needed |

Idempotency invariants:

- `plugin_post_copy_shared` is idempotent. `merge_devcontainer_json` and
  `merge_claude_settings_hooks` are idempotent by construction
  (JSON-structural merges). `copy_dir_with_confirm` is interactive but
  obeys `OVERWRITE_ALL` and `OVERWRITE_NONE`. The `post.sh` append is
  block-level idempotent via `GO_POSTSH_MARKER`.
- `plugin_post_copy_module` is `copy_with_confirm`-based and obeys the
  same overwrite-confirmation contract as every other module-scoped step.

### `GO_POSTSH_MARKER`

```
GO_POSTSH_MARKER="# >>> go (toolchain) post-create >>>"
```

Companion close marker (string-literal in `cat <<EOF`):

```
# <<< go (toolchain) post-create <<<
```

The marker is emitted in **both** single-mode and monorepo-mode appends
(deviation from Rust, which omits markers in single-mode to preserve NFR-1
byte-equality with pre-#263 output). Since Go is new, there is no pre-#263
baseline to preserve, so the simpler always-marked variant is used.

### `merge_devcontainer_json` Go payload (`.devcontainer/devcontainer.json`)

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
        "golang.go"
      ]
    }
  }
}
```

`merge_devcontainer_json` deep-merges this into the target's `devcontainer.json`,
deduplicating `features` keys and `customizations.vscode.extensions` array
entries.

### `merge_claude_settings_hooks` Go payload (`.claude/settings.json`)

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

`merge_claude_settings_hooks` appends entries to `hooks.PostToolUse` whose
`matcher` is not already present (matcher-keyed idempotency).

### `.claude/rules/go.md` (frontmatter)

```yaml
---
paths:
  - "**/*.go"
---
```

Applied to all `.go` files in the downstream project. Mirrors the
`rust.md` shape (frontmatter + sectioned coding guidance).

### `.golangci.yml` (per-module lint config)

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

Verbatim copy; the user edits this freely post-scaffold.
`copy_with_confirm` honors `--overwrite` and the user's overwrite
choices.

## Workflow Surface (`go-quality-check.yml`)

```yaml
name: Go Quality Check

on:
  pull_request:
    branches: [develop]
  push:
    branches: [develop]

env:
  GO_VERSION: "stable"

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: ${{ env.GO_VERSION }}
      - uses: actions/cache@v5
        with:
          path: |
            ~/.cache/go-build
            ~/go/pkg/mod
          key: ${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}
          restore-keys: |
            ${{ runner.os }}-go-
      - run: go build ./...

  vet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: ${{ env.GO_VERSION }}
      - run: go vet ./...

  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: ${{ env.GO_VERSION }}
      - name: gofmt
        run: |
          diff=$(gofmt -l .)
          if [[ -n "$diff" ]]; then
            echo "Files need gofmt:" && echo "$diff"
            exit 1
          fi

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: ${{ env.GO_VERSION }}
      - uses: golangci/golangci-lint-action@v6
        with:
          version: latest

  unit-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: ${{ env.GO_VERSION }}
      - uses: actions/cache@v5
        with:
          path: |
            ~/.cache/go-build
            ~/go/pkg/mod
          key: ${{ runner.os }}-go-${{ hashFiles('**/go.sum') }}
          restore-keys: |
            ${{ runner.os }}-go-
      - run: go install gotest.tools/gotestsum@latest
      - run: gotestsum --format pkgname -- ./...
```

Triggers: identical to `rust-quality-check.yml`.

Action-pin policy follows `../shared/architecture.md` :: "Cross-cutting
Concerns / GitHub Actions JS runtime" — earliest Node-24 native major. The
file lives under `templates/languages/go/.github/workflows/` and is copied
verbatim into downstream projects; the policy scope per #267 was the root
tarnished workflows only, but applying the same rule to new template
workflows from the start avoids the inevitable follow-up migration.

## Error Responses (delta)

No new error variants. All Go-plugin errors flow through the existing
plugin-error contract:

- Plugin install failure → shell warning, non-fatal (existing pattern).
- Marker collision → `print_info` + `return` (existing pattern).
- Overwrite-confirmation declined → `print_info "Skipping ..."` + `return 0`
  (existing pattern).
- Mutually-exclusive setup.sh flag combinations involving `--lang go` are
  rejected by the same code paths as any other language (no Go-specific
  guard).

## Versioning Policy (delta)

`modules.json :: modules[].language` accepts `"go"` as a sixth valid value.
Schema version remains `1`. Forward-compatible (per NFR-2: tolerant readers
ignore unknown values; widening the accepted set is non-breaking).

`tarnished_version` and `manifest_version` semantics unchanged.
