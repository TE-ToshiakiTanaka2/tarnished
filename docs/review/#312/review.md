# Review: #312 restructure lifecycle roles around a long-context orchestrator with delegated designer and executor

- **Branch**: `feature/TE-ToshiakiTanaka2/#312/extend-the-advisor-role-to-standing-content-review`
- **Base**: `develop` (merge base: `e0b9268`)
- **Scope**: Deep review — 33 files, 1084 insertions / 222 deletions (source trees only)
- **Timestamp**: 2026-07-28T00:59:30Z
- **Reviewer**: Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra) — resolved from `.codex/config.toml`, the single source for both values
- **Ground truths supplied**: `docs/design/#312/design.md` **and** the issue's Requirements section (criteria 8 and 9)
- **Scope exclusion**: `templates/**` was excluded from the reviewed diff. Those trees are byte-identical mirrors of `.claude/**`, `.agents/**`, and `.tarnished/workflows/*.md`, enforced by `scripts/verify-mirrors.sh`, which passed on all 21 pairs. The exclusion was stated in the reviewer's prompt.
- **Delegation note**: this issue's own review ran under the *pre-change* model — the orchestrator applied the fixes inline rather than dispatching the `executor`, because the branch that defines that delegation is the branch under review. The new structure is first exercised on the next issue.

---

### Major (must fix before PR)

- [scripts/lib/common.sh:555](/workspace/scripts/lib/common.sh:555) The settings merge reconstructs only `permissions` and `hooks`, discarding the new `model` key. [templates/claude/plugin.sh:88](/workspace/templates/claude/plugin.sh:88) invokes this whenever settings already exist, including every upgrade via [setup.sh:2191](/workspace/setup.sh:2191). Consequently, rerunning or upgrading removes `claude-fable-5`. Preserve arbitrary user-owned top-level keys and add a repeated-merge regression test for `.model`.

- [.claude/skills/_shared/delegation/SKILL.md:14](/workspace/.claude/skills/_shared/delegation/SKILL.md:14) Stale-project compatibility is incomplete. Precedence covers stale `.tarnished/workflows` but not non-refreshed `.agents`; additionally, the fallback at [line 84](/workspace/.claude/skills/_shared/delegation/SKILL.md:84) handles an absent `roles` object but not an existing #308 map containing `advisor` and no `designer`. Refreshed skills can therefore have neither an unambiguous Codex instruction nor a resolved designer binding. Cover both stale altitudes and define per-role missing-key fallback.

- [.claude/skills/design/SKILL.md:34](/workspace/.claude/skills/design/SKILL.md:34) The designer supposedly owns Phases 3–7, but artifact-producing research runs at [lines 78–85](/workspace/.claude/skills/design/SKILL.md:78) before dispatch at line 89. The Codex projection similarly delegates per-issue artifacts but leaves shared-snapshot regeneration separate. Dispatch before research and explicitly delegate research plus both artifact layers.

- [.claude/skills/flow/SKILL.md:83](/workspace/.claude/skills/flow/SKILL.md:83) Any implementation commit makes a resumed run enter `review`, while the executor commits incrementally and may return partial committed work in a blocked-result. Because orchestrator review happens only afterward, interruption can permanently skip unfinished implementation and its required review. Add durable post-review completion evidence or change commit ordering.

- [.claude/skills/pr/SKILL.md:43](/workspace/.claude/skills/pr/SKILL.md:43) The executor owns both body authoring and `gh pr create`, but no return/re-dispatch boundary lets the orchestrator inspect the draft first. [docs/design/shared/sequence.md:187](/workspace/docs/design/shared/sequence.md:187) consequently shows creation and CI occurring before the content check. Define an executable `draft → return → orchestrator check → re-dispatch/create` sequence.

- [.github/workflows/claude-code-review.yml:75](/workspace/.github/workflows/claude-code-review.yml:75) FR-12 reaches only the main prompt template. CI still loads only the design and lists eight criteria; [AGENTS.md:9](/workspace/AGENTS.md:9) also omits requirement adherence, while the supported built-in path runs bare `codex review` at [.claude/skills/review/SKILL.md:88](/workspace/.claude/skills/review/SKILL.md:88). Supply the issue Requirements and criterion 9 to every review entrypoint, including small reviews.

- [.claude/skills/implement/SKILL.md:61](/workspace/.claude/skills/implement/SKILL.md:61) `/implement` still permits missing design artifacts and calls design optional at line 143, but [executor.md:8](/workspace/.claude/agents/executor.md:8) requires a committed design and the orchestrator can review only “against the design.” Either require design consistently or define issue Requirements as the no-design review ground truth.

- [.claude/skills/review/SKILL.md:103](/workspace/.claude/skills/review/SKILL.md:103) Executor-applied review fixes are marked complete immediately at Phase 5 without orchestrator validation. This violates the orchestrator’s responsibility to review every delegated artifact and can record a Critical finding as fixed when the patch is incomplete or regressive. Add inspection/re-dispatch before writing “Fixes Applied.”

- [.claude/skills/flow/SKILL.md:131](/workspace/.claude/skills/flow/SKILL.md:131) The four interactive stop points are declared exhaustive, but `/review` introduces additional prompts for authentication and fallback consent at [.claude/skills/review/SKILL.md:208](/workspace/.claude/skills/review/SKILL.md:208). Define automatic flow-mode fallback or otherwise map every stage failure into one of FR-14’s permitted stops.

- [docs/design/shared/data-model.md:341](/workspace/docs/design/shared/data-model.md:341) The cumulative schema snapshot pins the orchestrator to `claude-opus-5[1m]`, contradicting the actual Fable setting and the other design artifacts. Because future design work consumes this as project truth, it violates FR-3 and snapshot alignment.

