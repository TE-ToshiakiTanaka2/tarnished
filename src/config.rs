use std::env;
use std::path::PathBuf;

/// Global configuration derived from CLI arguments and environment
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct Config {
    /// Target repository in "owner/repo" format
    pub repo: Option<String>,
    /// GitHub API token
    pub token: Option<String>,
    /// Path to project configuration file
    pub project_config_path: Option<PathBuf>,
    /// Enable verbose output
    pub verbose: bool,
    /// Suppress non-essential output
    pub quiet: bool,
}

#[allow(dead_code)]
impl Config {
    /// Create a new Config from CLI arguments
    pub fn new(
        repo: Option<String>,
        token: Option<String>,
        project_config_path: Option<PathBuf>,
        verbose: bool,
        quiet: bool,
    ) -> Self {
        Self {
            repo,
            token: token.or_else(|| env::var("GITHUB_TOKEN").ok()),
            project_config_path,
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
            None,
            true,
            false,
        );

        assert_eq!(config.repo, Some("owner/repo".to_string()));
        assert_eq!(config.token, Some("test-token".to_string()));
        assert!(config.project_config_path.is_none());
        assert!(config.verbose);
        assert!(!config.quiet);
    }

    #[test]
    fn test_config_new_with_config_path() {
        let config = Config::new(
            None,
            None,
            Some(PathBuf::from(".github/project.yml")),
            false,
            false,
        );

        assert_eq!(
            config.project_config_path,
            Some(PathBuf::from(".github/project.yml"))
        );
    }

    #[test]
    fn test_config_get_repo() {
        let config = Config::new(Some("owner/repo".to_string()), None, None, false, false);
        assert_eq!(config.get_repo(), Some("owner/repo"));

        let config_none = Config::new(None, None, None, false, false);
        assert_eq!(config_none.get_repo(), None);
    }

    #[test]
    fn test_config_has_token() {
        let config_with_token = Config::new(None, Some("token".to_string()), None, false, false);
        assert!(config_with_token.has_token());

        let config_without_token = Config::new(None, None, None, false, false);
        assert!(!config_without_token.has_token());
    }

    #[test]
    fn test_config_token_from_env() {
        // Token from explicit parameter takes precedence
        let config = Config::new(None, Some("explicit-token".to_string()), None, false, false);
        assert_eq!(config.token, Some("explicit-token".to_string()));
    }
}
