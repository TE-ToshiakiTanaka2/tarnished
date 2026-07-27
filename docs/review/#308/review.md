# Code Review: #308

- **Branch**: refactor/TE-ToshiakiTanaka2/#308/rebase-workflow-skills-on-an-opus-5-class-model
- **Base**: develop (merge base: 4dae334)
- **Review scope**: Large (59 files changed, 2098 insertions(+), 787 deletions(-))
- **Reviewed at**: 2026-07-27T04:10:20Z
- **Reviewer**: Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra)

The `templates/` side of every mirror pair was excluded from the reviewed diff;
`scripts/verify-mirrors.sh` passes, so it is byte-identical to the reviewed
workspace trees.

---

### Critical (must fix)

- [setup.sh:1890](/workspace/setup.sh:1890) and [setup.sh:1904](/workspace/setup.sh:1904) read user-controlled JSON values and interpolate them directly into the `sed` program at [common.sh:752](/workspace/scripts/lib/common.sh:752). A value containing a newline and GNU `sed`’s `e` command executes arbitrary shell commands during `--upgrade`; `&` and `|` also corrupt or abort replacement. I reproduced command execution with a harmless payload. Validate project names and profile enums, escape all replacement metacharacters, and fail closed on invalid recovery data.

- [setup.sh:1978](/workspace/setup.sh:1978) calls the final staging walk “authoritative” but never clears recorder-only entries. Service plugins record their temporary overlays and then delete them, e.g. [postgresql/plugin.sh:46](/workspace/templates/services/postgresql/plugin.sh:46) and [postgresql/plugin.sh:173](/workspace/templates/services/postgresql/plugin.sh:173). The stale hash reaches `NEW_HASHES`, and [manifest.sh:416](/workspace/scripts/lib/manifest.sh:416) attempts to copy a nonexistent file. I reproduced a same-version PostgreSQL upgrade aborting after entering the apply phase, leaving the target potentially partially updated and the old manifest intact. Rebuild `MANIFEST_TRACKED` solely from a successful final walk and add service-enabled regression coverage.

### Major (must fix before PR)

- [setup.sh:1901](/workspace/setup.sh:1901) ignores the manifest-derived `AI_PROFILE` and `CODEX_ENABLED` already loaded at [setup.sh:2423](/workspace/setup.sh:2423). Instead, malformed metadata becomes `claude-main`, and Codex enablement is inferred from whether the user-owned `.codex/config.toml` currently exists. This violates the manifest source-of-truth invariant at [setup.sh:2172](/workspace/setup.sh:2172) and can silently change a Codex reviewer to “Manual review” after an intentionally deleted config. Render from validated manifest state, using target files only as a compatibility fallback.

- [.claude/skills/flow/SKILL.md:47](/workspace/.claude/skills/flow/SKILL.md:47) finds an issue branch but checks commits “reachable from HEAD” and review artifacts in the current worktree. Invoking `/flow` from `develop` therefore misclassifies completed work on another issue branch. Additionally, any commit after the design commit is treated as implementation. Resolve and fetch the exact issue branch, then query that ref/tree and use stronger implementation evidence.

- [.claude/skills/flow/SKILL.md:74](/workspace/.claude/skills/flow/SKILL.md:74) assumes a design commit proves approval, but [design/SKILL.md:128](/workspace/.claude/skills/design/SKILL.md:128) commits before its sign-off gate. Likewise, flow treats review-artifact existence as completion although [review/SKILL.md:90](/workspace/.claude/skills/review/SKILL.md:90) writes it before fixes and final disposition. An interrupted run can therefore resume past both gates. Re-present design approval on resumed runs and require completed review disposition—not mere file existence—before PR.

- [.claude/skills/flow/SKILL.md:28](/workspace/.claude/skills/flow/SKILL.md:28) advertises `--from issue`, but line 37 requires an issue number before running the no-argument issue stage. The Codex projection also omits `$issue` from its orchestration list at [.agents/skills/flow/SKILL.md:19](/workspace/.agents/skills/flow/SKILL.md:19). Special-case the issue stage, capture the newly created number, and then continue.

- [.claude/skills/flow/SKILL.md:51](/workspace/.claude/skills/flow/SKILL.md:51) uses `gh pr list --head`, whose default only returns open PRs, and treats any returned PR as “nothing to do.” Consequently, `--merge` cannot resume an open PR, while merged or closed PRs are missed and flow attempts PR creation again. Query all states and handle open, merged, and closed PRs separately.

- [.claude/skills/review/SKILL.md:97](/workspace/.claude/skills/review/SKILL.md:97) and [.claude/skills/flow/SKILL.md:80](/workspace/.claude/skills/flow/SKILL.md:80) permit leaving a Critical finding unfixed with advice and rationale, contradicting the non-deferrable policy at [review/SKILL.md:106](/workspace/.claude/skills/review/SKILL.md:106). Restrict deferral/advisor consultation to Major findings; Critical findings must block PR creation.

- [.claude/skills/review/SKILL.md:64](/workspace/.claude/skills/review/SKILL.md:64) resolves role-specific model and reasoning-effort overrides, but the actual commands at [review/SKILL.md:74](/workspace/.claude/skills/review/SKILL.md:74) and [review/SKILL.md:80](/workspace/.claude/skills/review/SKILL.md:80) pass neither. The artifact can therefore attribute a review to settings that were not used. Apply the effective overrides to the reviewer invocation and record the actual invocation values.

- [.claude/skills/pr/SKILL.md:83](/workspace/.claude/skills/pr/SKILL.md:83) watches one GitHub Actions run and explicitly removes the aggregate re-check. A repository can have multiple workflow runs/check suites, so auto-merge may proceed while another check is pending or failing. Use timeout-bounded `gh pr checks <pr> --watch`, or require an aggregate check immediately before merge.

