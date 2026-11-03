# Sequence Diagram (System-wide)

Cumulative system-wide flows. Each `##` section is a named flow. Snapshot — regenerated on every `/design` (NFR-1).

## `erd issue link` — default + label routing (#230)

```mermaid
sequenceDiagram
    actor User
    participant CLI as erd CLI (cli/issue.rs)
    participant Config as ProjectConfig
    participant GH as GitHubClient
    participant API as GitHub API

    User->>CLI: erd issue link <N> [--overrides]
    CLI->>Config: load_with_path(project.yml)
    Config-->>CLI: ProjectConfig {default_project, label_projects, ...}

    CLI->>GH: get_issue(owner, repo, N)
    GH->>API: GET /repos/.../issues/N
    API-->>GH: issue JSON
    GH-->>CLI: GetIssueResponse {node_id, labels[]}

    Note over CLI,GH: Default link (with CLI overrides applied)
    CLI->>GH: add_issue_to_project_with_defaults(default_project, node_id, project_config, verbose)
    GH->>API: GraphQL addProjectV2ItemById + updateProjectV2ItemFieldValue*
    API-->>GH: ok
    GH-->>CLI: ok

    loop for each label on issue
        alt label.name in config.label_projects
            CLI->>GH: add_issue_to_project_with_defaults(label_project, node_id, label_config, verbose)
            GH->>API: GraphQL ...
            alt success
                API-->>GH: ok
                GH-->>CLI: ok
            else project not found / field invalid
                API-->>GH: error
                GH-->>CLI: error
                Note over CLI: log warning, continue (non-fatal)
            end
        end
    end

    CLI-->>User: success summary
```

## Tag bump computation from branch prefix (#228)

```mermaid
sequenceDiagram
    actor CI as CI workflow
    participant CLI as erd CLI
    participant Tag as tag_config.rs
    participant Git as git_ops.rs

    CI->>CLI: erd tag (or similar) on push
    CLI->>Tag: load versioning.yml
    alt Format B (canonical)
        Tag->>Tag: deserialize into BranchPrefixes directly
    else Format A (legacy template)
        Tag->>Tag: custom Deserialize: group `branches: [{prefix, bump}]` by bump
        Tag->>Tag: produce BranchPrefixes
    end
    Tag-->>CLI: BranchPrefixes

    CLI->>Git: current branch name
    Git-->>CLI: <branch>
    CLI->>CLI: match <branch> against major / minor / patch lists
    alt match found
        CLI->>CLI: BumpType = matched
    else no match
        CLI->>CLI: BumpType = Rc (default)
    end
    CLI-->>CI: new tag
```

## Container build and post-create (#325)

The generated environment installs in three layers: OS packages at image build
(root), runtimes from `mise.toml` at image build (`vscode`), and AI CLIs plus
Claude plugins in `post.sh`. No devcontainer `features` are involved, so a
plain `docker build` of `docker/Dockerfile.dev` yields the same runtimes as a
devcontainer build. `post.sh` runs under `set -e`; every helper returns 0.

```mermaid
sequenceDiagram
    participant Builder as docker build / compose / devcontainer
    participant Root as Dockerfile.dev (root section)
    participant Mise as mise
    participant Post as post.sh (set -e, non-login bash)
    participant SM as setup_mise.sh
    participant SC as setup_claude.sh
    participant NPM as npm_global_cli.sh
    participant SX as setup_codex.sh
    participant SP as setup_plugins.sh
    participant Claude as claude CLI

    Builder->>Root: apt (git, build-essential, ...), gh (signed-by repo)
    Root->>Root: download mise @ MISE_VERSION, minisign + sha256 verify
    Root->>Root: plugin OS blocks above SHELL (TeX Live, psql, mysql client, Godot GUI + .NET libs)
    Builder->>Mise: USER vscode, PATH += shims, MISE_TRUSTED_CONFIG_PATHS=/workspace
    Builder->>Mise: COPY mise.toml, mise install (optional github_token secret)
    Mise-->>Builder: node, python, uv, pnpm, rust, go, deno, dotnet, godot, gdtoolkit per mise.toml

    Builder->>Post: postCreateCommand: bash .devcontainer/scripts/post.sh
    Note over Post: git / SSH sections, Tarnished Asset Refresh
    Post->>SM: source then setup_mise
    alt mise missing (pre-#325 image)
        SM-->>Post: [WARN] rebuild / docs/maintenance.md, return 0
    else mise present
        SM->>Mise: mise install (converge edits made after the build)
        SM-->>Post: ok or [WARN] + manual command, return 0
    end
    Post->>SC: source then setup_claude
    SC->>NPM: install_npm_global_cli "Claude Code" pkg claude
    alt claude --version succeeds
        NPM-->>SC: already installed
    else missing or stale shim after a Node bump
        NPM->>NPM: npm present? prefix writable? (never sudo)
        NPM->>NPM: npm install -g (mise reshims via npm wrapper)
        NPM-->>SC: installed, or [WARN] + manual command
    end
    SC-->>Post: mkdir -p ~/.claude, return 0
    Note over Post: language / service post-create blocks
    Post->>SX: source then setup_codex (only with --codex)
    SX->>NPM: install_npm_global_cli "Codex CLI" pkg codex
    SX-->>Post: return 0
    Post->>SP: source then setup_plugins
    SP-->>Post: see "Claude plugin fallback" below, return 0
    Post-->>Builder: post-create complete
```

