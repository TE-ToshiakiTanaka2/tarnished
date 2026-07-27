# API Specification: #308 Rebase workflow skills on an Opus 5-class model policy

Interface deltas only. The cumulative project-wide spec lives in `docs/design/shared/api-spec.md`.

## Endpoints / Functions (delta)

| Name | Signature | Description |
| --- | --- | --- |
| `derive_agent_names` | `derive_agent_names <ai_profile>` (shell) | Sets `AI_PRIMARY_AGENT` / `AI_REVIEW_AGENT` from an `ai_profile` value. Extracted from the inline case block at `setup.sh:1223-1240` so scaffold and upgrade share one mapping. |
| `stage_plugin_run` | `stage_plugin_run <upstream_dir> <staging_dir>` (shell) | Unchanged signature. Now renders placeholders in `<staging_dir>` after `execute_plugin_post_copies`. |
| `stage_plugin_run_for_module` | `stage_plugin_run_for_module <upstream_dir> <staging_dir> <lang> <module_name>` (shell) | Same change. |
| `_shared/branch` Issue mode | `(issue_number, base = "develop")` (skill procedure) | `base` is the branch that new branches are cut from and pulled. |
| `/flow` | `/flow [--issue N] [--base <branch>] [--from <stage>] [--merge]` | Lifecycle orchestration entrypoint. |
| `/design` | `/design <issue_number> [--base <branch>]` | `--base` threaded to `_shared/branch`. |
| `/implement` | `/implement <issue_number> [--base <branch>]` | `--base` threaded to `_shared/branch`. |
| `/pr` | `/pr [target_branch] [--merge]` | Signature unchanged; `argument-hint` corrected to match. |

## Input/Output Schemas

### `.tarnished/agent-profile.json :: roles`

#### Input

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `roles` | object | No | Role→binding map. Absent on projects scaffolded before this change. |
| `roles.<role>.agent` | string | Yes when `roles` present | `"primary"`, `"review"`, or a concrete agent identifier |
| `roles.<role>.model` | string \| null | Yes when `roles` present | `null` = the agent's configured default |
| `roles.external-reviewer.reasoning_effort` | string \| null | No | `null` = the reviewer CLI's configured default |

Recognized roles: `orchestrator`, `executor`, `advisor`, `external-reviewer`. Unknown role keys are ignored rather than treated as errors, so a project can carry forward-looking entries.

#### Output (resolution result)

| Field | Type | Description |
| --- | --- | --- |
| agent | string | Concrete agent, after resolving `"primary"` / `"review"` through the sibling `primary_agent` / `review_agent` fields |
| model | string \| null | `null` → caller uses the agent default |
| source | enum | `profile` when read from `roles`; `fallback` when `roles` was absent or unrendered |

### Review artifact metadata header

| Field | Type | Description |
| --- | --- | --- |
| Branch | string | Current branch name |
| Base | string | Target branch plus short merge-base SHA |
| Review scope | enum | `Small` / `Medium` / `Large`, with the changed-line count |
| Reviewed at | string | ISO 8601 timestamp |
| Reviewer | string | Reviewer identity **with resolved model and reasoning effort**, e.g. `Codex CLI (model: gpt-5.6-sol, reasoning effort: ultra)` |

Model and effort are read from `.codex/config.toml` keys `model` and `model_reasoning_effort` at review time. An unset or unreadable key records `default`.

### `/flow` stage-entry derivation

| Input | Type | Description |
| --- | --- | --- |
| `--from` | enum \| absent | `issue` / `design` / `implement` / `review` / `pr` |
| branch list | git | Anchored `#<n>/` match |
| commit log | git | Presence of `docs: add design documents for #<n>` and of later commits |
| review artifact | filesystem | `docs/review/#<n>/review.md` |
| pull request | gh | `gh pr list --head <branch>` |

| Output | Type | Description |
| --- | --- | --- |
| entry stage | enum | First incomplete stage, or `complete` |

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| `roles` absent | non-fatal | Resolve all roles to the primary agent; `external-reviewer` to `review_agent`. `source = fallback`. |
| `roles` contains `{{...}}` | non-fatal | Treated as absent. |
| `.tarnished/workflows/flow.md` missing | non-fatal | `/flow` proceeds on the SKILL alone. `workflows/*.md` is not refresh-managed, so this is the normal state for projects scaffolded before it shipped. |
| `.claude/agents/advisor.md` missing | non-fatal | Skip the consult. Advice never gates a stage. |
| Primary agent has no subagent mechanism | non-fatal | Advisor points are skipped, not silently unhonored. |
| `.codex/config.toml` unreadable | non-fatal | Record `model: default`, `reasoning effort: default`. |
| CI wait timeout | blocking for merge | Report CI status unknown; stop. Merging on unknown CI is forbidden. |
| `--from <stage>` prerequisites absent | blocking | Report the missing prerequisite and stop. |
| Mechanical step exhausts its retry budget | escalation | The orchestrator takes over — the failure is no longer mechanical. |
