# Rust Plugin

Provides a complete Rust development environment with rust-analyzer, common tools, and CI workflow.

## Features

- **Rust toolchain** via rustup (configurable version)
- **rust-analyzer** language server
- **Common cargo tools** (cargo-watch, cargo-edit, etc.)
- **GitHub Actions CI** workflow template

## Configuration

### Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `RUST_VERSION` | select | stable | Rust toolchain version |
| `RUST_COMPONENTS` | multiselect | clippy, rustfmt | Additional rustup components |
| `CARGO_TOOLS` | multiselect | cargo-watch, cargo-edit | Cargo tools to install |

### Rust Version Options

- `stable` - Latest stable release
- `nightly` - Latest nightly build
- `1.75.0`, `1.76.0`, `1.77.0` - Specific versions

### Components

- `clippy` - Rust linter
- `rustfmt` - Code formatter
- `rust-src` - Rust source code (for rust-analyzer)
- `rust-analyzer` - Language server component
- `llvm-tools-preview` - LLVM tools for coverage

### Cargo Tools

- `cargo-watch` - Watch for changes and run commands
- `cargo-edit` - Add/remove/upgrade dependencies
- `cargo-deny` - Check dependencies for issues
- `cargo-audit` - Security audit
- `cargo-nextest` - Next-generation test runner
- `cargo-llvm-cov` - Code coverage

## VSCode Extensions

- `rust-lang.rust-analyzer` - Rust language support
- `tamasfe.even-better-toml` - TOML support
- `serayuzgur.crates` - Crates.io integration

## Generated Files

- `.github/workflows/rust-ci.yml` - CI workflow with check, fmt, clippy, and test jobs

## Claude Code Hooks

- Format check on `.rs` file writes
