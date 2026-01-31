//! Semantic version manipulation with prerelease (RC) support.

use anyhow::{anyhow, Result};
use semver::{Prerelease, Version};
use std::fmt;
use std::str::FromStr;

use crate::tag_config::BumpType;

/// A semantic version wrapper with bump operations and RC support.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SemVer {
    inner: Version,
}

impl SemVer {
    /// Create a new `SemVer` from components.
    #[cfg(test)]
    pub const fn new(major: u64, minor: u64, patch: u64) -> Self {
        Self {
            inner: Version::new(major, minor, patch),
        }
    }

    /// Parse a version string, optionally with a prefix (e.g., "v1.2.3").
    pub fn parse(s: &str) -> Result<Self> {
        // Remove common prefixes
        let version_str = s.trim_start_matches('v').trim_start_matches('V');
        let inner =
            Version::parse(version_str).map_err(|e| anyhow!("Invalid version '{s}': {e}"))?;
        Ok(Self { inner })
    }

    /// Parse a version from a git tag, stripping the prefix.
    pub fn from_tag(tag: &str, prefix: &str) -> Result<Self> {
        let version_str = tag
            .strip_prefix(prefix)
            .ok_or_else(|| anyhow!("Tag '{tag}' does not start with prefix '{prefix}'"))?;
        let inner = Version::parse(version_str)
            .map_err(|e| anyhow!("Invalid version in tag '{tag}': {e}"))?;
        Ok(Self { inner })
    }

    /// Format as a git tag with the given prefix.
    pub fn to_tag(&self, prefix: &str) -> String {
        format!("{prefix}{}", self.inner)
    }

    /// Check if this is a prerelease version.
    pub fn is_prerelease(&self) -> bool {
        !self.inner.pre.is_empty()
    }

    /// Get the RC number if this is an RC prerelease.
    fn rc_number(&self) -> Option<u64> {
        let pre_str = self.inner.pre.as_str();
        if pre_str.starts_with("rc.") {
            pre_str.strip_prefix("rc.").and_then(|n| n.parse().ok())
        } else {
            None
        }
    }

    /// Bump the major version (x.0.0).
    pub fn bump_major(&self) -> Self {
        let mut v = self.inner.clone();
        v.major += 1;
        v.minor = 0;
        v.patch = 0;
        v.pre = Prerelease::EMPTY;
        Self { inner: v }
    }

    /// Bump the minor version (0.x.0).
    pub fn bump_minor(&self) -> Self {
        let mut v = self.inner.clone();
        v.minor += 1;
        v.patch = 0;
        v.pre = Prerelease::EMPTY;
        Self { inner: v }
    }

    /// Bump the patch version (0.0.x).
    pub fn bump_patch(&self) -> Self {
        let mut v = self.inner.clone();
        v.patch += 1;
        v.pre = Prerelease::EMPTY;
        Self { inner: v }
    }

    /// Bump the RC prerelease version.
    ///
    /// - If not a prerelease: increment patch and add -rc.1
    /// - If already RC: increment RC number
    pub fn bump_rc(&self) -> Self {
        let mut v = self.inner.clone();

        if let Some(rc_num) = self.rc_number() {
            // Already an RC, increment the RC number
            let new_pre = format!("rc.{}", rc_num + 1);
            v.pre = Prerelease::from_str(&new_pre).unwrap();
        } else if self.is_prerelease() {
            // Other prerelease, reset to rc.1
            let new_pre = "rc.1";
            v.pre = Prerelease::from_str(new_pre).unwrap();
        } else {
            // Stable version, bump patch and add rc.1
            v.patch += 1;
            v.pre = Prerelease::from_str("rc.1").unwrap();
        }

        Self { inner: v }
    }

    /// Remove the prerelease suffix (release stable version).
    pub fn release(&self) -> Self {
        let mut v = self.inner.clone();
        v.pre = Prerelease::EMPTY;
        Self { inner: v }
    }

    /// Apply a bump type to this version.
    pub fn bump(&self, bump_type: BumpType) -> Self {
        match bump_type {
            BumpType::Major => self.bump_major(),
            BumpType::Minor => self.bump_minor(),
            BumpType::Patch => self.bump_patch(),
            BumpType::Rc => self.bump_rc(),
            BumpType::Release => self.release(),
        }
    }
}

impl fmt::Display for SemVer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.inner)
    }
}

