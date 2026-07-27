# Workflow: #308 Rebase workflow skills on an Opus 5-class model policy

Dependency-ordered implementation plan. Every step that touches `.claude/`, `.agents/`, `.codex/`, or `.tarnished/` writes both the workspace tree and its `templates/` mirror in the same commit; `scripts/verify-mirrors.sh` is the completion criterion for each.

## Step 0 — Prerequisite: render placeholders in the upgrade staging tree

**Depends on**: nothing. Must land before Step 5 and Step 6.

- Extract the `ai_profile` → (`primary_agent`, `review_agent`) case block (`setup.sh:1223-1240`) into a reusable `derive_agent_names` helper; call it from both the existing site and the new one.
- In `stage_plugin_run` and `stage_plugin_run_for_module`, after `execute_plugin_post_copies`, render the staging tree with values derived from the existing target: project name from the target directory basename, `ai_profile` from the target's `.tarnished/agent-profile.json`.
- Add a bats case asserting a staged upgrade run leaves no `{{...}}` token in `.tarnished/agent-profile.json` or `.tarnished/workflows/*.md`.

**Done when**: the new bats case passes and the existing `tests/setup_upgrade.bats` suite still passes.

## Step 1 — `_shared/branch`: base parameter and anchored detection (1-1, 1-3)

**Depends on**: nothing.

- Add a `base` parameter (default `develop`) to Issue mode; replace the hardcoded `git checkout develop && git pull origin develop` and the "branch from develop" preservation path.
- Replace `git branch -a | grep "#{issue_number}"` with a `#<n>/`-anchored match so `#12` stops matching `#123`.
- Replace the `## Base Branch` section ("Always use `develop`") with the parameter's documented default.

**Done when**: no unparameterized `develop` remains in the procedure, and the grep carries a delimiter anchor.

## Step 2 — Thread `--base` through the callers (1-1)

**Depends on**: Step 1.

- `/design` and `/implement` accept `--base <branch>` and pass it to `_shared/branch`.
- Update both `argument-hint` frontmatter values and the Usage blocks.

**Done when**: `--base main` reaches branch creation instead of being silently ignored.

## Step 3 — Point fixes (1-4, 1-6, 1-7)

**Depends on**: nothing.

- `/review`: renumber steps within each phase so the 3A/3B/3C branch stops producing a broken continuous sequence.
- `/issue`: unify the body template and the criteria table on P0/P1/P2; keep the High/Medium/Low → P-value mapping at the project-field boundary only.
- `/pr`: `argument-hint: "[target_branch] [--merge]"`.

**Done when**: `/review` numbering is per-phase, `/issue` carries one priority notation, `--merge` appears in argument completion.

## Step 4 — Conditionalize dead references (1-2)

**Depends on**: nothing.

- Make every `claude-code-review.yml` reference conditional: `code-reviewer.md`, `review/SKILL.md` (two sites), `pr/SKILL.md` (the Phase 4 first-pass-review branch).
- Drop the unconditional "Keep all three aligned" wording from `code-reviewer.md`.
- Reword `.tarnished/workflows/README.md` so it no longer promises downstream CI enforcement of mirror parity that exists only upstream.

**Done when**: no reference asserts the existence of an asset a scaffolded project does not have.

## Step 5 — Role vocabulary and binding (2-1)

**Depends on**: Step 0.

- Add the `roles` object to `.tarnished/agent-profile.json` and its template mirror, placeholder-free.
- Document the role vocabulary and the resolution/fallback contract in `.tarnished/workflows/README.md`.
- Remove hardcoded model names from skills; skills name roles only.

**Done when**: no skill names a model, and `roles` resolves for a project that predates the key.

## Step 6 — `_shared/delegation` routing table (2-3, 2-4)

**Depends on**: Step 5.

- New `.claude/skills/_shared/delegation/SKILL.md` in the refresh-managed channel, keyed by nature of work.
- Encode route-by-nature: retry budgets only for mechanical steps, only for command-level failure.
- Reference it from `/design`, `/implement`, `/review`, `/pr`, `/flow`.

**Done when**: the table exists in exactly one place and every consumer points at it.

## Step 7 — `advisor` agent (2-2)

**Depends on**: Step 6.

