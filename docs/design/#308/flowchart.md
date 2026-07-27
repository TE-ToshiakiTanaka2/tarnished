# Flowchart: #308 Rebase workflow skills on an Opus 5-class model policy

Two diagrams. The first is `/flow`'s stage-entry derivation — the only genuinely new control flow this issue introduces, and the reason `/flow` needs no state file. The second is the route-by-nature decision that replaces retry-then-escalate.

Class and system-wide sequence diagrams have no delta for this issue; the change surface is prompt documents plus one `setup.sh` helper.

## `/flow` stage-entry derivation

```mermaid
flowchart TD
    START([/flow invoked]) --> FROM{--from given?}
    FROM -->|yes| CHECKPRE[Check that stage's prerequisites]
    CHECKPRE -->|missing| STOPPRE[Report what is missing, stop]
    CHECKPRE -->|present| ENTER

    FROM -->|no| ISSUE{--issue given?}
    ISSUE -->|no| INFER[Infer issue number from current branch]
    INFER -->|no match| ASK[Structured question: which issue?]
    ASK --> HAVE
    INFER -->|matched| HAVE
    ISSUE -->|yes| HAVE[issue_number resolved]

    HAVE --> BR{Branch matching<br/>#N/ exists?}
    BR -->|no| S_DESIGN[entry = design]
    BR -->|yes| DES{Commit 'docs: add design<br/>documents for #N'<br/>reachable from HEAD?}

    DES -->|no| S_DESIGN
    DES -->|yes| IMPL{Commits beyond<br/>the design commit?}

    IMPL -->|no| S_IMPL[entry = implement]
    IMPL -->|yes| REV{docs/review/#N/review.md<br/>exists?}

    REV -->|no| S_REV[entry = review]
    REV -->|yes| PR{gh pr list --head branch<br/>non-empty?}

    PR -->|no| S_PR[entry = pr]
    PR -->|yes| DONE[All stages complete —<br/>report and stop]

    S_DESIGN --> ENTER
    S_IMPL --> ENTER
    S_REV --> ENTER
    S_PR --> ENTER
    ENTER([Run from entry stage to pr])
```

Evidence is read from git and GitHub, never from a persisted state file. A state file would go stale after a failed run, survive a branch reset, and need its own cleanup path; repository evidence is authoritative and survives context loss mid-run.

## Route-by-nature vs. retry-then-escalate

```mermaid
flowchart TD
    W([Unit of work]) --> NAT{Nature of the work}

    NAT -->|Judgment:<br/>design intent, pattern matching,<br/>review triage, refactor choice,<br/>merge decision, scope| ORCH[orchestrator — inline]
    NAT -->|Mechanical:<br/>repo survey, lint/format/type<br/>fix loop, boilerplate tests,<br/>cleanup, CI log collection| EXEC[executor — delegated]
    NAT -->|Independent verification:<br/>branch review| EXT[external-reviewer —<br/>separate vendor/context]

    EXEC --> OK{Command<br/>succeeded?}
    OK -->|yes| NEXT
    OK -->|no| BUDGET{Retry budget<br/>remaining?}
    BUDGET -->|yes| EXEC
    BUDGET -->|no| ORCH2[orchestrator takes over — the<br/>failure is no longer mechanical]
    ORCH2 --> NEXT

    ORCH --> GATE{Advisor trigger fired?}
    GATE -->|no| NEXT
    GATE -->|yes| ADV[advisor — read-only,<br/>one consult, never writes]
    ADV --> ORCH3[orchestrator still decides]
    ORCH3 --> NEXT

    EXT --> NEXT([Continue])
```

The retry budget applies only on the mechanical branch, and only to "the command errored". Judgment work is never retried on the theory that a second attempt lands better — it is routed to the orchestrator in the first place.

Advisor triggers are mechanical, not discretionary: issue size ≥ M at `/design`; an intent to leave a Critical or Major finding unfixed at `/flow` triage; unresolved scope ambiguity after `/issue` brainstorm. Without an objective trigger, "consult when unsure" becomes consulting on everything.
