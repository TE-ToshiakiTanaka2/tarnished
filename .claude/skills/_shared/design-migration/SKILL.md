---
name: _shared/design-migration
description: Internal shared skill for one-shot bootstrap of docs/design/shared/ from existing per-issue artifacts. Referenced by /design.
---

# Shared Skill: Design Migration (Bootstrap shared/)

Internal utility skill that synthesizes `docs/design/shared/*` from the cumulative content of pre-existing `docs/design/#{issue}/*` directories. Referenced by `/design` when the shared layer is missing but per-issue artifacts exist.

**This skill is NOT directly invocable by users.** It is a reference document included by `/design`.

## When to Run

`/design` invokes this procedure at Phase 1.5 (after branch creation, before reading shared/) when **both** of the following hold:

1. `docs/design/shared/` does not exist (or exists but is empty)
2. At least one `docs/design/#{issue}/` directory (or `docs/design/{issue}/` without the `#` prefix — see Naming below) exists with a `design.md` file inside

If only condition (1) is true (no prior issues at all), skip migration. The shared layer will be created lazily on the first `/design` Phase 6.

## Idempotency

Re-running this procedure on an already-populated `shared/` is safe. It overwrites the shared files with the latest synthesis from the current state of the per-issue artifacts. Existing per-issue files are never modified.

## Procedure

### Step 1: Discover existing per-issue directories

```bash
ls -1 docs/design/ | grep -E '^#?[0-9]+$'
```

Accept both naming forms:

- `#NNN` (e.g., `#228`, `#230`) — the current majority pattern
- `NNN` (e.g., `246`, `255`) — legacy form

Sort the directories so that newer issue numbers come last (numerically, ignoring the `#` prefix).

### Step 2: Read each `design.md` chronologically

For each directory in the sorted order, read `docs/design/<dir>/design.md` if it exists. Skip directories without `design.md`.

Reading newer issues last lets later content override earlier content during synthesis (newer is more authoritative).

Also opportunistically read `api-spec.md`, `class.md`, `sequence.md`, and `flowchart.md` from each issue directory — they may contain content that belongs in the shared layer.

### Step 3: Synthesize the shared layer

Produce all five shared files in one pass. The synthesis is a best-effort consolidation — small details that were only locally relevant to a single issue may be dropped. The originals are preserved (Step 5), so nothing is lost.

#### `docs/design/shared/architecture.md`

Aggregate from each issue's "Architecture Overview" / "Module Structure" sections. Produce:

```markdown
# Architecture

## Overview
<One paragraph: what this project is, at the latest known state>

## Module Structure
<Unified directory tree, with a one-line role per directory>

## Layer Boundaries
<Layered/hexagonal/etc. layout. Which layer may depend on which>

## Technology Choices
<Languages, frameworks, infra. With rationale where non-obvious>

## Cross-cutting Concerns
<Logging, config, error handling, observability strategy>
```

#### `docs/design/shared/data-model.md`

Aggregate from "Type Definitions", "Data Flow", and any entity descriptions:

```markdown
# Data Model

## Entities
| Entity | Fields | Description |
| --- | --- | --- |

## Type Definitions
<Project-wide shared types/structs/enums>

## Relationships
<Mermaid `erDiagram` or prose>

## Schemas / Migrations
<Persistent storage shape; brief migration history>
```

#### `docs/design/shared/api-spec.md`

Aggregate from each issue's `api-spec.md` (if present) and "Interface Design" sections of `design.md`:

```markdown
# API Specification (Project-wide)

## Public Endpoints / Functions
| Name | Method/Signature | Description |
| --- | --- | --- |

## Input/Output Schemas
<Per endpoint or function group>

## Error Responses
| Error | Code/Type | When |
| --- | --- | --- |

## Versioning Policy
<If applicable>
```

#### `docs/design/shared/class.md`

Aggregate Mermaid `classDiagram` blocks from each issue's `class.md`. Merge into a single coherent diagram. Resolve duplicates by keeping the most recent definition.

````markdown
# Class Diagram (Project-wide)

```mermaid
classDiagram
    ...
```
````

#### `docs/design/shared/sequence.md`

Aggregate Mermaid `sequenceDiagram` blocks from each issue's `sequence.md` and any system-wide flows from `flowchart.md`. Each named flow gets its own `##` section.

````markdown
# Sequence Diagram (System-wide)

## <Flow Name 1>
```mermaid
sequenceDiagram
    ...
```

## <Flow Name 2>
```mermaid
sequenceDiagram
    ...
```
````

State-machine-like flows belong here too, under their own `##` section.

### Step 4: (Optional) Cross-cutting research

If any `#{issue}/research.md` files describe libraries reusable across issues (e.g., a general-purpose library used in multiple features), promote that content to `docs/design/shared/research/<library-name>.md`. Be conservative — when in doubt, leave it in the per-issue directory.

### Step 5: Preserve per-issue artifacts

Existing `docs/design/#{issue}/*` files MUST NOT be modified or deleted by this procedure. They remain as historical record.

Verify with `git status` after Step 3-4: only files under `docs/design/shared/` should appear as new.

### Step 6: Return control to `/design`

Report the seed result (file count, total size) back to the caller. `/design` continues with Phase 2 (Load shared) using the freshly synthesized files.

## Naming Convention Going Forward

After this migration, all new per-issue directories MUST use the `#NNN` form (with the `#` prefix). The legacy `NNN` form is read but not written. `_shared/branch/SKILL.md` and `/design` already produce the `#NNN` form.

## Error Handling

| Error | Action |
| --- | --- |
| `docs/design/` does not exist | No prior artifacts. Skip migration entirely. |
| A `#{issue}/` directory has no `design.md` | Skip that directory. Do not error. |
| A `design.md` cannot be parsed (malformed markdown) | Include its raw content in synthesis with a note. Do not error. |
| Write to `shared/` fails (permissions) | Report error, abort. `/design` cannot proceed. |
| Per-issue file would be modified | This is a bug — abort and report. Migration MUST be read-only with respect to existing artifacts. |

## Integration

This skill is referenced by:

- `/design` — Phase 1.5 (Migration check) — Issue mode

The migration is intended as a one-shot bootstrap, but it is idempotent and may be re-run if the shared layer is lost or needs full regeneration.
