# API Specification: #312 extend the advisor role to standing content review with fix proposals

## Skill argument surface (delta)

| Skill | Arguments before | Arguments after |
| --- | --- | --- |
| `/design` | `<issue_number> [--base <branch>]` | `<issue_number> [--base <branch>] [--unattended]` |
| `/flow` | `[--issue N] [--base <branch>] [--from <stage>] [--merge]` | unchanged — `--unattended` is not user-facing |

`--unattended` is an internal stage argument passed by `/flow` to `/design`. It is documented in `design/SKILL.md`'s usage block and in `flow/SKILL.md`'s Stage 3 argument table, so it is greppable and projects into `.agents/skills/`. It is deliberately absent from `/flow`'s own surface: the user does not choose it, the caller supplies it.

| Value | `/design` step 22 behavior |
| --- | --- |
| absent (standalone invocation) | Present the design for approval and wait — current behavior, unchanged |
| present (invoked by `/flow`) | Skip the presentation; the Phase 7.5 conformance record stands in its place; the report states that it did |

## Role → model binding (delta)

| Role | Execution | Channel | Value after this change |
| --- | --- | --- | --- |
| `orchestrator` | Inline (the session) | `.claude/settings.json :: model` | `claude-opus-5[1m]` |
| `executor` | Delegated subagent | `.claude/agents/executor.md` frontmatter | `claude-sonnet-5` |
| `advisor` | Delegated subagent | `.claude/agents/advisor.md` frontmatter | `claude-fable-5` |
| `external-reviewer` | Separate vendor CLI | `.codex/config.toml` | reviewer-owned |

Before this change every cell read "inherit the session model", because no level of the chain named a model anywhere.

### `roles` schema change

```diff
  "roles": {
    "orchestrator":      { "agent": "primary", "model": null },
    "executor":          { "agent": "primary", "model": null },
    "advisor":           { "agent": "primary", "model": null },
-   "external-reviewer": { "agent": "review",  "model": null, "reasoning_effort": null }
+   "external-reviewer": { "agent": "review" }
  }
```

Backward compatible in both directions: absent keys already fall back, and unknown keys are already ignored, so a downstream profile that still carries the two removed keys is not an error — the keys are simply no longer read.

| Property | Constraint |
| --- | --- |
| `.tarnished/agent-profile.json` | Parity-checked against its template — the workspace copy cannot carry a per-role model without failing CI. Downstream copies are rendered and manifest-tracked, so precedence 1 works there |
| `.claude/agents/` | Parity-checked **and** refresh-managed — a frontmatter pin ships to every project on the next container start |
| `.claude/settings.json` | Neither parity-checked nor manifest-tracked. The two copies may diverge; the template value is a scaffold-time default only |
| `.codex/config.toml` | Parity-checked. Sole source for the reviewer's model and reasoning effort |

## Advisor consult contract (delta)

### Classes

| Class | Position | Question | Output posture |
| --- | --- | --- | --- |
| `challenge` | Before the artifact is written | Is the intended choice right? | Strongest objection, strongest alternative, per-finding fix proposal |
| `conformance` | After the artifact is written | Does the artifact carry the requirement it was supposed to carry? | Per-mismatch finding with a verdict |

### Conformance invocation inputs

| Input | Required | Contract |
| --- | --- | --- |
| Source of truth | Yes | Quoted **verbatim**. A paraphrase is itself a reportable finding, stated in `advisor.md`'s conformance mode |
| Subject | Yes | Artifact paths, or the artifact text when it is not yet on disk |
| Round | Yes | `1` or `2`; round 2 additionally receives what was corrected after round 1 |

### Conformance verdicts

| Verdict | Meaning | Stage proceeds? | Counts as a complete record? |
| --- | --- | --- | --- |
| `conform` | No mismatch found | Yes | Yes |
| `non-blocking gap` | Mismatch found, does not defeat the requirement | Yes, recorded | Yes |
| `blocking mismatch` | The artifact does not carry a requirement | Round 1: orchestrator corrects, re-consult. Round 2: escalate | Yes, as `(escalated, unresolved)` |
| `skipped — <reason>` | NFR-2 fallback: no advisor definition, or no read-only subagent mechanism | Yes | Yes |

Every verdict is written to the record. A record produced only on success deadlocks against NFR-2 and turns every resumed run into a destructive redesign.

### Per-run invocation ceiling

| Class | Points | Max invocations |
| --- | --- | --- |
| `challenge` | `/issue` scope, `/issue` estimation, `/design` architecture, `/design` workflow plan, Major-deferral triage | 5 |
| `challenge` | `/review` diff, 2-round loop | 2 |
| `conformance` | `/issue` and `/design`, each 2-round | 4 |
| | **Total** | **11** |

## `docs/design/#{issue}/conformance.md` schema

Written by `/design` Phase 7.5, staged and committed with the design artifacts in Phase 8.

```markdown
# Conformance: #{issue_number}

**Verdict**: <one of the four verdict strings>
**Rounds**: <1 | 2>
**Checked**: <artifact paths>
**Against**: <source of truth identifier>

## Findings

<per finding: severity label, the mismatch, and what was corrected or why it stands>
```

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `**Verdict**:` line | string | Yes | Machine-greppable. The single field `/flow`'s evidence derivation reads |
| `**Rounds**:` line | integer | Yes | `2` means a correction round ran |
| `**Checked**:` line | paths | Yes | What was verified |
| `**Against**:` line | string | Yes | What it was verified against |
| `## Findings` | section | Yes | Empty is permitted only under `conform` or `skipped` |

A second `/design` run **overwrites** the record, matching the snapshot discipline `/design` already applies to `docs/design/shared/*`.

## `/flow` Stage 2 evidence derivation (delta)

| # | Evidence, on the issue branch ref | Entry stage | Status |
| --- | --- | --- | --- |
| … | Branch exists, no design commit | `design` | unchanged |
| **new** | Design commit present, **no `docs/design/#<n>/conformance.md`** | Run the conformance consult against the already-committed artifacts, commit the record, then continue at `implement` | **added, ordered above the row below** |
| … | Design commit present, conformance record present, no later commit outside `docs/design/` | `implement` | precondition added |
| … | Implementation commits, no complete review artifact | `review` | unchanged |

`--from <stage>` bypasses the conformance precondition, warning rather than stopping. Without the carve-out, `--from implement` on a branch designed before this change fails closed against an explicit user instruction.

## `/review` prompt template (delta)

Two additions, both inline in the template because the criteria are piped to `codex exec` inside a read-only sandbox and embedded in CI workflow YAML:

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

Criterion 8 compares implementation against design; criterion 9 compares the branch against the issue. Only the second can catch a requirement dropped upstream of the design.

## Error surface (delta)

| Condition | Response | Where |
| --- | --- | --- |
| Advisor unavailable | Record `skipped — <reason>`, continue | `/issue`, `/design` |
| Blocking mismatch after round 2 | Record `(escalated, unresolved)`, escalate to user | `/flow` |
| Conformance record missing on resume | Verification-only re-entry; never `/design` | `/flow` Stage 2 |
| `--from` prerequisite is only the conformance record | Warn, proceed | `/flow` Stage 2 |
| Refreshed skill disagrees with stale `.tarnished/workflows/*.md` | The skill is authoritative | every affected skill |
