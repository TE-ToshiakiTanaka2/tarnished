#![allow(missing_docs)]
#![allow(clippy::unwrap_used)]

use assert_cmd::Command;
use predicates::prelude::*;

fn erd() -> Command {
    #[allow(deprecated)]
    Command::cargo_bin("erd").unwrap()
}

#[test]
fn test_help() {
    erd()
        .arg("--help")
        .assert()
        .success()
        .stdout(predicate::str::contains("erd"))
        .stdout(predicate::str::contains("issue"))
        .stdout(predicate::str::contains("tag"));
}

#[test]
fn test_version() {
    erd()
        .arg("--version")
        .assert()
        .success()
        .stdout(predicate::str::contains("erd 0.1.0"));
}

#[test]
fn test_issue_help() {
    erd()
        .args(["issue", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("list"))
        .stdout(predicate::str::contains("create"))
        .stdout(predicate::str::contains("view"))
        .stdout(predicate::str::contains("edit"))
        .stdout(predicate::str::contains("close"));
}

#[test]
fn test_tag_help() {
    erd()
        .args(["tag", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("list"))
        .stdout(predicate::str::contains("create"))
        .stdout(predicate::str::contains("delete"))
        .stdout(predicate::str::contains("bump"))
        .stdout(predicate::str::contains("auto"));
}

#[test]
fn test_issue_list() {
    erd()
        .args(["issue", "list"])
        .assert()
        .success()
        .stdout(predicate::str::contains("not implemented"));
}

#[test]
fn test_tag_list() {
    erd()
        .args(["tag", "list"])
        .assert()
        .success()
        .stdout(predicate::str::contains("not implemented"));
}

#[test]
fn test_issue_view() {
    erd()
        .args(["issue", "view", "123"])
        .assert()
        .success()
        .stdout(predicate::str::contains("#123"));
}

#[test]
fn test_tag_create() {
    erd()
        .args(["tag", "create", "v1.0.0"])
        .assert()
        .success()
        .stdout(predicate::str::contains("v1.0.0"));
}

#[test]
fn test_global_options() {
    erd()
        .args(["--verbose", "issue", "list"])
        .assert()
        .success()
        .stderr(predicate::str::contains("Config"));
}

#[test]
fn test_invalid_command() {
    erd()
        .arg("invalid")
        .assert()
        .failure()
        .stderr(predicate::str::contains("error"));
}

#[test]
fn test_tag_auto_help() {
    erd()
        .args(["tag", "auto", "--help"])
        .assert()
        .success()
        .stdout(predicate::str::contains("--branch"))
        .stdout(predicate::str::contains("--dry-run"))
        .stdout(predicate::str::contains("--config"));
}

#[test]
fn test_tag_auto_requires_branch() {
    erd()
        .args(["tag", "auto"])
        .assert()
        .failure()
        .stderr(predicate::str::contains("--branch"));
}

#[test]
fn test_tag_auto_dry_run() {
    // This test runs within a git repository
    erd()
        .args(["tag", "auto", "--branch", "feature/test", "--dry-run"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Dry run"))
        .stdout(predicate::str::contains("Would create tag"));
}

#[test]
fn test_tag_auto_dry_run_feature_branch() {
    // feature/ prefix is configured for Patch bump in .github/versioning.yml
    erd()
        .args(["tag", "auto", "--branch", "feature/new-button", "--dry-run"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Bump type: Patch"));
}

#[test]
fn test_tag_auto_dry_run_unmatched_branch() {
    // Unmatched branches default to RC bump
    erd()
        .args(["tag", "auto", "--branch", "chore/cleanup", "--dry-run"])
        .assert()
        .success()
        .stdout(predicate::str::contains("Bump type: Rc"));
}
