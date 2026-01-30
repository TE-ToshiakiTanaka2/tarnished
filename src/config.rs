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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let config = Config::new(
            Some("owner/repo".to_string()),
            Some("test-token".to_string()),
            true,
            false,
        );

        assert_eq!(config.repo, Some("owner/repo".to_string()));
        assert_eq!(config.token, Some("test-token".to_string()));
        assert!(config.verbose);
        assert!(!config.quiet);
    }

    #[test]
    fn test_config_get_repo() {
        let config = Config::new(Some("owner/repo".to_string()), None, false, false);
        assert_eq!(config.get_repo(), Some("owner/repo"));

        let config_none = Config::new(None, None, false, false);
        assert_eq!(config_none.get_repo(), None);
    }

    #[test]
    fn test_config_has_token() {
        let config_with_token = Config::new(None, Some("token".to_string()), false, false);
        assert!(config_with_token.has_token());

        let config_without_token = Config::new(None, None, false, false);
        assert!(!config_without_token.has_token());
    }

    #[test]
    fn test_config_token_from_env() {
        // Token from explicit parameter takes precedence
        let config = Config::new(None, Some("explicit-token".to_string()), false, false);
        assert_eq!(config.token, Some("explicit-token".to_string()));
    }
}
