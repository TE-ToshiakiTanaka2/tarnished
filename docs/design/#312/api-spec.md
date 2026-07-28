# API Specification: #312 restructure lifecycle roles around a long-context orchestrator with delegated designer and executor

## Role vocabulary (delta)

```diff
- orchestrator | executor | external-reviewer | advisor
+ orchestrator | designer | executor | external-reviewer
```

| Role | Execution | Writes? | Status |
| --- | --- | --- | --- |
| `orchestrator` | Inline (the main session) | Yes | redefined — now reviews rather than co-authors |
| `designer` | Delegated subagent | Yes | **new** |
| `executor` | Delegated subagent | Yes | gains an agent definition and a broadened scope |
| `external-reviewer` | Separate vendor CLI | No | unchanged |
| `advisor` | — | — | **removed** |

## Stage ownership (delta)

| Stage | Writes | Reviews | Change |
| --- | --- | --- | --- |
| `issue` | orchestrator | user dialogue | advisor consult removed |
| `design` | designer | orchestrator | authoring delegated; commit moved after review |
| `implement` | executor | orchestrator | authoring delegated; reverses the prior "stays with the orchestrator" position |
| `review` | external-reviewer | orchestrator triages, executor fixes | fixes now delegated; second ground truth added |
| `pr` | executor | orchestrator | split at the irreversible operation |

Routing principle: previously **by nature of work within a stage**, so a stage could be part-inline and part-delegated. Now each stage's *authoring* has a single owner and the orchestrator reviews; within a delegated stage the subagent routes its own internal work.

## Role → model binding

