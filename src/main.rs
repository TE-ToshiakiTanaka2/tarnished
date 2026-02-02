//! # erd
//!
//! A GitHub Issue/Tag management CLI tool.
//!
//! ## Usage
//!
//! ```bash
//! erd issue list
//! erd issue create --title "New feature" --body "Description"
//! erd tag create v1.0.0
//! ```

mod cli;
mod config;
pub mod date_parser;
mod error;
mod git_ops;
mod github;
mod project_config;
mod tag_config;
mod version;

use anyhow::Result;
use clap::Parser;

use cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.needs_async() {
        // Run async commands with tokio runtime
        let rt = tokio::runtime::Runtime::new()?;
        rt.block_on(cli.execute_async())
    } else {
        // Run sync commands directly
        cli.execute()
    }
}
