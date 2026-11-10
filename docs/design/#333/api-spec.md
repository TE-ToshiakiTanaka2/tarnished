# API Specification: #333 chore: rebind lifecycle roles to Fable 5.2 (high) / Opus 5.5 (designer high, executor medium)

This issue changes no function signature. Its interface is configuration: the keys each role's model and reasoning effort are read from. External key semantics are those verified by the orchestrator (see [design.md](./design.md) :: Context).

## Endpoints / Functions (delta)

| Name | Method/Signature | Description |
| --- | --- | --- |
| `merge_claude_settings` | `merge_claude_settings <base_file> <overlay_file> <output_file>` | **Unchanged.** Newly guarded by a test: top-level `effortLevel` survives repeated merges, whether supplied by the overlay or present only in the base |

## Input/Output Schemas

### Input — `.claude/settings.json` (orchestrator channel)

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `model` | string | No | Session model, read once at session start. Shipped: `"claude-fable-5-2"` (was `"claude-fable-5-1"`) |
| `effortLevel` | string enum `low` \| `medium` \| `high` \| `xhigh` | No | **New.** Session default reasoning effort. `max` is not accepted for this key. Shipped: `"high"` |
| `modelSettings.<model-id>.effortLevel` | string enum | No | Not shipped. Written by `/effort`; takes precedence over top-level `effortLevel` for that model |

Both values are shipped identically in `.claude/settings.json` and `templates/claude/.claude/settings.json`. No other key changes.

### Input — `.claude/agents/<name>.md` frontmatter (designer / executor channel)

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `model` | string | No | Alias, full ID, or `inherit`. `designer`: `claude-opus-5-5[1m]` (unchanged). `executor`: `claude-opus-5-5` (was `claude-sonnet-5-5`) |
| `effort` | string enum `low` \| `medium` \| `high` \| `xhigh` \| `max` | No | **New.** Overrides the session effort for the subagent; overridden by `CLAUDE_CODE_EFFORT_LEVEL`. `designer`: `high`. `executor`: `medium` |

`code-reviewer.md` carries neither key (inherits the session). `.tarnished/agent-profile.json` gains no effort field.

### Output — resolved per role

| Role | Model precedence | Effort precedence | Shipped resolution |
| --- | --- | --- | --- |
| `orchestrator` | settings `model` (local → project → user scope) | `CLAUDE_CODE_EFFORT_LEVEL` → `modelSettings.<active-id>.effortLevel` → top-level `effortLevel` | `claude-fable-5-2` / `high` |
| `designer` | `roles.designer.model` (non-null) → frontmatter → session | `CLAUDE_CODE_EFFORT_LEVEL` → frontmatter `effort` → session | `claude-opus-5-5[1m]` / `high` |
| `executor` | `roles.executor.model` (non-null) → frontmatter → session | `CLAUDE_CODE_EFFORT_LEVEL` → frontmatter `effort` → session | `claude-opus-5-5` / `medium` |
| `external-reviewer` | `.codex/config.toml :: model` | `.codex/config.toml :: model_reasoning_effort` | unchanged (`gpt-6-astra` / `high`) |

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| `effortLevel` outside `low\|medium\|high\|xhigh` (e.g. `max`) | Claude Code settings validation | Value not applied; session uses its default effort. Not reachable with the shipped `high` |
| Frontmatter `effort` outside the accepted set | Claude Code agent load | Value not applied; agent inherits the session effort. Not reachable with the shipped values |
| `effortLevel` lost on re-merge | Test failure in `tests/common_json.bats` | Regression guard for FR-6; no runtime error path |
