pub mod issue;
pub mod pr;
pub mod project;
pub mod repo;
pub mod tag;

use std::path::PathBuf;

use clap::{Parser, Subcommand};

use crate::config::Config;
use issue::IssueCommands;
use pr::PrCommands;
use project::ProjectCommands;
use repo::RepoCommands;
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

    /// Path to project configuration file (default: .github/project.yml)
    #[arg(short, long, global = true, env = "ERD_CONFIG")]
    pub config: Option<PathBuf>,

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
    /// Manage pull requests
    Pr {
        #[command(subcommand)]
        command: PrCommands,
    },
    /// Manage GitHub Projects
    Project {
        #[command(subcommand)]
        command: ProjectCommands,
    },
    /// Repository operations
    Repo {
        #[command(subcommand)]
        command: RepoCommands,
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
            self.config.clone(),
            self.verbose,
            self.quiet,
        )
    }

    /// Execute the CLI command (sync version for non-async commands)
    pub fn execute(&self) -> anyhow::Result<()> {
        let config = self.to_config();

        if config.verbose {
            eprintln!("Config: {config:?}");
        }

        match &self.command {
            Commands::Issue { command } => {
                if command.needs_async() {
                    anyhow::bail!(
                        "This command requires async execution. Use execute_async instead."
                    );
                }
                command.execute(&config)
            }
            Commands::Pr { command } => {
                if command.needs_async() {
                    anyhow::bail!(
                        "This command requires async execution. Use execute_async instead."
                    );
                }
                command.execute(&config)
            }
            Commands::Project { command } => {
                if command.needs_async() {
                    anyhow::bail!(
                        "This command requires async execution. Use execute_async instead."
                    );
                }
                command.execute(&config)
            }
            Commands::Repo { command } => {
                if command.needs_async() {
                    anyhow::bail!(
                        "This command requires async execution. Use execute_async instead."
                    );
                }
                command.execute(&config)
            }
            Commands::Tag { command } => command.execute(),
        }
    }

    /// Execute the CLI command (async version)
    pub async fn execute_async(&self) -> anyhow::Result<()> {
        let config = self.to_config();

        if config.verbose {
            eprintln!("Config: {config:?}");
        }

        match &self.command {
            Commands::Issue { command } => command.execute_async(&config).await,
            Commands::Pr { command } => command.execute_async(&config).await,
            Commands::Project { command } => command.execute_async(&config).await,
            Commands::Repo { command } => command.execute_async(&config).await,
            Commands::Tag { command } => command.execute(),
        }
    }

    /// Check if the current command needs async execution
    #[allow(clippy::missing_const_for_fn)]
    pub fn needs_async(&self) -> bool {
        match &self.command {
            Commands::Issue { command } => command.needs_async(),
            Commands::Pr { command } => command.needs_async(),
            Commands::Project { command } => command.needs_async(),
            Commands::Repo { command } => command.needs_async(),
            Commands::Tag { .. } => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cli_parse_help() {
        // Verify CLI can be parsed (clap derive)
        let result = Cli::try_parse_from(["erd", "--help"]);
        assert!(result.is_err()); // --help causes early exit
    }

    #[test]
    fn test_cli_parse_version() {
        let result = Cli::try_parse_from(["erd", "--version"]);
        assert!(result.is_err()); // --version causes early exit
    }

    #[test]
    fn test_cli_parse_issue_list() {
        let cli = Cli::try_parse_from(["erd", "issue", "list"]).unwrap();
        assert!(matches!(cli.command, Commands::Issue { .. }));
    }

    #[test]
    fn test_cli_parse_tag_list() {
        let cli = Cli::try_parse_from(["erd", "tag", "list"]).unwrap();
        assert!(matches!(cli.command, Commands::Tag { .. }));
    }

    #[test]
    fn test_cli_parse_with_repo() {
        let cli = Cli::try_parse_from(["erd", "--repo", "owner/repo", "issue", "list"]).unwrap();
        assert_eq!(cli.repo, Some("owner/repo".to_string()));
    }

    #[test]
    fn test_cli_parse_with_verbose() {
        let cli = Cli::try_parse_from(["erd", "--verbose", "issue", "list"]).unwrap();
        assert!(cli.verbose);
    }

    #[test]
    fn test_cli_parse_with_quiet() {
        let cli = Cli::try_parse_from(["erd", "--quiet", "issue", "list"]).unwrap();
        assert!(cli.quiet);
    }

    #[test]
    fn test_cli_to_config() {
        let cli =
            Cli::try_parse_from(["erd", "--repo", "owner/repo", "--verbose", "issue", "list"])
                .unwrap();
        let config = cli.to_config();

        assert_eq!(config.repo, Some("owner/repo".to_string()));
        assert!(config.verbose);
        assert!(!config.quiet);
    }

    #[test]
    fn test_cli_parse_invalid_command() {
        let result = Cli::try_parse_from(["erd", "invalid"]);
        assert!(result.is_err());
    }

    #[test]
    fn test_cli_parse_repo_projects() {
        let cli = Cli::try_parse_from(["erd", "repo", "projects"]).unwrap();
        assert!(matches!(cli.command, Commands::Repo { .. }));
    }

    #[test]
    fn test_cli_parse_project_get() {
        let cli =
            Cli::try_parse_from(["erd", "project", "get", "--owner", "test", "--number", "1"])
                .unwrap();
        assert!(matches!(cli.command, Commands::Project { .. }));
    }

    #[test]
    fn test_cli_parse_with_config() {
        let cli = Cli::try_parse_from(["erd", "--config", ".github/project.yml", "issue", "list"])
            .unwrap();
        assert_eq!(cli.config, Some(PathBuf::from(".github/project.yml")));
    }

    #[test]
    fn test_cli_to_config_with_config_path() {
        let cli = Cli::try_parse_from([
            "erd",
            "--config",
            "custom/path.yml",
            "--repo",
            "owner/repo",
            "pr",
            "status",
            "1",
        ])
        .unwrap();
        let config = cli.to_config();

        assert_eq!(config.repo, Some("owner/repo".to_string()));
        assert_eq!(
            config.project_config_path,
            Some(PathBuf::from("custom/path.yml"))
        );
    }
}
