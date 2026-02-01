//! PR-related CLI commands.

use clap::Subcommand;

use crate::config::Config;
use crate::github::client::GitHubClient;
use crate::github::types::{LinkedIssue, ProjectField, ProjectV2};
use crate::project_config::ProjectConfig;

/// PR-related subcommands
#[derive(Debug, Subcommand)]
pub enum PrCommands {
    /// Update project status for linked issues
    Status {
        /// PR number
        #[arg(value_name = "NUMBER")]
        number: u64,

        /// Override status value (default from config or "In Review")
        #[arg(long)]
        status: Option<String>,

        /// Override project number from config
        #[arg(long)]
        project_number: Option<u32>,

        /// Override project owner from config
        #[arg(long)]
        project_owner: Option<String>,
    },
}

impl PrCommands {
    /// Execute the PR subcommand (sync wrapper)
    pub fn execute(&self, _config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Status { .. } => {
                anyhow::bail!("Use execute_async for this command. This is an internal error.");
            }
        }
    }

    /// Execute the PR subcommand (async version)
    pub async fn execute_async(&self, config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Status {
                number,
                status,
                project_number,
                project_owner,
            } => {
                self.execute_status(
                    config,
                    *number,
                    status.as_deref(),
                    *project_number,
                    project_owner.as_deref(),
                )
                .await
            }
        }
    }

    /// Execute the pr status command
    #[allow(clippy::too_many_lines)]
    async fn execute_status(
        &self,
        config: &Config,
        pr_number: u64,
        status_override: Option<&str>,
        project_number_override: Option<u32>,
        project_owner_override: Option<&str>,
    ) -> anyhow::Result<()> {
        // Get repository from config
        let repo = config.get_repo().ok_or_else(|| {
            anyhow::anyhow!(
                "Repository not specified. Use --repo or set ERD_REPO environment variable."
            )
        })?;
        let (owner, repo_name) = parse_repo(repo)?;

        // Get token
        let token = std::env::var("PROJECT_TOKEN")
            .or_else(|_| std::env::var("GITHUB_TOKEN"))
            .or_else(|_| config.token.clone().ok_or(std::env::VarError::NotPresent))
            .map_err(|_| {
                anyhow::anyhow!(
                    "No GitHub token found. Set PROJECT_TOKEN or GITHUB_TOKEN environment variable."
                )
            })?;

        let client = GitHubClient::new(token)?;

        // Load project config
        let project_config = match ProjectConfig::load() {
            Ok(c) => c,
            Err(e) => {
                if config.verbose {
                    eprintln!("Warning: Could not load project config: {e}");
                }
                return Err(anyhow::anyhow!(
                    "Project configuration required. Create .github/project.yml"
                ));
            }
        };

        // Determine project settings
        let project_owner = project_owner_override.map_or_else(
            || project_config.default_project.owner.clone(),
            String::from,
        );
        let project_number =
            project_number_override.unwrap_or(project_config.default_project.number);

        // Determine target status
        let target_status = status_override
            .map(String::from)
            .or_else(|| project_config.get_pr_open_status().cloned())
            .unwrap_or_else(|| "In Review".to_string());

        if config.verbose {
            eprintln!("Fetching linked issues for PR #{pr_number} in {owner}/{repo_name}...");
        }

        // Get linked issues
        let linked_issues = client
            .get_pr_linked_issues(owner, repo_name, pr_number)
            .await?;

        if linked_issues.is_empty() {
            println!(
                "Warning: No linked issues found for PR #{pr_number}. No status updates performed."
            );
            return Ok(());
        }

        if config.verbose {
            eprintln!("Found {} linked issue(s):", linked_issues.len());
            for issue in &linked_issues {
                eprintln!("  - #{}: {}", issue.number, issue.title);
            }
        }

        // Get project info
        if config.verbose {
            eprintln!("Fetching project {project_owner}/projects/{project_number}...");
        }

        let project = client.get_project(&project_owner, project_number).await?;

        // Update status for each linked issue
        let mut updated_count = 0;
        let mut skipped_count = 0;

        for issue in &linked_issues {
            match self
                .update_issue_status(
                    &client,
                    config,
                    &project,
                    issue,
                    project_number,
                    &target_status,
                )
                .await
            {
                Ok(true) => {
                    updated_count += 1;
                    if !config.quiet {
                        println!(
                            "Updated issue #{} status to \"{target_status}\"",
                            issue.number
                        );
                    }
                }
                Ok(false) => {
                    skipped_count += 1;
                    if config.verbose {
                        eprintln!(
                            "Skipped issue #{}: not in project or status field not found",
                            issue.number
                        );
                    }
                }
                Err(e) => {
                    eprintln!("Warning: Failed to update issue #{}: {e}", issue.number);
                    skipped_count += 1;
                }
            }
        }

        if !config.quiet {
            println!(
                "PR #{pr_number}: Updated {updated_count} issue(s) to \"{target_status}\"{}",
                if skipped_count > 0 {
                    format!(", skipped {skipped_count}")
                } else {
                    String::new()
                }
            );
        }

        Ok(())
    }

    /// Update a single issue's project status
    async fn update_issue_status(
        &self,
        client: &GitHubClient,
        config: &Config,
        project: &ProjectV2,
        issue: &LinkedIssue,
        project_number: u32,
        target_status: &str,
    ) -> anyhow::Result<bool> {
        // Find the issue's project item ID
        let Some(item_id) = client
            .get_issue_project_item_id(&issue.id, project_number)
            .await?
        else {
            if config.verbose {
                eprintln!(
                    "Issue #{} is not in project #{project_number}",
                    issue.number
                );
            }
            return Ok(false);
        };

        // Find the Status field and target option
        let Some((field_id, option_id)) = find_status_option(project, target_status) else {
            if config.verbose {
                eprintln!("Status field or option \"{target_status}\" not found in project");
            }
            return Ok(false);
        };

        // Update the field
        client
            .update_project_item_field(&project.id, &item_id, field_id, option_id)
            .await?;

        Ok(true)
    }

    /// Check if this command needs async execution
    pub const fn needs_async(&self) -> bool {
        matches!(self, Self::Status { .. })
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

/// Find the Status field and the option ID for the target status value
fn find_status_option<'a>(
    project: &'a ProjectV2,
    target_status: &str,
) -> Option<(&'a str, &'a str)> {
    let fields = project.fields.as_ref()?;

    for field in &fields.nodes {
        if let ProjectField::SingleSelect(sf) = field {
            if sf.name == "Status" {
                for option in &sf.options {
                    if option.name.eq_ignore_ascii_case(target_status) {
                        return Some((&sf.id, &option.id));
                    }
                }
            }
        }
    }

    None
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
