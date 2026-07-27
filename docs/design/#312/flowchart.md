# Flowchart: #312 extend the advisor role to standing content review with fix proposals

## Conformance consult — the bounded loop

Identical in shape at both invocation points (`/issue` FR-13, `/design` FR-14). The two exits that are easy to get wrong are the skip path and the cap path: both must still write a record.

```mermaid
graph TD
    A[Stage writes its artifact] --> B{Advisor available?}
    B -->|No| S["Record verdict: skipped — reason"]
    S --> Z[Continue the stage]
    B -->|Yes| C[Conformance consult, round 1<br/>source of truth quoted verbatim]
    C --> D{Verdict}
    D -->|conform| R1[Record: conform]
    D -->|non-blocking gap| R2[Record: non-blocking gap]
    D -->|blocking mismatch| E[Orchestrator applies a correction]
    R1 --> Z
    R2 --> Z
    E --> F[Conformance consult, round 2]
    F --> G{Verdict}
    G -->|resolved| R3[Record: conform, rounds 2]
    G -->|still blocking| H["Record: blocking mismatch<br/>(escalated, unresolved)"]
    R3 --> Z
    H --> I[Escalate to the user<br/>with the finding and what was attempted]
    I --> Z
```

Every terminal path passes through a record. A record written only on the `conform` path deadlocks against NFR-2 and makes every resumed run redo the design stage destructively.

## `/flow` Stage 2 — where a missing conformance record leads

The rejected branch is drawn deliberately: sending a recordless design commit back into `/design` triggers Phase 7's overwrite of `docs/design/shared/*`, which is a destructive redesign on every resume of every branch designed before this change.

```mermaid
graph TD
    A[Resolve the issue branch] --> B{Design commit present?}
    B -->|No| C[Enter at design]
    B -->|Yes| D{"docs/design/#N/conformance.md present<br/>with a Verdict line?"}
    D -->|Yes| E{Later commit outside docs/design/?}
    D -->|No| F{--from given?}
    F -->|Yes| G[Warn: conformance precondition unmet<br/>proceed to the named stage]
    F -->|No| H[Verification-only re-entry:<br/>consult against the committed artifacts]
    H --> I[Commit the record<br/>touches only docs/design/]
    I --> E
    E -->|No| J[Enter at implement]
    E -->|Yes| K[Continue the existing derivation:<br/>review / pr]
    C -.rejected.-> X["Re-running /design would overwrite<br/>docs/design/shared/* and re-author design.md"]
    style X fill:#fdd,stroke:#c66
```

The record commit touching only `docs/design/` is what makes this compose with the existing table: the "no later commit outside `docs/design/`" row still resolves to `implement` on the next resume.
