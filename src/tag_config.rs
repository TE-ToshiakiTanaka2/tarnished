//! Tag configuration for automatic version bumping.
//!
//! Configuration is read from `.github/versioning.yml`.

use serde::Deserialize;
use std::fs;
use std::path::Path;

/// Root configuration structure
#[derive(Debug, Deserialize, Default)]
pub struct Config {
    /// Versioning configuration
    #[serde(default)]
    pub versioning: VersioningConfig,
}

/// Versioning configuration section
#[derive(Debug, Deserialize, Default)]
pub struct VersioningConfig {
    /// Branch prefix mappings
    #[serde(default)]
    pub branch_prefixes: BranchPrefixes,
}

/// Branch prefix to version type mapping
#[derive(Debug, Deserialize, Default)]
pub struct BranchPrefixes {
    /// Major version bump prefixes (X.0.0)
    #[serde(default)]
    pub major: Vec<String>,

    /// Minor version bump prefixes (0.X.0)
    #[serde(default)]
    pub minor: Vec<String>,

    /// Patch version bump prefixes (0.0.X)
    #[serde(default)]
    pub patch: Vec<String>,

    /// Release prefixes (remove RC suffix)
    #[serde(default)]
    pub release: Vec<String>,
}

/// Version bump types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BumpType {
    /// Major version bump (x.0.0)
    Major,
    /// Minor version bump (0.x.0)
    Minor,
    /// Patch version bump (0.0.x)
    Patch,
    /// Release candidate bump (0.0.0-rc.x)
    Rc,
    /// Remove prerelease suffix (rc -> stable)
    Release,
}

impl Config {
    /// Load configuration from file path
    pub fn load_from_file(path: &Path) -> anyhow::Result<Self> {
        let content = fs::read_to_string(path)?;
        let config: Self = serde_yaml::from_str(&content)?;
        Ok(config)
    }

    /// Load configuration from default location (.github/versioning.yml)
    pub fn load_from_default() -> anyhow::Result<Self> {
        let path = Path::new(".github/versioning.yml");
        if path.exists() {
            Self::load_from_file(path)
        } else {
            // Return default config if no file found
            Ok(Self::default())
        }
    }

    /// Load configuration from optional path or default location
    pub fn load(path: Option<&Path>) -> anyhow::Result<Self> {
        path.map_or_else(Self::load_from_default, Self::load_from_file)
    }
}

impl BranchPrefixes {
    /// Match a branch name and return the appropriate bump type.
    ///
    /// Returns `BumpType::Rc` if no prefix matches.
    pub fn match_branch(&self, branch: &str) -> BumpType {
        // Check major prefixes
        for prefix in &self.major {
            if branch.starts_with(prefix) {
                return BumpType::Major;
            }
        }

        // Check minor prefixes
        for prefix in &self.minor {
            if branch.starts_with(prefix) {
                return BumpType::Minor;
            }
        }

        // Check patch prefixes
        for prefix in &self.patch {
            if branch.starts_with(prefix) {
                return BumpType::Patch;
            }
        }

        // Check release prefixes
        for prefix in &self.release {
            if branch.starts_with(prefix) {
                return BumpType::Release;
            }
        }

        // Default to RC
        BumpType::Rc
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert!(config.versioning.branch_prefixes.major.is_empty());
        assert!(config.versioning.branch_prefixes.minor.is_empty());
        assert!(config.versioning.branch_prefixes.patch.is_empty());
    }

    #[test]
    fn test_parse_yaml_config() {
        let yaml = r#"
versioning:
  branch_prefixes:
    major:
      - "major/"
    minor:
      - "release/"
    patch:
      - "feature/"
      - "fix/"
"#;
        let config: Config = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(config.versioning.branch_prefixes.major, vec!["major/"]);
        assert_eq!(config.versioning.branch_prefixes.minor, vec!["release/"]);
        assert_eq!(
            config.versioning.branch_prefixes.patch,
            vec!["feature/", "fix/"]
        );
    }

    #[test]
    fn test_match_branch_major() {
        let prefixes = BranchPrefixes {
            major: vec!["major/".to_string(), "breaking/".to_string()],
            minor: vec!["release/".to_string()],
            patch: vec!["feature/".to_string()],
            release: vec![],
        };
        assert_eq!(prefixes.match_branch("major/v2"), BumpType::Major);
        assert_eq!(prefixes.match_branch("breaking/api"), BumpType::Major);
    }

    #[test]
    fn test_match_branch_minor() {
        let prefixes = BranchPrefixes {
            major: vec![],
            minor: vec!["release/".to_string()],
            patch: vec![],
            release: vec![],
        };
        assert_eq!(prefixes.match_branch("release/v1.1.0"), BumpType::Minor);
    }

    #[test]
    fn test_match_branch_patch() {
        let prefixes = BranchPrefixes {
            major: vec![],
            minor: vec![],
            patch: vec!["feature/".to_string(), "fix/".to_string()],
            release: vec![],
        };
        assert_eq!(prefixes.match_branch("feature/new-button"), BumpType::Patch);
        assert_eq!(prefixes.match_branch("fix/bug-123"), BumpType::Patch);
    }

    #[test]
    fn test_match_branch_default_rc() {
        let prefixes = BranchPrefixes {
            major: vec!["major/".to_string()],
            minor: vec!["release/".to_string()],
            patch: vec!["feature/".to_string()],
            release: vec![],
        };
        assert_eq!(prefixes.match_branch("chore/cleanup"), BumpType::Rc);
        assert_eq!(prefixes.match_branch("docs/readme"), BumpType::Rc);
        assert_eq!(prefixes.match_branch("random-branch"), BumpType::Rc);
    }

    #[test]
    fn test_priority_order() {
        // When a branch could match multiple prefixes, first match wins (major > minor > patch)
        let prefixes = BranchPrefixes {
            major: vec!["feature/".to_string()], // Put feature in major
            minor: vec!["feature/".to_string()], // Also in minor
            patch: vec![],
            release: vec![],
        };
        // Major is checked first, so it should return Major
        assert_eq!(prefixes.match_branch("feature/test"), BumpType::Major);
    }

    #[test]
    fn test_empty_config() {
        let yaml = "";
        let config: Config = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(
            config.versioning.branch_prefixes.match_branch("any"),
            BumpType::Rc
        );
    }
}
