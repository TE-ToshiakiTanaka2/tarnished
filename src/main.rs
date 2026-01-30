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

mod cli;
mod config;
mod error;

use anyhow::Result;
use clap::Parser;

use cli::Cli;

fn main() -> Result<()> {
    let cli = Cli::parse();
    cli.execute()
}
