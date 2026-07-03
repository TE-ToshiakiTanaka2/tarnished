# Code Review: #304

- **Branch**: refactor/TE-ToshiakiTanaka2/#304/modernize-ai-workflow-skills
- **Base**: develop (merge base: bce2aed)
- **Review scope**: Large (72 files, ~1,200 lines changed)
- **Reviewed at**: 2026-07-03T00:32:46Z
- **Reviewer**: Claude (code-reviewer subagent, fallback — Codex CLI not exercised for this asset-only change)

---

## Review Summary

**Overall**: REQUEST_CHANGES (all findings addressed; see Fixes Applied)

### Critical (must fix)

- None. Explicitly verified non-issues: `verify-mirrors.sh` arithmetic under `set -euo pipefail`; the `set +e`/`ERD_EXIT` capture block in auto-tag; `rsync --delete` idempotency of the new `.tarnished/workflows/erd` managed path (scaffold generates it from the identical source).

### Warnings (should fix)

- [.github/workflows/auto-tag.yml:30] Concurrency comment overstated the guarantee — GitHub keeps at most one pending run per group, so intermediate merges are superseded (one tag can cover several merges) rather than individually tagged.
- [templates/github-actions/auto-tag/.github/workflows/auto-tag.yml] The #303 fix did not reach downstream projects: concurrency declared inside a reusable workflow does not apply to caller runs; the caller template had no concurrency block. Same gap in the claude-review caller.
- [.github/workflows/claude-code-review.yml:60] `github.event.pull_request.draft == false` is unsafe for non-PR `workflow_call` events: GitHub expressions coerce `null == false` to `true`, so the guard passed and the job would fail at the action instead of skipping.
- [.tarnished/refresh.json] Existing downstream projects auto-refresh the new `/review` skill but cannot receive `.claude/agents/code-reviewer.md` (their old `refresh.json` lacks the managed path); `.tarnished/workflows/erd` likewise stays scaffold-frozen for the installed base.
- [.tarnished/refresh.json:30-34] Refresh-managing `.claude/agents` with `rsync --delete` deletes hand-authored user agents unless they migrate to `.claude/agents.local/` — undocumented hazard.
- [review/SKILL.md vs code-reviewer.md vs claude-code-review.yml] Review criteria existed in three diverging copies (7 vs 8 items, contradictory style guidance), contradicting design decision D4.

### Suggestions (nice to have)

- [claude-code-review.yml] `base-branch` input declared but never used; `types: [opened, ready_for_review]` cost bound undocumented.
- [auto-tag.yml] New `exit "$ERD_EXIT"` interacts non-obviously with `continue-on-error: true` (job still fails via the final gate step) — worth a comment.
- [AGENTS.md] erd overlay customization requires dual overlays downstream; undocumented.
- [docs/design/#304/design.md] D7 claimed bats tests were "extended"; the existing cross-check invariant covers the new entries without changes.
- [asset-parity.yml] PR path filter omitted the workflow file itself.

### Positive

- `scripts/verify-mirrors.sh` covers every touched tree (20 pairs, erd three-way via transitivity, generated `erd/` correctly excluded) and passes.
- The reviewer-resolution ladder is consistent across all three altitude levels, and the hardcoded `develop` merge base is gone at every level.
- All D2 contradiction fixes landed coherently (cleanup/improve mutual exclusion, test authoring ownership, build→troubleshoot escalation); no "Leveraging erd:X" or lifecycle mermaid restatements survive.
- MANIFEST_EXCLUDE_GLOBS wiring is complete (dir + dir/* + .local overlays) and the refresh_assets.bats cross-check passes over the new entries.

---

## Fixes Applied

- Caller templates (auto-tag, claude-review) gained their own `concurrency` blocks so serialization/cancellation reaches downstream projects
- Draft guard hardened with an explicit `github.event.pull_request &&` existence check
- Review criteria unified to one canonical 8-item list (skill Review Prompt Template) shared verbatim by the code-reviewer subagent and the CI prompt, with an identical anti-nitpick caveat
- `/review` Phase 3C degrades to a general-purpose subagent when `code-reviewer.md` is absent (pre-#304 projects)
- auto-tag concurrency comment corrected to state supersede semantics; `continue-on-error` interplay documented
- AGENTS.md section 6 documents the `.claude/agents.local/` migration hazard, the one-time `refresh.json` adoption step for existing projects, and the erd dual-overlay requirement; workflows README claim scoped accordingly
- asset-parity path filter includes itself; unused `base-branch` input dropped; design doc D7 wording corrected
- Commit: b61ed64
