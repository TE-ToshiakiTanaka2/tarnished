# Orchestrator Review: #333 design artifacts

- **Reviewed**: `docs/design/#333/{design,api-spec,workflow}.md`, `docs/design/shared/{data-model,api-spec}.md` (regenerated)
- **Reviewed against**: issue #333 Requirements (FR-1 to FR-7, NFR-1 to NFR-3)
- **Author**: `designer` subagent (`.claude/agents/designer.md`, dispatched at effort `high`)
- **Rounds used**: 0 returns (round 0 cleared)

## Requirement coverage

| Requirement | Carried by | Verdict |
| --- | --- | --- |
| FR-1 settings `model` + `effortLevel` in both copies | design.md "Exact edits"; workflow Step 1 (`jq`, `cmp`, NFR-3 diff) | Carried |
| FR-2 designer `effort: high`, `[1m]` kept, mirror | design.md; workflow Step 2 | Carried |
| FR-3 executor `claude-opus-5-5` + `effort: medium`, mirror | design.md; workflow Step 2 | Carried |
| FR-4 delegation Model binding table with effort + channel | design.md edits 1-4 (five-column table); workflow Step 3 greps | Carried |
| FR-5 shared snapshot free of old IDs | `data-model.md` and `api-spec.md` regenerated in this commit; `git grep` form in workflow Step 6 | Carried — the designer found a second stale table in `shared/api-spec.md` (#312 "Role → model binding") that the issue did not list |
| FR-6 `effortLevel` round-trip bats test | workflow Step 4 (full test), Step 5 (mutation check, already run by the designer: fails against a `del(.effortLevel)` merge) | Carried |
| FR-7 `code-reviewer.md` and `agent-profile.json` untouched | design.md "Deliberately unchanged"; workflow Step 2/6 `git diff --quiet` | Carried |
| NFR-1 mirror byte-identity | workflow Steps 3 and 6 (`verify-mirrors.sh`) | Carried |
| NFR-2 one declaration site per value | workflow Step 6 `git grep` for `"effortLevel"` / `^effort:`; test fixture uses `xhigh` | Carried |
| NFR-3 settings diff limited to two keys | workflow Step 1 `jq -S 'del(...)'` diff | Carried |

## Decisions the issue did not settle — verified

1. **Propagation of `settings.json`** — the designer corrected the issue's Risk Factors: since #319 `.claude/settings.json` is a whole-file refresh target. Verified: `.tarnished/refresh.json:80-81` and the template copy map `templates/claude/.claude/settings.json → .claude/settings.json`; `docs/maintenance.md` row "Replace the complete file ... no JSON/TOML merge". Accepted; the issue's wording is a note, not a requirement, and is left as-is.
2. **FR-5 grep run over tracked files** — verified that `.tarnished/backups/refresh.j14AVQ/` already contains `claude-fable-5-1` in a backed-up `settings.json` and delegation `SKILL.md`; backups are retained by design (#319). The `git grep` form checks the same paths. Accepted.
3. **Workspace and template `settings.json` byte-identical** — follows from decision 1. Accepted; `cmp` added to the workflow.
4. **Top-level `effortLevel` over `modelSettings`** — matches the orchestrator's own recommendation at the requirements gate. Accepted.
5. **Test fixture value `xhigh`** — keeps the test out of NFR-2's declaration-site count. Accepted.

## Noted, not blocking

- The Error Handling rows (Claude Code ignores an out-of-range `effortLevel` / frontmatter `effort`) are the designer's reading of documentation, not runtime-confirmed; the design says so. Shipped values are inside the documented sets, so no path depends on it. Workflow Step 7 is the only runtime check and is best-effort.
- `.claude/agents.local/` is referenced as an overlay that survives refresh; it exists only as `MANIFEST_EXCLUDE_GLOBS` entries in `scripts/lib/common.sh:202-203`. Not load-bearing for this issue.
- The executor dispatch for `/implement` is itself a runtime exercise of the new executor frontmatter once implemented; `/review` fix dispatch and `/pr` will run on the new pins.

## Verdict

Cleared for commit. No findings returned to the designer.