- [.claude/skills/design/SKILL.md:36](/workspace/.claude/skills/design/SKILL.md:36) places `Skill(erd:...)` before `.claude/commands.local/erd/...`. When the Skill route exists, the documented local overlay is never read. Put the local overlay first, or ensure the Skill mechanism explicitly loads the overlaid content. The same ordering appears in issue, implement, and PR.

- [templates/claude/CLAUDE.md:101](/workspace/templates/claude/CLAUDE.md:101) documents always-latest sidecars for commands, skills, and scripts but omits `.claude/agents` and `.claude/agents.local`. Because agent refresh uses deletion semantics, downstream users can lose hand-authored agents by following this guidance. Add the managed agent tree and its required sidecar.

### Minor (fix when cheap)

- [tests/setup_upgrade.bats:395](/workspace/tests/setup_upgrade.bats:395) claims the second upgrade is a NOOP, but only asserts it was not classified `SKIP_EDITED`; repeated `UPDATE` still passes. Assert exact disposition and unchanged target/manifest hashes. Add cases for services, every profile/Codex combination, malformed metadata, JSONC, and hostile replacement characters.

- [README.md:56](/workspace/README.md:56) still omits `$flow` from the invocation list, while [data-model.md:228](/workspace/docs/design/shared/data-model.md:228) retains the five-skill inventory. This violates the design’s enumeration-completeness criterion.

### Positive

- `UPGRADE_TARGET_DIR` is assigned before every production staging-helper path.
- Base-branch threading and the `#<issue>/` delimiter fix are clear improvements.
- Mirror identity passed for all 21 checked families.
- `setup_upgrade.bats` passed 24/24; manifest/plugin tests, shell syntax, diff checks, Rust formatting, Clippy, and all 124 Rust tests also passed.

Final verdict: **REQUEST_CHANGES**.

---

## Fixes Applied

All 2 Critical, all 11 Major, and both Minor findings were fixed. Nothing was
deferred.

### Critical

- **sed injection via placeholder values** — Added `sed_escape_replacement()` in
  `scripts/lib/common.sh` (escapes `\`, `|`, `&` in that order) and applied it to
  all four replacements; `replace_placeholders` now rejects any value containing a
  newline and fails closed. `stage_render_placeholders` additionally validates the
  recovered project name against `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` and skips
  rendering rather than proceeding when nothing usable can be recovered. Verified
  by reproducing the arbitrary file write (`w` flag) before the fix and confirming
  the payload lands as literal text after it.
- **staging walk was not actually authoritative** — `stage_plugin_run` and
  `stage_plugin_run_for_module` now reset `MANIFEST_TRACKED` before the final walk,
  so recorder entries for files a later `plugin_post_copy` deleted (the service
  plugins' docker-compose overlays) can no longer reach `NEW_HASHES` and abort
  `manifest_apply` mid-apply. The misleading "authoritative, not a fill-in" comment
  was replaced with one that states the three cases the walk actually covers.

### Major

- `stage_render_placeholders` now takes the AI profile from the manifest-derived
  globals that `apply_decisions_for_scope` already configured, falling back to the
  target's `agent-profile.json` only when the manifest predates those keys — so
  Codex enablement is no longer inferred from whether a user-owned file exists.
  Added `derive_agent_names_pair()` for a side-effect-free lookup.
- `/flow` stage detection now resolves and evaluates the **issue branch ref**
  rather than `HEAD`, so running it from `develop` no longer reports another
  issue's progress.
- Implementation evidence tightened to "a commit touching something outside
  `docs/design/`"; review completion tightened to "artifact carrying its Phase 5
  Fixes Applied section", since `/review` writes the artifact in Phase 4.
- The design approval gate now runs on resumed runs too — `/design` commits in
  Phase 8 and only then reaches sign-off, so a design commit is not evidence of
  approval.
- `--from issue` is special-cased: `/issue` runs with no arguments and its returned
  number feeds every later stage.
- Pull requests are queried with `--state all`, and open / merged / closed-unmerged
  are handled separately so `--merge` can resume an open PR.
- Critical findings are now non-deferrable in both `/review` and `/flow`; the
  advisor consult and rationale path applies to Major only.
- `/review` passes the resolved model and reasoning effort to `codex exec` and
  `codex review` via `-c`, so the artifact header attributes the review to settings
  that were actually used.
- `/pr` waits on the aggregate `gh pr checks --watch` state instead of a single
  workflow run, and re-reads check state immediately before merging.
- The erd invocation order puts `.claude/commands.local/erd/` ahead of the Skill
  route in all four skills, so a project's overlay cannot be silently bypassed.
- `templates/claude/CLAUDE.md` now lists `.claude/agents` among the always-latest
  trees, so users are warned that hand-authored agents need an `agents.local/`
  sidecar to survive the `rsync --delete` refresh.

### Minor

- The NOOP regression test asserts zero Updated and zero Skipped(edited) counts
  plus unchanged file and manifest-map hashes, instead of only checking that
  SKIP_EDITED was absent.
- `README.md` gained `$flow`; `docs/design/shared/data-model.md` gained the flow
  skill, the delegation skill, the advisor agent, and the pinned Codex model.

### Regression coverage added

Two bats cases in `tests/setup_upgrade.bats`, both verified to fail against the
pre-fix code and pass after:

- a service-enabled `--upgrade` does not stage a deleted overlay
- a hostile `devcontainer.json` name is rejected instead of reaching `sed`

The NOOP case was also strengthened as described above.
