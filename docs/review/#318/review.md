---
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 318
reviewed_head: dd334cee4e3db11a60eec9f80cef81351fe22dd8
base_ref: develop
base_commit: f136b29b598ffcc3ff82a34b7db1fb9845ba312a
merge_base: f136b29b598ffcc3ff82a34b7db1fb9845ba312a
issue_body_sha256: b859b35fcd9a5656c69011f6717d79e3f0a00ddf282c42d2ad75b0644c315547
review_status: complete
verified_head: 4c39f2cdf6c82c85faa277eb142fc65ebc042525
reviewer: Codex CLI 0.153.4
model: gpt-6-astra
reasoning_effort: high
review_scope: large
branch: bugfix/TE-ToshiakiTanaka2/#318/update-distributed-ai-assets-and-settings
reviewed_added_lines: 1013
reviewed_deleted_lines: 355
reviewed_at: 2026-09-06T00:07:33.399715+00:00
---

## Review Summary

**Overall**: REQUEST_CHANGES

Reviewed `f136b29…dd334cee` against both the supplied requirements and design. The verified backups, private run directories, conservative removal checks, and clearer maintenance documentation are strong improvements.

Assessed all nine criteria and applicable project invariants. All 21 mirror pairs, Bash syntax, catalog exclusions, and diff whitespace checks pass; ShellCheck introduces no additional diagnostics. Findings below rely on code inspection and focused read-only checks. Mutation-based behavioral suites were not rerun.

## Critical Issues

- **[setup.sh:2606](/tmp/tarnished-318/setup.sh:2606): A failed upgrade can leave a destructive legacy refresher installed.** Helper processing first installs files from the selected historical distribution, including `refresh-assets.sh`. If another helper application fails—or a later module fails—the earlier returns bypass `run_refresh`, which would restore the current updater. Selecting `46f7be7`, for example, can leave its `rsync --delete` refresher installed; the next container start can delete project-added siblings and overwrite edits without backups. Exclude the refresher from historical helper replacement and handle its trusted migration independently, or stage the current implementation for this helper. Add a pinned-upgrade regression that injects another helper failure and verifies the installed refresher remains current.

## Major Issues

- **[refresh-assets.sh:580](/tmp/tarnished-318/templates/core/.devcontainer/scripts/refresh-assets.sh:580): Broad overlays can still project private backup contents into live assets.** Pruning backups during `find` only excludes overlay-enumerated candidates. With `{src:"broad", dst:".claude/skills", overlay:".tarnished"}`, an upstream file named `backups/refresh.old/.codex/config.toml` creates a candidate whose derived overlay points inside the project’s backup directory. `reconcile_file` then selects those backup bytes, potentially copying sensitive settings into the tracked skills tree. Validate each derived overlay path against the reserved backup subtree before reading it. Apply this guard to both script mirrors and test an upstream-listed candidate beneath a broad overlay.

- **[setup.sh:1769](/tmp/tarnished-318/setup.sh:1769): Missing configuration bypasses settings migration for older selected releases.** The missing-config branch copies the selected catalog unchanged. The actual `46f7be7` catalog lacks `use_default_managed_paths` and both settings mappings, although that release contains both settings files. Consequently, the updater’s compatibility augmentation never runs, leaving settings unchanged on this invocation. Normalize newly installed recognized default catalogs to enable the current compatibility policy while preserving existing explicit custom/false configurations. Test a pre-opt-in target ref with missing `refresh.json` and differing Claude/Codex settings.

## Minor Issues

- **[setup.sh:2607](/tmp/tarnished-318/setup.sh:2607): Refresh overwrites the selected upgrade version in the manifest.** After helper maintenance records the requested target version, `run_refresh` rewrites `tarnished_version` and `tarnished_commit` using `SCRIPT_DIR` at lines 1878–1880. Thus a successful pinned upgrade records the invoking checkout instead of its selected distribution; monorepo root and module metadata can also disagree. Preserve the selected distribution metadata and record the current updater through its individual installed hash. Extend the pinned-upgrade test to assert manifest version/commit and repeat-run stability.

## Suggestions

None.

## Orchestrator triage

All findings accepted after inspection. Critical C1 (legacy updater downgrade on failed upgrade), Major M1 (derived broad-overlay backup access), Major M2 (pre-opt-in missing-config settings migration), and Minor m1 (pinned manifest version metadata) will be fixed. No deferrals. Fix round 1 pending.

## Fixes Applied

All findings fixed in `4c39f2cdf6c82c85faa277eb142fc65ebc042525`; no deferrals. Original reviewer output above is preserved verbatim.

| Finding | Verified disposition |
| --- | --- |
| Critical C1 | Upgrade staging substitutes the current refresher before helper application. An injected different-helper failure cannot leave the historical destructive updater installed. Historical bootstrap comparison remains unchanged. |
| Major M1 | Every derived overlay path is rejected if it points into private backups, before reading candidate bytes; both updater mirrors match. |
| Major M2 | Newly installed recognized pre-opt-in catalogs enable default mappings on the first invocation; explicit existing custom/false configurations remain authoritative. |
| Minor m1 | Root upgrade refresh records selected upstream version/commit metadata, retaining current updater provenance in its individual installed hash; repeat manifests remain stable. |

## Orchestrator verification

**Overall after fixes: APPROVE.** Fix round 1 completed; no unresolved Critical, Major or Minor findings. The orchestrator read the complete fix diff and its design/doc clarification, verified requirement coverage FR-1 through FR-9, and inspected passing output for 5 focused regressions and 14 affected existing regressions. All four defect regressions also failed against the original reviewed commit at their intended defect, demonstrating effective regression coverage. An independent small reproduction confirmed that a broad overlay cannot project private backup bytes into live skills.

Before review, all 139 affected refresh/maintenance/upgrade Bats tests passed. The final fixes passed affected Bash syntax, ShellCheck with baseline-only exclusions, mirror verification and whitespace checks. The parent also verified real-template four-file skill/settings replacement with exact backups, application/custom-sibling preservation, dry-run and repeated-content idempotency. The first final smoke overlapped implementation commits and detected source metadata changes; rerunning with the committed source fixed confirmed stable repeated output.

ShellCheck baseline exclusions: SC1090, SC1091, SC2015, SC2016, SC2034, SC2094, SC2206, SC2295; no new diagnostics. Rust sources/build definitions did not change, so local Rust suites were not repeated; standard PR CI remains required. No separate rerun of unchanged remote-bootstrap or manifest suites was necessary; historical bootstrap and manifest metadata paths affected by fixes have focused behavioral regressions.

Reviewer runtime configuration was confirmed as Codex CLI 0.153.4, gpt-6-astra, high reasoning, read-only sandbox. This is independent CLI review followed by orchestrator fix verification, not a new independent APPROVE verdict. Filesystem protections use per-call path/content checks, not a claim of arbitrary hostile-race atomicity.

Design initially fell back to inline authoring/self-review after the delegated designer failed at model capacity. Implementation and fixes were delegated to executor318; its README/reference work was delegated to docs318. Requirements dialogue was inline. No approval stop occurred after the user's overwrite-policy decision.

The reviewed implementation working tree was clean. Subsequent implementation changes are confined to the verified finding fixes; review-artifact-only commits preserve completion freshness.
