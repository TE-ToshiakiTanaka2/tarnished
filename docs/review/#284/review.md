# Code Review: #284

- **Branch**: bugfix/TE-ToshiakiTanaka2/#284/allow-devcontainer-json-merge-with-comments
- **Base**: develop (merge base: f4332e2eb99a74d63a8260b2c828360cfbe9c14b)
- **Review scope**: `develop...HEAD` for #284 plus review-fix changes in `scripts/lib/common.sh` and `tests/common_json.bats`
- **Reviewed at**: 2026-05-16T02:57:38Z
- **Reviewer**: Codex fallback review

## Review Summary

**Overall**: APPROVE after fix

The configured review-agent profile is templated in this workspace, so a distinct configured review agent was unavailable. An external `codex exec --sandbox read-only` review was attempted, but the working tree contains unrelated uncommitted workflow/devcontainer changes; that run reviewed those dirty files and produced findings outside #284's committed diff. Those findings are not applicable to this issue's scoped review.

## Critical Issues

- None.

## Major Issues

- [scripts/lib/common.sh:388] Block comments were originally stripped without replacing them with whitespace. That allowed malformed JSONC such as `1/* comment */2` to become valid strict JSON `12`, silently changing semantics instead of rejecting invalid input. Fixed by emitting a space when entering a block comment and adding a regression test at [tests/common_json.bats:192].

## Minor Issues

- None.

## Suggestions

- None.

## Fix Summary

- `/* ... */` comments in devcontainer JSONC are now treated as JSON whitespace rather than removed with no separator.
- Added a regression test ensuring token-concatenating block comments fail validation and remove stale output.

## Verification

- `bash -n scripts/lib/common.sh` passed.
- `git diff --check -- scripts/lib/common.sh tests/common_json.bats` passed.
- `shellcheck tests/common_json.bats` passed.
- `shellcheck scripts/lib/common.sh` still reports pre-existing warnings outside the changed lines.
- Manual JSONC success smoke test passed, including `https://...//...` strings and block comments in valid positions.
- Manual malformed block-comment smoke test passed: `1/*bad*/2` is rejected and stale output is removed.
- `cargo test` passed: 109 unit tests and 15 integration tests.
- `bats tests/common_json.bats` could not run because `bats` is not installed in this environment.
