# Flowchart: #312 restructure lifecycle roles around a long-context orchestrator with delegated designer and executor

## Stage ownership across a `/flow` run

Who writes, who reviews, and where the user appears. The user is reachable from every delegated stage, but only through the orchestrator — subagents cannot reach the user directly, which is the constraint the whole structure is built around.

```mermaid
graph TD
    U([user]) <-->|requirements dialogue| O["orchestrator — main session<br/>claude-fable-5"]
    O -->|authors inline| I[issue]
    O -->|delegates| D["designer<br/>claude-opus-5[1m]"]
    D -->|design artifacts| OR1{orchestrator reviews<br/>vs issue Requirements}
    OR1 -->|blocking, round ≤2| D
    OR1 -->|clear| C1[orchestrator commits]
    O -->|delegates| E["executor<br/>claude-sonnet-5"]
    E -->|implementation| OR2{orchestrator reviews<br/>vs design}
    OR2 -->|blocking| E
    OR2 -->|clear| XR["external-reviewer<br/>codex"]
    XR -->|findings| T{orchestrator triages}
    T -->|fixes| E
    T -->|clear| P["executor authors PR<br/>+ monitors CI"]
    P --> M{orchestrator:<br/>content check + merge decision}
    OR1 -.->|surviving blocking finding| U
    OR2 -.->|surviving blocking finding| U
    D -.->|blocked-result| O
    E -.->|blocked-result| O
    M -.->|CI unknown / conflict| U
```

Dotted edges are the only paths that reach the user: an escalation the orchestrator cannot resolve, a blocking review finding surviving two rounds, and a `/pr` failure. Requirement gathering is the fourth, at the top.

## The blocked-result protocol

A subagent cannot ask the user, so the only correct response to an unanswerable question is to stop and return it. The rejected branch is drawn because it is the failure mode the whole protocol exists to prevent.

```mermaid
graph TD
    A[Subagent is authoring] --> B{Question arises}
    B -->|Answer derivable from issue,<br/>design, or codebase| C[Answer it and continue]
    B -->|Not derivable| D[Return blocked-result:<br/>question, options,<br/>evidence already checked,<br/>partial work]
    D --> E{Orchestrator can resolve?}
    E -->|Yes| F[Answer, re-dispatch<br/>with the answer]
    E -->|No — the answer is the user's| G[Escalate to the user]
    G --> F
    B -.rejected.-> X[Assume a reading and proceed]
    style X fill:#fdd,stroke:#c66
```

"Evidence already checked" is a required field rather than a courtesy: it is what distinguishes a genuine block from a question the subagent simply did not try to answer.

## Why the commit moved after the review

The left path is the current `/design`; the right is the new one. The old ordering is why a design commit could not be distinguished from an approved design, and why the previous revision of this issue needed a durable conformance record purely to tell the two apart.

```mermaid
graph TD
    subgraph before["before — commit, then sign off"]
      A1[author artifacts] --> B1[commit] --> C1[sign-off gate]
      C1 -.-> D1["a design commit proves artifacts were<br/>written, not approved — so a resumed run<br/>needs a separate record to tell them apart"]
    end
    subgraph after["after — review, then commit"]
      A2[designer authors] --> B2{orchestrator reviews}
      B2 -->|blocking, ≤2 rounds| A2
      B2 -->|clear| C2[orchestrator commits]
      C2 -.-> D2["the design commit IS the record<br/>that the review happened — no new<br/>evidence artifact, no new evidence row"]
    end
    style D1 fill:#fdd,stroke:#c66
    style D2 fill:#dfd,stroke:#6c6
```

An interrupted run leaves uncommitted files, which `/flow`'s existing evidence table already reads correctly as "no design commit → enter at `design`". That is why Stage 2 needs no change at all.
