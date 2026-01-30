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