| Role | Channel | Value | Parity | Refresh-managed |
| --- | --- | --- | --- | --- |
| `orchestrator` | `.claude/settings.json :: model` | `claude-fable-5` | No | No (user-owned downstream) |
| `designer` | `.claude/agents/designer.md` frontmatter | `claude-opus-5[1m]` | Yes | Yes |
| `executor` | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5` | Yes | Yes |
| `external-reviewer` | `.codex/config.toml` | `gpt-5.6-sol` / `ultra` | Yes | No |

`roles.<role>.model` stays `null` in `.tarnished/agent-profile.json` for every role. Precedence for the two delegated roles remains `roles.<role>.model` → frontmatter → `inherit`; this repository cannot use the first level because `agent-profile.json` is parity-checked, but downstream projects can.

| Property | Value |
| --- | --- |
| Frontmatter `model` accepted values | `sonnet`, `opus`, `haiku`, `fable`, a full model ID, or `inherit`. Defaults to `inherit` — **verified** |
| `.claude/settings.json :: model` | Supported; read once at session start — **verified** |
| `[1m]` suffix in frontmatter | **Unverified.** Documented for `/model` and `ANTHROPIC_DEFAULT_*`; frontmatter is a separate code path. Fallback: `claude-opus-5` |

## Agent definition contracts

### `.claude/agents/designer.md` (new)

| Field | Value |
| --- | --- |
| `model` | `claude-opus-5[1m]` |
| `tools` | Read, Grep, Glob, Write, Edit, Bash |
| Scope | Author design artifacts from a settled specification, following `design/SKILL.md`'s phases |
| Must not | Re-decide scope; commit; interact with the user |
| On ambiguity | Return a structured blocked-result (see below) |

### `.claude/agents/executor.md` (new)

| Field | Value |
| --- | --- |
| `model` | `claude-sonnet-5` |
| `tools` | Read, Grep, Glob, Write, Edit, Bash |
| Scope | Implement against committed design artifacts; apply review fixes; author the PR body and monitor CI |
| Must not | Decide a judgment the design does not settle; decide a merge |
| On ambiguity | Return a structured blocked-result |

### `.claude/agents/advisor.md`

Deleted, together with every reference to the `advisor` role across the three altitudes and the template mirrors. `.claude/agents/` is refresh-managed and directory-managed, so the deletion reaches downstream projects on the next container start.

### `.claude/agents/code-reviewer.md`

Unchanged. It is the `/review` fallback when no external reviewer is installed and is unrelated to the removed advisory role.

## Blocked-result contract

Returned by `designer` or `executor` instead of proceeding on an assumption.

| Field | Required | Description |
| --- | --- | --- |
| Question | Yes | What could not be resolved, stated as a question |
| Options | Yes | The readings or approaches the subagent can see, with what each implies |
| Evidence checked | Yes | Issue, design artifacts, and code paths already consulted — this is what distinguishes a real block from an unasked question |
| Partial work | No | What was completed before the block, so it is not redone |

| Trigger | Definition |
| --- | --- |
| Requirement-level ambiguity | Two readings of an acceptance criterion producing different interfaces |
| Design/convention conflict | The design implies a pattern the codebase consistently does otherwise |
| Missing prerequisite | A required artifact does not exist |

The orchestrator resolves it, or escalates to the user when the answer is the user's to give.

## `/design` phase ownership (delta)

| Phase | Owner | Change |
| --- | --- | --- |
| Read issue, resolve branch, load `shared/*` | orchestrator | — |
| Author per-issue artifacts and regenerate the shared snapshot | **designer** | delegated |
| Review artifacts against the issue Requirements | orchestrator | **new** |
| Revise → re-review, capped at 2 rounds | designer / orchestrator | **new** |
| Write `orchestrator-review.md`, stage, commit | orchestrator | **commit moved after the review** |

The commit ordering is the load-bearing change. Previously Phase 8 committed and only then reached the sign-off step, so a design commit proved artifacts were written rather than approved — which is why the gate had to re-run on resumed runs. With the commit after the review, the design commit *is* the record that the review happened, and `/flow`'s Stage 2 evidence table needs no new row and no new artifact to key on.

`docs/design/#{issue}/orchestrator-review.md` records the findings as an audit trail, not as an evidence key.

## `/pr` split (delta)

| Work | Owner |
| --- | --- |
| PR body authoring, mechanical quality pass, `gh pr create`, CI monitoring, log collection | executor |
| Checking PR content before creation | orchestrator |
| Merge decision, including under `--merge` | orchestrator |

## `/review` prompt template (delta)

```diff
  ## Design Reference
  {Contents of docs/design/#<issue_number>/design.md, if available.
  Otherwise: "No design document available."}

+ ## Requirement Reference
+ {The issue's Requirements section, from `gh issue view <n>`.
+ Otherwise: "No issue requirements available."}

  ## Review Criteria
  …
  8. **Design Adherence** — Does the implementation match the design document?
+ 9. **Requirement Adherence** — Does the branch carry every requirement in the issue?
```

Criterion 8 compares implementation against design; criterion 9 compares the branch against the issue. Only the second catches a requirement dropped upstream of the design. Inline in the template, because the criteria are piped to `codex exec` in a read-only sandbox and embedded in CI workflow YAML.

## `/flow` (delta)

| Element | Change |
| --- | --- |
| Gate A, Gate B | **Removed** |
| Stage order | `issue → design → implement → review → triage → pr`, no gates |
| Stage 3 argument table | Gains the delegation target per stage |
| Stage 2 evidence derivation | **Unchanged** — the write→review→commit order preserves the meaning of every existing row |
| User stop points | Stated explicitly: requirement gathering, an unresolvable escalation, argument resolution, a `/pr` failure |

## Error surface (delta)

| Condition | Response |
| --- | --- |
| Subagent ambiguity | Blocked-result → orchestrator resolves or escalates |
| Blocking review finding after 2 rounds | Report, record, escalate |
| No subagent mechanism (e.g. `codex-main`) | Every stage runs inline under the primary agent; the report records that delegation was unavailable |
| `[1m]` rejected in frontmatter | Fall back to `claude-opus-5` |
| Refreshed skill vs stale contract | The skill is authoritative |
