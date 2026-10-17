# Review: #323 feat: optional Zed editor support in the generator and this repository's devcontainer

```yaml
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 323
review_status: complete
reviewed_head: a0321b230a3a9ef860da34b6484ddac2eeb7b69e
verified_head: 8d15678a4667af7e81d6669791e27dbccbb0e011
base_ref: develop
base_commit: 0860b09decdf69c80dcf4cc4487be7a1e160fc18
merge_base: 0860b09decdf69c80dcf4cc4487be7a1e160fc18
issue_body_sha256: 3e6a6fbcc2a8d206674a493e99bb9fe578ef05fc19d66fe096bf0e8becd5b693
branch: feature/TE-ToshiakiTanaka2/#323/optional-zed-editor-support-in-the-generator
scope: Large (48 files, +3059 / -32 including design docs; about 1,200 implementation lines plus tests and docs)
timestamp: 2026-10-17T13:02:39Z
reviewer: Claude-native code-reviewer subagent (fallback review; Codex CLI not installed, agent-profile placeholders unrendered). Model: inherited session model (claude-fable-5-1); reasoning effort: default
reviewer_resolution: explicit flag absent -> agent-profile.json unrendered -> `command -v codex` empty -> Claude-native fallback (review/SKILL.md Phase 2, rung 4)
```

## Reviewer Output (verbatim)

## Review Summary

**Overall**: APPROVE

Branch `feature/TE-ToshiakiTanaka2/#323/optional-zed-editor-support-in-the-generator` at `a0321b2`, reviewed against `docs/design/#323/*` and the issue #323 Requirements.

Verification performed (all read-only; outputs in the session scratchpad):

