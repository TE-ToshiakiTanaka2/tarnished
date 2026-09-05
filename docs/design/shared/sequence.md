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

## devcontainer plugin install (#249, #255, #273)

`setup_plugins.sh` is sourced by `post.sh` (which runs under `set -e`) and is contractually required to `return 0`. The flow has three early-exit gates before any `claude plugins …` invocation: (a) the `claude` CLI must be present, (b) the user must be authenticated (`~/.claude/.credentials.json` exists and is non-empty — added in #273), (c) the marketplace must register successfully. Only after all three pass does the per-plugin install loop run, and even then each install failure is isolated by `try_install_plugin` so siblings continue.

```mermaid
sequenceDiagram
    participant Container as devcontainer onCreate
    participant Post as post.sh (set -e)
    participant Setup as setup_plugins.sh
    participant Creds as ~/.claude/.credentials.json
    participant Claude as claude CLI

    Container->>Post: source post.sh
    Post->>Setup: source setup_plugins.sh; setup_plugins
    Setup->>Setup: command -v claude
    alt claude missing
        Setup-->>Post: warning + return 0
    else claude present
        Setup->>Setup: is_claude_authenticated()
        Setup->>Creds: [[ -s ~/.claude/.credentials.json ]]
        alt credentials missing or empty (first run, #273)
            Creds-->>Setup: false
            Setup-->>Post: guidance ("run claude to log in,<br/>then re-run setup_plugins.sh") + return 0
            Note over Post: set -e respected; post.sh proceeds to setup_codex
        else credentials present
            Creds-->>Setup: true
            Setup->>Setup: ensure_claude_marketplace()
            Setup->>Claude: claude plugins marketplace add anthropics/claude-plugins-official
            alt registration ok
                Claude-->>Setup: ok
            else registration fails
                Claude-->>Setup: error
                Setup-->>Post: warning + return 0
                Note over Post: set -e respected; post.sh continues
            end

            Setup->>Claude: claude plugins list (if-guarded, #273 review)
            alt query ok
                Claude-->>Setup: plugins_output
            else query fails
                Claude-->>Setup: error
                Setup-->>Post: warning + return 0
                Note over Post: set -e respected; post.sh continues
            end

            loop each plugin in [context7, serena, optionally playwright]
                Setup->>Setup: try_install_plugin(name)
                Setup->>Claude: claude plugins install <name>@claude-plugins-official -s project
                alt install ok
                    Claude-->>Setup: installed
                else install fails
                    Claude-->>Setup: error
                    Note over Setup: log warning, continue with next plugin
                end
            end

            Setup-->>Post: return 0
        end
    end
    Post-->>Container: post-create complete
```

The `is_claude_authenticated` gate (#273) is identical in the workspace `setup_plugins.sh` and the `templates/claude/.devcontainer/scripts/setup_plugins.sh` template variant — those two files are now structurally aligned (the template variant also adopted `ensure_claude_marketplace` + `try_install_plugin` from the workspace variant in #273), mirroring the workspace-Codex dogfooding convention from #261.

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
    Migration->>Issue: read each design.md (chronological; api-spec/class/sequence opportunistically)
    Issue-->>Migration: cumulative content
    Migration->>Migration: synthesize architecture, data-model, api-spec, class, sequence
    Migration->>Shared: write 5 shared files
    Note over Migration,Issue: existing #{old}/ files are PRESERVED unchanged (FR-5)
    Migration-->>Design: shared/ seeded; resume normal flow
```

## Codex CLI: install in devcontainer + `/review` execution (#261)

Two phases: (a) `setup_codex` runs once during devcontainer post-create to make `codex` available on `$PATH`; (b) every subsequent `/review` invocation streams a prompt to `codex exec` and captures the result. Phase (a) is system-wide for any project that ships `setup_codex.sh` (workspace + downstream Codex-flavor projects); phase (b) is invoked per `/review` call. The decision tree inside `setup_codex` itself lives in `docs/design/#261/flowchart.md`.

```mermaid
sequenceDiagram
    participant Container as devcontainer onCreate
    participant Post as post.sh (set -e)
    participant SetupCodex as setup_codex.sh
    participant Npm as npm
    participant Codex as codex CLI

    Container->>Post: source post.sh
    Note over Post: ... earlier blocks (git/SSH/Rust/codespell/setup_plugins) ...
    Post->>SetupCodex: source setup_codex.sh; setup_codex
    alt npm missing
        SetupCodex-->>Post: [WARN] + return 0
    else codex already installed
        SetupCodex->>Codex: codex --version
        Codex-->>SetupCodex: <version>
        SetupCodex-->>Post: log + return 0
    else needs install
        SetupCodex->>Npm: npm root -g
        Npm-->>SetupCodex: <prefix or empty>
        SetupCodex->>SetupCodex: decide sudo (see flowchart.md)
        SetupCodex->>Npm: [sudo -E] npm install -g @openai/codex
        alt install ok
            Npm-->>SetupCodex: installed
        else install fails
            Npm-->>SetupCodex: error
            Note over SetupCodex: [WARN] + manual recovery hint
        end
        SetupCodex-->>Post: return 0
    end
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
        Claude->>Claude: apply fixes; commit
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
    Note over Setup,Root: appends marker-guarded python + node toolchain blocks (FR-5)

    Setup->>Setup: execute_plugin_post_copies (monorepo mode)
    loop for each loaded plugin
        alt plugin in templates/languages/* (e.g. python)
            Setup->>Lang: plugin_post_copy_shared(root)
            Lang->>Root: patch .devcontainer/devcontainer.json (idempotent merge)
            Lang->>Root: patch .claude/settings.json (idempotent merge)
            Lang->>Root: append marker-guarded post.sh language block
            loop for each module with language == python (e.g. jing)
                Setup->>Lang: plugin_post_copy_module(root/jing, "jing")
                Lang->>SubDir: write pyproject.toml, ruff.toml, src/jing/__init__.py, tests/
            end
        else plugin in templates/services/* (e.g. postgres) or core/claude/codex/github-actions
            Setup->>Svc: plugin_post_copy(root)
            Svc->>Root: merge docker-compose.yml service "<project>-db" (project-name prefix; existing convention)
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
    Note over Setup,Project: No real-target post-copy; dry-run writes nothing
```

## `setup.sh` remote bootstrap (`curl | bash`) (#276)

The primary distribution path. The bootstrap block at `setup.sh:29-69` detects pipe execution, clones the upstream repo into a temp dir, then `exec`s the local copy. The `< /dev/null` on the `exec` line is what keeps the outer curl from emitting a spurious `curl: (23)` to the user terminal.

```mermaid
sequenceDiagram
    actor User
    participant Curl as curl
    participant BootBash as bash (bootstrap; reads script from curl's stdout)
    participant Git as git
    participant Tmp as $BOOTSTRAP_TEMP_DIR
    participant NewBash as bash (exec'd; reads script from disk)

    User->>Curl: curl -fsSL .../setup.sh | bash
    Curl->>BootBash: stream setup.sh bytes
    BootBash->>BootBash: detect [[ -z BASH_SOURCE[0] || == "-" || ! -f ... ]]
    BootBash->>Git: git clone --depth 1 --branch develop ... $BOOTSTRAP_TEMP_DIR
    Git->>Tmp: populated
    Tmp-->>BootBash: ok

    Note over BootBash,NewBash: exec replaces the process image; pre-#276 the<br/>outer curl pipe was inherited and curl hit EPIPE,<br/>printing "curl: (23) Failure writing output to destination"<br/>at a non-deterministic point during the rest of the setup.

    BootBash->>NewBash: exec bash "$BOOTSTRAP_TEMP_DIR/setup.sh" "$@" < /dev/null
    Note over Curl,NewBash: stdin redirected to /dev/null; the curl pipe is<br/>NOT inherited; curl exits cleanly with no terminal noise.

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
                Setup->>GhRun: get_project_fields_detailed (GraphQL; fallback to basic on empty)
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

## Safe continuous AI asset refresh

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
        alt Safe new/update/proven unchanged upstream removal
            Refresh->>Project: Apply one file atomically
            Refresh->>State: Advance only successful installed baseline
        else Unknown/edited/deleted/unsafe
            Refresh-->>Caller: Warn and preserve with recovery hint
        end
    end
    Note over Refresh,Project: No destination directory mirror deletion
    Note over Refresh,State: Same SHA still reconciles; dry-run writes nothing
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
    Note over Setup,Root: marker-guard skips re-append if python toolchain block already present
    Setup->>Lang: plugin_post_copy_shared(root) [idempotent: merge / marker-guards skip on re-run]

    Setup->>SubDir: mkdir -p root/anisette
    Setup->>Lang: plugin_post_copy_module(root/anisette, "anisette")
    Lang->>SubDir: write pyproject.toml, ruff.toml, src/anisette/__init__.py, tests/

    Setup->>Core: plugin_post_copy(root) [monorepo branch]
    Core->>Common: add_module_entry(cwd, "anisette", "python", services=[])
    Common->>Mods: append entry (atomic jq | mv); on duplicate → exit 2 (caller handled above)
    Core->>SubDir: write root/anisette/CLAUDE.md from template (skip if exists, unless --overwrite)

    Setup->>Common: update_gitignore(root) [idempotent]
    Setup-->>User: completion: "Module 'anisette' added"
```

## Devcontainer JSON merge with comment normalization

Language and service plugins call `merge_devcontainer_json` to merge
devcontainer features, VS Code extensions, and VS Code settings. The helper
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
