# Design: #257 Separate shared and issue-specific design artifacts

## Architecture Overview

Split the output surface of `/design` (and the input surface of `/implement`) into two layers:

1. **Shared layer** (`docs/design/shared/`) — Cumulative project-wide truth. Re-generated as a snapshot on every `/design` invocation.
2. **Issue layer** (`docs/design/#{issue_number}/`) — Self-contained per-issue delta and artifacts. Frozen after the issue is closed.

`/design` reads the shared layer at the start (to ground the new design in current truth) and writes both layers at the end. `/implement` reads both layers as input. A one-time migration bootstraps the shared layer from the existing per-issue artifacts.

This change is a documentation/skill refactor. There is no code logic to author — the contract is enforced by the prose of `SKILL.md` and the templates that downstream projects inherit.

## Module Structure

```
.claude/skills/
├── design/
│   └── SKILL.md                    # Modified: Phase 0 (load shared) + Phase 6 (snapshot shared)
├── implement/
│   └── SKILL.md                    # Modified: load shared/* in addition to #{issue}/*
└── _shared/
    └── design-migration/           # NEW: One-shot bootstrap procedure
        └── SKILL.md                # Reads existing #{issue}/* and seeds shared/*

templates/claude/.claude/skills/    # Mirrors all of the above, byte-for-byte
├── design/SKILL.md                 # Modified (also reconciles #248 drift)
├── implement/SKILL.md              # Modified (also reconciles #248 drift)
└── _shared/design-migration/
    └── SKILL.md                    # NEW

docs/design/
├── shared/                         # NEW: cumulative project truth (snapshot)
│   ├── architecture.md             # FR-1: A. Overall structure
│   ├── data-model.md               # FR-1: B. Domain entities, types, schemas
│   ├── api-spec.md                 # FR-1: C. Public API/interfaces
│   ├── class.md                    # FR-1: cumulative class diagram
│   ├── sequence.md                 # FR-1: cumulative sequence/state diagram (D)
│   └── research/
│       └── <library-name>.md       # FR-1: cross-cutting external research
└── #{issue_number}/                # Existing: per-issue (preserved as-is by FR-5)
    ├── design.md                   # Self-contained delta (option b)
    ├── workflow.md                 # Issue-specific implementation steps
    ├── flowchart.md                # Issue-specific control flow
    └── research.md                 # Issue-specific external research
```

### Why a separate `_shared/design-migration/` skill?

The migration is a one-shot bootstrap: read every existing `docs/design/#{issue}/` and synthesize `docs/design/shared/*`. Embedding this inside `design/SKILL.md` would inflate that skill with logic only used once. Putting it in `_shared/design-migration/SKILL.md` keeps `design/SKILL.md` lean and makes the migration auditable and re-runnable if needed (idempotent regeneration).

`design/SKILL.md` references the migration skill in a "first-run check" instruction: if `docs/design/shared/` does not exist but `docs/design/#{...}/` directories do, invoke the migration before proceeding.

## Interface Design

The "API" of `/design` and `/implement` is their **file contract** (what they read and write). Detailed schemas live in [api-spec.md](./api-spec.md); the public surface is summarized here.

### `/design <issue_number>` — file contract

| Phase | Action | Files Read | Files Written |
| --- | --- | --- | --- |
| 1. Preparation | Branch creation, dir setup | (none) | `docs/design/#{issue}/` (mkdir) |
| 1.5. Migration check | Run migration if `shared/` missing | `docs/design/#{old_issue}/*` | `docs/design/shared/*` (initial seed) |
| 2. Load shared | Read cumulative truth | `docs/design/shared/*` | (none) |
| 3. Research | (conditional) | (none) | `docs/design/#{issue}/research.md` and/or `docs/design/shared/research/<lib>.md` |
| 4. Design | Produce design + UML | `docs/design/shared/*` | `docs/design/#{issue}/design.md`, `flowchart.md` |
| 5. Workflow | Produce impl plan | (none) | `docs/design/#{issue}/workflow.md` |
| 6. Snapshot | Regenerate shared layer | `docs/design/shared/*` (current state, in memory) | `docs/design/shared/architecture.md`, `data-model.md`, `api-spec.md`, `class.md`, `sequence.md` |
| 7. Commit | Single commit covering both layers | (none) | git index |

