# Review: #331 Add Godot (GDScript + C#) language flavor with WSLg GUI overlay and headless CI

```yaml
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 331
review_status: complete
reviewed_head: 86e923f4c3c8505f1e203d9975c233d22c782f75
verified_head: 564cfb3562101dc82d31b1661985bf65d1427741
base_ref: develop
base_commit: b6c5ec85d4da1ffbbc665767a63426cd419493f7
merge_base: b6c5ec85d4da1ffbbc665767a63426cd419493f7
issue_body_sha256: 16bfe96c5b092f627db0bb10909947d1045dae2860d60d5a3346f6b19fe979d3
```

- **Branch**: `feature/TE-ToshiakiTanaka2/#331/add-godot-gdscript-c-language-flavor-with-wslg-gui`
- **Reviewed at**: 2026-11-03T15:02:05Z
- **Scope**: Large (deep review). `git diff b6c5ec8 86e923f`: 35 files, +3965 / −105 (implementation commits add2e34..86e923f: 23 files, +1883 / −56)
- **Reviewer**: Claude-native `code-reviewer` subagent (**fallback review**). Resolution ladder: no explicit flag; `.tarnished/agent-profile.json` carries unrendered `{{AI_REVIEW_AGENT}}` placeholders (skipped); Codex CLI 0.166.0 is installed but `codex login status` reports "Not logged in", so under `/flow` the run fell through to the Claude-native reviewer. Model: inherited (the agent definition pins none); reasoning effort: default.
- **Ground truths supplied**: `docs/design/#331/design.md`, `api-spec.md`, `orchestrator-review.md`; issue #331 Requirements.
- **Committed diff excludes**: nothing — the working tree was clean at `reviewed_head`.

## Reviewer output (verbatim)

## Review Summary

**Overall**: APPROVE

Scope reviewed: `git diff add2e34 HEAD` (23 files), `docs/design/#331/{design,api-spec,orchestrator-review}.md`, issue #331 Requirements. Checks run: the five touched bats suites (138 tests: 136 pass; #34 needs `python3`, #113 is the python-flavor scaffold hitting a mise template error that reproduces at the merge base, so both are environmental), `shellcheck 0.11.0` (no findings in the new/changed files; all reported lines are pre-existing `common.sh` code), `bash scripts/verify-mirrors.sh` (all pairs byte-identical), an NFR-3 byte-identity comparison of full scaffolds from `b6c5ec8` vs `HEAD` for `--lang rust`, `--lang python --zed --codex`, `--lang latex`, `--lang deno --github-actions` and (up to the yq-dependent compose merge) `--lang rust --postgresql`, `--lang go --lang node --redis` (all identical apart from the manifest `created_at`), the three `run:` blocks of `godot-quality-check.yml` extracted and executed against a stub repo and stub `gdlint`/`gdformat`/`godot`/`dotnet`, and the pinned mise 2026.10.25 reading the generated `mise.toml` (`[tool_alias]` accepted; `mise current godot|gdtoolkit|dotnet` print `4.7.2-stable`, `4.5.0`, `10.0.403`, which is what `smoke-runtimes.sh` and the export job assume). Docker builds, the real Godot/.NET/gdtoolkit installs and the scaffold-build godot leg could not be exercised here.

### Critical (must fix)
No findings.

### Major (must fix before PR)
No findings.