Order is load-bearing: a Node change in `mise.toml` installs a new Node in
`setup_mise`, which drops npm globals, so `setup_claude` and `setup_codex`
must run after it and before `setup_plugins` needs `claude`.

## Godot flavor: GUI opt-in and container launch (#331)

Two moments carry the system-wide part of the godot flavor:

1. **Scaffold.** Recording the opt-in.
2. **Container start.** Compose applies the separate WSLg overlay only when
   `devcontainer.json` lists it.

Headless is the default on every host, so a non-WSLg host never sees
`/dev/dxg`. Plugin-internal branching is in `docs/design/#331/flowchart.md`.

```mermaid
sequenceDiagram
    actor Dev as Developer
    participant Setup as setup.sh
    participant Godot as godot plugin
    participant Common as common.sh
    participant DC as .devcontainer/devcontainer.json
    participant Ov as docker-compose.godot-gui.yml
    participant Compose as docker compose / devcontainer CLI
    participant Img as Dockerfile.dev + mise
    participant Post as post.sh

    Dev->>Setup: ./setup.sh --lang godot [-y] (optionally GODOT_GUI=true)
    Setup->>Godot: plugin_copy(root)
    Godot->>Ov: copy_with_confirm (inert file)
    Setup->>Godot: plugin_dockerfile(root)
    Godot->>Common: dockerfile_add_os_packages(godot, X11/Wayland/Mesa/Vulkan/audio/.NET libs)
    Note over Setup,Godot: plugin.sh is sourced for the post-copy pass, GODOT_GUI_ENABLED reset to empty
    opt TTY available (setup.sh gates plugin_interactive_setup on a TTY, not on -y)
        Setup->>Godot: plugin_interactive_setup()
        Godot->>Godot: _godot_resolve_gui_choice (GODOT_GUI, already listed, staging or -y means off)
        opt choice still empty
            Godot->>Dev: Enable the Godot GUI editor through WSLg? [y if /mnt/wslg and /dev/dxg]
            Dev-->>Godot: y / n
        end
    end
    Setup->>Godot: plugin_post_copy_shared(root)
    Godot->>Common: mise_toml_has_key tools godot / gdtoolkit
    Godot->>Common: mise_toml_ensure tool_alias + tools (only if absent), dotnet, uv, env
    opt GODOT_GUI_ENABLED empty (every non-TTY run)
        Godot->>Godot: _godot_resolve_gui_choice (never prompts, empty afterwards means off)
    end
    opt GODOT_GUI_ENABLED == true
        Godot->>DC: jq append "../docker-compose.godot-gui.yml" (order kept, no duplicate)
    end
    Godot->>Common: post_sh_add_block "# Godot Engine Setup" before Codex / plugin markers
    Setup->>Setup: replace_placeholders (renders overlay service key)

    Dev->>Compose: Reopen in Container
    Compose->>DC: read dockerComposeFile
    alt overlay listed (WSLg host)
        Compose->>Ov: multi-file merge: + X11/WSLg/usr-lib-wsl mounts, + /dev/dxg, + DISPLAY/WAYLAND/XDG/PULSE/LD_LIBRARY_PATH
    else not listed
        Note over Compose: dev service unchanged (headless)
    end
    Compose->>Img: build: apt godot block, then mise install (godot .NET via github backend, dotnet, uv, private CPython, gdtoolkit)
    Compose->>Post: postCreateCommand
    Post->>Post: mise → Claude Code → Godot Engine Setup (versions, export-template hint, GUI or headless) → Codex → plugins
    Note over Post: every Godot line is guarded and set -e safe, with no download and no exit
```

