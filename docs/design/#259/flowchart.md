# Flowchart: #259 `update_gitignore()` per-block branching

Issue-local control flow inside `update_gitignore()` (and the analogous Codex plugin gitignore step). Each block is independently marker-guarded; partial application is supported by design.

## `update_gitignore()` — three blocks

```mermaid
graph TD
    A["update_gitignore(target_dir)"] --> B["print_info: Updating .gitignore..."]
    B --> C{".gitignore exists?"}
    C -->|No| D["touch .gitignore"]
    C -->|Yes| E
    D --> E[Block 1: Claude whitelist]

    E --> E1{"grep -q '^# Claude Code (track...)\\$'"}
    E1 -->|match| F[Block 2: .serena/]
    E1 -->|no match| E2["echo blank line<br/>echo Claude marker<br/>echo .claude/*<br/>echo !.claude/commands/<br/>echo !.claude/skills/<br/>echo !.claude/scripts/<br/>echo !.claude/agents/<br/>echo !.claude/rules/<br/>echo !.claude/hooks/<br/>echo !.claude/settings.json"]
    E2 --> F

    F --> F1{"grep -q '^# Serena MCP...\\$'"}
    F1 -->|match| G[Block 3: screenshots/]
    F1 -->|no match| F2["echo blank line<br/>echo Serena marker<br/>echo .serena/"]
    F2 --> G

    G --> G1{"grep -q '^# Local screenshots...\\$'"}
    G1 -->|match| H["print_success: .gitignore updated"]
    G1 -->|no match| G2["echo blank line<br/>echo screenshots marker<br/>echo screenshots/"]
    G2 --> H
```

## Codex plugin gitignore step — single block

```mermaid
graph TD
    A["plugin_post_copy(target_dir)"] --> B{"target_dir/.gitignore exists?"}
    B -->|No| Z[skip — nothing to update]
    B -->|Yes| C{"grep -q '^# Codex CLI (track...)\\$'"}
    C -->|match| Z
    C -->|no match| D["echo blank line<br/>echo Codex marker<br/>echo .codex/*<br/>echo !.codex/config.toml"]
    D --> E[continue plugin_post_copy]
```

The Codex block is gated by `[[ -f "$gitignore" ]]`, not by `touch` — `update_gitignore()` runs first in the `setup.sh` pipeline and is responsible for creating the file. The Codex plugin only appends.
