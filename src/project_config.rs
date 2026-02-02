//! Project configuration for GitHub Projects v2 integration.
//!
//! This module handles loading and parsing project configuration files
//! that define default project settings and field values.

use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

/// Project configuration loaded from a YAML file.
///
/// Configuration file locations (in priority order):
/// 1. `.github/project.yml` (project-local, recommended)
/// 2. `~/.config/erd/project.yaml` (user-global)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectConfig {
    /// Default project to link issues to
    pub default_project: ProjectReference,

    /// Default field values to set when adding items to the project
    #[serde(default)]
    pub field_defaults: HashMap<String, String>,

    /// PR event status configuration
    #[serde(default)]
    pub pr_status: Option<PrStatusConfig>,
}

/// PR event status configuration
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PrStatusConfig {
    /// Status to set when a PR is opened
    #[serde(default)]
    pub on_open: Option<String>,
}

/// Reference to a GitHub Project v2
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectReference {
    /// Project owner (user or organization)
    pub owner: String,

    /// Project number
    pub number: u32,
}

/// Error types for project configuration
#[derive(Debug, thiserror::Error)]
pub enum ProjectConfigError {
    /// Configuration file not found
    #[error("Project configuration file not found. Create .github/project.yml or run 'erd init'.")]
    NotFound,

    /// Failed to read configuration file
    #[error("Failed to read project configuration: {0}")]
    ReadError(#[from] std::io::Error),

    /// Failed to parse configuration file
    #[error("Failed to parse project configuration: {0}")]
    ParseError(#[from] serde_yaml::Error),
}

impl ProjectConfig {
    /// Load project configuration from the default locations.
    ///
    /// Searches in the following order:
    /// 1. `.github/project.yml` in the current directory (recommended)
    /// 2. `~/.config/erd/project.yaml` in the user's home directory
    #[allow(dead_code)]
    pub fn load() -> Result<Self, ProjectConfigError> {
        Self::load_with_path(None)
    }

    /// Load project configuration with an optional explicit path.
    ///
    /// If `path` is provided, only that path is used (no fallback).
    /// If `path` is `None`, searches in the default locations.
    pub fn load_with_path(path: Option<&PathBuf>) -> Result<Self, ProjectConfigError> {
        // If explicit path is provided, use only that path
        if let Some(explicit_path) = path {
            if !explicit_path.exists() {
                return Err(ProjectConfigError::NotFound);
            }
            return Self::load_from_path(explicit_path);
        }

        // Try local config first (.github directory)
        let local_path = PathBuf::from(".github/project.yml");
        if local_path.exists() {
            return Self::load_from_path(&local_path);
        }

        // Try global config
        if let Some(config_dir) = dirs::config_dir() {
            let global_path = config_dir.join("erd").join("project.yaml");
            if global_path.exists() {
                return Self::load_from_path(&global_path);
            }
        }

        Err(ProjectConfigError::NotFound)
    }

    /// Load project configuration from a specific path.
    pub fn load_from_path(path: &PathBuf) -> Result<Self, ProjectConfigError> {
        let content = std::fs::read_to_string(path)?;
        let config: Self = serde_yaml::from_str(&content)?;
        Ok(config)
    }

    /// Get the default value for a field, if configured.
    #[allow(dead_code)]
    pub fn get_field_default(&self, field_name: &str) -> Option<&String> {
        self.field_defaults.get(field_name)
    }

    /// Get the status to set when a PR is opened.
    pub fn get_pr_open_status(&self) -> Option<&String> {
        self.pr_status.as_ref().and_then(|ps| ps.on_open.as_ref())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_project_config_deserialize() {
        let yaml = r#"
default_project:
  owner: "test-owner"
  number: 1

field_defaults:
  Status: "Todo"
  Size: "M"
  Priority: "P1"
"#;

        let config: ProjectConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.default_project.owner, "test-owner");
        assert_eq!(config.default_project.number, 1);
        assert_eq!(
            config.get_field_default("Status"),
            Some(&"Todo".to_string())
        );
        assert_eq!(config.get_field_default("Size"), Some(&"M".to_string()));
        assert_eq!(
            config.get_field_default("Priority"),
            Some(&"P1".to_string())
        );
    }

    #[test]
    fn test_project_config_with_pr_status() {
        let yaml = r#"
default_project:
  owner: "test-owner"
  number: 1

field_defaults:
  Status: "Todo"

pr_status:
  on_open: "In Review"
"#;

        let config: ProjectConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.get_pr_open_status(), Some(&"In Review".to_string()));
    }

    #[test]
    fn test_project_config_without_pr_status() {
        let yaml = r#"
default_project:
  owner: "test-owner"
  number: 1
"#;

        let config: ProjectConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.get_pr_open_status(), None);
    }

    #[test]
    fn test_project_config_empty_field_defaults() {
        let yaml = r#"
default_project:
  owner: "test-owner"
  number: 1
"#;

        let config: ProjectConfig = serde_yaml::from_str(yaml).unwrap();
        assert!(config.field_defaults.is_empty());
    }

    #[test]
    fn test_project_config_serialize() {
        let config = ProjectConfig {
            default_project: ProjectReference {
                owner: "test-owner".to_string(),
                number: 1,
            },
            field_defaults: HashMap::from([("Status".to_string(), "Todo".to_string())]),
            pr_status: None,
        };

        let yaml = serde_yaml::to_string(&config).unwrap();
        assert!(yaml.contains("owner: test-owner"));
        assert!(yaml.contains("number: 1"));
        assert!(yaml.contains("Status: Todo"));
    }

    #[test]
    fn test_load_with_path_none_falls_back_to_default() {
        // When path is None, it should behave like load()
        // This test verifies the function signature works
        let result = ProjectConfig::load_with_path(None);
        // Result depends on whether .github/project.yml exists
        // We just verify it doesn't panic
        let _ = result;
    }

    #[test]
    fn test_load_with_path_nonexistent_returns_not_found() {
        let path = PathBuf::from("/nonexistent/path/config.yml");
        let result = ProjectConfig::load_with_path(Some(&path));
        assert!(matches!(result, Err(ProjectConfigError::NotFound)));
    }
}