Turning the GUI off for one host means deleting the `dockerComposeFile`
entry and rebuilding. The overlay file itself stays in the project.

## Claude plugin fallback (`setup_plugins`, #249, #255, #273, #325)

`.claude/settings.json` declares the plugin set (`extraKnownMarketplaces`,
`enabledPlugins`). Claude Code does not download external plugins on a new
machine by itself, so the fallback installs enabled ids that are missing.

```mermaid
sequenceDiagram
    participant Post as post.sh (set -e)
    participant SP as setup_plugins.sh
    participant Settings as .claude/settings.json
    participant Creds as ~/.claude/.credentials.json
    participant Claude as claude CLI

    Post->>SP: setup_plugins
    SP->>SP: command -v claude, jq
    alt missing
        SP-->>Post: warning, return 0
    end
    SP->>Settings: jq enabledPlugins entries == true
    alt file missing, invalid JSON or no enabled ids
        SP-->>Post: warning, return 0
    end
    SP->>Creds: [[ -s ... ]] (is_claude_authenticated, #273)
    alt not authenticated
        SP-->>Post: guidance (log in, re-run), return 0
    end
    SP->>Claude: claude plugin list --json
    Claude-->>SP: installed ids (failure: treat as none)
    loop each enabled id not installed
        SP->>SP: validate name@marketplace
        opt marketplace not yet registered (once per marketplace)
            SP->>Settings: extraKnownMarketplaces[marketplace].source
            SP->>Claude: claude plugin marketplace add repo-or-url
        end
        SP->>Claude: claude plugin install id --scope project
        alt failure
            Claude-->>SP: exit 1
            Note over SP: warning, continue with next id
        end
    end
    SP-->>Post: return 0
```

The workspace and template copies of `setup_plugins.sh` are byte-identical
(`verify-mirrors.sh`).

## Claude Code skill workflow (`/issue` → `/design` → `/implement` → `/review` → `/pr`)

Role ownership per stage follows the #312 restructure: the orchestrator **is** the session, authoring is delegated to `designer` and `executor`, and the orchestrator reviews each delegated artifact before it is committed.

```mermaid
sequenceDiagram
    actor Dev
    participant O as orchestrator (session)
    participant Dsg as designer (subagent)
    participant Exe as executor (subagent)
    participant XR as external-reviewer
    participant Docs as docs/design/
    participant GH as GitHub

    Dev->>O: /issue
    O->>O: erd:brainstorm + erd:estimate
    O->>Dev: requirements summary (iterate until approved)
    O->>GH: gh issue create + project field set
    O-->>Dev: Issue #N

    Dev->>O: /design N
    O->>Docs: read shared/* (cumulative truth, #257)
    O->>Dsg: delegate authoring (issue + shared layer as input)
    Dsg->>Docs: write #N/design.md, api-spec.md, workflow.md, diagrams
    Dsg->>Docs: regenerate shared/* as snapshot (NFR-1)
    Dsg-->>O: artifacts (or a blocked-result, #312)
    O->>O: review vs issue Requirements (≤2 rounds)
    O->>Docs: write #N/orchestrator-review.md
    O->>GH: commit — after the review, so the commit records it (#312)
    O-->>Dev: branch + artifacts

    Dev->>O: /implement N
    O->>Exe: delegate authoring (design artifacts as input)
    Exe->>Exe: erd:index-repo, erd:implement, erd:build, erd:test
    Exe-->>O: code + commits (or a blocked-result)
    O->>O: review vs design

    Dev->>O: /review
    O->>XR: branch diff + design + issue Requirements (#312)
    XR-->>O: findings (criteria 8 and 9)
    O->>O: triage — Critical not deferrable
    O->>Exe: delegate fix application
    Exe-->>O: fix commits

    Dev->>O: /pr
    O->>Exe: delegate quality pass, push, and PR body drafting
    Exe-->>O: drafted body (nothing created yet)
    O->>O: content check — revise or re-dispatch
    O->>GH: gh pr create (the orchestrator's own command)
    O->>Exe: delegate CI monitoring and fix commits
    Exe-->>O: CI status
    O->>O: merge decision (never delegated)
    O-->>Dev: PR URL
```

