# Code Review: #263

- **Branch**: feature/TE-ToshiakiTanaka2/#263/support-monorepo-layout-with-per-module-scaffolds
- **Base**: develop (merge base: 9cd6e18)
- **Review scope**: Large (~2.7k lines changed across 19 files)
- **Reviewed at**: 2026-04-29T02:56:47+00:00
- **Reviewer**: Codex CLI 0.125.0

---

### Critical (must fix)
- [templates/languages/python/plugin.sh:102] Single-project output is no longer byte-identical to `develop`: the new marker blocks are written into `docker/Dockerfile.dev` and `.devcontainer/scripts/post.sh` even on the first single-project run. The same regression exists at [templates/languages/node/plugin.sh:123], [templates/languages/rust/plugin.sh:122], [templates/languages/deno/plugin.sh:121], and [templates/languages/latex/plugin.sh:129]. NFR-1 and V1-V7 require no diff vs `develop`. Fix by keeping the markerized path only for monorepo/add-module reruns and leaving the single-project shim byte-for-byte equivalent to the pre-#263 implementation.
- [setup.sh:1004] `modules.json` validation never runs before writes. `detect_existing_monorepo` only checks file existence, `find_module_by_name` at [scripts/lib/common.sh:797] treats parse/version errors as "not found", and `core_seed_modules_json` at [templates/core/plugin.sh:87] mutates the registry after copy/post-copy work has already run. With malformed JSON or `version: 2`, the command can partially modify the tree before failing, instead of rejecting the registry up front as the design requires. Fix by calling `read_modules_json` during mode resolution/conflict detection and aborting before any file-copy/post-copy phase.
- [setup.sh:1166] Add-module service deduplication is broken. The interactive filter maps `mysql` to `-mysql` and `celery` to `-celery`, but the real service names are `{{PROJECT_NAME}}-db` at [templates/services/mysql/docker-compose.mysql.yml:2] and `{{PROJECT_NAME}}-celery-worker` / `-celery-beat` at [templates/services/celery/docker-compose.celery.yml:2]. On top of that, explicit CLI flags bypass the filter entirely because `SELECTED_SERVICES` is never scrubbed before `load_selected_plugins` at [setup.sh:466]. Since the unchanged service plugins append non-idempotently, rerunning one duplicates `depends_on`, `runServices`, env vars, and `post.sh` blocks; see [templates/services/mysql/plugin.sh:71] and [templates/services/celery/plugin.sh:85]. Fix by normalizing existing compose services to service IDs correctly and filtering both interactive choices and CLI-selected services.

### Warnings (should fix)
- [setup.sh:1210] Add-module mode still derives `PROJECT_NAME` from the current invocation instead of the existing monorepo. If the original init used a custom project name or the repo directory was later renamed, newly added service placeholders and module `CLAUDE.md` content will use a different project prefix than the existing root files. The new per-module template at [templates/core/module.CLAUDE.md.template:5] makes this visible immediately. Fix by persisting the canonical project name or deriving it from an existing root artifact before rendering new placeholders.
- [setup.sh:1263] The add-module UX still asks about Codex/GitHub Actions, but `load_selected_plugins` intentionally skips those plugins in add-module mode at [setup.sh:449]. That makes "yes" a silent no-op and contradicts the documented mode-agnostic flag behavior. Either suppress those prompts/flags in add-module mode with a clear message, or add a safe idempotent path for installing them.
- [scripts/lib/common.sh:844] `replace_module_entry` rebuilds the matched module object from scratch and drops unknown per-module keys. That violates the forward-compatibility contract for version-1 schema extensions. Fix by updating only the known fields with `jq --arg/--argjson` instead of replacing the whole object.

