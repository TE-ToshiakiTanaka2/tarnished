# Review: #333 chore: rebind lifecycle roles to Fable 5.2 (high) / Opus 5.5 (designer high, executor medium)

```yaml
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 333
review_status: complete
reviewed_head: 2fdb0fa035291c6fafdfe6a239d90d1d9d6392c4
verified_head: 2fdb0fa035291c6fafdfe6a239d90d1d9d6392c4
base_ref: develop
base_commit: 5052a64a5ef636061cd4370e68679b2788673921
merge_base: 5052a64a5ef636061cd4370e68679b2788673921
issue_body_sha256: ef7efbf9a5b44465fd934448302f66c32a24a7a224c170b9ae9bec5f2b6deba0
```

- **Branch**: `feature/TE-ToshiakiTanaka2/#333/rebind-lifecycle-roles-to-fable-5-2-high-opus-5-5`
- **Target**: `develop` (fetched `5052a64a5ef636061cd4370e68679b2788673921`); merge base is the same commit
- **Reviewed head**: `2fdb0fa035291c6fafdfe6a239d90d1d9d6392c4` (design commit `e821ff8` + three implementation commits `5210fb4`, `4557856`, `2fdb0fa`); working tree and index clean at review time, so the committed diff is the whole change
- **Scope**: Medium — 15 files, +548/-38 including the design commit; implementation alone 9 files, +84/-20. All nine criteria applied
- **Timestamp**: 2026-11-10T09:29:15Z
- **Reviewer**: Claude-native `code-reviewer` subagent (**fallback review**). Resolution ladder: no explicit flag; `.tarnished/agent-profile.json` carries unrendered `{{AI_REVIEW_AGENT}}` placeholders (treated as absent); Codex CLI 0.166.0 is installed but `codex login status` reports "Not logged in", so under `/flow` the run fell through to the Claude-native reviewer. Model: inherited session model (`claude-fable-5-1`; the agent definition pins none); reasoning effort: default (session had no effort pin when it started)
- **Ground truths supplied**: `docs/design/#333/design.md`, `workflow.md`, `api-spec.md`; issue #333 Requirements section (digest above)

## Review Output (verbatim)

Verified: `$base * { hooks: ... }` cannot drop a base key, so the design's rationale for skipping a second test holds. I have everything needed for the review.

## Review Summary

**Overall**: APPROVE

Reviewed head `2fdb0fa` against merge base `5052a64` (three implementation commits after the design commit `e821ff8`). The diff is the exact file set named in `/workspace/docs/design/#333/design.md` :: Module Structure, with no extra paths. Every acceptance check in issue #333 and in `/workspace/docs/design/#333/workflow.md` Steps 1-6 was re-run here and passes:

| Check | Result |
| --- | --- |
| FR-1 `jq -r '.model, .effortLevel'` on both settings files | `claude-fable-5-2` / `high` on both; `cmp` identical |
| FR-2 / FR-3 frontmatter | designer: `model: claude-opus-5-5[1m]` + `effort: high`; executor: `model: claude-opus-5-5` + `effort: medium`; `code-reviewer.md` has neither key |
| FR-4 delegation table | Five-column table at `/workspace/.claude/skills/_shared/delegation/SKILL.md:49-54` matches the channel files value-for-value and names `effortLevel` / frontmatter `effort:` as channels; new precedence paragraph at line 66 |
| FR-5 old IDs | `git grep` and `grep -r --exclude-dir=backups` over `.claude .tarnished .codex templates docs/design/shared` return nothing |
| FR-6 | `tests/common_json.bats` 20/20 pass; the new test fails against a `del(.effortLevel)` mutation (run on a scratch copy of `common.sh`, tracked tree untouched: mutated result `effortLevel=null` vs expected `xhigh`) |
| FR-7 | `git diff --quiet` on `code-reviewer.md` (both copies) and `agent-profile.json` (both copies) exits 0 |
| NFR-1 | `scripts/verify-mirrors.sh`: "all mirror pairs are byte-identical" |
| NFR-2 | `git grep '"effortLevel"' / '^effort:'` outside `docs`/`tests` lists only the two settings copies and the four designer/executor files; no `templates/{languages,core,codex}` fragment mentions `effortLevel` |
| NFR-3 | `jq -S 'del(.model, .effortLevel)'` diff against `5052a64` is empty for both settings files; numstat is `2 1` for each |

### Critical (must fix)
No findings.

### Major (must fix before PR)
No findings.

### Minor (fix when cheap)
No findings.

### Suggestions (nice to have)
- [/workspace/docs/design/#333/workflow.md:328] Step 5 ("Prove the test fails when `effortLevel` is dropped") and Step 7 (runtime smoke check) both end with "the PR body records ...". Neither is verifiable from the branch; the PR author should carry the mutation-check result (reproduced above) and the Step 7 outcome (confirmed or "not possible in this environment") into the PR body so the design's own acceptance trail is complete.
- [/workspace/tests/common_json.bats:268] The test covers the three paths the design names (overlay supplies the key, same overlay re-merged, language fragment without the key). `merge_claude_settings_hooks` is deliberately not covered for `effortLevel`; I verified its `$base * { hooks: ... }` expression at `/workspace/scripts/lib/common.sh` cannot drop a base key and that the existing `keeps the base plugin keys` test guards that generic property, so no additional test is needed. Noting it only so a future rewrite of that function knows the invariant is implicit there.

### Positive
- The implementation is byte-for-byte the design's "Exact edits": the settings diff is exactly two lines per file, frontmatter edits are limited to the `model:`/`effort:` lines, agent bodies are untouched, and the delegation section changes are confined to the four specified edits.
- The test fixture uses `xhigh`, which is not a shipped pin, so the test cannot become a second declaration site and does not need editing on the next re-pin (NFR-2 by construction). The three-stage shape (scaffold, `--upgrade` re-merge, add-module with a fragment lacking the key) covers the real call sites in `templates/claude/plugin.sh` and the language plugins rather than just the first merge.
- The shared snapshot (`/workspace/docs/design/shared/data-model.md:462-477`, `/workspace/docs/design/shared/api-spec.md:612-621`) was corrected beyond the issue's literal ask: the stale "workspace and template values may diverge and `--upgrade` does not revisit" sentence now reflects the #319 whole-file refresh behaviour, and the second stale role table in `shared/api-spec.md` (not listed in FR-5) was updated as well. The only remaining "Sonnet" mention under `docs/design/shared` is the #333 change-log row describing the move away from it, which is correct history, not a live binding.
- The design documents the FR-5 grep caveat (`.tarnished/backups/` is gitignored restoration material holding old IDs) and the equivalent tracked-file form of the check rather than quietly weakening the acceptance; the tracked-file grep is empty on this branch.

## Orchestrator Triage

| Finding | Severity | Disposition |
| --- | --- | --- |
| Carry the Step 5 mutation-check result and the Step 7 runtime-check outcome into the PR body | Suggestion | Accepted; recorded in the PR body by `/pr` |
| `merge_claude_settings_hooks` has no `effortLevel` test; invariant implicit in its `$base * {hooks}` shape | Suggestion | Noted; no change (reviewer and design agree the existing plugin-key test guards it) |

Orchestrator verification before this record: `scripts/verify-mirrors.sh` byte-identical; `tests/common_json.bats` 20/20; FR-5 `git grep` empty; implementation diff matches `docs/design/#333/design.md` "Exact edits" line for line (orchestrator review of the executor's result, round 0, no returns).

## Fixes Applied

None required.
