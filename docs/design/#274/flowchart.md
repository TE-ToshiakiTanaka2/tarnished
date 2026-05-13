# Flowchart: #274 feat(templates): add Go language template

## Go plugin hook dispatch and idempotency

Captures the per-hook control flow inside `templates/languages/go/plugin.sh`
during one `setup.sh` invocation. The orchestrator dispatch
(`execute_plugin_post_copies` in `setup.sh`) is documented in
`../shared/api-spec.md` :: "Orchestrator dispatch"; this diagram zooms in on
what happens **inside** the Go plugin once the orchestrator hands off
control.

```mermaid
graph TD
    Start([setup.sh dispatch reaches Go plugin]) --> Hook{Which hook?}

    Hook -->|plugin_copy<br/>target_dir| Copy[mkdir .github/workflows]
    Copy --> CopyCheck{go-quality-check.yml<br/>exists?}
    CopyCheck -->|No| CopyWrite[copy via OVERWRITE_ALL=true<br/>copy_with_confirm]
    CopyCheck -->|Yes| CopyPrompt{TTY available?}
    CopyPrompt -->|Yes| AskUser{User: overwrite?}
    AskUser -->|y| CopyWrite
    AskUser -->|n / default| CopySkip[print_info skip]
    CopyPrompt -->|No| CopySkip
    CopyWrite --> CopyDone([plugin_copy returns])
    CopySkip --> CopyDone

    Hook -->|plugin_post_copy_shared<br/>target_dir| Shared1[merge_devcontainer_json<br/>features + extensions]
    Shared1 --> Shared2[merge_claude_settings_hooks<br/>Write/Edit *.go]
    Shared2 --> Shared3[copy_dir_with_confirm<br/>.claude/rules/]
    Shared3 --> PostShCheck{post.sh exists?}
    PostShCheck -->|No| SharedDone([plugin_post_copy_shared returns])
    PostShCheck -->|Yes| ModeCheck{MONOREPO_MODE<br/>or<br/>IS_ADD_MODULE_MODE?}

    ModeCheck -->|Yes| MarkerCheck{GO_POSTSH_MARKER<br/>already in post.sh?}
    MarkerCheck -->|Yes| AlreadyPresent[print_info<br/>skip append]
    AlreadyPresent --> SharedDone
    MarkerCheck -->|No| AppendMarked[append marker-guarded<br/>Go toolchain block<br/>gotestsum + golangci-lint]
    AppendMarked --> SharedDone

    ModeCheck -->|No| AppendSingle[append marker-guarded<br/>Go toolchain block<br/>NOTE: Go uses markers in<br/>both modes — simpler<br/>than Rust's split]
    AppendSingle --> SharedDone

    Hook -->|plugin_post_copy_module<br/>target_dir, module_name| Mod1[copy_with_confirm<br/>.golangci.yml -> target_dir]
    Mod1 --> ModDone([plugin_post_copy_module returns])

    Hook -->|plugin_post_copy<br/>target_dir<br/>backward-compat shim| Shim1[plugin_post_copy_shared<br/>target_dir]
    Shim1 --> Shim2[plugin_post_copy_module<br/>target_dir, $PROJECT_NAME]
    Shim2 --> ShimDone([plugin_post_copy returns])
```

## Re-run idempotency at the project level

Captures what happens when the user runs `setup.sh` twice against the same
target — the property the marker guards protect.

```mermaid
graph TD
    Run1([First run: setup.sh --monorepo --module svc:go]) --> FirstShared
    FirstShared[plugin_post_copy_shared] --> FirstAppend[post.sh:<br/>no marker present<br/>→ append block]
    FirstAppend --> FirstModule[plugin_post_copy_module svc:<br/>write svc/.golangci.yml]
    FirstModule --> FirstDone([State A:<br/>marker + 1 module config])

    Run2([Second run: same command]) --> SecondShared
    SecondShared[plugin_post_copy_shared] --> SecondAppend[post.sh:<br/>marker present<br/>→ short-circuit return]
    SecondAppend --> SecondModule[plugin_post_copy_module svc:<br/>copy_with_confirm sees identical file<br/>→ skip or overwrite prompt]
    SecondModule --> SecondDone([State B: identical to State A])

    FirstDone -.->|idempotent| SecondDone

    Run3([Third run: --add-module worker --lang go]) --> ThirdShared
    ThirdShared[plugin_post_copy_shared] --> ThirdAppend[post.sh:<br/>marker present<br/>→ short-circuit]
    ThirdAppend --> ThirdModule[plugin_post_copy_module worker:<br/>write worker/.golangci.yml]
    ThirdModule --> ThirdDone([State C:<br/>marker + 2 module configs])
```

## Decision: when to add `plugin_dockerfile`?

Documented for future reference. The Go plugin does **not** implement
`plugin_dockerfile` today; this diagram captures why and when the choice
might change.

```mermaid
graph TD
    Q{Does Go need to set ENV vars<br/>or RUN commands in Dockerfile.dev?} --> No[No — devcontainer Go feature<br/>exports GOPATH/GOROOT/PATH<br/>automatically]
    Q --> Yes{Yes — what kind?}

    No --> Decision[SKIP plugin_dockerfile<br/>same as Rust]

    Yes --> EnvOnly{ENV vars only?}
    EnvOnly -->|GOPROXY, GOSUMDB,<br/>GOTOOLCHAIN auto| Future1[Future-add ENV-only block<br/>via plugin_dockerfile]
    EnvOnly -->|Need apt-get install,<br/>protoc, build deps| Future2[Future-add RUN block<br/>via plugin_dockerfile]
```

Today the answer is "no", so `plugin_dockerfile` is omitted. If a downstream
project later needs `GOPROXY` pinning or `protoc` for protobuf generation,
add `plugin_dockerfile` following the Python/LaTeX precedent (awk-based
marker-guarded insertion) — the contract permits it without breaking
existing scaffolds.
