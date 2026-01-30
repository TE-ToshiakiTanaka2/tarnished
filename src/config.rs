use std::env;

/// Global configuration derived from CLI arguments and environment
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct Config {
    /// Target repository in "owner/repo" format
    pub repo: Option<String>,
    /// GitHub API token
    pub token: Option<String>,
    /// Enable verbose output
    pub verbose: bool,
    /// Suppress non-essential output
    pub quiet: bool,
}

#[allow(dead_code)]
impl Config {
    /// Create a new Config from CLI arguments
    pub fn new(repo: Option<String>, token: Option<String>, verbose: bool, quiet: bool) -> Self {
        Self {
            repo,
            token: token.or_else(|| env::var("GITHUB_TOKEN").ok()),
            verbose,
            quiet,
        }
    }

    /// Get the repository, attempting to detect from git if not specified
    pub fn get_repo(&self) -> Option<&str> {
        self.repo.as_deref()
    }

    /// Check if we have a valid token
    pub const fn has_token(&self) -> bool {
        self.token.is_some()
    }
}
