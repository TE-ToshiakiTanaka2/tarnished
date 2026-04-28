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