- `npx --yes bats tests/` — 362/362 pass, 3 pre-existing skips (service plugins, #265), 0 new skips. The four Zed suites (57 tests) pass individually.
- `bash scripts/verify-mirrors.sh` — all 18 mirror pairs byte-identical (AGENTS.md §7, NFR-3).
- `bash -n` on `setup.sh` and `scripts/lib/common.sh` — clean. `shellcheck` is not installed in this sandbox; not run.
- NFR-1, helper level: ran the merge-base `merge_devcontainer_json` and the branch version over `templates/core` + `rust` + `postgresql` overlays — `cmp` byte-identical.
- NFR-1, end-to-end: extracted the merge-base tree with `git archive`, scaffolded `--lang rust --postgresql -y` with both generators, `diff -r` of the trees is identical; the only difference is `.tarnished-manifest.json` gaining `"zed_enabled": false`, which FR-6 requires.
- FR-7: ran `apply_zed_assets` for `templates/core` then `templates/languages/rust` into a scratch target; result `diff`s clean against `.zed/settings.json`, and `customizations.zed.extensions` is `["dockerfile","toml"]` in both.
- `--lang rust --postgresql --zed -y` scaffold: no `*.tmp` leftovers, `.zed/settings.json` matches the api-spec, extensions `["dockerfile","sql","toml"]`, "Or open in Zed" block printed.
- `--upgrade --dry-run` and `--upgrade` over a committed `--zed` scaffold: exit 0, no Zed warnings, `.zed/settings.json` sha256 unchanged, manifest keeps `zed_enabled: true`. This exercises `populate_setup_state_from_manifest` restoring `ZED_ENABLED` and `apply_zed_assets` running under `MANIFEST_RECORDING` in the staging tree.
- `manifest_options_valid '{"zed_enabled":"yes"}'` returns non-zero; `true` is accepted.
- New template files are mode 100644 (workflow Step 2).

Project-specific invariants: no plugin reimplements copy/merge logic or bypasses `copy_with_confirm` (§1); shell rules honored except the line-width note below (§2); `.zed/` is documented in AGENTS.md §4 with the non-verbatim note; `refresh.json`, `MANIFEST_EXCLUDE_GLOBS`, `refresh-assets.sh`, `update_gitignore` and `verify-mirrors.sh` are untouched as the design requires (§6/§7). The language call sites sit in `plugin_post_copy_shared` before the early-returning `post.sh` marker branch, and never in `plugin_post_copy_module`. Every extension ID in the shipped `.zed/devcontainer.json` files appears in `research.md` §2.

### Critical (must fix)

No findings.

### Major (must fix before PR)

No findings.

### Minor (fix when cheap)

- `scripts/lib/common.sh:299-305` — In the first-contributor branch of `apply_zed_assets`, the return value of `copy_with_confirm` is discarded and `print_success "Created .zed/settings.json"` is printed unconditionally. `copy_with_confirm` can return 1 (`_recording_destination_safe` rejection, non-regular source, `cp` failure), and because the call is a plain statement under `setup.sh`'s `set -e`, that would abort the whole scaffold, contradicting the function's "Always returns 0" contract and the design's error table (design.md "Error Handling"). Suggested fix: `if copy_with_confirm ...; then print_success ...; else print_warning "Failed to create $target_settings"; fi` (and the same for the raw-copy fallback).
- `scripts/lib/common.sh:288-306` and `docs/design/#323/api-spec.md` "apply_zed_assets" — The implementation normalizes the first contributor's fragment through a self-merge (`merge_zed_settings "$fragment" "$fragment"`) before copying, so the seeded file has sorted, deduplicated arrays. Commit `010c285` and the inline comment explain why (idempotency of a second `plugin_post_copy` run), and the FR-7 fixture already reflects the sorted output, so behaviour is correct. However the design/api-spec still describe the first contributor as a raw `copy_with_confirm` of the fragment ("core creates `.zed/settings.json` by copy, later flavors merge"). The design should be updated to record this deviation so the next reader does not "fix" it back.
- `scripts/lib/common.sh:164,268,285` and `setup.sh:2865` — Four newly added lines exceed the 100-character limit in `.claude/rules/shell.md` (the jq `.extensions = (...)` line at 136 chars and three `print_warning` strings at 101-120 chars). The repository already has ~130 such lines, so this is low weight; the three warning strings can be shortened cheaply.

### Suggestions (nice to have)

- Test coverage, untested paths (everything in workflow.md Step 8 is present and green; these are the gaps beyond the plan):
  - `apply_zed_assets` devcontainer-step failure: an unparseable `<plugin>/.zed/devcontainer.json` should warn and leave the live `devcontainer.json` untouched (design.md error table row 3). Only the settings-merge failure path is tested (`tests/common_zed.bats` "leaves the live settings file unchanged").
  - `populate_setup_state_from_manifest` restoring `ZED_ENABLED` / `--upgrade` over a `--zed` project. I verified it manually (above); a `tests/setup_upgrade.bats` case asserting `.zed/settings.json` is byte-unchanged and `zed_enabled` survives would lock it in.
  - `manifest_options_valid` rejecting a non-boolean `zed_enabled` (api-spec "Error Handling" row 5). `tests/manifest.bats:384` covers `codex_enabled:null`; adding `{"zed_enabled":"yes"}` to that loop is a one-line change.
  - The interactive prompt (FR-1) cannot be driven without a TTY in bats; acknowledged in the design.
- FR-1 wording "with `-y` the default is off": the prompt lives in the same `check_tty_available && !IS_ADD_MODULE_MODE` block as the GitHub-Project/auto-tag prompts, which is not gated on `SKIP_CONFIRM`, so `-y` on a real TTY still asks (default `n`). design.md "Assumptions recorded for review" documents this reading and the orchestrator accepted it; I agree consistency with the siblings is right, but if the issue author meant "never prompt under `-y`", that is a separate change for all three prompts.
- `merge_zed_settings` sorts every array present on both sides. Today the only order-sensitive array in a shipped fragment is deno's `language_servers`, and it is only reordered when it is the first contributor (never in practice, since core runs first) — orchestrator-review.md finding 3 already records this. Worth a one-line comment on the jq program so a future fragment author knows arrays are treated as sets.

### Positive

- The presence-gated jq change in `merge_devcontainer_json` is exactly as specified and verifiably pure: byte-identical output without Zed input was confirmed both at the helper level and end-to-end against the merge-base generator.
- `apply_zed_assets` is the single reader of `ZED_ENABLED`, every plugin gained exactly one unconditional call, and no file was placed inside a verbatim-copied template directory — the three properties the design's option (c) depends on all hold.
- Error paths are careful: every merge goes through a temp file that is removed on failure, the live file is never replaced after a failed merge, and the helper returns 0 on every branch except the `copy_with_confirm` edge noted above.
- The idempotency fix in `010c285` was found by the author's own `plugin_idempotency` variants rather than left as a latent `--upgrade` re-run diff; the `MONOREPO_MODE=true` routing in those tests isolates the Zed delta from the pre-existing single-mode `post.sh` duplication and explains why in the file.
- Provenance is by filesystem evidence (`.zed/settings.json` presence), pre-#323 manifests validate unchanged, and the upgrade/staging path leaves the developer-owned file alone, as confirmed by a real `--upgrade` run.
- Documentation (README, `docs/setup.md`, AGENTS.md §4, `--help`, completion message) carries every FR-5 caveat the issue lists, including the Compose-project-name collision reason and `forwardPorts`.

## Orchestrator Triage

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M1 | Minor | `copy_with_confirm` return discarded in `apply_zed_assets` first-write path; a failure would abort the scaffold under `set -e` | Fix (cheap, and it restores the documented "always returns 0" contract) |
| M2 | Minor | Design/api-spec describe the first contributor as a raw copy; implementation self-merges first | Fix: record the normalization in `docs/design/#323/design.md` and `api-spec.md` |
| M3 | Minor | Four new lines over 100 chars | Fix: shorten the three warning strings and split the jq line |
| O1 | Minor (orchestrator) | `docs/setup.md` says `use_podman` goes in `devcontainer.json`; Zed reads it from Zed's own `settings.json` | Fix |
| S1 | Suggestion | Test: unparseable `.zed/devcontainer.json` warns and leaves the live devcontainer untouched | Apply (cheap) |
| S2 | Suggestion | Test: `manifest_options_valid` rejects non-boolean `zed_enabled` | Apply (one-line) |
| S3 | Suggestion | Test: `--upgrade` over a `--zed` project keeps `.zed/settings.json` and `zed_enabled` | Apply if `tests/setup_upgrade.bats` already has a reusable `--zed`-free fixture; otherwise record as deferred |
| S4 | Suggestion | Comment on `zedmerge` that arrays are sets | Apply (one line) |
| S5 | Suggestion | `-y` prompt semantics | No change; accepted in design review, consistent with sibling prompts |

## Fixes Applied

Fix commit: `8d15678a4667af7e81d6669791e27dbccbb0e011` (`fix: address review feedback for #323`), verified by the orchestrator by reading the diff against each finding and re-running `tests/common_zed.bats`, `tests/manifest.bats`, `tests/setup_upgrade.bats`, `tests/setup_zed.bats` (122/122 passing) and `scripts/verify-mirrors.sh` (all pairs identical). The executor's full-suite run after the fix: 364 passing, 0 failing, 3 pre-existing skips.

| # | Disposition | Verification |
| --- | --- | --- |
| M1 | Fixed | `apply_zed_assets` tracks `seeded`; both `copy_with_confirm` calls are checked, failure warns and the function still returns 0 |
| M2 | Fixed | `design.md` Data Flow / Implementation Notes and `api-spec.md` body + Contract notes now describe the self-merge normalization before `copy_with_confirm` |
| M3 | Fixed | Three warning strings shortened, jq `.extensions` expression split; touched hunks are within 100 chars |
| O1 | Fixed | `docs/setup.md` now states `use_podman` is a Zed user setting |
| S1 | Applied | `common_zed.bats` "leaves the live devcontainer unchanged when the overlay is unparseable" passes |
| S2 | Applied | `manifest.bats` rejected-options loop includes `{"zed_enabled":"yes"}` |
| S3 | Applied | `setup_upgrade.bats` "#323: --upgrade over a --zed scaffold leaves .zed/settings.json byte-unchanged" passes |
| S4 | Applied | Comment above `zedmerge` documents array-as-set semantics |
| S5 | No change | Accepted in design review; consistent with sibling prompts |

Deferred: none. Critical/Major findings: none.
