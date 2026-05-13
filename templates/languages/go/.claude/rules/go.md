---
paths:
  - "**/*.go"
---

# Go Coding Rules

## Style

- Use the latest stable Go (set via `go.mod`'s `go` directive)
- Format with `gofmt` (standard Go formatter; no configuration knobs)
- Use `goimports` (via `golangci-lint`) to keep imports grouped: stdlib, third-party, project-local
- Tab indentation (gofmt default), no trailing whitespace
- Package names: lowercase, single word, no underscores. Avoid stutter (`http.Server`, not `http.HTTPServer`)
- Identifiers: `MixedCaps` for exported, `mixedCaps` for unexported. Acronyms stay uppercase (`URL`, `HTTPClient`, `userID`)
- Receiver names: short (1-2 chars), consistent across methods of the same type

## Error Handling

- Return errors as the last value; never use exceptions or panics for control flow
- Wrap errors with `fmt.Errorf("context: %w", err)` to preserve the chain
- Inspect wrapped errors with `errors.Is` (sentinel) and `errors.As` (typed)
- Define sentinel errors as `var ErrNotFound = errors.New("not found")`; define typed errors as structs implementing `Error() string`
- Never silently discard errors with `_ = call()` — handle, log, or propagate
- `panic` is reserved for genuinely unrecoverable states (programmer error); convert to error at API boundaries

## Type System

- Prefer explicit types over `interface{}` / `any`; use generics (Go 1.18+) when a type parameter actually adds value
- Use pointer receivers when the method mutates or when the struct is large; use value receivers otherwise. Be consistent within a type
- Avoid named return values unless they clarify intent or are required by `defer` for cleanup
- `nil` checks: prefer explicit `if x == nil` over relying on zero values when intent matters
- Use `struct{}` for set-style maps (`map[string]struct{}`) — zero memory cost vs. `bool`

## Concurrency

- Communicate by sharing channels; don't share by communicating with mutexes when a channel is clearer
- Always `defer wg.Done()` / `defer mu.Unlock()` paired with the acquire
- Use `context.Context` for cancellation and deadlines; accept it as the first parameter
- Race detector (`go test -race`) is mandatory for any code touching goroutines

## Testing

- Place tests in `_test.go` files alongside the code (same package for white-box, `package foo_test` for black-box)
- Table-driven tests with `t.Run(name, ...)` for clear failure output
- Use `t.Helper()` in test helpers so failures point to the caller
- Prefer the standard library (`testing`); reach for `testify` only if assertion ergonomics meaningfully help readability
- Always run `go test -race ./...` locally before pushing

## Security

- Validate all external input (CLI args, file content, network data, env vars)
- Use `crypto/rand` for any randomness with security implications — never `math/rand`
- Avoid `os/exec.Command` with shell strings; pass args as a slice
- Use `filepath.Clean` and `filepath.Rel` to prevent path traversal
- Don't log secrets; redact at the boundary

## Dependencies

- Keep `go.mod` minimal; audit additions
- Pin versions in `go.mod`; use `go mod tidy` before committing
- Run `golangci-lint run` and `gofmt -l .` before every commit
- `go vet ./...` and `go test -race ./...` are part of the local pre-push checklist

## Module Organization

- One package per directory; package name matches the last path segment
- Keep the public API minimal — start unexported, export when a consumer needs it
- `internal/` for code that must not be imported outside the module
- `cmd/<name>/main.go` for binaries; `pkg/` is only useful if you publish reusable libraries
