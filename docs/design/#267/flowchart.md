# Flowchart: #267 — Node 24 migration decision + verification

Two diagrams. Issue-local control flow / decision tree (per `_shared/design` UML auto-detection); class and system-wide sequence diagrams have no delta for this issue and live in `../shared/`.

## Per-action target selection

For each affected JS action, follow the same rule: **pin to the earliest major whose `action.yml` declares `runs.using: node24`**. The `research.md` per-action verification feeds directly into this tree.

```mermaid
graph TD
    A[Action currently on Node 20] --> B{Composite action?<br/>runs.using: composite}
    B -->|Yes| Z1[Out of scope<br/>no Node runtime]
    B -->|No| C{Earliest major with<br/>runs.using: node24<br/>has API breaking changes?}
    C -->|No breaking changes<br/>checkout v5, cache v5,<br/>github-script v8, action-gh-release v3| D[Pin to that major]
    C -->|Yes - default-runtime moved later<br/>upload-artifact v5 still node20| E{Next major default<br/>runs.using: node24?}
    E -->|Yes - upload-artifact v6| D
    E -->|No| F[Investigate further]
    D --> G{Does v+1 add<br/>unrelated behavior change<br/>we don't need?}
    G -->|Yes - checkout v6 cred-persist,<br/>github-script v9 ESM-only,<br/>upload-artifact v7 archive flag| H[Stay on the picked major<br/>smaller delta wins]
    G -->|No| H

    Z1 --> END[No change]
    H --> END[Apply pin]

    style Z1 fill:#eee
    style F fill:#fdd
    style END fill:#dfd
```

Concrete outcomes (verified in `research.md` :: Question 2):

| Action | Composite? | Earliest Node-24 major (default) | v+1 quirk | Final pin |
| --- | --- | --- | --- | --- |
| `dtolnay/rust-toolchain` | Yes | n/a | n/a | unchanged (`@stable`) |
| `taiki-e/install-action` | Yes | n/a | n/a | unchanged |
| `actions/checkout` | No | `v5` | `v6` adds cred-persist | `@v5` |
| `actions/cache` | No | `v5` | n/a observed | `@v5` |
| `actions/github-script` | No | `v8` | `v9` ESM-only `@actions/github` | `@v8` |
| `actions/upload-artifact` | No | `v6` (v5 default still node20) | `v7` adds `archive: false` | `@v6` |
| `softprops/action-gh-release` | No | `v3` | n/a observed | `@v3` |

## Migration → verification signal mapping

Where each acceptance criterion gets its evidence. Branches show parallelism: PR-time signals fire concurrently; post-merge signals fan out from the squash-merge commit.

```mermaid
graph TD
    PR[Open PR vs develop] --> RQ[rust-quality-check.yml<br/>push event]
    PR --> PPS[pr-project-status.yml<br/>pull_request opened]

    RQ -->|all 5 jobs green<br/>no Node-20 annotation| GATE{All PR-time<br/>signals clean?}
    PPS -->|green<br/>no Node-20 annotation| GATE

    GATE -->|No| FIX[Diagnose;<br/>amend or revert]
    FIX --> PR
    GATE -->|Yes| MERGE[Squash-merge to develop]

    MERGE --> AT[auto-tag.yml<br/>push to develop]
    MERGE --> RD{Release wanted now?}
    MERGE --> DS[Downstream consumers<br/>freyja next push]

    AT -->|tag created<br/>no Node-20 annotation<br/>github-script v8 comment ok| OK1[Tag flow verified]
    RD -->|Manual workflow_dispatch<br/>against new -rc.N tag| RE[release-erd.yml]
    RD -->|No, defer| OK2[release-erd verified later<br/>on natural release]
    RE -->|binary + sha256 uploaded by upload-artifact v6<br/>Release created by action-gh-release v3<br/>no Node-20 annotation| OK3[Release flow verified]

    DS -->|freyja CI green<br/>annotation gone via workflow_call| OK4[Reusable workflow<br/>consumer verified]

    OK1 --> DONE[Acceptance criteria 1, 2, 3 met]
    OK3 --> DONE2[Acceptance criterion 4 met]
    OK4 --> DONE3[Acceptance criterion 3 met]

    PLR[project-label-routing.yml<br/>label event - not on PR] -.->|exercise post-merge<br/>by labelling a test issue| OK5[Label routing verified]
    PI[project-integration.yml<br/>already exercised by issue 267 creation] -.->|durable green run on issue| OK6[Project integration verified]

    style FIX fill:#fdd
    style GATE fill:#ffd
    style DONE fill:#dfd
    style DONE2 fill:#dfd
    style DONE3 fill:#dfd
    style OK5 fill:#dfd
    style OK6 fill:#dfd
```

Six workflows, six independent verification signals. Two (`project-integration.yml`, `project-label-routing.yml`) need a manual nudge or are already covered by the issue's own lifecycle; the other four are exercised naturally by the PR + merge flow.
