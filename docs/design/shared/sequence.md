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

## devcontainer plugin install (#249, #255)

```mermaid
sequenceDiagram
    participant Container as devcontainer onCreate
    participant Post as post.sh (set -e)
    participant Setup as setup_plugins.sh
    participant Claude as claude CLI

    Container->>Post: source post.sh
    Post->>Setup: source setup_plugins.sh
    Setup->>Setup: ensure_claude_marketplace()
    Setup->>Claude: claude plugins marketplace add anthropics/claude-plugins-official
    alt marketplace registration ok
        Claude-->>Setup: ok
    else registration fails
        Claude-->>Setup: error
        Setup->>Post: warning + return 0
        Note over Post: set -e is respected; post.sh continues
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
    Post-->>Container: post-create complete
```

## Claude Code skill workflow (`/issue` → `/design` → `/implement` → `/review` → `/pr`)

```mermaid
sequenceDiagram
    actor Dev
    participant Issue as /issue
    participant Design as /design
    participant Implement as /implement
    participant Review as /review
    participant PR as /pr
    participant Docs as docs/design/
    participant GH as GitHub

    Dev->>Issue: /issue
    Issue->>Issue: erd:brainstorm + erd:estimate
    Issue->>GH: gh issue create + project field set
    Issue-->>Dev: Issue #N

    Dev->>Design: /design N
    Design->>Docs: read shared/* (cumulative truth, #257)
    Design->>Docs: write #N/design.md (delta, self-contained)
    Design->>Docs: write #N/api-spec.md, #N/workflow.md, #N/flowchart.md as applicable
    Design->>Docs: regenerate shared/* as snapshot (NFR-1)
    Design-->>Dev: branch + artifacts

    Dev->>Implement: /implement N
    Implement->>Docs: read shared/* AND #N/* (constant cost wrt issue count, #257)
    Implement->>Implement: erd:index-repo, erd:implement, erd:build, erd:test, erd:analyze, erd:improve
    Implement-->>Dev: code + commits

    Dev->>Review: /review (optional)
    Review-->>Dev: review notes

    Dev->>PR: /pr
    PR->>GH: gh pr create
    PR-->>Dev: PR URL
```

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

## `setup.sh --create-manifest` — bootstrap a manifest for an existing project (#265)

One-shot mode that scans the current state of an already-scaffolded project and writes `.tarnished-manifest.json` (root + per-module if monorepo). Required before the first `--upgrade` on legacy projects. Idempotent — safe to re-run.

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Common as scripts/lib/common.sh
    participant Manifest as scripts/lib/manifest.sh
    participant Target as <project>/
    participant ManFile as <project>/.tarnished-manifest.json
    participant ModSubDir as <project>/<module>/

    User->>Setup: ./setup.sh --create-manifest --from-version v0.0.74 -y
    Setup->>Setup: parse_arguments → CREATE_MANIFEST_MODE=true, FROM_VERSION="v0.0.74"
    Setup->>Common: detect_existing_monorepo(target_dir)
    alt monorepo target (modules.json present)
        Common-->>Setup: yes
        Setup->>Manifest: manifest_walk_directory(target_dir)
        Note over Manifest,Target: skip MANIFEST_EXCLUDE_GLOBS<br/>skip <module>/ subtrees<br/>hash every other file
        Manifest-->>Setup: <rel_path, sha> lines (root scope)
        Setup->>Manifest: manifest_write(target_dir, FROM_VERSION, "", scaffold_options{monorepo: true})
        Manifest->>ManFile: atomic write (tmp + mv)

        loop each module in modules.json
            Setup->>Manifest: manifest_walk_directory(target_dir/<module>)
            Manifest-->>Setup: <rel_path, sha> lines (module scope)
            Setup->>Manifest: manifest_write(target_dir/<module>, FROM_VERSION, "", scaffold_options{monorepo: false, languages: [<module_lang>]})
            Manifest->>ModSubDir: <module>/.tarnished-manifest.json
        end
    else single-mode target
        Common-->>Setup: no
        Setup->>Manifest: manifest_walk_directory(target_dir)
        Manifest-->>Setup: <rel_path, sha> lines
        Setup->>Manifest: manifest_write(target_dir, FROM_VERSION, "", scaffold_options{monorepo: false})
        Manifest->>ManFile: atomic write
    end

    Setup-->>User: completion: "Manifest created"