impl PartialOrd for SemVer {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SemVer {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.inner.cmp(&other.inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let v = SemVer::new(1, 2, 3);
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn test_parse_simple() {
        let v = SemVer::parse("1.2.3").unwrap();
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn test_parse_with_v_prefix() {
        let v = SemVer::parse("v1.2.3").unwrap();
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn test_parse_with_prerelease() {
        let v = SemVer::parse("1.2.3-rc.1").unwrap();
        assert_eq!(v.to_string(), "1.2.3-rc.1");
        assert!(v.is_prerelease());
    }

    #[test]
    fn test_from_tag() {
        let v = SemVer::from_tag("v1.2.3", "v").unwrap();
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn test_from_tag_custom_prefix() {
        let v = SemVer::from_tag("release-1.2.3", "release-").unwrap();
        assert_eq!(v.to_string(), "1.2.3");
    }

    #[test]
    fn test_to_tag() {
        let v = SemVer::new(1, 2, 3);
        assert_eq!(v.to_tag("v"), "v1.2.3");
        assert_eq!(v.to_tag("release-"), "release-1.2.3");
    }

    #[test]
    fn test_bump_major() {
        let v = SemVer::new(1, 2, 3);
        let bumped = v.bump_major();
        assert_eq!(bumped.to_string(), "2.0.0");
    }

    #[test]
    fn test_bump_major_clears_prerelease() {
        let v = SemVer::parse("1.2.3-rc.1").unwrap();
        let bumped = v.bump_major();
        assert_eq!(bumped.to_string(), "2.0.0");
        assert!(!bumped.is_prerelease());
    }

    #[test]
    fn test_bump_minor() {
        let v = SemVer::new(1, 2, 3);
        let bumped = v.bump_minor();
        assert_eq!(bumped.to_string(), "1.3.0");
    }

    #[test]
    fn test_bump_patch() {
        let v = SemVer::new(1, 2, 3);
        let bumped = v.bump_patch();
        assert_eq!(bumped.to_string(), "1.2.4");
    }

    #[test]
    fn test_bump_rc_from_stable() {
        let v = SemVer::new(1, 2, 3);
        let bumped = v.bump_rc();
        assert_eq!(bumped.to_string(), "1.2.4-rc.1");
    }

    #[test]
    fn test_bump_rc_increment() {
        let v = SemVer::parse("1.2.3-rc.1").unwrap();
        let bumped = v.bump_rc();
        assert_eq!(bumped.to_string(), "1.2.3-rc.2");
    }

    #[test]
    fn test_bump_rc_increment_higher() {
        let v = SemVer::parse("1.2.3-rc.5").unwrap();
        let bumped = v.bump_rc();
        assert_eq!(bumped.to_string(), "1.2.3-rc.6");
    }

    #[test]
    fn test_release_removes_prerelease() {
        let v = SemVer::parse("1.2.3-rc.5").unwrap();
        let released = v.release();
        assert_eq!(released.to_string(), "1.2.3");
        assert!(!released.is_prerelease());
    }

    #[test]
    fn test_release_on_stable_is_noop() {
        let v = SemVer::new(1, 2, 3);
        let released = v.release();
        assert_eq!(released.to_string(), "1.2.3");
    }

    #[test]
    fn test_bump_with_type() {
        let v = SemVer::new(1, 2, 3);
        assert_eq!(v.bump(BumpType::Major).to_string(), "2.0.0");
        assert_eq!(v.bump(BumpType::Minor).to_string(), "1.3.0");
        assert_eq!(v.bump(BumpType::Patch).to_string(), "1.2.4");
        assert_eq!(v.bump(BumpType::Rc).to_string(), "1.2.4-rc.1");
    }

    #[test]
    fn test_ordering() {
        let v1 = SemVer::parse("1.0.0").unwrap();
        let v2 = SemVer::parse("1.0.1").unwrap();
        let v3 = SemVer::parse("1.1.0").unwrap();
        let v4 = SemVer::parse("2.0.0").unwrap();
        let v_rc = SemVer::parse("1.0.1-rc.1").unwrap();

        assert!(v1 < v2);
        assert!(v2 < v3);
        assert!(v3 < v4);
        // Prerelease is less than release
        assert!(v_rc < v2);
    }

    #[test]
    fn test_parse_invalid() {
        assert!(SemVer::parse("invalid").is_err());
        assert!(SemVer::parse("1.2").is_err());
    }
}
