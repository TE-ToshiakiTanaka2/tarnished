---
repository: "TE-ToshiakiTanaka2/tarnished"
issue_number: 316
reviewed_head: "7e2642ec6bf0f434d876d73e2c870fd015ed47bb"
base_ref: "develop"
base_commit: "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b"
merge_base: "c78bb7afd71e029503262dcf3d30f8d5e6ae4e4b"
issue_body_sha256: "09c92d33ac68e638bfd1cc05fc682c8a8b8a60e05398b5dd1d03345b4ca897e7"
timestamp: "2026-09-05T12:39:19.663902+00:00"
review_status: "complete"
verified_head: "b6e9d7187fdd621b49ef841d01845b894662a0f9"
reviewer: "Independent Codex CLI 0.153.4 (fresh context, read-only)"
reviewer_model: "gpt-6-astra"
reviewer_reasoning_effort: "high (runtime verified)"
---

# Independent review — original output

## Review Summary

**Overall: REQUEST_CHANGES**

Reviewed committed `c78bb7a..7e2642e` against all nine criteria, the raw issue requirements, and design. Excluded `.claude/scheduled_tasks.lock`.

Good practices include conservative legacy ownership handling, per-file atomic refresh, preserved conflict baselines, and removal of maintenance post-copy hooks against the project.

Verification: Bash syntax, error-level ShellCheck, and whitespace checks passed. All 21 mirror pairs matched through read-only comparisons. Bats could not run because its fixtures require filesystem writes.

## Critical

- **[refresh-assets.sh:137](/workspace/templates/core/.devcontainer/scripts/refresh-assets.sh:137) — Branch validation permits Git option injection.** `git check-ref-format "refs/heads/$UPSTREAM_BRANCH"` accepts names starting with `--upload-pack=...`. With an existing cache and SSH/local upstream, the fetch at line 212 interprets that value as an option capable of executing a shell command. This leaves the FR-7 validation requirement incomplete. Reject leading-hyphen branch names and terminate fetch option parsing with `--`. Add a regression asserting rejection before invoking fetch.

## Major

- **[refresh-assets.sh:199](/workspace/templates/core/.devcontainer/scripts/refresh-assets.sh:199) — Default container refresh cannot create its cache.** The default remains `/opt/tarnished`, but the template runs as `vscode` and does not provision a writable directory there. Removing the previous home-directory fallback makes ordinary container refresh warn and stop indefinitely, including migrated installations that previously used that fallback. Restore a validated writable fallback or provision a writable default, with migration handling. Test the shipped configuration under the non-root container user. This blocks FR-4 and FR-6.

- **[refresh.json:45](/workspace/templates/agent-workflows/.tarnished/refresh.json:45) — Newly managed workflow files still require scaffold rendering.** `workflows/README.md` and `workflows/review.md` contain project/profile placeholders. Scaffolding renders them, but refresh compares and installs raw template bytes. Consequently, untouched scaffolded files conflict on adoption; missing files receive unresolved placeholders, including the reviewer fallback. Render effective candidates consistently before hashing, or make these contracts placeholder-free with appropriate migration. Test actual scaffolded templates through adoption and subsequent updates; the maintenance fixtures currently replace their contents with synthetic text. This undermines FR-4’s consistent distribution.

- **[setup.sh:2313](/workspace/setup.sh:2313) — Legacy deletion protection lasts only one upgrade.** A missing helper listed in a v1 manifest receives `SKIP_USER_DELETED`, but the rewritten v2 manifest drops its entry. The next unchanged upgrade sees no baseline and selects `NEW`, resurrecting the helper. An in-memory probe of the actual decision driver confirmed this sequence. Preserve deletion intent separately from trusted ownership—for example, with migration tombstones—and test two consecutive upgrades. This violates the design’s deletion-preservation contract and FR-6 repeat-update safety.

## Minor

