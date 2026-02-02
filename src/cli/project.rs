//! Project-related CLI commands.
//!
//! Provides commands for GitHub Projects operations.

use clap::Subcommand;

use crate::config::Config;
use crate::github::client::GitHubClient;
use crate::github::types::{FieldDetails, ProjectDetails, ProjectField};

/// Project subcommands
#[derive(Debug, Subcommand)]
pub enum ProjectCommands {
    /// Get project details including field schemas
    Get {
        /// Project owner (username or organization)
        #[arg(long)]
        owner: String,

        /// Project number
        #[arg(long)]
        number: u32,

        /// Output format in JSON
        #[arg(long, default_value = "false")]
        json: bool,
    },
}

impl ProjectCommands {
    /// Check if this command needs async execution
    pub const fn needs_async(&self) -> bool {
        matches!(self, Self::Get { .. })
    }

    /// Execute sync commands (placeholder for non-async commands)
    #[allow(clippy::unused_self)]
    pub fn execute(&self, _config: &Config) -> anyhow::Result<()> {
        anyhow::bail!("This command requires async execution")
    }

    /// Execute async commands
    pub async fn execute_async(&self, config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Get {
                owner,
                number,
                json,
            } => self.get(config, owner, *number, *json).await,
        }
    }

    /// Get project details
    async fn get(
        &self,
        config: &Config,
        owner: &str,
        number: u32,
        json: bool,
    ) -> anyhow::Result<()> {
        // Get token
        let token = std::env::var("PROJECT_TOKEN")
            .or_else(|_| std::env::var("GITHUB_TOKEN"))
            .or_else(|_| config.token.clone().ok_or(std::env::VarError::NotPresent))
            .map_err(|_| anyhow::anyhow!("GitHub token not found. Set PROJECT_TOKEN or GITHUB_TOKEN environment variable"))?;

        // Create client and fetch project
        let client = GitHubClient::new(token)?;
        let project = client.get_project(owner, number).await?;

        // Convert to output format
        let fields: Vec<FieldDetails> = project
            .fields
            .as_ref()
            .map(|f| {
                f.nodes
                    .iter()
                    .filter_map(|field| match field {
                        ProjectField::SingleSelect(sf) => Some(FieldDetails {
                            name: sf.name.clone(),
                            field_type: "SingleSelect".to_string(),
                            options: Some(sf.options.iter().map(|o| o.name.clone()).collect()),
                            iterations: None,
                        }),
                        ProjectField::Iteration(it) => {
                            let iterations = it.configuration.as_ref().map(|cfg| {
                                cfg.iterations.iter().map(|i| i.title.clone()).collect()
                            });
                            Some(FieldDetails {
                                name: it.name.clone(),
                                field_type: "Iteration".to_string(),
                                options: None,
                                iterations,
                            })
                        }
                        ProjectField::Field(f) => {
                            let data_type = f.data_type.as_deref().unwrap_or("Unknown");
                            Some(FieldDetails {
                                name: f.name.clone(),
                                field_type: data_type.to_string(),
                                options: None,
                                iterations: None,
                            })
                        }
                        ProjectField::Other => None,
                    })
                    .collect()
            })
            .unwrap_or_default();

        if json {
            // JSON output
            let details = ProjectDetails {
                id: project.id,
                number,
                title: project.title,
                owner: owner.to_string(),
                fields,
            };
            println!("{}", serde_json::to_string_pretty(&details)?);
        } else {
            // Human-readable output
            println!("Project: {} (#{}) @{}", project.title, number, owner);
            println!("ID: {}", project.id);
            println!();
            println!("Fields:");
            for field in &fields {
                print!("  - {} ({})", field.name, field.field_type);
                if let Some(options) = &field.options {
                    println!(": {}", options.join(", "));
                } else {
                    println!();
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
        command: ProjectCommands,
    }

    #[test]
    fn test_parse_get_command() {
        let cli =
            TestCli::try_parse_from(["test", "get", "--owner", "test", "--number", "1"]).unwrap();
        assert!(matches!(
            cli.command,
            ProjectCommands::Get { owner, number: 1, json: false } if owner == "test"
        ));
    }

    #[test]
    fn test_parse_get_with_json() {
        let cli =
            TestCli::try_parse_from(["test", "get", "--owner", "test", "--number", "1", "--json"])
                .unwrap();
        assert!(matches!(
            cli.command,
            ProjectCommands::Get { json: true, .. }
        ));
    }

    #[test]
    fn test_needs_async() {
        let cmd = ProjectCommands::Get {
            owner: "test".to_string(),
            number: 1,
            json: false,
        };
        assert!(cmd.needs_async());
    }
}
