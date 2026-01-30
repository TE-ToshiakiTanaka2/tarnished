//! # erd
//!
//! A GitHub Issue/Tag management CLI tool.
//!
//! ## Usage
//!
//! ```bash
//! erd issue list
//! erd tag create v1.0.0
//! ```

mod branch_matcher;
mod cli;
mod config;
mod error;
mod git_ops;
mod tag_config;
mod version;

use anyhow::Result;
use clap::Parser;

use cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();
    cli.execute()
}
