# Flowchart: #325 Replace devcontainer features with mise runtimes, Dockerfile OS packages, and post.sh AI CLI installs

Scaffold-time decisions made by `setup.sh` and the plugins. The build-time and
post-create flows are system-wide and live in
[`../shared/sequence.md`](../shared/sequence.md) ("Container build and
post-create").

## Scaffold pipeline

```mermaid
graph TD
    A[setup.sh scaffold<br/>single / monorepo / add-module] --> B{add-module?}
    B -->|No| C[load core, agent-workflows,<br/>languages, services, claude, codex?]
    B -->|Yes| C2[load selected language<br/>+ new service plugins only]

    C --> D[plugin_copy pass]
    C2 --> D
    D --> D1[core: copy .devcontainer/ incl.<br/>setup_mise.sh, setup_claude.sh, npm_global_cli.sh;<br/>docker/Dockerfile.dev; mise.toml]

    D1 --> E[execute_plugin_dockerfiles]
    E --> E0{Dockerfile has<br/>'# >>> mise runtimes >>>'?}
    E0 -->|No| E0W[print_warning once:<br/>pre-#325 Dockerfile, see docs/maintenance.md]
    E0 -->|Yes| E1
    E0W --> E1[for each plugin with plugin_dockerfile]
    E1 --> E2{plugin}
    E2 -->|latex| E3[existing awk block<br/>before ^SHELL - unchanged]
    E2 -->|postgresql / mysql| E4[dockerfile_add_os_packages]
    E2 -->|languages python/node/rust/go/deno| E5[no hook any more]
    E4 --> E6{marker present?}
    E6 -->|Yes| E7[skip]
    E6 -->|No| E8{^SHELL anchor?}
    E8 -->|Yes| E9[insert apt block above SHELL]
    E8 -->|No| E10[warn: add packages by hand]

    E3 --> F[plugin_post_copy pass]
    E5 --> F
    E7 --> F
    E9 --> F
    E10 --> F

    F --> F1[core: post_sh_add_block<br/>'# mise Runtime Setup'<br/>then '# Claude Code Setup']
    F1 --> F2[languages: plugin_post_copy_shared root]
    F2 --> F3[merge feature-free devcontainer overlay<br/>customizations only]
    F3 --> F4[mise_toml_ensure for each entry]
    F4 --> F5{key present in section?<br/>bare, quoted, table or dotted form}
    F5 -->|Yes| F6[keep developer value<br/>no write]
    F5 -->|No| F7{section exists?}
    F7 -->|Yes| F8[insert after last line of section]
    F7 -->|No| F9[append section + entry]
    F6 --> F10
    F8 --> F10
    F9 --> F10[language post.sh block<br/>existing marker logic]
    F10 --> F11[services: compose merge,<br/>runServices, overlay]
    F11 --> F12[claude: merge settings incl.<br/>extraKnownMarketplaces + enabledPlugins;<br/>post_sh_add_block '# Claude Code Plugin Setup' - append]
    F12 --> F13{codex enabled?}
    F13 -->|Yes| F14[post_sh_add_block '# Codex CLI Setup'<br/>before '# Claude Code Plugin Setup']
    F13 -->|No| G
    F14 --> G[replace_placeholders, update_gitignore,<br/>manifest write]
```

## `post_sh_add_block` placement

```mermaid
graph TD
    P0[post_sh_add_block post_sh marker before...] --> P1{post.sh exists?}
    P1 -->|No| P9[return 0]
    P1 -->|Yes| P2{exact line == marker?}
    P2 -->|Yes| P9
    P2 -->|No| P3{any before-marker present?}
    P3 -->|No| P4[append block at EOF]
    P3 -->|Yes| P5[take the earliest one by line number]
    P5 --> P6[move up over the dashed rule above it<br/>and one blank line above that]
    P6 --> P7[insert block there]
    P4 --> P8[atomic mv]
    P7 --> P8
    P8 --> P9
```

Resulting order for a default `--codex` scaffold:
`# Tarnished Asset Refresh` → `# mise Runtime Setup` → `# Claude Code Setup`
→ language/service blocks → `# Codex CLI Setup` → `# Claude Code Plugin Setup`.
