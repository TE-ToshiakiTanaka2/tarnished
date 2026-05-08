# Flowchart: #273 setup_plugins auth-gate decision

The new pre-flight inside `setup_plugins()`. Inserted between the existing `command -v claude` prerequisite check and the existing `ensure_claude_marketplace` step. Both `setup_plugins.sh` files (workspace + template) follow this flow identically after #273.

```mermaid
graph TD
    A[setup_plugins called by post.sh] --> B{command -v claude}
    B -->|missing| B1["echo 'Claude Code CLI not installed'<br/>return 0"]
    B -->|present| C{is_claude_authenticated?<br/>[[ -s $HOME/.claude/.credentials.json ]]}

    C -->|no credentials| C1["echo 'Not yet authenticated'<br/>echo 'Run claude to log in,<br/>then re-run setup_plugins.sh'<br/>return 0"]
    C -->|credentials present| D[ensure_claude_marketplace<br/>'anthropics/claude-plugins-official']

    D -->|registration ok| E[claude plugins list<br/>-> plugins_output]
    D -->|registration fails| D1["echo 'Skipping due to<br/>marketplace registration failure'<br/>return 0"]

    E --> F[try_install_plugin context7]
    F --> G[try_install_plugin serena]
    G --> H{is_interactive AND<br/>playwright not installed?}
    H -->|yes| H1[prompt 'Install Playwright? y/N']
    H1 -->|y| H2[try_install_plugin playwright]
    H1 -->|n| H3[skip playwright]
    H -->|no| H4[skip playwright<br/>note: non-interactive]

    H2 --> Z["echo 'Plugin setup complete'<br/>return 0"]
    H3 --> Z
    H4 --> Z

    B1 -.->|set -e respected,<br/>post.sh continues| POST[setup_codex runs next]
    C1 -.->|set -e respected,<br/>post.sh continues| POST
    D1 -.->|set -e respected,<br/>post.sh continues| POST
    Z -.->|set -e respected,<br/>post.sh continues| POST
```

## Key invariants

- **Every terminal node returns 0.** This is the contract `setup_plugins` owes `post.sh` under `set -e` — already documented in `docs/design/shared/api-spec.md` :: "templates/claude/.devcontainer/scripts/setup_plugins.sh". The new C → C1 path is an additional `return 0` exit, not a new contract.
- **`is_claude_authenticated` is read-only.** No subprocess, no network, no mutation of `~/.claude/`. Idempotent and safe to call repeatedly.
- **`claude` is never invoked when unauthenticated.** The auth gate at C is a hard precondition for any `claude plugins …` call in nodes D and beyond. This is what eliminates the cascade of "Warning: failed to register / install" messages users currently see on first run.
- **Authenticated path is byte-identical to pre-#273 behavior** for the workspace variant, and structurally aligned with the workspace variant for the template (with the additional improvement that the template now also has `ensure_claude_marketplace` + `try_install_plugin` isolation).
