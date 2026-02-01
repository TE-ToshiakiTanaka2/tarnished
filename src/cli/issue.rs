//! Issue-related CLI commands.

use clap::Subcommand;

use crate::config::Config;
use crate::github::client::GitHubClient;
use crate::github::types::CreateIssueRequest;
use crate::project_config::ProjectConfig;

/// Issue-related subcommands
#[derive(Debug, Subcommand)]
#[allow(clippy::large_enum_variant)]
pub enum IssueCommands {
    /// List issues (placeholder)
    List,

    /// Create a new issue and optionally link to a project
    Create {
        /// Issue title
        #[arg(long)]
        title: String,

        /// Issue body/description
        #[arg(long)]
        body: Option<String>,

        /// Labels to add (comma-separated or multiple flags)
        #[arg(short, long, value_delimiter = ',')]
        labels: Option<Vec<String>>,

        /// Milestone number
        #[arg(short, long)]
        milestone: Option<u64>,

        /// Assignees (comma-separated or multiple flags)
        #[arg(short, long, value_delimiter = ',')]
        assignees: Option<Vec<String>>,

        /// Link to project (uses config default if not specified)
        #[arg(long, default_value = "true")]
        link_project: bool,

        /// Override project number from config
        #[arg(long)]
        project_number: Option<u32>,

        /// Override project owner from config
        #[arg(long)]
        project_owner: Option<String>,

        /// Override Size field value
        #[arg(long)]
        size: Option<String>,

        /// Override Priority field value
        #[arg(long)]
        priority: Option<String>,

        /// Override Status field value
        #[arg(long)]
        status: Option<String>,
    },

    /// View an issue (placeholder)
    View {
        /// Issue number
        #[arg(value_name = "NUMBER")]
        number: u64,
    },

    /// Edit an issue (placeholder)
    Edit {
        /// Issue number
        #[arg(value_name = "NUMBER")]
        number: u64,
    },

    /// Close an issue (placeholder)
    Close {
        /// Issue number
        #[arg(value_name = "NUMBER")]
        number: u64,
    },
}

