# Code Review: #274

- **Branch**: `feature/TE-ToshiakiTanaka2/#274/add-go-language-template`
- **Base**: develop (merge base: `b104dff`)
- **Review scope**: Medium (~440 implementation lines, 1475 total incl. design docs)
- **Reviewed at**: 2026-05-13
- **Reviewer**: Codex CLI (`codex-cli 0.128.0`)

---

## Codex Verdict: REQUEST_CHANGES

### Warnings (should fix)

- **[templates/languages/go/.claude/settings.json:9]** The shared Claude hook
  runs `go vet ./...` from repository root. In `--monorepo --module svc:go`,
  this file is merged once at the root via
  `templates/languages/go/plugin.sh:97`, but the template intentionally does
  not create a root `go.work`. After users initialize per-module `go.mod`
  files, edits under `svc/**/*.go` will still trigger `go vet ./...` outside
  any module and fail. Make the hook locate the edited file's owning
  module/workspace before running `go vet`, or only install this root hook
  for single-project Go scaffolds.

- **[templates/languages/go/.github/workflows/go-quality-check.yml:35]** The
  workflow has the same root-module assumption: `go build ./...`,
  `go vet ./...`, `golangci-lint`, and `gotestsum -- ./...` all execute from
  repo root. That works for a single-module scaffold, but not for the
  supported monorepo path unless the user manually adds a root `go.work`,
  which this template neither scaffolds nor documents. Either gate this
  workflow to single-project scaffolds, emit module-aware jobs, or
  generate/document the required workspace file.

### Suggestions (nice to have)

- **[templates/languages/go/.devcontainer/devcontainer.json:10]**
  `files.exclude` hides every `**/pkg` directory. In Go repos `pkg/` is
  sometimes real source, and `templates/languages/go/.claude/rules/go.md:70`
  even calls that layout out as valid. Dropping `**/pkg`, or narrowing the
  exclusion to generated cache locations, would avoid hiding user code.

- **[templates/languages/go/.github/workflows/go-quality-check.yml:85]** and
  **[templates/languages/go/plugin.sh:146]** use `latest` for
  `golangci-lint`/`gotestsum`. That keeps the scaffold simple, but it makes
  downstream CI and devcontainer rebuilds non-reproducible. Pinning explicit
  versions would reduce supply-chain churn.

### Positive

- `templates/languages/go/plugin.sh:83` follows the existing helper-based
  merge/copy pattern cleanly, and the always-markered `GO_POSTSH_MARKER`
  block matches the Go-specific idempotency rule from the design.
- `setup.sh:91` keeps the registration delta minimal and consistent:
  language registry, help text, examples, and `go.mod` auto-detection were
  all updated in the right places.

---

## Triage Notes

### Warnings — accepted (fixes will be applied)

Both warnings stem from the same root cause: the design documented the
"hook fails before `go mod init`" edge case but did **not** account for the
monorepo layout where per-module `go.mod` exists but no root `go.work`
unifies them. Codex correctly identifies that `./...` from repo root will
fail in that arrangement.

1. **Claude hook** — Drop `go vet ./...` from the edit-time hook. The hook
   becomes `gofmt -w "$CLAUDE_FILE_PATH"` only. Rationale: edit-time hooks
   should be fast and self-contained; project-wide vet belongs to CI (which
   the workflow already runs). This is consistent with the principle of
   lightweight pre-save checks vs. heavyweight CI checks.

2. **CI workflow** — The same root-module assumption applies to **every**
   language template's CI workflow (Rust's `cargo` discovers Cargo.toml
   upward but still expects one at root or in a workspace). Per-language
   monorepo-aware CI is an out-of-scope cross-cutting concern.
   Documenting the assumption in the workflow header is the lowest-effort,
   precedent-consistent fix.

### Suggestions — pending user decision

3. `devcontainer.json` `files.exclude` — Removing `**/pkg` (and arguably
   `**/bin`) is a one-line edit; the original intent was to mirror Rust's
   `**/target` exclusion but Go has no direct analog.

4. Pinning `golangci-lint`/`gotestsum` to explicit versions — Quality
   improvement, but introduces maintenance burden (someone has to bump the
   pins). The design.md explicitly chose `@latest` for simplicity.
