# /erd:build - Build Verification

Build, compile, and verify projects with intelligent error handling.

## Usage

```
/erd:build [target path or component]
```

## MCP Tools

- **context7**: `resolve-library-id`, `query-docs` -- for looking up build tool documentation when resolving configuration issues

## Behavioral Flow

1. **Detect**: Identify project type and build system (Cargo, npm, pip, make, etc.)
2. **Validate**: Check dependencies and configuration
3. **Execute**: Run build with real-time error monitoring
4. **Analyze**: Parse errors and provide actionable fixes
5. **Fix**: Apply fixes iteratively until build passes

## Build System Detection

| Indicator | Build System | Commands |
| --- | --- | --- |
| `Cargo.toml` | Rust/Cargo | `cargo build`, `cargo clippy`, `cargo fmt --check` |
| `package.json` | Node.js/npm | `npm run build`, `npm run lint` |
| `pyproject.toml` | Python/pip | `python -m build`, `ruff check`, `mypy` |
| `Makefile` | Make | `make build` |
| `go.mod` | Go | `go build ./...`, `go vet ./...` |

## Error Handling Strategy

1. **Read error output** carefully
2. **Identify root cause** (syntax error, type mismatch, missing dependency, etc.)
3. **Apply targeted fix** to the source of the error
4. **Re-run build** to verify fix
5. **Repeat** until build passes or report blocker to user

## Output

```markdown
## Build Report

- Build system: [detected system]
- Status: [passed/failed]

### Checks
- Compilation: [pass/fail]
- Linting: [pass/fail]
- Formatting: [pass/fail]
- Type checking: [pass/fail]

### Errors Fixed (if any)
- [file:line] [description of fix]

### Remaining Issues (if any)
- [issues that need user attention]
```

## CRITICAL BOUNDARIES

**BUILD VERIFICATION ONLY**

This command runs build tools and fixes build errors.

**Will NOT**:
- Modify build system configuration or create new build scripts
- Install missing build dependencies
- Change project structure

**Next Step**: After build passes, use `/erd:test` to run tests.
