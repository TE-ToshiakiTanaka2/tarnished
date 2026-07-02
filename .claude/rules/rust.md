---
paths:
  - "**/*.rs"
---

# Rust Coding Rules

## Style

- Edition 2024, use latest stable Rust
- Format with `cargo fmt` (rustfmt: max_width=100, tab_spaces=4, Unix line endings)
- snake_case for functions/variables/modules, PascalCase for types/traits/enums, SCREAMING_SNAKE_CASE for constants
- Configure lints in `[lints.clippy]` in Cargo.toml: enable `all` and `pedantic` groups (warn level), cherry-pick useful nursery lints individually

## Error Handling

- Use `anyhow::Result` for application-level errors with context
- Use `thiserror` derive macro for library/domain error types
- Propagate errors with `?` operator -- never silently ignore
- Add context with `.context()` or `.with_context(|| format!(..))`
- Pattern match on error variants when recovery is possible

## Type System

- Prefer strong types over primitive types for domain values (newtype pattern)
- Use `Option<T>` for nullable values, never sentinel values like -1 or ""
- Prefer `&str` over `String` in function parameters where ownership is not needed
- Consider `Cow<'_, str>` for functions that conditionally allocate (escaping, normalization); for most functions `&str` or `String` is clearer

## Testing

- Place unit tests in `#[cfg(test)] mod tests` within the same file
- Place integration tests in `tests/` directory
- Name tests: `test_<function>_<scenario>_<expected>`
- Use `assert_eq!`, `assert_ne!`, `assert!(matches!(..))` for assertions
- Test both success and error paths

## Security

- `unsafe_code` = forbid -- no unsafe blocks allowed
- Validate all external input (CLI args, file content, network data)
- Use `secrecy` crate for sensitive values in memory
- Prefer `&[u8]` with explicit encoding over raw string manipulation for binary data

## Dependencies

- Keep dependencies minimal -- optionally audit with `cargo deny` (not preinstalled; `cargo install cargo-deny`)
- Pin major versions in `Cargo.toml`
- For file watching during development, `bacon` is a good option (not preinstalled; `cargo install bacon`); `cargo add`/`cargo rm` are built-in
- Run `cargo clippy` and `cargo fmt` before every commit
- Enable `overflow-checks = true` in `[profile.release]`

## Module Organization

- One module per file, group related functionality in subdirectories
- Use `mod.rs` or filename modules for re-exports
- Keep public API minimal -- default to `pub(crate)` visibility
