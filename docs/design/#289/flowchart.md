# Flowchart: #289 fix(manifest): jq ARG_MAX overflow in manifest_write

## `manifest_write` — corrected control flow (writer side)

The fix moves the unbounded files map off the `jq` argument vector and onto stdin,
removing the `E2BIG` ("Argument list too long") failure mode. The atomic tmp+mv and
the existing error guard are unchanged.

```mermaid
graph TD
    A[manifest_write scope_root, version, commit, opts] --> B{scope_root empty?}
    B -->|yes| Z1[print_error; return 1]
    B -->|no| C[_manifest_files_to_json -> files_json]
    C --> D{serialize ok?}
    D -->|no| Z2[print_error; return 1]
    D -->|yes| E["printf '%s' files_json | jq --arg/--argjson bounded fields, 'files: .' &gt; tmp"]
    E --> F{jq exit 0?}
    F -->|no E2BIG/error| G[rm -f tmp; print_error 'jq build failed'; return 1]
    F -->|yes| H[mv tmp file]
    H --> I{mv ok?}
    I -->|no| Z3[return 1]
    I -->|yes| J[return 0]
```

Key change is node **E**: previously `jq -n ... --argjson files "$files_json"` placed
the whole map in `argv`, which `execve` rejects with `E2BIG` once it exceeds `ARG_MAX`.
Streaming via stdin (`files: .`) makes the call size-independent.

## Caller guard — corrected success reporting (caller side)

Applies to all four `manifest_write` call sites (`setup.sh:1689`, `1709`, `1721`,
`2051`). Before the fix, the success/`summary` step ran regardless of exit status.

```mermaid
graph TD
    A[caller invokes manifest_write ...] --> B{return code}
    B -->|0 success| C[print_success 'wrote ...' / allow summary 'Manifest updated']
    B -->|non-zero| D[print_error; propagate non-zero return]
    C --> E[continue]
    D --> F[abort scope / exit non-zero]
```

This guarantees the contradictory `"[ERROR] ... [OK] wrote ..."` output can no longer
occur: a failed write surfaces an error and a non-zero exit, never a false success.