- New `.claude/agents/advisor.md`: read-only, decision-focused, `tools: Read, Grep, Glob, Bash` with the read-only constraint stated in prose (matching `code-reviewer.md`'s shape).
- Wire the three bounded invocation points with their mechanical triggers.
- State the capability gate for primary agents without a subagent mechanism.

**Done when**: each invocation point has an objective trigger and a documented skip path.

## Step 8 — Review criteria and taxonomy (4-5, 2-5)

**Depends on**: Step 3.

- Make `review/SKILL.md`'s Review Prompt Template the canonical criteria + taxonomy source; keep criteria **inline** at prompt-construction time.
- `code-reviewer.md`: drop the restatement, point at the invoking prompt then `review/SKILL.md`.
- `AGENTS.md` (and its template): keep a compressed self-sufficient list plus a pointer; adopt the four-level taxonomy.
- `.github/workflows/claude-code-review.yml`: adopt the four-level taxonomy.
- Record the resolved reviewer model and reasoning effort in the artifact header.

**Done when**: one taxonomy repository-wide, and the artifact header names the model and effort actually used.

## Step 9 — Codex reviewer model (2-5, user directive)

**Depends on**: Step 8.

- `.codex/config.toml` and its template: `model = "gpt-5.6-sol"`, `model_reasoning_effort = "ultra"`; rewrite the "always-latest" comment to match a pinned model.
- Leave `.tarnished-manifest.json` alone. The workspace manifest is a scaffold-time snapshot from v0.0.87 and its `.codex/config.toml` entry was already stale before this change (recorded `add21d6a…` vs. the hash at HEAD). The workspace is not upgraded via `--upgrade`, and refreshing one entry while the rest stay stale would misrepresent the file.

**Done when**: `codex exec --strict-config` accepts the config and the artifact header reports the pinned values.

## Step 10 — `/flow` skill (D4, 1-5, 1-8)

**Depends on**: Steps 1-9.

- `.tarnished/workflows/flow.md` — contract, placeholder-free.
- `.claude/skills/flow/SKILL.md` — five stages, derived stage state, `--base` threading, task tracking, approval gates. Stage 5 quality pass runs inline (resolving the inline-vs-delegate contradiction).
- `.agents/skills/flow/{SKILL.md,agents/openai.yaml}` — Codex projection.
- Tolerate a missing `workflows/flow.md`, since `workflows/*.md` is not refresh-managed.
- Extend `scripts/verify-mirrors.sh` with `flow` in the workflow-summaries loop.
- Update the lifecycle enumerations in `workflows/README.md`, `templates/claude/CLAUDE.md`, `templates/codex/AGENTS.md` (with its `$name` alias list), and the repository `README.md`.

**Done when**: `verify-mirrors.sh` passes with the new pairs and no enumeration still says the lifecycle has five entrypoints.

## Step 11 — Harness affordances (3-1, 3-2, 3-3)

**Depends on**: Step 10.

- Remove the Skill-tool prohibition from `issue`/`design`/`implement`/`pr`; adopt the `Skill → commands.local → commands` preference order.
- Adopt task tracking (`/flow`), structured questions (`/issue` discovery, `/flow` with no arguments), plan approval (`/design` sign-off).
- `/pr` Phase 4: wait on CI via the harness's condition-waiting affordance with an explicit timeout that owns the previously unowned "CI timeout" rule; drop the manual re-check step; forbid merging on timeout.

**Done when**: no skill forbids the canonical mechanism, and every error-handling rule has an actor that can execute it.

## Step 12 — Compression pass (4-1, 4-2, 4-3, 4-4)

**Depends on**: Step 11.

- Replace verbatim output templates with required-element lists across `implement`, `pr`, `design`, `review`, `flow`.
- Collapse `/implement`'s Phase 1-6 / step 1-14 enumeration into a pipeline plus explicit skip conditions.
- Delete the diagram quotas from `/design`.
- Reduce emphasis to genuinely irreversible rules: merge guards, the `git add -A` prohibition, snapshot overwrite.

**Done when**: no skill carries a fully worked output example with placeholder values, and no skill mandates a minimum artifact count.

## Step 13 — Verification

**Depends on**: all.

- `bash scripts/verify-mirrors.sh`
- `bats tests/*.bats`
- `cargo fmt --check`, `cargo clippy`, `cargo test`
- `codex exec --strict-config` smoke check against the pinned config

**Done when**: all green.

## Test Strategy

The lifecycle assets are prompt documents with no executable test surface; their invariant is mirror byte-identity, enforced by `verify-mirrors.sh` in CI. The only new executable behavior is Step 0, which gets a bats case. Existing bats suites guard against regression in `setup.sh`.