### Suggestions (nice to have)
- [scripts/lib/common.sh:821] `add_module_entry` and `replace_module_entry` interpolate `name`/`lang` directly into the jq program string. Current validation makes it low-risk, but `jq --arg` / `--argjson` would harden the helper contract and remove reliance on caller-side sanitization.
- [docs/design/#263/workflow.md:184] The manual matrix misses two cases that would have caught the current regressions: add-module against an existing `mysql`/`celery` service, and add-module where the original `PROJECT_NAME` differs from the checkout directory name.

### Positive
- [setup.sh:590] The monorepo dispatch in `execute_plugin_post_copies` is localized and easy to reason about; the language-plugin split did not leak mode checks all over the orchestrator.
- [templates/core/plugin.sh:125] Promoting the per-module `CLAUDE.md` generation into a dedicated helper is a good separation of concerns.
- [setup.sh:1116] The overwrite prompt is placed before the normal add-module write path, which is the right shape for FR-9.

**Verdict: REQUEST_CHANGES**

---

## Fixes Applied

All 3 critical, 3 warning, and 1 of 2 suggestion items addressed:

| # | Item | Commit | Notes |
| --- | --- | --- | --- |
| Critical 1 | NFR-1 marker leak into single mode | `646c337` | Marker-guarded write path only fires when `MONOREPO_MODE \|\| IS_ADD_MODULE_MODE`. Single mode falls back to pre-#263 verbatim insertion. Verified: Rust / Python / Python+Postgres single-mode trees byte-identical to develop via `git worktree`. |
| Critical 2 | Validate `modules.json` before any writes | `435b742` | Both `--add-module` path and the auto-detect path call `read_modules_json` immediately after `detect_existing_monorepo`. Malformed JSON and `version: 2` now abort with a clear error before any file-copy / post-copy hook runs. |
| Critical 3 | Service dedup wrong suffixes + CLI bypass | `23c2290` | Replaced the suffix table with `service_overlay_collides_with_target`, which reads each candidate plugin's docker-compose overlay, substitutes `{{PROJECT_NAME}}`, and checks whether any of its service keys are already present in the target. Both `AVAILABLE_SERVICES` (interactive offer list) and `SELECTED_SERVICES` (CLI-flag-set list) are scrubbed. Verified: postgres + add-module --postgresql, mysql + add-module --mysql, and celery + add-module --celery all produce no duplicate compose services. |
| Warning 4 | `PROJECT_NAME` consistency in add-module | `4fa5b35` | New `derive_project_name_from_compose` helper extracts the first top-level service in the existing docker-compose.yml (always the dev container per template) and overrides any user-typed `PROJECT_NAME` with that canonical value. Per-module CLAUDE.md / service overlay substitutions now use the original project name even after directory rename or wrong-name invocation. |
| Warning 5 | Suppress no-op Codex / GH Actions prompts in add-module | `da7a544` | The three interactive prompts (Codex, project-integration, auto-tag) are gated on `IS_ADD_MODULE_MODE != true`. CLI flags `--codex` / `--github-actions` are also reset to `false` with a one-line warning when used in add-module mode, so they're not silently ignored. |
| Warning 6 | `replace_module_entry` preserves unknown keys | `4b873d0` | Rewrote with `. + {…}` merge so only `path` / `language` / `services` are overwritten; user-added forward-compatible per-module fields (e.g., `commands`, `version_file`) survive the rewrite. Verified by injecting `commands.build` into a module entry, triggering a replace, and checking the field was retained. |
| Suggestion 7 | jq `--arg` / `--argjson` hardening | `4b873d0` | `write_modules_json` now forwards extra arguments to `jq`. `add_module_entry` and `replace_module_entry` switched from string-interpolated jq filters to `--arg name --arg lang --argjson svcs`. Helper layer is now safe-by-construction against quote / backslash injection. |
| Suggestion 8 | Manual matrix missing rows | (deferred) | The two missing scenarios (V25 mysql / celery dedup, V26 PROJECT_NAME mismatch) are now actually verified in the post-fix matrix run, but `docs/design/#263/workflow.md` was not updated since the workflow doc is frozen with the per-issue design and updating it post-implementation would muddle the design vs. implementation timeline. The new scenarios are captured in this review record and the post-fix run output. |

### Final verification

`PASS=17, FAIL=0` on the post-fix matrix (the script-reported failures were artifacts of `git stash`/checkout interference with itself — re-verified cleanly via `git worktree add`).

`cargo check` / `cargo test` (109 + 15 tests) / `cargo clippy -D warnings` / `cargo fmt --check`: all clean.

### Fix commits (in order)

```
4b873d0 fix(common): preserve unknown module keys + harden jq with --arg
da7a544 fix(setup): suppress no-op prompts/flags in add-module mode (Warning #5)
4fa5b35 fix(setup): anchor PROJECT_NAME to existing monorepo in add-module mode
23c2290 fix(setup): correct service dedup in add-module mode (Critical #3)
435b742 fix(setup): validate modules.json before any writes (Critical #2)
646c337 fix(languages): preserve NFR-1 byte-identity in single mode (Critical #1)
```
