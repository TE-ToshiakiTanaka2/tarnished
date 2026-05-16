# Flowchart: #284 devcontainer JSONC merge path

```mermaid
graph TD
    A[Plugin post-copy wants devcontainer merge] --> B[merge_devcontainer_json base overlay output]
    B --> C{Base file exists?}
    C -->|no| Z1[print_error Base file not found; return 1]
    C -->|yes| D{Overlay file exists?}
    D -->|no| Z2[print_error Overlay file not found; return 1]
    D -->|yes| E[mktemp normalized base and overlay files]

    E --> F[Normalize base JSONC to strict JSON]
    F --> G{Base normalization ok?}
    G -->|no| Z3[cleanup temps and output; return 1]
    G -->|yes| H[Normalize overlay JSONC to strict JSON]
    H --> I{Overlay normalization ok?}
    I -->|no| Z4[cleanup temps and output; return 1]
    I -->|yes| J[Run existing jq -s devcontainer merge]

    J --> K{Merge ok?}
    K -->|no| Z5[print_error Failed to merge; cleanup output; return 1]
    K -->|yes| L[Write strict JSON to caller output file]
    L --> M[Remove internal temp files]
    M --> N[return 0]

    style Z1 fill:#fdd
    style Z2 fill:#fdd
    style Z3 fill:#fdd
    style Z4 fill:#fdd
    style Z5 fill:#fdd
    style N fill:#dfd
```

## Comment Stripping State Machine

```mermaid
stateDiagram-v2
    [*] --> Normal
    Normal --> String: quote
    Normal --> LineComment: slash slash
    Normal --> BlockComment: slash star
    Normal --> Normal: other char emitted

    String --> Escape: backslash
    String --> Normal: quote
    String --> String: other char emitted

    Escape --> String: escaped char emitted

    LineComment --> Normal: newline emitted
    LineComment --> LineComment: other char skipped

    BlockComment --> Normal: star slash
    BlockComment --> BlockComment: other char skipped
```

The state machine only treats comment markers as comments while in `Normal`.
That preserves URL strings and other string values that contain `//` or `/*`.