Under `/flow` the same sequence runs in one pass with **no approval gates** (#312). The two human confirmations that formerly sat before `design` and before `implement` are gone, because the party that reviews each artifact is now the session itself rather than a subagent that cannot reach the user. A run stops for the user in exactly four places: requirement gathering, an escalation the orchestrator cannot resolve (a subagent blocked-result, or a blocking review finding surviving two rounds), argument resolution, and a `/pr` failure.

## Design-artifact migration (one-shot, #257)

```mermaid
sequenceDiagram
    participant Design as /design
    participant Migration as _shared/design-migration
    participant Issue as docs/design/#{old}/
    participant Shared as docs/design/shared/

    Design->>Migration: shared/ missing AND prior #{issue}/ exist
    Migration->>Issue: list directories (#NNN and NNN forms)
    Migration->>Issue: read each design.md (chronological, api-spec/class/sequence opportunistically)
    Issue-->>Migration: cumulative content
    Migration->>Migration: synthesize architecture, data-model, api-spec, class, sequence
    Migration->>Shared: write 5 shared files
    Note over Migration,Issue: existing #{old}/ files are PRESERVED unchanged (FR-5)
    Migration-->>Design: shared/ seeded, resume normal flow
```

## Codex CLI: install in devcontainer + `/review` execution (#261)

Two phases: (a) `setup_codex` runs during devcontainer post-create to make `codex` available on `$PATH`; (b) every subsequent `/review` invocation streams a prompt to `codex exec` and captures the result. Phase (a) is system-wide for any project that ships `setup_codex.sh` (workspace + downstream Codex-flavor projects); since #325 it delegates to the shared `npm_global_cli.sh::install_npm_global_cli` (detailed in "Container build and post-create" above) and runs after `setup_claude`, before `setup_plugins`. The sudo decision tree of `docs/design/#261/flowchart.md` no longer applies: the helper never uses sudo.

```mermaid
sequenceDiagram
    participant Container as devcontainer onCreate
    participant Post as post.sh (set -e)
    participant SetupCodex as setup_codex.sh
    participant Npm as npm
    participant Codex as codex CLI

    Container->>Post: source post.sh
    Note over Post: ... mise, Claude Code, language blocks ...
    Post->>SetupCodex: source setup_codex.sh then setup_codex
    alt codex --version succeeds
        SetupCodex->>Codex: codex --version
        Codex-->>SetupCodex: <version>
        SetupCodex-->>Post: log + return 0
    else npm missing or global prefix not writable
        SetupCodex-->>Post: [WARN] + recovery hint, return 0 (no sudo)
    else needs install
        SetupCodex->>Npm: npm install -g @openai/codex (mise per-version prefix)
        alt install ok
            Npm-->>SetupCodex: installed (npm wrapper reshims)
        else install fails
            Npm-->>SetupCodex: error
            Note over SetupCodex: [WARN] + manual recovery hint
        end
        SetupCodex-->>Post: return 0
    end
    Note over Post: ... then setup_plugins ...
    Post-->>Container: post-create complete

    actor Dev
    participant Claude as Claude Code (/review skill)
    participant ConfTOML as .codex/config.toml
    participant Agents as AGENTS.md

    Dev->>Claude: /review
    Claude->>Claude: prerequisites: command -v codex
    alt codex missing
        Claude-->>Dev: refuse with install instructions
    else codex present
        Claude->>Claude: collect git diff + design.md + prompt
        Claude->>Codex: codex exec - --sandbox read-only<br/>(or codex review --base develop)
        Codex->>ConfTOML: read model / approval / sandbox
        Codex->>Agents: read review-agent role
        Codex-->>Claude: structured review (Critical/Warnings/Suggestions/Positive)
        Claude->>Claude: save to docs/review/#{issue}/review.md
        Claude->>Claude: apply fixes, commit
        Claude-->>Dev: review summary + applied fixes
    end
```

## `update_gitignore` — block-level idempotent appends (#259)

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Common as scripts/lib/common.sh
    participant Codex as templates/codex/plugin.sh (optional)
    participant File as ${target}/.gitignore

    User->>Setup: ./setup.sh -y --lang ...
    Setup->>Common: update_gitignore(target_dir)
    Common->>Common: print_info "Updating .gitignore..."
    alt .gitignore missing
        Common->>File: touch
    end

    Note over Common,File: Block 1 — .claude/* whitelist
    Common->>File: grep -q "^# Claude Code (track project configs only)$"
    alt marker absent
        Common->>File: append blank + marker + .claude/* + 7 allow-list lines
    else marker present
        Note over Common: skip
    end

    Note over Common,File: Block 2 — .serena/
    Common->>File: grep -q "^# Serena MCP working files$"
    alt marker absent
        Common->>File: append blank + marker + .serena/
    end

    Note over Common,File: Block 3 — screenshots/
    Common->>File: grep -q "^# Local screenshots (manual UI testing)$"
    alt marker absent
        Common->>File: append blank + marker + screenshots/
    end

    Common->>Common: print_success ".gitignore updated"
    Common-->>Setup: ok

    opt Codex plugin selected
        Setup->>Codex: plugin_post_copy(target_dir)
        Note over Codex,File: Block 4 — .codex/* whitelist
        Codex->>File: grep -q "^# Codex CLI (track shared config only)$"
        alt marker absent
            Codex->>File: append blank + marker + .codex/* + !.codex/config.toml
        end
        Codex-->>Setup: ok
    end
```

## `setup.sh --monorepo` — one-shot monorepo init (#263)

Runs against an empty target directory. Generates root assets + per-module sub-directories + `modules.json`. The mode-selection portion of `main()` is captured separately in `docs/design/#263/flowchart.md`; this sequence focuses on the post-copy dispatch.

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Common as scripts/lib/common.sh
    participant Lang as language plugins (e.g. python, node)
    participant Core as core plugin
    participant Svc as service plugins (optional)
    participant Root as <project>/ (root)
    participant Mods as <project>/modules.json
    participant SubDir as <project>/<module>/

    User->>Setup: ./setup.sh --monorepo --module jing:python --module kir:node --postgresql -y
    Setup->>Setup: parse_arguments → MONOREPO_MODE=true, MODULES=("jing:python","kir:node")
    Setup->>Setup: derive SELECTED_LANGUAGES = ("python","node")
    Setup->>Setup: load_selected_plugins (core, claude, python, node, postgres, ...)
    Setup->>Setup: execute_plugin_copies(root)
    Note over Setup,Root: copies .devcontainer/, .claude/, docker/, docker-compose.yml, etc.
    Setup->>Setup: execute_plugin_dockerfiles(root)
    Note over Setup,Root: OS-package blocks only (latex, postgresql, mysql) above the SHELL anchor (#325)

    Setup->>Setup: execute_plugin_post_copies (monorepo mode)
    loop for each loaded plugin
        alt plugin in templates/languages/* (e.g. python)
            Setup->>Lang: plugin_post_copy_shared(root)
            Lang->>Root: patch .devcontainer/devcontainer.json (idempotent merge)
            Lang->>Root: patch .claude/settings.json (idempotent merge)
            Lang->>Root: mise_toml_ensure → root mise.toml (union of module runtimes, #325)
            Lang->>Root: append marker-guarded post.sh language block
            loop for each module with language == python (e.g. jing)
                Setup->>Lang: plugin_post_copy_module(root/jing, "jing")
                Lang->>SubDir: write pyproject.toml, ruff.toml, src/jing/__init__.py, tests/
            end
        else plugin in templates/services/* (e.g. postgres) or core/claude/codex/github-actions
            Setup->>Svc: plugin_post_copy(root)
            Svc->>Root: merge docker-compose.yml service "<project>-db" (project-name prefix, existing convention)
            Svc->>Root: append marker-guarded post.sh service block
        end
    end

    Setup->>Core: plugin_post_copy(root) [monorepo branch]
    Core->>Mods: write modules.json from MODULES (FR-4)
    loop for each module
        Core->>SubDir: write <module>/CLAUDE.md from template
    end

    Setup->>Common: replace_placeholders(root, project_name)
    Setup->>Common: update_gitignore(root)
    Setup-->>User: completion message
```

## Setup ownership bootstrap and runtime-helper upgrade

```mermaid
sequenceDiagram
    participant Developer
    participant Setup
    participant Stage as Private template staging
    participant Project
    participant Manifest
    Developer->>Setup: create-manifest or upgrade
    Setup->>Stage: Render selected distribution privately
    Stage-->>Setup: Eligible runtime-helper candidates
    Setup->>Manifest: Validate schema, scope and prior ownership
    Note over Setup,Manifest: Legacy hashes alone provide no authority
    Setup->>Project: Compare only safe candidate/prior-owned paths
    alt Exact distribution match without trusted baseline
        Setup->>Manifest: Adopt without changing project bytes
    else Trusted baseline and unchanged current file
        Setup->>Project: Install helper or explicitly prune proven removal
        Setup->>Manifest: Record successful installed baseline
    else Unknown, edited, deleted or unsafe
        Setup-->>Developer: Preserve and report recovery path
    end
    Note over Setup,Project: No real-target post-copy, dry-run writes nothing
```

## `setup.sh` remote bootstrap (`curl | bash`) (#276)

The primary distribution path. The bootstrap block at `setup.sh:29-69` detects pipe execution, clones the upstream repo into a temp dir, then `exec`s the local copy. The `< /dev/null` on the `exec` line is what keeps the outer curl from emitting a spurious `curl: (23)` to the user terminal.

```mermaid
sequenceDiagram
    actor User
    participant Curl as curl
    participant BootBash as bash (bootstrap, reads script from curl's stdout)
    participant Git as git
    participant Tmp as $BOOTSTRAP_TEMP_DIR
    participant NewBash as bash (exec'd, reads script from disk)

    User->>Curl: curl -fsSL .../setup.sh | bash
    Curl->>BootBash: stream setup.sh bytes
    BootBash->>BootBash: detect [[ -z BASH_SOURCE[0] || == "-" || ! -f ... ]]
    BootBash->>Git: git clone --depth 1 --branch develop ... $BOOTSTRAP_TEMP_DIR
    Git->>Tmp: populated
    Tmp-->>BootBash: ok

    Note over BootBash,NewBash: exec replaces the process image, pre-#276 the<br/>outer curl pipe was inherited and curl hit EPIPE,<br/>printing "curl: (23) Failure writing output to destination"<br/>at a non-deterministic point during the rest of the setup.

    BootBash->>NewBash: exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null
    Note over Curl,NewBash: stdin redirected to /dev/null, the curl pipe is<br/>NOT inherited, curl exits cleanly with no terminal noise.

    NewBash->>Tmp: read setup.sh from disk
    NewBash->>NewBash: parse_arguments + run modes (single / monorepo / upgrade / ...)
    NewBash-->>User: completion message
```

## GitHub Project Integration — auto-detection and fallback (#276)

`plugin_interactive_setup` (in `templates/github-actions/project-integration/plugin.sh`) attempts `gh` CLI auto-detection of GitHub Projects and falls back to manual prompts on failure. Pre-#276 the fallback could be skipped when `gh` failed under `set -e`; post-#276 every gh invocation goes through `_gh_run`, which always returns 0 and writes the first line of gh's stderr to `GH_LAST_ERROR_FILE_FILE` (a process-wide `mktemp`'d path) so the parent shell can surface it after the `$(...)` subshell returns.

```mermaid
sequenceDiagram
    actor User
    participant Setup as plugin_interactive_setup
    participant GhRun as _gh_run
    participant Gh as gh CLI
    participant Warn as print_warning / _print_gh_warning
    participant Manual as prompt_manual_project_config + prompt_manual_field_defaults

    User->>Setup: enter "y" to enable Project integration
    Setup->>Setup: prompt ERD_REF (read /dev/tty)
    Setup->>Setup: check_gh_available
    alt gh missing
        Setup->>Warn: print_info "gh CLI not found, using manual configuration"
        Setup->>Manual: invoke manual prompts
    else gh present
        Setup->>Warn: print_info "Detected gh CLI, attempting to fetch projects..."

        Setup->>GhRun: get_current_user
        GhRun->>Gh: gh api user --jq '.login' </dev/null 2>tmp
        alt gh ok
            Gh-->>GhRun: stdout=<login>, stderr empty, exit 0
            GhRun-->>Setup: stdout=<login>, GH_LAST_ERROR_FILE=""
        else gh fails
            Gh-->>GhRun: stdout="", stderr="gh: not logged in...", exit 1
            GhRun-->>Setup: stdout="", GH_LAST_ERROR_FILE="gh: not logged in..."
        end

        alt current_user empty
            Setup->>Warn: _print_gh_warning "Could not determine current user"
            Setup->>Manual: invoke manual prompts
        else current_user non-empty
            Setup->>GhRun: get_owner_projects current_user
            GhRun->>Gh: gh project list --owner <user> --format json
            Gh-->>GhRun: stdout=<JSON or empty>, GH_LAST_ERROR_FILE set if failed
            GhRun-->>Setup: stdout, GH_LAST_ERROR_FILE
            alt projects fetched and length > 0
                Setup->>Setup: use_gh_detection=true
                Setup->>Setup: select project (auto if 1, list if many)
                Setup->>GhRun: get_project_fields_detailed (GraphQL, fallback to basic on empty)
                GhRun->>Gh: gh api graphql -f ...
                Gh-->>GhRun: detailed JSON or empty
                GhRun-->>Setup: stdout, GH_LAST_ERROR_FILE
                Setup->>Setup: categorize + configure single-select / iteration / date fields
            else fetch failed or empty
                Setup->>Warn: _print_gh_warning "Could not fetch projects" or "No projects found"
                Setup->>Manual: invoke manual prompts
            end
        end
    end

    Setup->>Setup: prompt_label_routing_setup (if TTY)
    Setup-->>User: print_success "Project configuration collected"
```

## Continuous AI asset refresh with backups

```mermaid
sequenceDiagram
    participant Caller as Container start / current setup
    participant Refresh
    participant Source as Validated source/cache
    participant Project
    participant State as refresh-state.json
    Caller->>Refresh: Refresh explicit/discovered project root
    Refresh->>Project: Read project config/profile without replacing choices
    Refresh->>Source: Resolve distribution and default/custom catalog
    Refresh->>State: Validate prior installed provenance
    loop Active mappings and owned entries
        Refresh->>Source: Enumerate regular source/overlay candidate
        Refresh->>Project: Validate boundaries and compare current hash
        alt Currently distributed candidate
            Refresh->>Project: Verify private backup if live bytes differ
            Refresh->>Project: Recheck and install atomically (restore deleted targets)
            Refresh->>State: Advance only successful installed baseline
        else Proven unchanged upstream removal
            Refresh->>Project: Remove only this proven unchanged file
            Refresh->>State: Advance only successful installed baseline
        else Unknown sibling, edited obsolete file, unsafe path or failed backup
            Refresh-->>Caller: Warn and preserve with recovery hint
        end
    end
    Note over Refresh,Project: No destination directory mirror deletion
    Note over Refresh,State: Same SHA still reconciles, dry-run writes nothing
    Refresh-->>Caller: Nonfatal summary
```

Current setup bypasses an old installed updater. Proven unchanged legacy helpers migrate automatically from shipped-content evidence; unproven/edited helpers receive explicit migration guidance. Explicit add-module remains a scaffold extension, not automatic rerun behavior.

## `setup.sh --add-module` — incremental add to existing monorepo (#263)

Detects an existing `modules.json` in CWD (or accepts `--add-module` flag) and adds a single module. Idempotent against shared assets via marker-guarded blocks and JSON merge helpers.

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Common as scripts/lib/common.sh
    participant Lang as language plugin (e.g. python)
    participant Core as core plugin
    participant Mods as <project>/modules.json
    participant Root as <project>/ (root)
    participant SubDir as <project>/<module>/

    User->>Setup: ./setup.sh --add-module anisette --lang python -y
    Setup->>Common: detect_existing_monorepo(cwd)
    Common-->>Setup: ok (modules.json present)
    Setup->>Common: find_module_by_name(cwd, "anisette")
    Common-->>Setup: not present (else: prompt overwrite, FR-9)

    Setup->>Common: list_existing_compose_services(cwd) → diff vs AVAILABLE_SERVICES
    Note over Setup,Common: only un-added services are offered (FR-10)

    Setup->>Setup: load python plugin (+ any newly-selected service plugin)
    Setup->>Setup: execute_plugin_dockerfiles(root)
    Note over Setup,Root: python has no Dockerfile hook since #325, warns if the root Dockerfile predates the mise layer
    Setup->>Lang: plugin_post_copy_shared(root) [idempotent: merge / marker-guards / mise_toml_ensure skip existing keys]

    Setup->>SubDir: mkdir -p root/anisette
    Setup->>Lang: plugin_post_copy_module(root/anisette, "anisette")
    Lang->>SubDir: write pyproject.toml, ruff.toml, src/anisette/__init__.py, tests/

    Setup->>Core: plugin_post_copy(root) [monorepo branch]
    Core->>Common: add_module_entry(cwd, "anisette", "python", services=[])
    Common->>Mods: append entry (atomic jq | mv), on duplicate → exit 2 (caller handled above)
    Core->>SubDir: write root/anisette/CLAUDE.md from template (skip if exists, unless --overwrite)

    Setup->>Common: update_gitignore(root) [idempotent]
    Setup-->>User: completion: "Module 'anisette' added" + "run mise install (or rebuild)"
```

## `setup.sh --zed` — optional Zed editor assets (#323)

Additive editor flavor. One global (`ZED_ENABLED`) and one shared helper
(`common.sh::apply_zed_assets`) carry all four artifact groups;
`customizations.vscode` is always kept, so the generated project opens in
either editor. Without `--zed` every `apply_zed_assets` call returns at its
first guard and `merge_devcontainer_json` emits no `zed` key, so the generated
tree is byte-identical to a pre-#323 run. The helper's internal branching is
in `docs/design/#323/flowchart.md`.

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Core as core plugin
    participant Lang as language plugin (e.g. rust)
    participant Svc as service plugin (e.g. postgresql)
    participant Common as common.sh::apply_zed_assets
    participant DC as <target>/.devcontainer/devcontainer.json
    participant Zed as <target>/.zed/settings.json
    participant Manifest as <target>/.tarnished-manifest.json

    User->>Setup: ./setup.sh --lang rust --postgresql --zed -y
    Setup->>Setup: parse_arguments → ZED_ENABLED=true
    Note over Setup: interactive runs instead ask<br/>"Enable Zed editor support? (y/n) [n]",<br/>add-module mode warns and forces false
    Setup->>Setup: Setup Configuration prints "Zed: true"

    Setup->>Core: plugin_copy(root)
    Core->>DC: copy templates/core/.devcontainer verbatim (no zed keys)

    Setup->>Core: plugin_post_copy(root)
    Core->>Common: apply_zed_assets(root, templates/core)
    Common->>DC: merge_devcontainer_json(DC, core/.zed/devcontainer.json)
    Note over Common,DC: customizations.zed.extensions = ["dockerfile"],<br/>customizations.vscode untouched
    Common->>Zed: .zed/ absent → mkdir + copy_with_confirm(core/.zed/settings.json)

    Setup->>Lang: plugin_post_copy_shared(root)
    Lang->>DC: merge_devcontainer_json(DC, rust/.devcontainer/devcontainer.json)
    Note over Lang,DC: vscode extensions/settings (no features since #325),<br/>base customizations.zed carried through
    Lang->>Common: apply_zed_assets(root, templates/languages/rust)
    Common->>DC: merge → zed.extensions = ["dockerfile","toml"] (unique union)
    Common->>Zed: merge_zed_settings(Zed, rust/.zed/settings.json)
    Note over Common,Zed: + lsp.rust-analyzer.check.command=clippy<br/>+ file_scan_exclusions ∪ ["**/target"]

    Setup->>Svc: plugin_post_copy(root)
    Svc->>Common: apply_zed_assets(root, templates/services/postgresql)
    Common->>DC: merge → zed.extensions ∪ ["sql"]

    Setup->>Setup: infer_scaffold_options(root) → zed_enabled: true<br/>(evidence = .zed/settings.json exists)
    Setup->>Manifest: manifest_write(scaffold_options incl. zed_enabled)
    Note over Setup,Manifest: .zed/settings.json itself is NOT hashed —<br/>outside _manifest_path_eligible, so --upgrade/--prune never touch it
    Setup-->>User: Next steps — VS Code steps + "Or open in Zed" steps
```

A merge failure on either file is non-fatal: the helper removes its temp file,
emits `print_warning` and leaves the live file untouched, then returns 0.

## Devcontainer JSON merge with comment normalization

Language and service plugins call `merge_devcontainer_json` to merge VS Code
extensions, VS Code settings, and — when either side declares it (#323) — the
`customizations.zed` subtree. Since #325 no shipped overlay carries
`features`; other top-level keys (including a developer's own `features`) are
deep-merged and emitted only when present. The helper
accepts strict JSON or comment-bearing devcontainer JSON, normalizes comments
away in private temp files, and then runs the structural `jq` merge. The output
is strict JSON.

```mermaid
sequenceDiagram
    participant Plugin as template plugin
    participant Common as scripts/lib/common.sh
    participant Base as target .devcontainer/devcontainer.json
    participant Overlay as plugin .devcontainer/devcontainer.json
    participant Jq as jq
    participant Out as caller temp output

    Plugin->>Common: merge_devcontainer_json(base, overlay, output)
    Common->>Base: read base file
    Common->>Common: _jsonc_to_json_file(base, base_tmp)
    alt base invalid after comment stripping
        Common-->>Plugin: print_error + return 1
    else base ok
        Common->>Overlay: read overlay file
        Common->>Common: _jsonc_to_json_file(overlay, overlay_tmp)
        alt overlay invalid after comment stripping
            Common-->>Plugin: cleanup temps/output + return 1
        else overlay ok
            Common->>Jq: jq -s devcontainer merge base_tmp overlay_tmp
            alt jq merge fails
                Jq-->>Common: non-zero
                Common-->>Plugin: cleanup temps/output + return 1
            else merge ok
                Jq-->>Out: strict merged JSON
                Common-->>Plugin: return 0
                Plugin->>Base: mv output to target devcontainer
            end
        end
    end
```
