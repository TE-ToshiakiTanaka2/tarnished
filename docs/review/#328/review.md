# Review — Issue #328

```yaml
repository: TE-ToshiakiTanaka2/tarnished
issue_number: 328
review_status: complete
reviewed_head: ad036f3adea10a07b9816211db6ad469ee663ac9
verified_head: ad036f3adea10a07b9816211db6ad469ee663ac9
base_ref: develop
base_commit: d8e0d6a51325f12314852690d887d324793f742c
merge_base: d8e0d6a51325f12314852690d887d324793f742c
issue_body_sha256: 94c2aad6df22e109addf2cd28fb59967393dc284d9bae9a9c0b038da4d9dd027
reviewer: Claude-native code-reviewer subagent (fallback)
reviewer_model: claude-fable-5 (session-inherited; no frontmatter pin resolved a different model)
review_scope: Small (12 changed lines, 1 file)
timestamp: 2026-11-02T03:02:17Z
```

## Reviewer resolution

- `--codex`/`--claude` flags: none given (run under `/flow`).
- Configured review agent: skipped — `.tarnished/agent-profile.json` contains unrendered `{{...}}` placeholders (`primary_agent`, `review_agent`), treated as absent per the delegation skill.
- Codex CLI (`codex exec`, model `gpt-6-astra`, reasoning effort `high` from `.codex/config.toml`): **attempted and failed** — `401 Unauthorized: Missing bearer or basic authentication in header` from the Codex API (not logged in). Under `/flow`, the resolution ladder falls through rather than prompting.
- **Fallback used: Claude-native `code-reviewer` subagent** in a fresh read-only context, receiving the standard Review Prompt Template with both ground truths (no design document exists for this XS bugfix; the issue's Requirements and Implementation Approach were supplied). This is a fallback review, marked per `/review` Phase 2.

## Review output (verbatim)

## Review Summary

**Overall**: APPROVE

### Critical (must fix)
- No findings.

### Major (must fix before PR)
- No findings in the diff itself. One pre-existing sibling defect discovered during verification is listed under Suggestions with a recommendation to file a follow-up P0 issue (it is outside issue #328's stated scope, pre-dates this branch, and is not regressed by it — but it must not be lost; see below).

### Minor (fix when cheap)
- No findings.

### Suggestions (nice to have)
- [/workspace/templates/github-actions/claude-review/.github/workflows/claude-code-review.yml:33-37] **The identical duplicated-concurrency defect survives in the sibling caller template, and it carries the exact claim this branch disproves.** The claude-review caller declares `concurrency: group: claude-review-${{ github.event.pull_request.number || github.ref }}`, and the reusable workflow it calls (`/workspace/.github/workflows/claude-code-review.yml:31-33`, which does accept `workflow_call`) declares the byte-identical group at its own top level — the same caller/callee same-group pattern that issue #328 empirically demonstrated fails the run before any job starts in auto-tag. The template's comment ("Concurrency declared inside the reusable workflow does not apply to caller runs") is the same false premise the new auto-tag comment now explicitly refutes, and it is the last remaining live copy of that claim in the repo (the other occurrences are historical artifacts in `docs/review/#304/review.md`). Mitigating factors for severity: it uses `cancel-in-progress: true` (failure mode may differ from the auto-tag deadlock), the template is manual opt-in ("not wired into setup.sh"), and #328's Requirements scope only auto-tag. Recommended resolution: file a follow-up P0 issue (or fold the two-line removal into this branch if the owner accepts the scope extension) and verify the failure mode in a downstream adopter the way #328 did.
- [tests/] **No regression guard against reintroducing the block.** This exact `concurrency` block was added once already (#305) on a plausible-but-wrong premise flagged by the #304 review, so a comment alone has already failed once as a deterrent. A trivial bats test (e.g., assert `! grep -q '^concurrency:' templates/github-actions/auto-tag/.github/workflows/auto-tag.yml` and `grep -q '^concurrency:' .github/workflows/auto-tag.yml`) would pin both halves of the invariant the new comment describes. No obligation — the issue is XS/trivial and names no test task.

### Positive
- The fix is exactly the issue's Implementation Approach: the duplicated block is removed and the replacement comment at `/workspace/templates/github-actions/auto-tag/.github/workflows/auto-tag.yml:34-38` is a genuine improvement — it names the callee's group (`auto-tag-<ref>`), explains the deadlock mechanism, and will stop a future contributor from "restoring" the block the way #305 added it.
- Both functional requirements verified: the reusable workflow `/workspace/.github/workflows/auto-tag.yml:35-37` still owns the per-ref serialization (`auto-tag-${{ github.ref }}`, `cancel-in-progress: false`), and the diff touches neither the `workflow_call` contract (`uses:`/`with:`/`secrets: inherit` at template lines 42-45 are intact, `__ERD_REF__` placeholder preserved) nor version-bump semantics.
- No collateral obligations missed: the template is not a mirrored asset (`scripts/verify-mirrors.sh` has no auto-tag entry), and the tests that consume it (`tests/setup_upgrade.bats:41`, `tests/plugin_tracking.bats:100`, `tests/plugin_idempotency.bats:113`) compute hashes dynamically or exercise the plugin, so none assert the removed block.

### Verification notes
- Checks run: traced both caller templates and both reusable workflows; grepped tests, `scripts/verify-mirrors.sh`, and docs for dependencies on the removed block and for remaining copies of the disproven comment.
- Check prevented by the environment: `bats` is not installed in this sandbox, so I could not execute the auto-tag plugin tests (`tests/plugin_tracking.bats`, `tests/plugin_idempotency.bats`). Static inspection shows they do not assert the removed content, so breakage is not expected.

**Verdict: APPROVE** — the diff fully and minimally implements issue #328 with no defects. The claude-review sibling defect is real but pre-existing and out of this issue's scope; it warrants an immediate follow-up issue rather than blocking this merge.

## Orchestrator triage

| Finding | Severity | Disposition |
| --- | --- | --- |
| Sibling claude-review caller template duplicates its reusable workflow's concurrency group | Suggestion (pre-existing, out of #328 scope) | Recorded; recommend a follow-up issue. Not folded into this branch — #328's Requirements scope only auto-tag, and the claude-review failure mode is unverified downstream |
| No bats regression guard pinning the removed block's absence | Suggestion | Recorded; no obligation for an XS bugfix whose issue names no test task |

No Critical, Major, or Minor findings. The committed diff is the entire branch delta; the working tree was clean at review time, so nothing was excluded from review.

## Fixes Applied

None required.
