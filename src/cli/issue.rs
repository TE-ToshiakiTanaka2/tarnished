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

    /// Link an existing issue to a project
    Link {
        /// Issue number
        #[arg(value_name = "NUMBER")]
        number: u64,

        /// Override project number from config
        #[arg(long)]
        project_number: Option<u32>,

        /// Override project owner from config
        #[arg(long)]
        project_owner: Option<String>,

        /// Override Size field value (or parse from issue body)
        #[arg(long)]
        size: Option<String>,

        /// Override Priority field value (or parse from issue body)
        #[arg(long)]
        priority: Option<String>,

        /// Override Status field value
        #[arg(long)]
        status: Option<String>,

        /// Parse Size/Priority from issue body if not specified
        #[arg(long, default_value = "true")]
        parse_body: bool,

        /// Only perform label-based project routing (skip default project link)
        #[arg(long)]
        label_only: bool,
    },
}

impl IssueCommands {
    /// Execute the issue subcommand (sync wrapper)
    pub fn execute(&self, _config: &Config) -> anyhow::Result<()> {
        match self {
            Self::Create { .. } | Self::Link { .. } => {
                // These commands need async runtime
                anyhow::bail!("Use execute_async for this command. This is an internal error.");
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
            Self::Link {
                number,
                project_number,
                project_owner,
                size,
                priority,
                status,
                parse_body,
                label_only,
            } => {
                self.execute_link(
                    config,
                    *number,
                    *project_number,
                    project_owner.as_deref(),
                    size.as_deref(),
                    priority.as_deref(),
                    status.as_deref(),
                    *parse_body,
                    *label_only,
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
            if let Some(project_config) = Self::load_project_config(
                config,
                project_number_override,
                project_owner_override,
                size_override,
                priority_override,
                status_override,
            ) {
                Self::link_issue_to_project(
                    &client,
                    &project_config,
                    &issue.node_id,
                    config.verbose,
                )
                .await?;
            }
        }

        Ok(())
    }

    /// Execute the link issue command
    #[allow(clippy::too_many_arguments)]
    async fn execute_link(
        &self,
        config: &Config,
        issue_number: u64,
        project_number_override: Option<u32>,
        project_owner_override: Option<&str>,
        size_override: Option<&str>,
        priority_override: Option<&str>,
        status_override: Option<&str>,
        parse_body: bool,
        label_only: bool,
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
            .or_else(|_| config.token.clone().ok_or(std::env::VarError::NotPresent))
            .map_err(|_| {
                anyhow::anyhow!(
                    "No GitHub token found. Set PROJECT_TOKEN or GITHUB_TOKEN environment variable."
                )
            })?;

        let client = GitHubClient::new(token)?;

        // Get the issue to obtain node_id and optionally parse body
        if config.verbose {
            eprintln!("Fetching issue #{issue_number} from {owner}/{repo_name}...");
        }

        let issue = client.get_issue(owner, repo_name, issue_number).await?;

        // Parse Size/Priority from issue body if requested and not overridden
        let (parsed_size, parsed_priority) = if parse_body {
            parse_size_priority_from_body(issue.body.as_deref())
        } else {
            (None, None)
        };

        // Use parsed values if CLI overrides not provided
        let effective_size = size_override.or(parsed_size.as_deref());
        let effective_priority = priority_override.or(parsed_priority.as_deref());

        if config.verbose {
            if let Some(s) = &parsed_size {
                eprintln!("Parsed Size from body: {s}");
            }
            if let Some(p) = &parsed_priority {
                eprintln!("Parsed Priority from body: {p}");
            }
        }

        // Load and prepare project config
        let Some(project_config) = Self::load_project_config(
            config,
            project_number_override,
            project_owner_override,
            effective_size,
            effective_priority,
            status_override,
        ) else {
            return Ok(());
        };

        // Link to default project (skipped with --label-only)
        if !label_only {
            Self::link_issue_to_project(&client, &project_config, &issue.node_id, config.verbose)
                .await?;
        }

        // Label-based project routing: link to additional projects based on issue labels
        if !project_config.label_projects.is_empty() {
            let label_names: Vec<&str> = issue.labels.iter().map(|l| l.name.as_str()).collect();

            for (label_key, label_config) in &project_config.label_projects {
                if !label_names.contains(&label_key.as_str()) {
                    continue;
                }

                if config.verbose {
                    eprintln!(
                        "Label '{label_key}' matched: routing to project {}/projects/{}",
                        label_config.owner, label_config.number
                    );
                }

                // Build a temporary ProjectConfig for this label route
                let label_project_config = ProjectConfig {
                    default_project: crate::project_config::ProjectReference {
                        owner: label_config.owner.clone(),
                        number: label_config.number,
                    },
                    field_defaults: label_config.field_defaults.clone(),
                    schedule_defaults: None,
                    pr_status: None,
                    label_projects: std::collections::HashMap::new(),
                };

                match Self::link_issue_to_project(
                    &client,
                    &label_project_config,
                    &issue.node_id,
                    config.verbose,
                )
                .await
                {
                    Ok(()) => {}
                    Err(e) => {
                        eprintln!(
                            "Warning: Failed to link issue to label project '{label_key}' \
                             ({}/projects/{}): {e}",
                            label_config.owner, label_config.number
                        );
                    }
                }
            }
        }

        println!("Successfully linked issue #{issue_number} to project");

        Ok(())
    }

    /// Load project config and apply CLI overrides.
    fn load_project_config(
        config: &Config,
        project_number_override: Option<u32>,
        project_owner_override: Option<&str>,
        size_override: Option<&str>,
        priority_override: Option<&str>,
        status_override: Option<&str>,
    ) -> Option<ProjectConfig> {
        let mut project_config =
            match ProjectConfig::load_with_path(config.project_config_path.as_ref()) {
                Ok(c) => c,
                Err(e) => {
                    if config.verbose {
                        eprintln!("Warning: Could not load project config: {e}");
                        eprintln!("Skipping project linking.");
                    }
                    return None;
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

        Some(project_config)
    }

    /// Link an issue to a single project and set field defaults.
    async fn link_issue_to_project(
        client: &GitHubClient,
        project_config: &ProjectConfig,
        issue_node_id: &str,
        verbose: bool,
    ) -> anyhow::Result<()> {
        let project_owner = &project_config.default_project.owner;
        let project_number = project_config.default_project.number;

        if verbose {
            eprintln!("Fetching project {project_owner}/projects/{project_number}...");
        }

        // Get project info
        let project = client.get_project(project_owner, project_number).await?;

        if verbose {
            eprintln!("Adding issue to project '{}'...", project.title);
        }

        // Add issue to project with defaults
        let item_id = client
            .add_issue_to_project_with_defaults(&project, issue_node_id, project_config, verbose)
            .await?;

        println!(
            "Linked to project '{}' (item: {})",
            project.title,
            &item_id[..8.min(item_id.len())]
        );

        // Print applied field defaults
        if !project_config.field_defaults.is_empty() && verbose {
            eprintln!("Applied field defaults:");
            for (field, value) in &project_config.field_defaults {
                eprintln!("  - {field}: {value}");
            }
        }

        Ok(())
    }

    /// Check if this command needs async execution
    pub const fn needs_async(&self) -> bool {
        matches!(self, Self::Create { .. } | Self::Link { .. })
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

/// Parse Size and Priority from issue body
///
/// Supports formats:
/// - `**Size**: L`
/// - `- **Size**: L`
/// - `Size: L`
/// - `**Priority**: High`
/// - `- **Priority**: High`
/// - `Priority: High`
fn parse_size_priority_from_body(body: Option<&str>) -> (Option<String>, Option<String>) {
    let Some(body) = body else {
        return (None, None);
    };

    // Regex patterns for Size and Priority
    // Match: optional "- ", optional "**", "Size"/"Priority", optional "**", ":", whitespace, value
    let size_pattern = regex::Regex::new(r"(?i)(?:-\s*)?\*?\*?Size\*?\*?\s*:\s*(\w+)").unwrap();
    let priority_pattern =
        regex::Regex::new(r"(?i)(?:-\s*)?\*?\*?Priority\*?\*?\s*:\s*(\w+)").unwrap();

    let size = size_pattern
        .captures(body)
        .and_then(|caps| caps.get(1))
        .map(|m| m.as_str().to_string());

    let priority = priority_pattern
        .captures(body)
        .and_then(|caps| caps.get(1))
        .map(|m| m.as_str().to_string());

    (size, priority)
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

    #[test]
    fn test_parse_size_priority_markdown_bold() {
        let body = "## Estimation\n- **Size**: L\n- **Priority**: High";
        let (size, priority) = parse_size_priority_from_body(Some(body));
        assert_eq!(size, Some("L".to_string()));
        assert_eq!(priority, Some("High".to_string()));
    }

    #[test]
    fn test_parse_size_priority_simple() {
        let body = "Size: M\nPriority: Medium";
        let (size, priority) = parse_size_priority_from_body(Some(body));
        assert_eq!(size, Some("M".to_string()));
        assert_eq!(priority, Some("Medium".to_string()));
    }

    #[test]
    fn test_parse_size_priority_case_insensitive() {
        let body = "SIZE: XL\nPRIORITY: LOW";
        let (size, priority) = parse_size_priority_from_body(Some(body));
        assert_eq!(size, Some("XL".to_string()));
        assert_eq!(priority, Some("LOW".to_string()));
    }

    #[test]
    fn test_parse_size_priority_partial() {
        let body = "Only Size: S here";
        let (size, priority) = parse_size_priority_from_body(Some(body));
        assert_eq!(size, Some("S".to_string()));
        assert_eq!(priority, None);
    }

    #[test]
    fn test_parse_size_priority_none() {
        let (size, priority) = parse_size_priority_from_body(None);
        assert_eq!(size, None);
        assert_eq!(priority, None);
    }

    #[test]
    fn test_parse_size_priority_no_match() {
        let body = "This body has no size or priority info";
        let (size, priority) = parse_size_priority_from_body(Some(body));
        assert_eq!(size, None);
        assert_eq!(priority, None);
    }
}
