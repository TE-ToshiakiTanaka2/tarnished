---
paths:
  - "**/*.rs"
---

# Rust Coding Rules

## Style

- Edition 2021, minimum Rust 1.74
- Format with `cargo fmt` (rustfmt defaults)
- snake_case for functions/variables/modules, PascalCase for types/traits/enums, SCREAMING_SNAKE_CASE for constants
- Max line width: 100 characters

## Linting

- `unsafe_code` = forbid -- no unsafe code allowed
- `missing_docs` = warn
- Configure lints in `[lints.clippy]` in Cargo.toml: enable `all` and `pedantic` groups (warn level), cherry-pick useful nursery lints individually
- Allowed lints: `module_name_repetitions`, `must_use_candidate`, `missing_errors_doc`, `missing_panics_doc`, `unnecessary_wraps`
- Cognitive complexity threshold: 25
- Max function arguments: 7

## Error Handling

- Use `anyhow::Result` for application-level errors
- Use `thiserror` for library/domain error types
- Never swallow errors silently -- propagate with `?` or handle explicitly
- Provide context with `.context()` or `.with_context()`

## Testing

- Place unit tests in `#[cfg(test)] mod tests` within the same file
- Place integration tests in `tests/` directory
- Use descriptive test names: `test_<function>_<scenario>_<expected>`
- Test error paths, not just happy paths

## Security

- Never use `unsafe` blocks
- Validate all external input before processing
- Use strong types instead of raw strings for domain values
- Prefer `&str` over `String` in function parameters where ownership is not needed

## CLI Design

- Use clap derive macros for argument parsing
- Support both CLI flags and environment variables
- Follow subcommand pattern: `erd <subcommand> <action>`

## Module Organization

- Group related functionality into submodules
- Use mod.rs for re-exports
- Keep types.rs for shared type definitions