### `/implement <issue_number>` — file contract

| Phase | Action | Files Read | Files Written |
| --- | --- | --- | --- |
| 1. Preparation | Branch detection | `docs/design/shared/*` **AND** `docs/design/#{issue}/*` | (none) |

The added read of `shared/*` is the only change to `/implement`. All downstream phases (build, test, analyze) are unaffected.

### Type Definitions

These are conceptual "types" — the schemas of the markdown files. See `api-spec.md` for full templates.

- `SharedArchitecture` — `shared/architecture.md`: project-wide module map, layer boundaries, technology choices
- `SharedDataModel` — `shared/data-model.md`: domain entities, type definitions, schemas
- `SharedApiSpec` — `shared/api-spec.md`: public API/interface contracts
- `SharedClassDiagram` — `shared/class.md`: cumulative Mermaid `classDiagram`
- `SharedSequenceDiagram` — `shared/sequence.md`: cumulative Mermaid `sequenceDiagram` covering system-wide flows and state machines
- `SharedResearch` — `shared/research/<library-name>.md`: reusable external research
- `IssueDesign` — `#{issue}/design.md`: self-contained delta for the issue (option **b**)
- `IssueWorkflow` — `#{issue}/workflow.md`: implementation steps
- `IssueFlowchart` — `#{issue}/flowchart.md`: issue-local control flow
- `IssueResearch` — `#{issue}/research.md`: issue-specific external research

### Where does new content go? (Decision Rules)

| Content kind | Destination |
| --- | --- |
| New module / changed layer boundary | `shared/architecture.md` (snapshot updated) AND `#{issue}/design.md` (delta) |
| New entity / type / schema | `shared/data-model.md` (snapshot updated) AND `#{issue}/design.md` (delta) |
| New public API endpoint or function | `shared/api-spec.md` (snapshot updated) AND `#{issue}/design.md` (delta) |
| New class / class change | `shared/class.md` (snapshot updated) AND `#{issue}/design.md` (delta description) |
| System-wide sequence / state transition | `shared/sequence.md` (snapshot updated) |
| Issue-local control flow / decision tree | `#{issue}/flowchart.md` only |
| Reusable library research | `shared/research/<library>.md` |
| Issue-specific library usage | `#{issue}/research.md` |

## Data Flow

### `/design` flow

```
User: /design <issue>
  ↓
[Phase 1] Read issue meta + create branch + mkdir #{issue}/
  ↓
[Phase 1.5] If shared/ missing AND any #{old_issue}/ exists → run _shared/design-migration
  ↓
[Phase 2] Read shared/* into context (architecture, data-model, api-spec, class, sequence)
  ↓
[Phase 3-5] Author #{issue}/design.md, #{issue}/workflow.md, #{issue}/flowchart.md (delta against shared/*)
  ↓
[Phase 6] Regenerate shared/* in snapshot mode:
        - Take the in-context shared/* + this issue's contributions
        - Write the merged result fully into shared/*
        - NO append-only changelog sections (NFR-1)
  ↓
[Phase 7] Single commit: shared/* + #{issue}/* changes together
```

### `/implement` flow (unchanged except for added read)

```
User: /implement <issue>
  ↓
[Phase 1] Detect branch + Read shared/* + Read #{issue}/* → context
  ↓
[Phase 2..N] (unchanged: index-repo, implement, build, test, analyze, improve)
```

### Migration flow (one-shot)

```
First /design after #257 ships:
  ↓
Detect shared/ does not exist
  ↓
List existing docs/design/#{issue}/ directories (note: mixed naming: '#228', '246', '255')
  ↓
Read all #{issue}/design.md files chronologically (newest last, so newer overrides older)
  ↓
Synthesize shared/architecture.md, data-model.md, api-spec.md, class.md, sequence.md
  ↓
Existing #{issue}/* directories are PRESERVED as-is (FR-5)
  ↓
Commit shared/* as a separate "chore: bootstrap docs/design/shared from existing artifacts" commit (or as the first commit of the current branch)
```

