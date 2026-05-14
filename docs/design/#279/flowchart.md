# Flowchart: #279 refresh-assets.sh decision tree

`refresh-assets.sh` is invoked twice per container lifecycle:

1. From `post.sh` on the very first boot (via the marker-guarded block
   appended by `templates/core/plugin.sh::plugin_post_copy`).
2. From `postStartCommand` on every subsequent container start.

Both paths reach the same entry point and traverse the decision tree
below. The script is contractually `return 0` on every leaf except an
explicit CLI argument error (FR-5: container start MUST NOT block).

```mermaid
graph TD
    A[refresh-assets.sh invoked] --> B{Parse CLI flags}
    B -->|unknown flag| Z1[print_error; exit 1]
    B -->|ok| C{Locate refresh.json}

    C -->|--config given| C1[Use given path]
    C -->|default lookup| C2[<repo_root>/.tarnished/refresh.json]
    C1 --> D
    C2 --> D

    D{File exists?} -->|no| Z2[print_warning 'refresh.json missing'; exit 0]
    D -->|yes| E{jq parse ok?}
    E -->|no| Z3[print_warning 'refresh.json malformed'; exit 0]
    E -->|yes| F{schema_version == 1?}
    F -->|no| Z4[print_warning 'unsupported schema_version'; exit 0]
    F -->|yes| G{managed_paths empty?}
    G -->|yes| Z5[print_info 'nothing to sync'; exit 0]
    G -->|no| H{clone_dir exists?}

    H -->|no| H1{Parent dir writable?}
    H1 -->|yes| H2[git clone --depth 1 --branch <ref> <url> <clone_dir>]
    H1 -->|no| H3[print_warning 'fallback to ~/.cache/tarnished'<br/>clone_dir := $HOME/.cache/tarnished]
    H3 --> H2
    H2 -->|fail| Z6[print_warning 'clone failed: network?'; exit 0]
    H2 -->|ok| K[goto SYNC]

    H -->|yes| I{<clone_dir>/.git exists?}
    I -->|no| Z7[print_error 'clone_dir not a git repo; manual cleanup needed'; exit 0]
    I -->|yes| J{--force-pull set?}

    J -->|yes| J1[skip ls-remote]
    J -->|no| J2[git ls-remote origin <branch>]

    J2 -->|fail| Z8[print_warning 'ls-remote failed; using cached'; exit 0]
    J2 -->|ok| J3{remote_sha == local_sha?}
    J3 -->|yes| Z9[print_info 'upstream unchanged'; exit 0]
    J3 -->|no| J1

    J1 --> J4[git fetch origin <branch>]
    J4 -->|fail| Z10[print_warning 'fetch failed; cache untouched'; exit 0]
    J4 -->|ok| J5[git reset --hard origin/<branch>]
    J5 -->|fail| Z11[print_warning 'reset failed'; exit 0]
    J5 -->|ok| K

    K[SYNC: foreach managed_paths entry] --> L{--dry-run?}
    L -->|yes| L1[print intended actions; tally] --> M
    L -->|no| L2[rsync -a --delete<br/><clone_dir>/<src>/ <project>/<dst>/]
    L2 -->|fail| L3[print_warning 'rsync of <dst> failed; skip']
    L3 --> M
    L2 -->|ok| L4{<project>/<overlay>/ exists?}
    L4 -->|yes| L5[rsync -a (no --delete)<br/><project>/<overlay>/ <project>/<dst>/]
    L5 -->|fail| L6[print_warning 'overlay rsync failed']
    L6 --> M
    L5 -->|ok| M
    L4 -->|no| M

    M{more paths?} -->|yes| K
    M -->|no| N[print_summary line<br/>'N paths synced; A added; R removed; O overlay preserved']
    N --> END[exit 0]

    style Z1 fill:#fdd
    style Z2 fill:#ffd
    style Z3 fill:#ffd
    style Z4 fill:#ffd
    style Z5 fill:#dfd
    style Z6 fill:#ffd
    style Z7 fill:#fdd
    style Z8 fill:#ffd
    style Z9 fill:#dfd
    style Z10 fill:#ffd
    style Z11 fill:#ffd
    style END fill:#dfd
```

Legend:

- 🟩 green = success exit (0)
- 🟨 yellow = non-fatal warning, exit (0) — container start continues
- 🟥 red = error printed (exit 0 unless CLI arg error)

## Three-state lifecycle of `/opt/tarnished`

```mermaid
stateDiagram-v2
    [*] --> Absent: container scaffold complete

    Absent --> Cloned: first refresh succeeds
    Absent --> Absent: first refresh fails (offline)<br/>note: project keeps original<br/>scaffolded bytes; warning printed

    Cloned --> Cloned: ls-remote ok, sha unchanged
    Cloned --> Cloned: ls-remote fails<br/>(transient; cache used as-is)
    Cloned --> Updated: sha differs, fetch+reset ok
    Updated --> Cloned: sync complete

    Cloned --> Error: <clone_dir>/.git missing<br/>(manual intervention)
    Updated --> Error: <clone_dir>/.git missing
    Error --> Error: subsequent runs print same error<br/>until user removes <clone_dir>
```

The `Error` state is reached only when something external corrupts the
clone (e.g., user manually removed `.git/` but left other files). The
script refuses to silently delete the directory because it cannot
distinguish a corrupted clone from a user's intentional non-tarnished
content.

## First-boot vs nth-boot ordering

```
┌─────────── First boot ───────────┐    ┌── Subsequent boots ──┐
│                                  │    │                      │
│ postCreateCommand                │    │  postStartCommand    │
│   ↓                              │    │    ↓                 │
│ post.sh                          │    │  refresh-assets.sh   │
│   ↓ (existing blocks)            │    │    ↓                 │
│ setup_plugins                    │    │  ls-remote → no-op   │
│   ↓                              │    │  (or pull + sync)    │
│ setup_codex                      │    │                      │
│   ↓                              │    └──────────────────────┘
│ refresh_assets ← NEW             │
│   ↓ (clones /opt/tarnished;      │
│      first sync)                 │
│                                  │
│ postStartCommand                 │
│   ↓                              │
│ refresh-assets.sh                │
│   ↓                              │
│ ls-remote → matches local sha    │
│ → no-op (just clone'd)           │
└──────────────────────────────────┘
```

The double invocation on first boot is benign: the second call hits
the SHA cache and exits early. We accept the small redundancy in
exchange for the guarantee that:

- The first-ever Claude Code session on a freshly-scaffolded project
  already sees the latest assets (because `post.sh` runs before any
  user shell is exposed).
- Every container restart thereafter independently re-syncs without
  needing `post.sh` to run again.
