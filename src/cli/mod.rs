pub mod issue;
pub mod tag;

use clap::{Parser, Subcommand};

use crate::config::Config;
use issue::IssueCommands;
use tag::TagCommands;

/// erd - GitHub Issue/Tag management CLI
#[derive(Debug, Parser)]
#[command(name = "erd")]
#[command(author, version, about, long_about = None)]
#[command(propagate_version = true)]
pub struct Cli {
    /// Target repository in 'owner/repo' format
    #[arg(short, long, global = true, env = "ERD_REPO")]
    pub repo: Option<String>,

    /// GitHub API token
    #[arg(short, long, global = true, env = "GITHUB_TOKEN")]
    pub token: Option<String>,

    /// Enable verbose output
    #[arg(short, long, global = true, default_value = "false")]
    pub verbose: bool,

    /// Suppress non-essential output
    #[arg(short, long, global = true, default_value = "false")]
    pub quiet: bool,

    #[command(subcommand)]
    pub command: Commands,
}

/// Top-level commands
#[derive(Debug, Subcommand)]
pub enum Commands {
    /// Manage GitHub issues
    Issue {
        #[command(subcommand)]
        command: IssueCommands,
    },
    /// Manage git tags
    Tag {
        #[command(subcommand)]
        command: TagCommands,
    },
}

impl Cli {
    /// Create a Config from CLI arguments
    pub fn to_config(&self) -> Config {
        Config::new(
            self.repo.clone(),
            self.token.clone(),
            self.verbose,
            self.quiet,
        )
    }

    /// Execute the CLI command
    pub fn execute(&self) -> anyhow::Result<()> {
        let config = self.to_config();

        if config.verbose {
            eprintln!("Config: {:?}", config);
        }

        match &self.command {
            Commands::Issue { command } => command.execute(),
            Commands::Tag { command } => command.execute(),
        }
    }
}