### Minor (fix when cheap)
- [/workspace/templates/languages/godot/plugin.sh:39, 134, 185, 188, 220, 388, 390, 394] Eight lines exceed the 100-column limit in `.claude/rules/shell.md` (line 39 is 209 columns). Existing plugins carry two such lines each, so this is a documented-rule deviation rather than a style preference. The constant on line 39 and the `hint` string on 185 can be split with `\` continuations or built in two assignments; the three post.sh `echo` lines can be shortened.
- [/workspace/templates/languages/godot/.github/workflows/godot-quality-check.yml:44-71] Lint roots are the union of directories holding `project.godot` or `gdlintrc`. In a single-mode scaffold (`gdlintrc` at the root) where the developer later creates the project in a subdirectory, every `*.gd` under that subdirectory is linted twice (once from `.`, once from `./game`; verified with stubs). In a monorepo (no root `gdlintrc`) any `*.gd` outside a discovered root is counted by the detect step but never linted. Consider pruning nested roots (skip a root whose ancestor is also a root) and, when roots exist, also linting the remaining files from `.`, or document that only project/module trees are linted.
- [/workspace/docs/design/#331/design.md:122 (D18); /workspace/docs/design/#331/api-spec.md:163] Undocumented deviation: the export job writes to `build/ci-export/<project slug>/<preset index>/<basename>` (workflow lines 217, 248), not `build/ci-export/<preset index>/<basename>` as D18 states. The change is an improvement (two monorepo projects can no longer collide on preset `0`), but D18/api-spec should be updated so the design matches the shipped behaviour. Likewise `scripts/lib/manifest.sh` (needed so `manifest_options_valid` accepts `godot`, otherwise `--upgrade` of a godot scaffold would reject its manifest) is absent from the design's "Module Structure" table.

### Suggestions (nice to have)
- [/workspace/docs/setup.md:213] The documented checksum command `grep " ${tpz}\$" SHA512-SUMS.txt | sha512sum -c -` only matches the two-space form of the sums file, whereas the workflow (line 190) also tolerates the `*filename` binary-mode form. Mirroring the workflow's parsing (or `grep -E "[ *]${tpz}\$"`) keeps the two in step.
- [/workspace/tests/godot_plugin.bats] Untested paths worth adding cheaply: (a) the TTY `y` answer in `_godot_copy_workflow` (lines 77-90 of plugin.sh; only the non-TTY decline is covered), (b) `GODOT_GUI=1` / `GODOT_GUI=yes` accepted as true and an arbitrary non-empty value treated as false (plugin.sh:152-155), (c) a content assertion that `--zed` installs `languages.GDScript.formatter.external.command == "gdformat"` and `**/.godot` in `.zed/settings.json` (the idempotency test only proves stability, not content), (d) `plugin_interactive_setup` when `TARGET_DIR` is unset but the overlay is already listed, documenting that step 2 is skipped there by design.
- [/workspace/templates/languages/godot/.github/workflows/godot-quality-check.yml] The workflow's shell logic has no automated test; the extracted-step approach used in this review (stub tools on `PATH`, fixture `export_presets.cfg` with a `[preset.N.options]` section) would make a cheap bats case guarding the preset parser and the skip notices.

### Positive
- The resolver/prompt split (`_godot_resolve_gui_choice` + `plugin_interactive_setup`, plugin.sh:147-249) implements the orchestrator's corrected D9 exactly; every row of the design's behaviour table is covered by a bats case, including the "TTY with `-y`", "already listed", "UPGRADE_MODE" and "re-source resets the choice" rows.
- `_godot_enable_gui_overlay` (plugin.sh:181-223) edits `devcontainer.json` through `mktemp` next to the file + `mv` only on success, keeps array order (no `unique`), normalises a string-valued `dockerComposeFile`, and the comments-in-JSON test asserts byte-identity and no leftover temp files.
- `_godot_ensure_aliased_tool` (plugin.sh:98-124) honours FR-2 precisely: a developer's own `tools.godot` is kept and no alias is written that would retarget it, while a developer-authored `tool_alias.godot` is preserved and only the tool entry is added; both cases are tested.
- Extracting `MISE_TOML_AWK_SCAN` (common.sh:836-881) so `mise_toml_ensure` and `mise_toml_has_key` share one presence rule, with the existing `common_mise.bats` cases guarding byte-identical output; NFR-3 holds for every existing flavor I scaffolded.
- The `post.sh` block is placed with `post_sh_add_block` before the Codex and plugin markers, never calls `exit` or `sudo`, and is executed in tests under `set -e` with a restricted `PATH` for the missing-godot, failing-godot and working-godot cases.
- The CI workflow gates `jdx/mise-action` behind a cheap detect step in every job, verifies export templates against `SHA512-SUMS.txt` before unzipping, and the scaffold-build leg already forwards `secrets.GITHUB_TOKEN` to `mise install`, so the `github:` backend will not hit unauthenticated API limits in CI.
- The gitignore block uses an exact-line marker guard and append-only writes; the plugin ships nothing outside the permitted template subdirectories, and the root-level compose overlay is documented in `AGENTS.md` §4 as a non-merged file.

## Orchestrator triage

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| M1 | Minor | `plugin.sh` lines over 100 columns (8) | Fix (cheap; documented rule) |
| M2 | Minor | CI lint roots: nested roots lint twice, files outside roots never linted | Fix: prune nested roots, lint leftover files from `.` |
| M3 | Minor | design.md D18 / api-spec export path and missing `manifest.sh` in Module Structure | Fix: update the design docs to the shipped behaviour |
| S1 | Suggestion | docs/setup.md checksum grep misses `*filename` form | Fix (cheap, keeps docs and CI in step) |
| S2 | Suggestion | Untested paths (a)-(d) | Fix (b) and (c); (a) and (d) recorded, not required |
| S3 | Suggestion | bats case for the workflow shell logic | Recorded; not required for this PR |

## Fixes Applied

Applied by the `executor` subagent in commit `564cfb3562101dc82d31b1661985bf65d1427741` (`fix: address review feedback for #331`); verified by the orchestrator by reading the diff against each finding.

| # | Disposition | Verification |
| --- | --- | --- |
| M1 | Fixed | `awk 'length > 100'` reports no line in `templates/languages/godot/plugin.sh`; the `GODOT_MISE_TOOL_VALUE` literal is assembled from parts and the generated `mise.toml` is byte-identical (`cmp`) |
| M2 | Fixed | Lint job prunes roots nested under another root and lints leftover `*.gd` from `.` through a shared `lint_files` helper; stub runs cover single-mode root + `./game`, monorepo `a/gdlintrc` + stray `tools/x.gd`, no roots, and a failing `gdlint` (exit 1); `actionlint` passes |
| M3 | Fixed | design.md D18/D20 and Module Structure (adds `scripts/lib/manifest.sh`), api-spec.md export path now match the shipped workflow |
| S1 | Fixed | docs snippet uses the workflow's awk parsing; verified against a fixture sums file in both forms |
| S2 | Fixed (b, c) | Three new cases in `tests/godot_plugin.bats` (33/33 pass): `GODOT_GUI=1`/`yes` enable, `maybe` disables without prompting, Zed settings content asserted with jq. (a) and (d) recorded, not required |
| S3 | Recorded | No bats case for the workflow shell logic in this PR |

Checks after the fixes: `tests/godot_plugin.bats` 33/33; `shellcheck` clean on `plugin.sh` and `smoke-runtimes.sh`; `scripts/verify-mirrors.sh` all pairs byte-identical. The full bats suite fails the same 40 environment-dependent tests (python3 / yq / claude stubs) on `develop` and on this branch; no regression.

Critical or Major findings left unfixed: none (none were raised).
