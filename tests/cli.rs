use assert_cmd::Command;
use predicates::prelude::*;

fn erd() -> Command {
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
        .stdout(predicate::str::contains("bump"));
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