### Minor (fix when cheap)

- [.agents/skills/flow/SKILL.md:21](/workspace/.agents/skills/flow/SKILL.md:21) Hard-coding that Codex has no subagent mechanism contradicts the capability-conditional standalone Codex skills. Detect capability instead; inline execution should be the fallback, not an agent-family rule.

- [.claude/skills/flow/SKILL.md:142](/workspace/.claude/skills/flow/SKILL.md:142) This says Critical and Major must be fixed, while line 146 permits Major deferral. State the canonical rule directly: Critical never deferrable; Major only with recorded rationale.

- [.claude/skills/design/SKILL.md:129](/workspace/.claude/skills/design/SKILL.md:129) “Two rounds” is ambiguous about whether the initial review is round one or whether two revision cycles follow it. Define the count and require re-review after each return; `/implement` has the same ambiguity.

- [.tarnished/agent-profile.json:10](/workspace/.tarnished/agent-profile.json:10) The profile retains `external-reviewer.model: null`, while [.claude/skills/review/SKILL.md:72](/workspace/.claude/skills/review/SKILL.md:72) and the shared docs claim the role carries no model key. Clarify that the null field remains but is ignored.

### Positive

- The designer and executor definitions have appropriate write tools, bounded responsibilities, and actionable blocked-result fields.
- `/design` clearly enforces write → review → commit and distinguishes the audit artifact from lifecycle evidence.
- No live operational references to `advisor`, Gate A, or Gate B remain.
- JSON validation and `git diff --check` pass. All 21 mirror pairs are byte-identical.

Final verdict: **REQUEST_CHANGES**.

---

## Fixes Applied

All 10 Major and all 4 Minor findings were verified against the code and fixed. None was deferred. No Critical findings were raised.

| # | Finding | Disposition |
| --- | --- | --- |
| Major 1 | `merge_claude_settings` rebuilt the object from `permissions` and `hooks` only, discarding `model` and every other top-level key on each re-run and `setup.sh --upgrade` | **Fixed.** Deep-merges all top-level keys, then overrides the two special-cased ones with array unions. Hook events other than PreToolUse/PostToolUse now survive too — a latent loss the finding did not name. Regression test added: `merge_claude_settings preserves unrelated top-level keys across repeated merges` |
| Major 2 | Stale-project compatibility covered `.tarnished/workflows` but not `.agents`; the `roles` fallback handled an absent map but not a #308-era map carrying `advisor` and no `designer` | **Fixed.** Precedence now names both stale altitudes; resolution is per role rather than all-or-nothing, with the #308 case stated as the reason |
| Major 3 | The designer was said to own Phases 3-7, but research — which produces `research.md` — ran before the dispatch in Phase 4 | **Fixed.** Dispatch moved to the start of Phase 3 with the reason recorded: research produces an artifact, so authorship would otherwise split across two agents |
| Major 4 | Any implementation commit sends a resumed run to `review`, but the executor commits incrementally, so an interrupted run could skip unreviewed work | **Fixed.** A resumed run entering `review` re-runs the implementation review first. Chosen over a durable completion marker, which would reintroduce the evidence bookkeeping that moving `/design`'s commit after its review removed |
| Major 5 | The executor owned both body authoring and `gh pr create`, so "the orchestrator checks first" had no executable boundary | **Fixed.** The executor drafts and returns; the orchestrator checks, then runs `gh pr create` itself. `sequence.md` and `design.md` corrected to match |
| Major 6 | Criterion 9 reached only the main prompt template; CI and `AGENTS.md` still carried eight criteria and one ground truth | **Fixed.** Both updated. The `--builtin` path, which takes no custom prompt, now states that it receives neither ground truth so its output is not read as covering criteria 8 and 9 |
| Major 7 | `/implement` treats design as optional, but the executor required a committed design and the review was defined only "against the design" | **Fixed.** The issue's Requirements are the ground truth for both when no design exists |
| Major 8 | Executor-applied review fixes were recorded complete without orchestrator validation | **Fixed.** A verification step precedes "Fixes Applied", with the same return-and-re-review loop |
| Major 9 | The four stop points were declared exhaustive while `/review` could still prompt for auth or fallback consent | **Fixed.** Under `/flow` the reviewer ladder falls through automatically and records the fallback; a stop occurs only when no reviewer resolves at all |
| Major 10 | `data-model.md` pinned the orchestrator to `claude-opus-5[1m]`, contradicting the Fable setting | **Fixed.** Corrected to `claude-fable-5` |
| Minor 1 | The Codex projection hard-coded that Codex has no subagent mechanism | **Fixed.** Capability-conditional; inline execution is the fallback, not an agent-family rule |
| Minor 2 | `/flow` triage said Critical **and** Major must be fixed, then permitted Major deferral | **Fixed.** Defers to the canonical policy in `review/SKILL.md` rather than restating it inconsistently |
| Minor 3 | "Two rounds" did not say whether the initial review counted, or require re-review after a return | **Fixed.** Defined as at most two *returns*, first review is round 0, and each return is explicitly re-reviewed. Applied to the delegation policy, `/design`, `/implement`, and `/review` |
| Minor 4 | `agent-profile.json` kept `external-reviewer.model: null` while the docs said the role carries no model key | **Fixed.** Key removed from both profile copies and from the policy's example block |

### Verification after fixes

- `scripts/verify-mirrors.sh` — all 21 mirror pairs byte-identical
- `bats tests/common_json.bats` — 7/7 pass, including the new regression test
- JSON validity re-checked for both `agent-profile.json` copies and both `settings.json` copies
