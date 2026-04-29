# Flowchart: #265 manifest lifecycle decision

The `manifest_decide` function takes three hashes — `old` (from the existing manifest), `current` (sha256 of the user's current file, or `-` if absent), and `new` (sha256 of the staging-area file produced by re-running plugins, or `-` if absent) — and emits exactly one of 8 lifecycle decisions. This is the single place where "did the user edit this file" is interpreted: the predicate is `current == old`.

The flowchart below mirrors the state table in `design.md` :: "manifest_decide state table". It is intended for the implementer building Step 3.4 and the test author writing the FR-4 row coverage.

```mermaid
flowchart TD
    Start([three hashes:<br/>old, current, new]) --> NewExists{new<br/>present?}

    %% new file present
    NewExists -->|yes| OldExists{old<br/>present?}
    OldExists -->|no| CurrentExists{current<br/>present?}
    CurrentExists -->|no| NEW[/"NEW<br/>FR-4 row 4"/]
    CurrentExists -->|yes| SKIP_NEW_CONFLICT[/"SKIP_NEW_CONFLICT<br/>FR-4 row 5"/]
    OldExists -->|yes| CurrExistsOnUpdate{current<br/>present?}
    CurrExistsOnUpdate -->|no| SKIP_USER_DELETED[/"SKIP_USER_DELETED<br/>FR-4 row 8"/]
    CurrExistsOnUpdate -->|yes| HashChanged{new ==<br/>old?}
    HashChanged -->|yes<br/>upstream<br/>unchanged| Unedited1{current ==<br/>old?}
    Unedited1 -->|yes| NOOP1[/"NOOP<br/>FR-4 row 1"/]
    Unedited1 -->|no| SKIP_EDITED1[/"SKIP_EDITED<br/>FR-4 row 3 super-set:<br/>edited, no upstream change → no-op<br/>but tracked as 'edited' for safety"/]
    HashChanged -->|no<br/>upstream<br/>changed| Unedited2{current ==<br/>old?}
    Unedited2 -->|yes| UPDATE[/"UPDATE<br/>FR-4 row 2"/]
    Unedited2 -->|no| SKIP_EDITED2[/"SKIP_EDITED<br/>FR-4 row 3"/]

    %% new file absent — upstream removed
    NewExists -->|no| OldExistsOnRemove{old<br/>present?}
    OldExistsOnRemove -->|no| NOOP_VOID[/"NOOP<br/>row 9 — total-function safety;<br/>file in neither old nor new manifest"/]
    OldExistsOnRemove -->|yes| CurrExistsOnRemove{current<br/>present?}
    CurrExistsOnRemove -->|no| SKIP_USER_DELETED2[/"SKIP_USER_DELETED<br/>FR-4 row 8 (also)"/]
    CurrExistsOnRemove -->|yes| EditedOnRemove{current ==<br/>old?}
    EditedOnRemove -->|no<br/>edited locally| LEAVE_REMOVED_EDITED[/"LEAVE_REMOVED<br/>FR-4 row 7 — always leave"/]
    EditedOnRemove -->|yes<br/>unedited| PruneEnabled{--prune<br/>set?}
    PruneEnabled -->|no| LEAVE_REMOVED[/"LEAVE_REMOVED<br/>FR-4 row 6 default"/]
    PruneEnabled -->|yes| PRUNE[/"PRUNE<br/>FR-4 row 6 with flag"/]

    classDef writeOp fill:#ffe5b4,stroke:#cc8400
    classDef noOp fill:#e0f0ff,stroke:#0077cc
    classDef skipOp fill:#f5e0ff,stroke:#7a2cb3
    classDef removeOp fill:#ffd6d6,stroke:#cc0000
    class NEW,UPDATE writeOp
    class NOOP1,NOOP_VOID noOp
    class SKIP_NEW_CONFLICT,SKIP_USER_DELETED,SKIP_USER_DELETED2,SKIP_EDITED1,SKIP_EDITED2,LEAVE_REMOVED,LEAVE_REMOVED_EDITED skipOp
    class PRUNE removeOp
```

## Notes on the SKIP_EDITED1 case

When `new == old` (upstream unchanged) but the user has edited the file (`current != old`), the formal lifecycle is "no upstream change to apply" — i.e. no overwrite happens regardless of user edits. The decision could be `NOOP`. We deliberately classify it as `SKIP_EDITED` (with a special "no upstream change" sub-flag in the summary) so:

1. The user is *informed* that they have local edits to a tracked file (useful diagnostic).
2. The summary's "Skipped (edited)" bucket gives a complete audit of every file the upgrade declined to touch *because* of edits.

In `manifest_apply` both `SKIP_EDITED1` and `SKIP_EDITED2` produce identical filesystem behavior (no change) but the diff-summary line indicates `(=)` for the unchanged-upstream case so the user knows there was nothing to lose.

## How this maps onto `setup.sh --upgrade`'s outer loop

```text
for each path in OLD ∪ NEW:
    old_h     = OLD.files[path]                  # "" if absent
    new_h     = NEW.files[path]                  # "" if absent (no entry in staged manifest)
    current_h = sha256_file(target/path) or ""   # "" if user deleted

    decision = manifest_decide old_h current_h new_h
    manifest_apply decision staging/path target/path
```

`manifest_apply` is the only function that touches the filesystem (when `DRY_RUN=false`). Tally counters and per-decision file-list arrays are updated inside `manifest_apply` so `manifest_summary_print` has everything it needs at the end of the loop.
