# Flowchart: #261 `setup_codex()` install decision tree

The `setup_codex()` function in `.devcontainer/scripts/setup_codex.sh` makes its install decisions based on three runtime signals — whether `npm` is available, whether `codex` is already installed, and whether the npm global prefix can be written by the current user. The branching matters because the wrong choice (no sudo where sudo is needed) is the exact failure that the original `templates/codex/setup_codex.sh` exhibits under the `claude-code:1.0` devcontainer feature.

```mermaid
graph TD
    Start([post.sh sources setup_codex.sh<br/>and calls setup_codex])
    Start --> NpmCheck{command -v npm<br/>found?}

    NpmCheck -->|No| WarnNoNpm["log [WARN] npm not found.<br/>Skipping Codex CLI installation."]
    WarnNoNpm --> Return0a([return 0])

    NpmCheck -->|Yes| CodexCheck{command -v codex<br/>found?}

    CodexCheck -->|Yes| LogAlready["log: Codex CLI already installed:<br/>codex --version"]
    LogAlready --> LogComplete

    CodexCheck -->|No| GetPrefix[npm_prefix = npm root -g]
    GetPrefix --> PrefixEmpty{npm_prefix<br/>empty?}

    PrefixEmpty -->|Yes| WarnPrefix["log: Warning - 'npm root -g'<br/>did not resolve a prefix"]
    WarnPrefix --> InstallNoSudo[install_cmd =<br/>npm install -g @openai/codex]
    InstallNoSudo --> RunInstall

    PrefixEmpty -->|No| PrefixExists{npm_prefix path<br/>exists on disk?}

    PrefixExists -->|Yes| WriteCheckExisting{"-w npm_prefix?<br/>(prefix dir is writable)"}
    PrefixExists -->|No| WriteCheckParent{"-w dirname npm_prefix?<br/>(parent dir is writable)"}

    WriteCheckExisting -->|Yes| InstallNoSudo
    WriteCheckExisting -->|No| LogSudo

    WriteCheckParent -->|Yes| InstallNoSudo
    WriteCheckParent -->|No| LogSudo

    LogSudo["log: npm global prefix '<prefix>'<br/>is not user-writable; using sudo"]
    LogSudo --> InstallSudo[install_cmd =<br/>sudo -E npm install -g @openai/codex]
    InstallSudo --> RunInstall

    RunInstall{Run install_cmd}
    RunInstall -->|exit 0| LogInstalled[log: Codex CLI installed successfully]
    RunInstall -->|non-zero| WarnFailed["log [WARN] Failed to install Codex CLI<br/>(network error or npm issue)"]
    WarnFailed --> LogManual[log: You can install it manually later: install_cmd]
    LogManual --> Return0b([return 0])

    LogInstalled --> LogComplete
    LogComplete[log: Codex CLI setup complete.<br/>To authenticate, run: codex]
    LogComplete --> Return0c([return 0])
```

## Decision rationale

The two-pronged write check (existing dir vs. parent dir) is necessary because `npm install -g` writes **into** the prefix when it already exists, but creates the prefix if it does not. Writability requirements differ between those two cases — checking only `-w "$npm_prefix"` would falsely report "needs sudo" for a soon-to-be-created prefix whose parent is writable, while checking only the parent would falsely report "no sudo" for an existing root-owned prefix.

Empty `npm_prefix` (the third branch) is treated optimistically — we attempt the install without sudo and let `npm` itself report the EACCES if it happens. Returning `0` from a failed install is intentional: post.sh runs under `set -e`, and we do not want a Codex install hiccup to abort the entire devcontainer post-create. The user can rerun `npm install -g @openai/codex` manually later — the WARN log makes that path discoverable.

All three return points (`Return 0a/b/c`) are intentional: this function is contractually idempotent and non-fatal under `set -e` in `post.sh`, matching the `setup_plugins.sh` invariant documented in `shared/api-spec.md::Setup / Plugin Surface`.
