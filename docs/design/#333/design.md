# Design: #333 chore: rebind lifecycle roles to Fable 5.2 (high) / Opus 5.5 (designer high, executor medium)

## Context

The lifecycle names four **roles** — `orchestrator`, `designer`, `executor`, `external-reviewer` — and never names models inside skills (`../shared/architecture.md` :: "Role-based delegation policy", "Explicit model binding"). Each role's model is declared in exactly one **channel**, recorded once in the Model binding table of `.claude/skills/_shared/delegation/SKILL.md` and mirrored into the shared snapshot (`../shared/data-model.md` :: "Model binding by role", `../shared/api-spec.md` :: "Role → model binding").

State before this issue:

| Role | Channel | Model | Effort |
| --- | --- | --- | --- |
| `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5-1` | unset (Claude Code default) |
| `designer` | `.claude/agents/designer.md` frontmatter | `claude-opus-5-5[1m]` | unset (inherits session) |
| `executor` | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5-5` | unset (inherits session) |
| `external-reviewer` | `.codex/config.toml` | `gpt-6-astra` | `high` (`model_reasoning_effort`) |

`code-reviewer.md` (the `/review` fallback) carries no pin and inherits the session. `.tarnished/agent-profile.json :: roles.<role>.model` is `null` for the three primary roles; `external-reviewer` has no model key. The Claude dispatch precedence for designer/executor is `roles.<role>.model` (non-null) → frontmatter `model:` → session inheritance.

How each channel reaches a project:

| Channel | Mirror check | Manifest (`--upgrade`) | Refresh (container start) |
| --- | --- | --- | --- |
| `.claude/agents/*.md`, `.claude/skills/**` | `scripts/verify-mirrors.sh` (byte-identical to `templates/claude/.claude/…`) | Excluded (`MANIFEST_EXCLUDE_GLOBS`) | Refresh-managed directories |
| `.claude/settings.json` | Not checked | Excluded (`MANIFEST_EXCLUDE_GLOBS`) | Whole-file catalog target since #319 (`refresh.json` maps `templates/claude/.claude/settings.json` → `.claude/settings.json`; differing live bytes are backed up under `.tarnished/backups/<run>/` before replacement) |
| `.tarnished/agent-profile.json` | Byte-identical to template | Excluded | Not managed (project-owned) |

At scaffold time `templates/claude/plugin.sh::plugin_post_copy` copies the template settings file when the target has none and otherwise calls `scripts/lib/common.sh::merge_claude_settings <target> <template> <tmp>`; every language plugin and the codex plugin call the same function with their own settings fragment as the overlay. The function computes `$base * $overlay` (deep merge of every top-level key, overlay wins on conflict) and then rebuilds only `permissions` and `hooks` as array unions.

External facts this design relies on (verified by the orchestrator before dispatch; not re-researched):

- Claude Fable 5.2 was released 2026-11-09, API ID `claude-fable-5-2`; Claude Code 2.1.322 lists it. `claude-fable-5-1` and `claude-fable-5` are legacy.
- Subagent frontmatter accepts `model:` (alias, full ID, or `inherit`) and `effort:` ∈ `low|medium|high|xhigh|max`. Frontmatter `effort` overrides the session effort but not the `CLAUDE_CODE_EFFORT_LEVEL` environment variable (code.claude.com/docs/en/sub-agents.md). The `[1m]` suffix is not documented for frontmatter, but it is the existing working designer pin from #312.
- `settings.json` accepts top-level `model` and `effortLevel` ∈ `low|medium|high|xhigh` (`max` is not accepted for this key). `/effort` writes a per-model `modelSettings.<model-id>.effortLevel` (Claude Code ≥ 2.1.251), which takes precedence over the top-level `effortLevel` (code.claude.com/docs/en/settings-reference.md, model-config.md).

## Architecture Overview (delta)

Reasoning effort becomes a second pinned attribute of each Claude-dispatched role. It is declared **in the same file as the role's model**, so the "one channel per role" rule holds without a new file: the orchestrator's channel `.claude/settings.json` gains the top-level `effortLevel`, and each delegated agent's frontmatter gains `effort:`. The orchestrator moves to `claude-fable-5-2` at `high`, the designer keeps `claude-opus-5-5[1m]` and gains `high`, and the executor moves from Sonnet to `claude-opus-5-5` at `medium`. `external-reviewer` is untouched.

No module, function or control flow changes. `merge_claude_settings` already carries every top-level key, so the only code-adjacent change is a regression test that locks `effortLevel` survival in place (FR-6). The Model binding table grows from one value column to model and effort columns, each naming its channel, and the shared snapshot is regenerated to match.

## Module Structure (delta)

```
.claude/settings.json                                    # model → claude-fable-5-2; + effortLevel: "high"
templates/claude/.claude/settings.json                   # same two values; stays byte-identical to the workspace copy
.claude/agents/designer.md                               # + effort: high (model unchanged)
templates/claude/.claude/agents/designer.md              # mirror
.claude/agents/executor.md                               # model → claude-opus-5-5; + effort: medium
templates/claude/.claude/agents/executor.md              # mirror
.claude/skills/_shared/delegation/SKILL.md               # Model binding table: model + effort columns, channel per value
templates/claude/.claude/skills/_shared/delegation/SKILL.md   # mirror
tests/common_json.bats                                   # + effortLevel round-trip test
docs/design/shared/data-model.md                         # snapshot: role table + precedence prose (this design commit)
docs/design/shared/api-spec.md                           # snapshot: Role → model binding table (this design commit)
```

Deliberately unchanged (FR-7, NFR-3): `.claude/agents/code-reviewer.md` and its mirror, `.tarnished/agent-profile.json` and its mirror, `.codex/config.toml` and its mirror, `.agents/**`, `.tarnished/workflows/**`, `scripts/lib/common.sh`, every other `templates/*/.claude/settings.json` fragment (none carries `model` or `effortLevel` today, and none may — NFR-2).

## Interface Design (delta)

### Configuration keys

Full schema in [api-spec.md](./api-spec.md).

| Key | File | Accepted values | Shipped value |
| --- | --- | --- | --- |
| `model` (top-level) | `.claude/settings.json` | Claude model ID or alias | `claude-fable-5-2` |
| `effortLevel` (top-level, **new**) | `.claude/settings.json` | `low` \| `medium` \| `high` \| `xhigh` | `high` |
| `model:` | `.claude/agents/designer.md` frontmatter | alias, full ID, `inherit` | `claude-opus-5-5[1m]` (unchanged) |
| `effort:` (**new**) | `.claude/agents/designer.md` frontmatter | `low` \| `medium` \| `high` \| `xhigh` \| `max` | `high` |
| `model:` | `.claude/agents/executor.md` frontmatter | alias, full ID, `inherit` | `claude-opus-5-5` |
| `effort:` (**new**) | `.claude/agents/executor.md` frontmatter | `low` \| `medium` \| `high` \| `xhigh` \| `max` | `medium` |

### Exact edits

**`.claude/settings.json` and `templates/claude/.claude/settings.json`** (identical edit; `effortLevel` is placed directly after `model` so `jq -r '.model, .effortLevel'` reads naturally and the diff stays two lines):

```diff
 {
-  "model": "claude-fable-5-1",
+  "model": "claude-fable-5-2",
+  "effortLevel": "high",
   "permissions": {
```

No other key, whitespace or ordering changes (NFR-3). The two files are byte-identical before the edit and must be byte-identical after it (see Implementation Notes, "Workspace settings must equal the template").

**`.claude/agents/designer.md` and its template mirror:**

```diff
 tools: Read, Grep, Glob, Write, Edit, Bash
 model: claude-opus-5-5[1m]
+effort: high
 ---
```

**`.claude/agents/executor.md` and its template mirror:**

```diff
 tools: Read, Grep, Glob, Write, Edit, Bash
-model: claude-sonnet-5-5
+model: claude-opus-5-5
+effort: medium
 ---
```

Agent bodies are unchanged.

**`.claude/skills/_shared/delegation/SKILL.md` and its template mirror — `## Model binding` section.** Four edits; everything else in the section (the `dual`-mode paragraph, the model precedence table, the Role Binding section) is unchanged.

1. First sentence of the opening paragraph:

   ```diff
   -Each role's model comes from its dispatch channel. The table below describes Claude-primary dispatch.
   +Each role's model and reasoning effort come from its dispatch channel. The table below describes Claude-primary dispatch.
   ```

   and, in the same paragraph:

   ```diff
   -Claude agent frontmatter pins are not Codex model IDs.
   +Claude agent frontmatter pins — model and effort alike — apply to Claude dispatch only and are not Codex settings.
   ```

2. The binding table:

   ```markdown
   | Role | Model channel | Model | Effort channel | Effort |
   | --- | --- | --- | --- | --- |
   | `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5-2` | `.claude/settings.json :: effortLevel` | `high` |
   | `designer` | `.claude/agents/designer.md` frontmatter `model:` | `claude-opus-5-5[1m]` | `.claude/agents/designer.md` frontmatter `effort:` | `high` |
   | `executor` | `.claude/agents/executor.md` frontmatter `model:` | `claude-opus-5-5` | `.claude/agents/executor.md` frontmatter `effort:` | `medium` |
   | `external-reviewer` | `.codex/config.toml :: model` | reviewer-owned | `.codex/config.toml :: model_reasoning_effort` | reviewer-owned |
   ```

3. The orchestrator paragraph that follows the table:

   ```diff
   -The orchestrator is the session rather than a subagent, so no frontmatter channel reaches it; `.claude/settings.json :: model` is its only channel and is read once at session start.
   +The orchestrator is the session rather than a subagent, so no frontmatter channel reaches it; `.claude/settings.json` is its only channel — `model`, read once at session start, and the top-level `effortLevel` (`low`, `medium`, `high` or `xhigh`; `max` is not accepted there). A per-model `modelSettings.<model-id>.effortLevel` entry, which `/effort` writes, takes precedence over the top-level key, so a developer's own `/effort` choice wins over the shipped default.
   ```

4. A new paragraph directly after the model precedence table (before the `roles.<role>.model ships as null` paragraph):

   ```markdown
   Reasoning effort has no profile level — `.tarnished/agent-profile.json` carries no effort field. Frontmatter `effort:` (`low`, `medium`, `high`, `xhigh` or `max`) overrides the session effort, and `CLAUDE_CODE_EFFORT_LEVEL`, when set, overrides frontmatter. An agent without `effort:` — `code-reviewer`, for one — inherits the session effort.
   ```

### Test (FR-6)

A new `@test "merge_claude_settings preserves effortLevel across repeated merges"` in `tests/common_json.bats`, placed directly after the existing `merge_claude_settings preserves unrelated top-level keys across repeated merges` test. Exact shape in [workflow.md](./workflow.md) Step 4.

## Data Flow

Effort and model are resolved independently per role at dispatch. The shipped pins are the *defaults* in each chain; nothing here adds a new level.

**`orchestrator`** (the session itself, resolved when the session starts):

- Model: `.claude/settings.json :: model` under the normal settings-scope order (native local `.claude/settings.local.json` outranks the shared project file, which outranks user settings) → `claude-fable-5-2`.
- Effort: `CLAUDE_CODE_EFFORT_LEVEL` (environment) → `modelSettings.<active-model-id>.effortLevel` (what `/effort` writes) → top-level `effortLevel` (same scope order) → `high`. The per-model entry is keyed on the model ID, so an entry written by `/effort` while the session ran `claude-fable-5-1` no longer matches once the session runs `claude-fable-5-2`; the shipped `high` then applies until the developer runs `/effort` again.

**`designer` / `executor`** (Claude-dispatched subagents, resolved per dispatch):

- Model: `roles.<role>.model` when non-null → frontmatter `model:` → session model. Shipped: `claude-opus-5-5[1m]` / `claude-opus-5-5`.
- Effort: `CLAUDE_CODE_EFFORT_LEVEL` → frontmatter `effort:` → session effort. Shipped: `high` / `medium`. The session's `effortLevel: high` does not reach either agent, because both now pin their own.

**`code-reviewer`** (no pins, FR-7): session model and session effort, i.e. `claude-fable-5-2` at `high` by default. Before this issue it inherited `claude-fable-5-1` at the Claude Code default effort; the change in its effective effort is a consequence of the orchestrator pin, not a new pin on the agent.

**Codex-native dispatch**: frontmatter `model:` and `effort:` are Claude-only; Codex-native designer/executor inherit the active Codex session (`gpt-6-astra` / `high`) unless a supported Codex override is set. Unchanged.

**Downstream propagation.** The two channels reach generated projects by the same route:

| Channel | New project | Existing project |
| --- | --- | --- |
| `.claude/agents/*.md`, `.claude/skills/_shared/delegation/SKILL.md` | Copied at scaffold | Refresh on next container start (`postStartCommand`); an `.claude/agents.local/` overlay still wins |
| `.claude/settings.json` | Copied at scaffold, or merged (`merge_claude_settings`, template as overlay) | Whole-file refresh on next container start for projects whose `refresh.json` uses the default catalog (`use_default_managed_paths: true`) or lists the mapping; differing live bytes are backed up first. Root-inclusive `--upgrade` does the same. Projects with a custom catalog that omits the mapping pick it up only on regeneration |

The issue's Risk Factors say `settings.json` changes reach downstream "only on regeneration or `--upgrade`". That predates #319: `.claude/settings.json` is a refresh catalog target in `templates/agent-workflows/.tarnished/refresh.json` and in the workspace mirror. The requirements are unaffected; only the propagation statement is corrected here and in the shared snapshot.

## Error Handling

No new error paths in this repository's code. The failure modes are Claude Code's handling of the configured values, and the shipped values avoid all of them:

| Condition | Behavior | Mitigation in this design |
| --- | --- | --- |
| `effortLevel: "max"` in `settings.json` | Not an accepted value for this key; Claude Code reports the setting as invalid and does not apply it, so the session runs at its default effort | Ship `high`; the delegation table and the snapshot record the accepted set so a future edit does not pick `max` there |
| Unrecognised frontmatter `effort:` value | Not applied; the agent falls back to the session effort | Ship `high` / `medium`, both in the documented set |
| Model ID the runtime does not recognise | Session or dispatch fails to use the model | `claude-fable-5-2` and `claude-opus-5-5` are listed by Claude Code 2.1.322; `claude-opus-5-5[1m]` is the existing working pin |
| `CLAUDE_CODE_EFFORT_LEVEL` set in the environment | Overrides both shipped effort channels | Intended: it is the operator's override, documented in the delegation table's follow-up paragraph |
| Developer had customised `.claude/settings.json` (e.g. their own `effortLevel`) | Next refresh replaces the file and reports the verified backup path | Existing #319 behaviour; durable per-developer choices belong in `.claude/settings.local.json` or `/effort` |
| `effortLevel` dropped by a future `merge_claude_settings` rewrite | Generated projects would lose the orchestrator effort on add-module / `--upgrade` | FR-6 regression test, verified to fail against a mutated merge (workflow Step 5) |

Cross-link: `../shared/api-spec.md` :: "Error Responses" is unchanged; this issue adds no shell error path.

## Implementation Notes

- **Top-level `effortLevel` rather than `modelSettings.<id>.effortLevel`.** The per-model form would repeat the orchestrator's model ID as a JSON key in the same file, a second spelling of the model pin that must be bumped in lockstep; a missed bump silently disables the effort pin because the key stops matching the active model. It would also occupy the namespace `/effort` writes into, so the shipped default and a developer's choice would collide on one key instead of layering. The top-level key is the documented session default, applies to whatever model the session runs, and leaves the per-model layer to the developer — which is exactly the precedence the issue relies on.
- **`[1m]` is kept.** The issue settles it, and it is the pin #312 chose and the designer has run on since. It is still undocumented for frontmatter; the design records the risk rather than changing a working value. Its role is unchanged: the designer reads the whole shared snapshot (≈2.9k lines across five files) plus the per-issue inputs in one fresh context.
- **Executor to Opus 5.5 at `medium`.** The issue settles the values; the reasoning recorded here is the design's reading of them. The executor implements, applies review fixes and runs CI loops — many tool-heavy turns against an already-decided design — so it gets the stronger model while effort stays at `medium` to bound per-turn latency and cost. The designer makes the judgment-heavy calls within a stage and gets `high`, matching the orchestrator.
- **Effort is not added to the profile.** `.tarnished/agent-profile.json` stays untouched (FR-7); there is no `roles.<role>.effort`. A downstream `roles.executor.model` override changes the executor's model but keeps the frontmatter `effort: medium`. Adding a profile-level effort would be a scope change and is not proposed.
- **Workspace settings must equal the template.** The workspace's own `.tarnished/refresh.json` maps `templates/claude/.claude/settings.json` → `.claude/settings.json` from upstream `develop`, so any byte difference between the two copies is reverted (with a backup) on the next workspace container start after merge. The two files are identical today; the executor keeps them identical (`cmp`), even though `verify-mirrors.sh` does not check this pair. This also corrects the snapshot sentence that said the two copies "may diverge and `--upgrade` does not revisit" the default.
- **Mid-branch container restarts.** For the same reason, a container restart on this branch before merge refreshes `.claude/settings.json`, `.claude/agents/**` and `.claude/skills/**` back to `develop`'s bytes and leaves backups under `.tarnished/backups/`. This is existing behaviour for every asset edit, not introduced here; if it happens, restore the branch versions with `git checkout -- <path>`.
- **FR-5 grep scope.** `.tarnished/backups/` is gitignored, retained by design and never auto-deleted, and current backups already contain the old IDs. The literal FR-5 command therefore cannot return nothing on a workspace that has refreshed before. The verification runs the same pattern over tracked files (`git grep`) for the same paths, which is the requirement's evident intent; backups are not edited (they are restoration material).
- **NFR-2 check.** After the change, `effortLevel` and frontmatter `effort:` appear only in the three channel files (plus mirrors), the delegation table, the shared snapshot, and the bats fixture. The fixture uses `xhigh`, deliberately not a shipped value, so it cannot be mistaken for a second declaration site and does not need editing on the next re-pin.
- **No `merge_claude_settings_hooks` test.** Its `$base * {hooks}` shape preserves every base key, and FR-6 names only `merge_claude_settings`; the existing plugin-key test for `merge_claude_settings_hooks` already guards the same property.
