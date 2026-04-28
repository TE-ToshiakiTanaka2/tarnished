# Sequence Diagram: #257 Separate shared and issue-specific design artifacts

## `/design` Flow with shared/ layer

```mermaid
sequenceDiagram
    actor User
    participant Design as /design skill
    participant Branch as _shared/branch
    participant Migration as _shared/design-migration
    participant Shared as docs/design/shared/
    participant Issue as docs/design/#{issue}/
    participant Git

    User->>Design: /design 257
    Design->>Branch: create branch (Issue mode)
    Branch-->>Design: branch checked out
    Design->>Issue: mkdir #{issue}/

    alt shared/ missing AND prior #{issue}/ exist
        Design->>Migration: bootstrap shared/
        Migration->>Issue: read all prior #{old_issue}/design.md
        Migration->>Shared: synthesize architecture/data-model/api-spec/class/sequence
        Migration-->>Design: shared/ seeded
    end

    Design->>Shared: read architecture, data-model, api-spec, class, sequence
    Shared-->>Design: cumulative truth (in-context)

    opt external dependency
        Design->>Issue: write research.md (issue-specific)
        Design->>Shared: write/update research/<lib>.md (cross-cutting)
    end

    Design->>Issue: write design.md (self-contained delta, option b)
    Design->>Issue: write workflow.md
    Design->>Issue: write flowchart.md (issue-local control flow)

    Note over Design,Shared: Phase 6 — Snapshot regeneration<br/>(NFR-1: no append-style updates)
    Design->>Shared: regenerate architecture.md
    Design->>Shared: regenerate data-model.md
    Design->>Shared: regenerate api-spec.md
    Design->>Shared: regenerate class.md
    Design->>Shared: regenerate sequence.md

    Design->>Git: single commit (shared/* + #{issue}/*)
    Design-->>User: report (branch, files, summary)
```

## `/implement` Flow (input contract)

```mermaid
sequenceDiagram
    actor User
    participant Implement as /implement skill
    participant Branch as _shared/branch
    participant Shared as docs/design/shared/
    participant Issue as docs/design/#{issue}/
    participant Repo as codebase

    User->>Implement: /implement 257
    Implement->>Branch: detect or create branch
    Branch-->>Implement: branch ready

    Implement->>Shared: read architecture, data-model, api-spec, class, sequence
    Shared-->>Implement: cumulative truth

    Implement->>Issue: read design.md, workflow.md, flowchart.md, research.md
    Issue-->>Implement: per-issue delta + plan

    Note over Implement: design context = shared/* + #{issue}/*<br/>(constant size, not linear in issue count)

    Implement->>Repo: index-repo, implement, build, test, analyze, improve
    Implement-->>User: implementation complete
```

## Migration (one-shot bootstrap)

```mermaid
sequenceDiagram
    participant Design as /design skill
    participant Migration as _shared/design-migration
    participant Issue as docs/design/#{old}/
    participant Shared as docs/design/shared/

    Design->>Migration: shared/ missing, but #{old_issue}/ exist — bootstrap
    Migration->>Issue: list directories (#NNN and NNN forms)
    Migration->>Issue: read design.md from each (chronological order)
    Issue-->>Migration: cumulative content

    Migration->>Migration: synthesize shared layers
    Migration->>Shared: write architecture.md
    Migration->>Shared: write data-model.md
    Migration->>Shared: write api-spec.md
    Migration->>Shared: write class.md
    Migration->>Shared: write sequence.md

    Note over Migration,Issue: existing #{old}/ files are PRESERVED unchanged (FR-5)

    Migration-->>Design: shared/ seeded; proceed with normal /design flow
```
