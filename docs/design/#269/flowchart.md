# Flowchart: #269 MySQL parity insertion points

This flowchart maps each FR to the existing setup.sh / test pipeline location
where the insertion happens. The diagram is read-only annotation of an
existing pipeline — no new branching is introduced.

```mermaid
graph TD
    A[User invokes setup.sh / curl pipe] --> B[parse_arguments]
    B --> C{interactive mode<br/>available?}
    C -->|no, missing flags| C1["show_interactive_mode_error()<br/>(scripts/lib/common.sh:665-686)<br/><b>FR-2 inserts --mysql line here</b>"]
    C1 --> Z[exit 1]
    C -->|yes| D[plugin_copy hooks<br/>copy docker-compose.&lt;db&gt;.yml overlays]
    D --> E[plugin_post_copy hooks<br/>merge overlays into docker-compose.yml<br/>then delete overlay]
    E --> F["replace_placeholders()<br/>(scripts/lib/common.sh:546-579)<br/><b>FR-1 inserts docker-compose.mysql.yml</b>"]
    F --> G[update_gitignore + manifest write]
    G --> H[Completion message]

    subgraph Documentation
        R0["README.md quickstart<br/>(README.md:33-50)<br/><b>FR-3 inserts MySQL example</b>"]
    end

    subgraph "Test surface (CI verification)"
        T1["tests/setup_create_manifest.bats<br/>'--create-manifest rejects service flags'<br/><b>FR-4 mirrors postgresql test for --mysql</b>"]
        T2["tests/setup_service_selection.bats<br/>'plugin_post_copy does not add overlay<br/>to dockerComposeFile'<br/><b>FR-5 mirrors postgresql test for mysql</b>"]
    end

    classDef inserted fill:#dff5e0,stroke:#3a8d3a,stroke-width:2px,color:#1a4d1a
    class C1,F,R0,T1,T2 inserted
```

Legend: green nodes are existing locations where this issue inserts a single
new line, block, or test mirroring the postgresql equivalent. No node is
removed or restructured.

## Per-FR insertion summary

| FR | File | Anchor | Insertion |
| --- | --- | --- | --- |
| FR-1 | `scripts/lib/common.sh` | `replace_placeholders()` `files=()` array (line ~558) | `"${target_dir}/docker-compose.mysql.yml"` |
| FR-2 | `scripts/lib/common.sh` | `show_interactive_mode_error()` help block (line ~679) | `echo "  --mysql               Include MySQL database support"` |
| FR-3 | `README.md` | Monorepo quickstart block (line ~40-46) | MySQL alternative example or inline annotation |
| FR-4 | `tests/setup_create_manifest.bats` | After existing postgresql rejection test (line ~109) | `@test "--create-manifest rejects --mysql"` block |
| FR-5 | `tests/setup_service_selection.bats` | Inside `# MySQL plugin_post_copy Integration Tests` section (line ~471-473), before existing test | `@test "plugin_post_copy does not add docker-compose.mysql.yml to dockerComposeFile"` block |
