//! Git operations for tag management.

use anyhow::{anyhow, Context, Result};
use std::process::Command;

use crate::version::SemVer;

/// Get all version tags from the repository.
///
/// Returns tags sorted by version (highest first).
pub fn list_version_tags(prefix: &str) -> Result<Vec<SemVer>> {
    let output = Command::new("git")
        .args(["tag", "-l", &format!("{prefix}*")])
        .output()
        .context("Failed to execute git tag command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("git tag failed: {stderr}"));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut versions: Vec<SemVer> = stdout
        .lines()
        .filter(|line| !line.is_empty())
        .filter_map(|tag| SemVer::from_tag(tag, prefix).ok())
        .collect();

    // Sort descending (highest version first)
    versions.sort_by(|a, b| b.cmp(a));

    Ok(versions)
}

/// Get the latest version tag.
///
/// Returns None if no version tags exist.
pub fn get_latest_version(prefix: &str) -> Result<Option<SemVer>> {
    let versions = list_version_tags(prefix)?;
    Ok(versions.into_iter().next())
}

/// Create a new git tag.
pub fn create_tag(tag_name: &str, message: Option<&str>) -> Result<()> {
    let mut args = vec!["tag"];

    if let Some(msg) = message {
        args.push("-m");
        args.push(msg);
    }

    args.push(tag_name);

    let output = Command::new("git")
        .args(&args)
        .output()
        .context("Failed to execute git tag command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("Failed to create tag '{tag_name}': {stderr}"));
    }

    Ok(())
}

/// Push a tag to the remote repository.
pub fn push_tag(tag_name: &str, remote: &str) -> Result<()> {
    let output = Command::new("git")
        .args(["push", remote, tag_name])
        .output()
        .context("Failed to execute git push command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!(
            "Failed to push tag '{tag_name}' to '{remote}': {stderr}"
        ));
    }

    Ok(())
}

/// Delete a local tag.
#[allow(dead_code)]
pub fn delete_tag(tag_name: &str) -> Result<()> {
    let output = Command::new("git")
        .args(["tag", "-d", tag_name])
        .output()
        .context("Failed to execute git tag -d command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("Failed to delete tag '{tag_name}': {stderr}"));
    }

    Ok(())
}

/// Check if we're in a git repository.
pub fn is_git_repository() -> bool {
    Command::new("git")
        .args(["rev-parse", "--git-dir"])
        .output()
        .is_ok_and(|o| o.status.success())
}

/// Get the current HEAD commit short hash.
#[allow(dead_code)]
pub fn get_head_short_hash() -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .context("Failed to execute git rev-parse command")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(anyhow!("git rev-parse failed: {stderr}"));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_git_repository() {
        // This test is run within a git repository, so it should return true
        assert!(is_git_repository());
    }

    // Note: Most git operations tests would require a test repository setup,
    // which is better suited for integration tests. Here we just test the
    // basic functionality that doesn't modify state.
}