## Error Handling

| Condition | Behavior |
| --- | --- |
| `docs/design/shared/` missing on `/design` | Run migration (Phase 1.5). If no `#{issue}/` exists either, treat shared/* as empty and create files lazily as designs warrant. |
| `docs/design/shared/` missing on `/implement` | Warn but continue — shared/* may be empty for the very first issue. |
| `docs/design/#{issue}/` already populated (re-running `/design`) | Existing files are overwritten by Phase 3-5 outputs. The branch should already exist (handled by `_shared/branch`). |
| Snapshot regeneration would *shrink* a shared file (e.g., classes removed) | Acceptable. The snapshot is the new truth. Git history retains the previous state. |
| Mixed directory naming (`#228` vs `246`) discovered during migration | Migration reads both formats. Going forward, `/design` always creates `#{issue_number}` with the `#` prefix to match the existing majority pattern. |
| `.claude/skills/` and `templates/claude/.claude/skills/` drift detected post-PR | NFR-4 violation — surfaced as a future PR. Out of scope for this issue beyond the initial reconciliation. |

## Implementation Notes

### Snapshot Strategy enforcement (NFR-1)

The `SKILL.md` text MUST contain explicit imperative phrases such as:

> "Regenerate `docs/design/shared/<file>.md` in full from the latest combined state. Do NOT append `## Issue #N` sections. Do NOT keep stale entries from prior snapshots."

This wording leaves no room for changelog-style accumulation, which would re-introduce the bloat problem this issue solves.

### Self-containment of `#{issue}/design.md` (NFR-3, option b)

`#{issue}/design.md` SHOULD repeat enough surrounding context that a reader can understand what changed without diffing against `shared/*`. This is intentional duplication — the staleness it accrues over time is treated as historical record, not a bug.

The `design/SKILL.md` template for `#{issue}/design.md` will gain a "## Context" section near the top, summarizing the relevant slice of `shared/architecture.md` and `shared/data-model.md` that the delta is acting on.

### In-repo / template parity (FR-6, NFR-4)

Two-location duplication (`/.claude/skills/` and `templates/claude/.claude/skills/`) is a known maintenance hazard. This PR reconciles the existing drift from #248 and adds a final task to verify byte-equality (modulo deliberate template-only differences) before opening the PR.

A future improvement (out of scope) could replace the duplication with a build step that copies `.claude/skills/` into `templates/claude/.claude/skills/` at release time. That is **not** done here to keep the change focused.

### Migration semantics

- **Idempotent**: Re-running the migration on an already-populated `shared/` should be safe; it overwrites with the latest synthesis.
- **Lossy by design**: The synthesized `shared/*` is a best-effort consolidation. Subtleties recorded only in old `#{issue}/design.md` may not survive into `shared/*` — that is acceptable since the originals are preserved.
- **Naming normalization**: Migration accepts both `#NNN` and `NNN` directory names. New issues continue to use `#{issue_number}` with the `#` prefix (current majority pattern).

### Edge cases

- **Empty repo (no prior issues)**: First `/design` finds shared/* missing and no #{issue}/ to migrate from. It creates shared/* lazily during Phase 6 with only the current issue's contributions.
- **Issue closed without `/design`**: Some legacy issues may not have artifacts. Migration ignores them.
- **Concurrent issues** (out of scope per Constraints, but for the record): Two parallel branches modifying `shared/*` will collide on merge. The repo is single-branch in practice; if this changes, snapshot regeneration would need a "rebase-aware" mode.

### Performance considerations

- Reading `shared/*` adds 5-10 small files per `/design` and `/implement` invocation. Negligible compared to the savings from not reading every prior `#{issue}/design.md`.
- Snapshot regeneration writes 5+ files per `/design`. All small markdown — no concern.
