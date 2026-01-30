//! Tag configuration for automatic version bumping.
//!
//! Configuration is read from `.erd.toml` or `erd.toml` files.

use serde::Deserialize;
use std::fs;
use std::path::Path;

/// Root configuration structure
#[derive(Debug, Deserialize, Default)]
pub struct Config {
    /// Tag-related configuration
    #[serde(default)]
    pub tag: TagConfig,
}

/// Tag configuration section
#[derive(Debug, Deserialize)]
pub struct TagConfig {
    /// Tag prefix (default: "v")
    #[serde(default = "default_prefix")]
    pub prefix: String,

    /// Initial version when no tags exist (default: "0.1.0")
    #[serde(default = "default_initial_version")]
    pub initial_version: String,

    /// Version bump rules
    #[serde(default)]
    pub rules: TagRules,
}

impl Default for TagConfig {
    fn default() -> Self {
        Self {
            prefix: default_prefix(),
            initial_version: default_initial_version(),
            rules: TagRules::default(),
        }
    }
}

fn default_prefix() -> String {
    "v".to_string()
}

fn default_initial_version() -> String {
    "0.1.0".to_string()
}

/// Tag rules configuration
#[derive(Debug, Deserialize, Default)]
pub struct TagRules {
    /// List of branch patterns and their bump types
    #[serde(default)]
    pub patterns: Vec<BumpPattern>,

    /// Default bump behavior when no pattern matches
    #[serde(default)]
    pub default: DefaultBump,
}

/// A branch pattern and its associated bump type
#[derive(Debug, Deserialize, Clone)]
pub struct BumpPattern {
    /// Glob pattern to match branch names (e.g., "feat/*", "fix/*")
    pub pattern: String,

    /// Bump type when pattern matches
    pub bump: BumpType,
}

/// Default bump behavior
#[derive(Debug, Deserialize)]
pub struct DefaultBump {
    /// Bump type when no pattern matches (default: "rc")
    #[serde(default = "default_bump_type")]
    pub bump: BumpType,
}

impl Default for DefaultBump {
    fn default() -> Self {
        Self {
            bump: default_bump_type(),
        }
    }
}

const fn default_bump_type() -> BumpType {
    BumpType::Rc
}

/// Version bump types
#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
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
        let config: Self = toml::from_str(&content)?;
        Ok(config)
    }

    /// Load configuration from default locations (.erd.toml or erd.toml)
    pub fn load_from_default() -> anyhow::Result<Self> {
        let candidates = [".erd.toml", "erd.toml"];

        for candidate in candidates {
            let path = Path::new(candidate);
            if path.exists() {
                return Self::load_from_file(path);
            }
        }

        // Return default config if no file found
        Ok(Self::default())
    }

    /// Load configuration from optional path or default locations
    pub fn load(path: Option<&Path>) -> anyhow::Result<Self> {
        path.map_or_else(Self::load_from_default, Self::load_from_file)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.tag.prefix, "v");
        assert_eq!(config.tag.initial_version, "0.1.0");
        assert_eq!(config.tag.rules.default.bump, BumpType::Rc);
    }

    #[test]
    fn test_parse_minimal_config() {
        let toml = "";
        let config: Config = toml::from_str(toml).unwrap();
        assert_eq!(config.tag.prefix, "v");
    }

    #[test]
    fn test_parse_full_config() {
        let toml = r#"
[tag]
prefix = "v"
initial_version = "1.0.0"

[[tag.rules.patterns]]
pattern = "feat/*"
bump = "minor"

[[tag.rules.patterns]]
pattern = "fix/*"
bump = "patch"

[[tag.rules.patterns]]
pattern = "breaking/*"
bump = "major"

[[tag.rules.patterns]]
pattern = "release/*"
bump = "release"

[tag.rules.default]
bump = "rc"
"#;
        let config: Config = toml::from_str(toml).unwrap();
        assert_eq!(config.tag.prefix, "v");
        assert_eq!(config.tag.initial_version, "1.0.0");
        assert_eq!(config.tag.rules.patterns.len(), 4);
        assert_eq!(config.tag.rules.patterns[0].pattern, "feat/*");
        assert_eq!(config.tag.rules.patterns[0].bump, BumpType::Minor);
        assert_eq!(config.tag.rules.default.bump, BumpType::Rc);
    }

    #[test]
    fn test_parse_custom_prefix() {
        let toml = r#"
[tag]
prefix = "release-"
"#;
        let config: Config = toml::from_str(toml).unwrap();
        assert_eq!(config.tag.prefix, "release-");
    }

    #[test]
    fn test_bump_type_deserialize() {
        let toml = r#"
[[tag.rules.patterns]]
pattern = "test"
bump = "major"
"#;
        let config: Config = toml::from_str(toml).unwrap();
        assert_eq!(config.tag.rules.patterns[0].bump, BumpType::Major);
    }
}
