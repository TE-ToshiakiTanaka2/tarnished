use thiserror::Error;

/// Application-level errors for the erd CLI
#[derive(Error, Debug)]
#[allow(dead_code)]
pub enum ErdError {
    #[error("Repository not specified. Use --repo or run from a git repository.")]
    RepositoryNotSpecified,

    #[error("GitHub token not found. Set GITHUB_TOKEN environment variable or use --token.")]
    TokenNotFound,

    #[error("Invalid repository format: {0}. Expected 'owner/repo'.")]
    InvalidRepositoryFormat(String),

    #[error("Command not implemented: {0}")]
    NotImplemented(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display_repository_not_specified() {
        let err = ErdError::RepositoryNotSpecified;
        assert_eq!(
            err.to_string(),
            "Repository not specified. Use --repo or run from a git repository."
        );
    }

    #[test]
    fn test_error_display_token_not_found() {
        let err = ErdError::TokenNotFound;
        assert_eq!(
            err.to_string(),
            "GitHub token not found. Set GITHUB_TOKEN environment variable or use --token."
        );
    }

    #[test]
    fn test_error_display_invalid_repository_format() {
        let err = ErdError::InvalidRepositoryFormat("invalid".to_string());
        assert_eq!(
            err.to_string(),
            "Invalid repository format: invalid. Expected 'owner/repo'."
        );
    }

    #[test]
    fn test_error_display_not_implemented() {
        let err = ErdError::NotImplemented("test command".to_string());
        assert_eq!(err.to_string(), "Command not implemented: test command");
    }

    #[test]
    fn test_error_is_debug() {
        let err = ErdError::RepositoryNotSpecified;
        let debug_str = format!("{err:?}");
        assert!(debug_str.contains("RepositoryNotSpecified"));
    }
}
