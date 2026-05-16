# Code Review: #286

- **Branch**: feature/TE-ToshiakiTanaka2/#286/exclude-github-from-upgrade-tracking
- **Base**: develop (merge base: 2ff6cde)
- **Review scope**: Medium (~386 lines changed across 11 files)
- **Reviewed at**: 2026-05-16
- **Reviewer**: Codex CLI (`codex exec`, custom prompt)

---

### Warnings (should fix)

- [setup.sh:2020] `--upgrade` still re-runs `plugin_post_copy` on the real target after lifecycle decisions. That bypasses the new `.github/*` manifest exclusion and can still mutate user-owned `.github` files. Specifically, [templates/github-actions/auto-tag/plugin.sh:126](/workspace/templates/github-actions/auto-tag/plugin.sh:126) recreates `.github/versioning.yml` when missing, and [templates/github-actions/project-integration/plugin.sh:1411](/workspace/templates/github-actions/project-integration/plugin.sh:1411) can prompt before even checking whether `.github/project.yml` exists, then creates it at line 1421 when missing. A user deleting those now-user-owned files can get them reintroduced by `setup.sh --upgrade`, which violates the #286 contract that upgrade should not touch `.github/`. Fix by skipping GitHub Actions `plugin_post_copy` during upgrade reruns, or adding an explicit upgrade-rerun guard in those plugins for `.github/*` emissions.

### Suggestions (nice to have)

- [tests/setup_upgrade.bats:288] The new prune regression covers `.github/workflows/auto-tag.yml`, but not the `.github/project.yml` / `.github/versioning.yml` post-copy path above. Add a regression where one of those files is absent before `--upgrade`, then assert it remains absent after upgrade.

- [tests/setup_upgrade.bats:292] The comment says "Use a sha that does not match the current file," but the test correctly uses the real current hash to exercise `current == old` and the `PRUNE` branch. Update the comment to avoid misleading future maintainers.

### Positive

- The core manifest filtering is implemented in the right two places: `.github{,/*}` is added to `MANIFEST_EXCLUDE_GLOBS`, and old manifest entries are filtered before entering `ALL_PATHS`. That correctly handles fresh manifests and pre-#286 migration manifests.

- The new tests cover recording-side exclusion, walk-side exclusion, `--create-manifest`, edited workflow preservation, and prune migration for workflow YAML.

**Final verdict: REQUEST_CHANGES.**

---

## Fixes Applied

### Reproduction

Manually reproduced the warning on `develop` HEAD: scaffolded a minimal target with `seed_scaffold`-equivalent layout (`.github/workflows/auto-tag.yml` only), ran `setup.sh --create-manifest -y`, then `setup.sh --upgrade -y`. After the upgrade, `.github/versioning.yml` was present even though it had never existed pre-upgrade. The same flow on this branch (post-fix) leaves `.github/` unchanged.

### Warning — `rerun_post_copy_on_target` resurrected user-owned `.github/` files

Added an `UPGRADE_MODE` early-return at the top of `plugin_post_copy` in both GitHub Actions plugins:

- `templates/github-actions/auto-tag/plugin.sh:plugin_post_copy` — skips `.github/versioning.yml` creation during upgrade.
- `templates/github-actions/project-integration/plugin.sh:plugin_post_copy` — skips both the `plugin_interactive_setup` re-prompt AND `.github/project.yml` creation during upgrade.

Initial scaffold (`UPGRADE_MODE=false`) keeps its existing behavior. This is consistent with how plugins already read `OVERWRITE_ALL`, `MANIFEST_RECORDING`, and other setup.sh-owned globals.

### Suggestion 1 — Regression for deleted `.github/versioning.yml`

Added `#286: --upgrade does not resurrect a deleted .github/versioning.yml` in `tests/setup_upgrade.bats`. The test asserts the file is absent before AND after `--upgrade -y`. This test would fail without the new `UPGRADE_MODE` guard.

### Suggestion 2 — Misleading prune-test comment

Rewrote the comment block in the `--upgrade --prune` regression test to correctly describe the intent: the real current-file hash is used so that `(current == old)` and `(has_new == false)`, which is the exact combination that triggers `PRUNE` under `--prune`.

### Verification

- `bats tests/`: **195/195 passing** (was 194/194; added one new regression).
- Manual reproduction (pre-fix vs post-fix): `.github/versioning.yml` resurrection confirmed gone.

Commit: see follow-up commit on this branch.