- **[data-model.md:125](/workspace/docs/design/shared/data-model.md:125) — Documented refresh-state schema differs from implementation.** Documentation specifies `files` with flat mapping fields and `installed_hash`; the updater requires `entries`, nested `mapping`, and `sha256`. Recovery tooling or manually restored state following this documentation is rejected. Document the actual serialized schema and provide a valid example.

## Suggestions

None.

# Orchestrator verification

Scope: committed implementation, raw Issue #316 requirements and design artifacts. The unrelated untracked `.claude/scheduled_tasks.lock` is excluded. Original reviewer verdict is retained above.

Additional Major finding: `setup.sh::run_refresh` migrates an explicit `use_default_managed_paths: false` when the list matches a legacy catalog. Only an absent key may trigger automatic legacy migration; explicit false must remain authoritative. Reproduced with the actual jq predicate.

## Fixes Applied

All findings fixed and verified in one executor return round. The original REQUEST_CHANGES verdict remains unchanged above.

| Finding | Disposition and verification |
| --- | --- |
| Critical: Git branch option injection | `21f2d49` rejects leading-hyphen configuration/environment branches before Git and uses `fetch --quiet -- origin ...`. Regression checks fetch was never called. |
| Major: nonroot default cache | `21f2d49` selects the historical home cache only for an absent, unwritable shipped `/opt/tarnished`. Both paths undergo the same origin, cleanliness, symlink and overlap checks; an invalid existing cache is never bypassed. Actual UID 1000 tests cover initial/repeated refresh, legacy config, dry-run and unsafe fallback caches. |
| Major: rendered shared contracts | `b6e9d71` makes README/review contracts profile-neutral and reads project-owned `agent-profile.json`. An actual scaffold→adopt→upstream-update regression passes. Older rendered contracts remain preserved for explicit one-time adoption, documented in README. |
| Major: repeated legacy deletion | `19457a9` and `b6e9d71` persist validated, eligible `deleted_paths` separately from trusted hashes, across bootstrap, upgrade and helper migration. Two consecutive runs retain deletion; exact manual restoration permits adoption. Schema/path/contradiction and other-tombstone preservation regressions pass. |
| Minor: state schema documentation | `b6e9d71` aligns shared/issue docs to `entries`, nested `mapping`, unprefixed `sha256`, and valid JSON examples. |
| Additional Major: explicit false | `b6e9d71` migrates only an absent opt-in key, preserving explicit false byte-for-byte. Exact-legacy-catalog regression passes. |

The orchestrator read the completed code and tests, checked all finding dispositions, reran mirror/whitespace checks, and re-fetched develop and Issue #316. Base and issue digest are unchanged. Only finding fixes and corresponding design clarifications changed since the independent review; no unrelated scope was introduced.

## Validation

- Before review: bootstrap/upgrade 52/52, runtime refresh 52/52, manifest/plugin/maintenance 67/67, related integration 78/78; actual monorepo scaffold/add-module smoke test preserved application bytes.
- After fixes: runtime refresh 56/56; library/plugin 58/58; maintenance 14/14 plus three final affected checks; four upgrade/bootstrap regressions. Bash syntax, error-level ShellCheck, whitespace and all 21 mirror comparisons passed.
- Unchanged Rust checks reused: format, check all targets, Clippy with warnings denied, 109 binary tests and 15 integration tests passed.
- Independent review's read-only environment could not run writable Bats fixtures. The executor ran those fixtures in the shared workspace; the orchestrator verified results and inspected the regressions.
- No downstream production project was updated; validation used disposable fixtures. The preexisting untracked lock remains excluded.

## Requirement coverage and limitations

FR-1–8 are covered by the ownership/persona documentation, safe rerun dispatch, positive provenance inventory, consistent Claude/Codex/shared refresh, customization and deletion preservation, conservative legacy adoption, validated failure paths, and behavioral regression/mirror checks. No model IDs or project profile choices are changed.

Unknown/edited legacy assets and rendered contracts need a one-time explicit comparison/adoption. An unrecognized or edited installed updater is preserved with migration guidance before its next container start. Already deleted content is not recovered automatically. CI is assessed at the PR stage; this artifact records local review completion, not CI or merge approval.