impl IssueCommands {
    /// Execute the issue subcommand (sync wrapper)
    pub fn execute(&self, _config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Create { .. } => {
                // Create commands need async runtime
                anyhow::bail!("Use execute_async for create command. This is an internal error.");
            }
            Self::List => {
                println!("Issue list command (not implemented)");
            }
            Self::View { number } => {
                println!("Issue view #{number} command (not implemented)");
            }
            Self::Edit { number } => {
                println!("Issue edit #{number} command (not implemented)");
            }
            Self::Close { number } => {
                println!("Issue close #{number} command (not implemented)");
            }
        }
        Ok(())
    }

    /// Execute the issue subcommand (async version)
    pub async fn execute_async(&self, config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Create {
                title,
                body,
                labels,
                milestone,
                assignees,
                link_project,
                project_number,
                project_owner,
                size,
                priority,
                status,
            } => {
                self.execute_create(
                    config,
                    title,
                    body.as_deref(),
                    labels.as_ref(),
                    *milestone,
                    assignees.as_ref(),
                    *link_project,
                    *project_number,
                    project_owner.as_deref(),
                    size.as_deref(),
                    priority.as_deref(),
                    status.as_deref(),
                )
                .await
            }
            _ => self.execute(config),
        }
    }

    /// Execute the create issue command
    #[allow(clippy::too_many_arguments)]
    async fn execute_create(
        &self,
        config: &Config,
        title: &str,
        body: Option<&str>,
        labels: Option<&Vec<String>>,
        milestone: Option<u64>,
        assignees: Option<&Vec<String>>,
        link_project: bool,
        project_number_override: Option<u32>,
        project_owner_override: Option<&str>,
        size_override: Option<&str>,
        priority_override: Option<&str>,
        status_override: Option<&str>,
    ) -> anyhow::Result<()> {
        // Get repository from config
        let repo = config.get_repo().ok_or_else(|| {
            anyhow::anyhow!(
                "Repository not specified. Use --repo or set ERD_REPO environment variable."
            )
        })?;
        let (owner, repo_name) = parse_repo(repo)?;

        // Get token - prefer PROJECT_TOKEN for project operations, fall back to GITHUB_TOKEN
        let token = std::env::var("PROJECT_TOKEN")
            .or_else(|_| std::env::var("GITHUB_TOKEN"))
            .or_else(|_| {
                config
                    .token
                    .clone()
                    .ok_or(std::env::VarError::NotPresent)
            })
            .map_err(|_| anyhow::anyhow!("No GitHub token found. Set PROJECT_TOKEN or GITHUB_TOKEN environment variable."))?;

        let client = GitHubClient::new(token)?;

        // Create the issue
        let request = CreateIssueRequest {
            title: title.to_string(),
            body: body.map(String::from),
            labels: labels.cloned(),
            milestone,
            assignees: assignees.cloned(),
        };

        if config.verbose {
            eprintln!("Creating issue in {owner}/{repo_name}...");
        }

        let issue = client.create_issue(owner, repo_name, &request).await?;

        println!("Created issue #{}: {}", issue.number, issue.html_url);

        // Link to project if requested
        if link_project {
            self.link_issue_to_project(
                &client,
                config,
                &issue.node_id,
                project_number_override,
                project_owner_override,
                size_override,
                priority_override,
                status_override,
            )
            .await?;
        }

        Ok(())
    }

    /// Link an issue to a project and set field defaults
    #[allow(clippy::too_many_arguments)]
    async fn link_issue_to_project(
        &self,
        client: &GitHubClient,
        config: &Config,
        issue_node_id: &str,
        project_number_override: Option<u32>,
        project_owner_override: Option<&str>,
        size_override: Option<&str>,
        priority_override: Option<&str>,
        status_override: Option<&str>,
    ) -> anyhow::Result<()> {
        // Load project config
        let mut project_config = match ProjectConfig::load() {
            Ok(c) => c,
            Err(e) => {
                if config.verbose {
                    eprintln!("Warning: Could not load project config: {e}");
                    eprintln!("Skipping project linking.");
                }
                return Ok(());
            }
        };

        // Apply CLI overrides
        if let Some(owner) = project_owner_override {
            project_config.default_project.owner = owner.to_string();
        }
        if let Some(number) = project_number_override {
            project_config.default_project.number = number;
        }

        // Apply field overrides
        if let Some(size) = size_override {
            project_config
                .field_defaults
                .insert("Size".to_string(), size.to_string());
        }
        if let Some(priority) = priority_override {
            project_config
                .field_defaults
                .insert("Priority".to_string(), priority.to_string());
        }
        if let Some(status) = status_override {
            project_config
                .field_defaults
                .insert("Status".to_string(), status.to_string());
        }

        let project_owner = &project_config.default_project.owner;
        let project_number = project_config.default_project.number;

        if config.verbose {
            eprintln!("Fetching project {project_owner}/projects/{project_number}...");
        }

        // Get project info
        let project = client.get_project(project_owner, project_number).await?;

        if config.verbose {
            eprintln!("Adding issue to project '{}'...", project.title);
        }

        // Add issue to project with defaults
        let item_id = client
            .add_issue_to_project_with_defaults(&project, issue_node_id, &project_config)
            .await?;

        println!(
            "Linked to project '{}' (item: {})",
            project.title,
            &item_id[..8.min(item_id.len())]
        );

        // Print applied field defaults
        if !project_config.field_defaults.is_empty() && config.verbose {
            eprintln!("Applied field defaults:");
            for (field, value) in &project_config.field_defaults {
                eprintln!("  - {field}: {value}");
            }
        }

        Ok(())
    }

    /// Check if this command needs async execution
    pub const fn needs_async(&self) -> bool {
        matches!(self, Self::Create { .. })
    }
}

/// Parse repository string into (owner, repo) tuple
fn parse_repo(repo: &str) -> anyhow::Result<(&str, &str)> {
    let parts: Vec<&str> = repo.split('/').collect();
    if parts.len() != 2 {
        anyhow::bail!("Invalid repository format: {repo}. Expected 'owner/repo'.");
    }
    Ok((parts[0], parts[1]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_repo_valid() {
        let (owner, repo) = parse_repo("owner/repo").unwrap();
        assert_eq!(owner, "owner");
        assert_eq!(repo, "repo");
    }

    #[test]
    fn test_parse_repo_invalid() {
        assert!(parse_repo("invalid").is_err());
        assert!(parse_repo("a/b/c").is_err());
        assert!(parse_repo("").is_err());
    }
}