```

## `setup.sh --upgrade` — refresh tracked files of an existing project (#265)

The core upgrade flow. Loads the existing manifest, clones upstream tarnished at `--target-version`, runs the same plugin pipeline against a per-scope staging directory with `MANIFEST_RECORDING` enabled, then dispatches the FR-4 lifecycle decision per file. The 8-case `manifest_decide` state machine is detailed in `docs/design/#265/flowchart.md`. Only verbatim-copy files participate in tracking; merge logic (`update_gitignore`, JSON merges) is re-applied directly to the target by re-running `plugin_post_copy` (FR-5).

```mermaid
sequenceDiagram
    actor User
    participant Setup as setup.sh
    participant Common as scripts/lib/common.sh
    participant Manifest as scripts/lib/manifest.sh
    participant Git as git
    participant Tmp as TMP_DIR (cloned tarnished)
    participant Plugins as plugin pipeline
    participant Stage as STAGING_DIR
    participant Target as <project>/
    participant ManFile as .tarnished-manifest.json

    User->>Setup: ./setup.sh --upgrade --target-version v0.0.76 -y
    Setup->>Setup: parse_arguments → UPGRADE_MODE=true, TARGET_VERSION="v0.0.76"
    Setup->>Manifest: manifest_exists(target_dir)
    alt manifest absent
        Manifest-->>Setup: no
        Setup-->>User: error 1 — "run --create-manifest first"
    else manifest present
        Manifest-->>Setup: yes
        Setup->>Setup: check_git_clean(target_dir)
        alt dirty + no --force
            Setup-->>User: error 1 — "commit/stash or --force"
        else clean OR --force
            Setup->>Manifest: manifest_read(target_dir)
            Manifest-->>Setup: OLD_MANIFEST {tarnished_version, scaffold_options, files}
            Setup->>Setup: compute_upgrade_scopes (--shared-only / --module filtering)

            Setup->>Git: clone --depth 1 --branch <ref> upstream/tarnished
            Git->>Tmp: TMP_DIR populated
            Tmp-->>Setup: ok

            loop each scope (shared, then per-module)
                Setup->>Manifest: manifest_recording_start(STAGING_DIR_<scope>)
                Setup->>Plugins: execute_plugin_copies(STAGING_DIR_<scope>)
                Setup->>Plugins: execute_plugin_dockerfiles(STAGING_DIR_<scope>)
                Setup->>Plugins: execute_plugin_post_copies(STAGING_DIR_<scope>)
                Note over Plugins,Stage: copy_with_confirm intercept records<br/>(rel_path, sha256) into MANIFEST_TRACKED
                Setup->>Manifest: manifest_recording_stop
                Note over Setup,Manifest: NEW_HASHES := MANIFEST_TRACKED snapshot

                loop each path in OLD_MANIFEST.files ∪ NEW_HASHES
                    Setup->>Common: sha256_file(target/path)
                    Common-->>Setup: current_h (or "" if missing)
                    Setup->>Manifest: manifest_decide(old_h, current_h, new_h)
                    Manifest-->>Setup: decision (NOOP/UPDATE/SKIP_EDITED/NEW/...)
                    Setup->>Manifest: manifest_apply(decision, stage_path, target_path)
                    alt --dry-run
                        Note over Manifest,Target: skip mutation; tally only
                    else live run
                        Manifest->>Target: cp / rm per decision
                    end
                end

                Setup->>Plugins: rerun plugin_post_copy on Target (FR-5: merge logic)
                Note over Plugins,Target: idempotent re-application of<br/>update_gitignore / merge_devcontainer_json /<br/>merge_claude_settings_hooks
                Setup->>Manifest: manifest_write(scope_root, TARGET_VERSION, target_commit, scaffold_options)
                alt --dry-run
                    Note over Manifest,ManFile: skip write
                else live run
                    Manifest->>ManFile: update manifest with new version + hashes
                end
            end

            Setup->>Manifest: manifest_summary_print(old, new)
            Manifest-->>User: Updated/Skipped/New/Removed/...  summary
        end
    end
```

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
