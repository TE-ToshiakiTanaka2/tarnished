# Orchestrator review: #323 design artifacts

Reviewed against the Requirements section of issue #323 (FR-1 to FR-7, NFR-1 to NFR-3, Constraints).

## Rounds

- Round 0 (initial review): no blocking findings. No return to the designer was needed.

## Requirement coverage

| Requirement | Carried by | Verdict |
| --- | --- | --- |
| FR-1 `--zed` flag, prompt, summary line | api-spec.md "CLI surface" (parse case, prompt text, `Zed:` line) | Carried |
| FR-2 `customizations.zed.extensions`, vscode always kept, no key when off | `merge_devcontainer_json` presence-gated jq program; `templates/<flavor>/.zed/devcontainer.json` overlays; `apply_zed_assets` | Carried; byte-identity proven empirically by the designer against core + rust |
| FR-3 `.zed/settings.json` from core | `templates/core/.zed/settings.json` installed via `copy_with_confirm` | Carried |
| FR-4 per-language LSP/formatter fragments, `merge_zed_settings` | fragments for rust/python/node/deno/go/latex; `zedmerge` jq (deep merge, unique arrays, idempotent) | Carried |
| FR-5 Next steps, README, docs/setup.md | api-spec.md "Next steps"; workflow.md Step 6 | Carried |
| FR-6 `scaffold_options.zed_enabled`, inference, add-module warning | `infer_scaffold_options`, `manifest_options_valid`, `populate_setup_state_from_manifest`, warning block | Carried, plus `scaffold_flags_supplied` so `--zed` on an existing project errors instead of silently refreshing |
| FR-7 repository dogfooding | api-spec.md "FR-7" (devcontainer.json + merged `.zed/settings.json`) | Carried |
| NFR-1 byte-identical without `--zed` | presence gating; nothing inside verbatim-copied `templates/core/.devcontainer/` | Carried |
| NFR-2 bats coverage | workflow.md Step 8: 5 + 16 + 7 + 13 named tests | Carried |
| NFR-3 shell rules, verify-mirrors unaffected | design.md decision 9; `scripts/verify-mirrors.sh` passes on the design branch | Carried |
| Constraint: verified extension IDs | research.md §2, checked against `extensions.toml` and `api.zed.dev` | Carried |
| Constraint: `.zed/settings.json` not an AI asset | design.md decision 5 and the recorded assumption | Carried; see finding 1 |

## Findings

1. **Manifest tracking wording (accepted, issue clarified).** The issue said `.zed/settings.json` is "tracked as an ordinary scaffold helper in the manifest". `_manifest_path_eligible` (`scripts/lib/common.sh`) is a positive allow-list restricted to `.devcontainer/scripts/*.sh`, so no scaffold seed is hashed any more; hashing `.zed/settings.json` would widen the ownership model (#316/#318), which is out of scope. The designer's reading (not an AI asset, ordinary `copy_with_confirm` path, no new exclusion glob, provenance via `scaffold_options.zed_enabled`) is the intended one. The issue's Constraints bullet was reworded to say exactly that so criterion 9 of the review does not misread it.
2. **`-y` and the prompt (accepted).** The new prompt sits in the TTY-gated block shared with the GitHub Project and auto-tag prompts. That block is not gated on `SKIP_CONFIRM` today, so the three prompts behave alike; the default answer is `n`, and non-TTY runs stay off. Consistency with the siblings is preferred over a one-off gate.
3. **Array sorting in `merge_zed_settings` (noted for the executor, not blocking).** `unique` sorts arrays, so a `language_servers` list is reordered (`!`-prefixed entries sort first). Zed treats the first non-negated entry as primary; every shipped fragment has exactly one positive server per language, so the reorder is harmless. Future fragments must keep that property or the merge rule must change.
4. **Rust early return (carried in api-spec).** `plugin_post_copy_shared` in the rust plugin returns early when the post.sh marker is present; the `apply_zed_assets` call must precede that branch. The api-spec states this; the executor must honor it.

## Decisions the designer made that the issue did not settle

All ten are accepted as reported: separate `templates/<flavor>/.zed/` directory (option c), `AGENTS.md` §4 extension, no `MANIFEST_EXCLUDE_GLOBS` entry, `--zed` in `scaffold_flags_supplied`, `zed_enabled` in `manifest_options_valid` and `populate_setup_state_from_manifest`, short extension list with recorded rejections, JSONC-tolerant `merge_zed_settings`, omitted Biome `require_config_file` / texlab build settings, prompt placement, and the recorded `--add-module` limitation.

## Outcome

Design approved for implementation. Commit follows this review.
