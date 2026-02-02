//! Repository-related CLI commands.
//!
//! Provides commands for repository operations like listing linked projects.

use clap::Subcommand;

use crate::config::Config;
use crate::github::client::GitHubClient;
use crate::github::types::ProjectV2Summary;

/// Repository subcommands
#[derive(Debug, Subcommand)]
pub enum RepoCommands {
    /// List projects linked to the repository
    Projects {
        /// Output format in JSON
        #[arg(long, default_value = "false")]
        json: bool,

        /// Include closed projects
        #[arg(long, default_value = "false")]
        include_closed: bool,
    },
}

impl RepoCommands {
    /// Check if this command needs async execution
    pub const fn needs_async(&self) -> bool {
        matches!(self, Self::Projects { .. })
    }

    /// Execute sync commands (placeholder for non-async commands)
    #[allow(clippy::unused_self)]
    pub fn execute(&self, _config: &Config) -> anyhow::Result<()> {
        anyhow::bail!("This command requires async execution")
    }

    /// Execute async commands
    pub async fn execute_async(&self, config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Projects {
                json,
                include_closed,
            } => self.projects(config, *json, *include_closed).await,
        }
    }

    /// List projects linked to the repository
    async fn projects(
        &self,
        config: &Config,
        json: bool,
        include_closed: bool,
    ) -> anyhow::Result<()> {
        // Get repository from config or environment
        let repo = config.repo.as_ref().ok_or_else(|| {
            anyhow::anyhow!(
                "Repository not specified. Use --repo or set ERD_REPO environment variable"
            )
        })?;

        // Parse owner/repo
        let parts: Vec<&str> = repo.split('/').collect();
        if parts.len() != 2 {
            anyhow::bail!("Invalid repository format. Expected 'owner/repo'");
        }
        let (owner, repo_name) = (parts[0], parts[1]);

        // Get token
        let token = std::env::var("PROJECT_TOKEN")
            .or_else(|_| std::env::var("GITHUB_TOKEN"))
            .or_else(|_| config.token.clone().ok_or(std::env::VarError::NotPresent))
            .map_err(|_| anyhow::anyhow!("GitHub token not found. Set PROJECT_TOKEN or GITHUB_TOKEN environment variable"))?;

        // Create client and fetch projects
        let client = GitHubClient::new(token)?;
        let projects = client.get_repository_projects(owner, repo_name).await?;

        // Filter closed projects if needed
        let projects: Vec<ProjectV2Summary> = if include_closed {
            projects
        } else {
            projects.into_iter().filter(|p| !p.closed).collect()
        };

        if json {
            // JSON output
            let output: Vec<serde_json::Value> = projects
                .iter()
                .map(|p| {
                    serde_json::json!({
                        "number": p.number,
                        "title": p.title,
                        "owner": p.owner.login,
                        "url": p.url,
                        "closed": p.closed
                    })
                })
                .collect();
            println!("{}", serde_json::to_string_pretty(&output)?);
        } else {
            // Human-readable output
            if projects.is_empty() {
                println!("No projects linked to {owner}/{repo_name}");
            } else {
                println!("Projects linked to {owner}/{repo_name}:");
                for project in &projects {
                    let status = if project.closed { " (closed)" } else { "" };
                    println!(
                        "  #{} - {} (@{}){}",
                        project.number, project.title, project.owner.login, status
                    );
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[derive(Parser)]
    struct TestCli {
        #[command(subcommand)]
        command: RepoCommands,
    }

    #[test]
    fn test_parse_projects_command() {
        let cli = TestCli::try_parse_from(["test", "projects"]).unwrap();
        assert!(matches!(
            cli.command,
            RepoCommands::Projects {
                json: false,
                include_closed: false
            }
        ));
    }

    #[test]
    fn test_parse_projects_with_json() {
        let cli = TestCli::try_parse_from(["test", "projects", "--json"]).unwrap();
        assert!(matches!(
            cli.command,
            RepoCommands::Projects { json: true, .. }
        ));
    }

    #[test]
    fn test_parse_projects_with_include_closed() {
        let cli = TestCli::try_parse_from(["test", "projects", "--include-closed"]).unwrap();
        assert!(matches!(
            cli.command,
            RepoCommands::Projects {
                include_closed: true,
                ..
            }
        ));
    }

    #[test]
    fn test_needs_async() {
        let cmd = RepoCommands::Projects {
            json: false,
            include_closed: false,
        };
        assert!(cmd.needs_async());
    }
}
