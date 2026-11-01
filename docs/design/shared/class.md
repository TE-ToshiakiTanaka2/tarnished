# Class Diagram (Project-wide)

Cumulative class/type diagram for the Rust CLI, shell maintenance metadata, and the generated install contract. Snapshot — overwritten on every `/design` (NFR-1).

## Configuration types

```mermaid
classDiagram
    class ProjectConfig {
        +default_project: ProjectReference
        +field_defaults: HashMap~String, String~
        +schedule_defaults: Option~ScheduleDefaults~
        +pr_status: Option~PrStatusConfig~
        +label_projects: HashMap~String, LabelProjectConfig~
        +load_with_path(path: Option~PathBuf~) ProjectConfig
        +get_field_default(field: str) Option~String~
        +get_pr_open_status() Option~String~
    }

    class ProjectReference {
        +owner: String
        +number: u32
    }

    class LabelProjectConfig {
        +owner: String
        +number: u32
        +field_defaults: HashMap~String, String~
    }

    class ScheduleDefaults {
        +iteration: Option~String~
        +start: Option~String~
        +end: Option~String~
    }

    class PrStatusConfig {
        +on_open: Option~String~
    }

    class TagConfig {
        +versioning: Option~VersioningSection~
        +default_bump: Option~BumpType~
    }

    class VersioningSection {
        +branch_prefixes: BranchPrefixes
    }

    class BranchPrefixes {
        +major: Vec~String~
        +minor: Vec~String~
        +patch: Vec~String~
    }

    class BumpType {
        <<enum>>
        Major
        Minor
        Patch
        Rc
    }

    ProjectConfig "1" --> "1" ProjectReference : default_project
    ProjectConfig "1" --> "0..*" LabelProjectConfig : label_projects
    ProjectConfig "1" --> "0..1" ScheduleDefaults : schedule_defaults
    ProjectConfig "1" --> "0..1" PrStatusConfig : pr_status
    TagConfig "1" --> "0..1" VersioningSection : versioning
    VersioningSection "1" --> "1" BranchPrefixes : branch_prefixes
    TagConfig --> BumpType : default_bump
```

## GitHub types

```mermaid
classDiagram
    class GetIssueResponse {
        +node_id: String
        +number: u64
        +title: String
        +body: Option~String~
        +html_url: String
        +labels: Vec~IssueLabel~
    }

    class IssueLabel {
        +name: String
    }

    class ProjectV2 {
        +id: String
        +number: u32
        +title: String
        +fields: Vec~ProjectField~
    }

    class ProjectField {
        +id: String
        +name: String
        +data_type: String
    }

    GetIssueResponse "1" --> "0..*" IssueLabel : labels
    ProjectV2 "1" --> "0..*" ProjectField : fields
```

## CLI command + clients

```mermaid
classDiagram
    class IssueCommands {
        +execute_link(config, number, overrides) Result
        -link_issue_to_project(client, config, project_config, node_id) Result
    }

    class GitHubClient {
        +get_issue(owner, repo, number) GetIssueResponse
        +get_project(owner, number) ProjectV2
        +add_issue_to_project_with_defaults(project, node_id, project_config, verbose) String
    }

    class Config {
        +verbose: bool
        +project_config_path: Option~PathBuf~
    }

    IssueCommands --> GitHubClient : uses
    IssueCommands --> ProjectConfig : reads via Config
    IssueCommands --> Config : injected
    GitHubClient --> GetIssueResponse : returns
    GitHubClient --> ProjectV2 : returns
```

## Foundation ownership metadata

```mermaid
classDiagram
    class DownstreamProject
    class ManifestV2 {
        +scaffold_options
        +files: installed helper hashes
    }
    class RefreshConfig {
        +managed_paths
        +use_default_managed_paths
    }
    class RefreshState {
        +schema_version
    }
    class ZedProjectSettings {
        +terminal_shell
        +file_scan_exclusions
        +languages
        +lsp
    }
    DownstreamProject --> ZedProjectSettings : owns outright (#323)
    class MiseConfig {
        +tools
        +env
        +settings
    }
    DownstreamProject --> MiseConfig : owns outright (#325)
    class ReplacementBackup {
        +run_directory
        +original_relative_path
        +verified_original_bytes
    }
    DownstreamProject --> ReplacementBackup : retains privately
    class InstalledAsset {
        +destination
        +mapping_src
        +mapping_dst
        +repo_url
        +installed_hash
        +origin
        +commit
    }
    DownstreamProject --> ManifestV2
    DownstreamProject --> RefreshConfig : owns choices
    DownstreamProject --> RefreshState
    RefreshState "1" --> "0..*" InstalledAsset
    RefreshConfig --> InstalledAsset : constrains active mappings
```

## Generated install contract (#325)

Shell-side structure of the three install layers. "Classes" are files; methods
are their entry functions. Arrows read "uses" unless labelled. File mapping:
`CommonSh` = `scripts/lib/common.sh`; `CorePlugin`/`ClaudePlugin`/`CodexPlugin`
= `templates/{core,claude,codex}/plugin.sh`; `LanguagePlugin` =
`templates/languages/{python,node,rust,go,deno}/plugin.sh`; `LatexPlugin` =
`templates/languages/latex/plugin.sh`; `ServicePlugin` =
`templates/services/{postgresql,mysql}/plugin.sh`; `DockerfileDev`,
`MiseConfig`, `PostSh`, `ClaudeSettings` = the generated
`docker/Dockerfile.dev`, `mise.toml`, `.devcontainer/scripts/post.sh`,
`.claude/settings.json`; `Setup*` / `NpmGlobalCli` = the
`.devcontainer/scripts/*.sh` helpers of the same names.

```mermaid
classDiagram
    class CommonSh {
        <<library>>
        +mise_toml_ensure(file, section, key, value) int
        +dockerfile_add_os_packages(dockerfile, block_id, packages) int
        +post_sh_add_block(post_sh, marker, before_markers) int
        +merge_devcontainer_json(base, overlay, out) int
        +merge_claude_settings(base, overlay, out) int
    }
    class CorePlugin {
        <<plugin>>
        +plugin_copy(target)
        +plugin_post_copy(target)
    }
    class LanguagePlugin {
        <<plugin>>
        +plugin_post_copy_shared(root)
        +plugin_post_copy_module(dir, name)
    }
    class LatexPlugin {
        <<plugin>>
        +plugin_dockerfile(target)
    }
    class ServicePlugin {
        <<plugin>>
        +plugin_dockerfile(target)
        +plugin_post_copy(target)
    }
    class ClaudePlugin {
        <<plugin>>
        +plugin_post_copy(target)
    }
    class CodexPlugin {
        <<plugin>>
        +plugin_post_copy(target)
    }
    class DockerfileDev {
        <<generated file>>
        +ARG MISE_VERSION
        +root OS packages
        +SHELL anchor
        +mise runtime layer
    }
    class MiseConfig {
        <<generated file>>
        +tools
        +env
    }
    class PostSh {
        <<generated file>>
        +mise Runtime Setup
        +Claude Code Setup
        +Codex CLI Setup
        +Claude Code Plugin Setup
    }
    class SetupMise {
        <<helper>>
        +setup_mise()
    }
    class NpmGlobalCli {
        <<library>>
        +install_npm_global_cli(name, pkg, cmd)
    }
    class SetupClaude {
        <<helper>>
        +setup_claude()
    }
    class SetupCodex {
        <<helper>>
        +setup_codex()
    }
    class SetupPlugins {
        <<helper>>
        +setup_plugins()
        +is_claude_authenticated()
    }
    class ClaudeSettings {
        <<generated file>>
        +extraKnownMarketplaces
        +enabledPlugins
    }

    CorePlugin --> CommonSh
    LanguagePlugin --> CommonSh
    ServicePlugin --> CommonSh
    ClaudePlugin --> CommonSh
    CodexPlugin --> CommonSh
    CorePlugin --> MiseConfig : seeds node
    LanguagePlugin --> MiseConfig : mise_toml_ensure
    LatexPlugin --> DockerfileDev : TeX Live block
    ServicePlugin --> DockerfileDev : os-packages block
    CorePlugin --> PostSh : mise + Claude blocks
    CodexPlugin --> PostSh : Codex block before plugins
    ClaudePlugin --> PostSh : plugin block
    ClaudePlugin --> ClaudeSettings : merge keeps plugin keys
    DockerfileDev --> MiseConfig : COPY + mise install
    PostSh --> SetupMise
    PostSh --> SetupClaude
    PostSh --> SetupCodex
    PostSh --> SetupPlugins
    SetupMise --> MiseConfig : mise install
    SetupClaude --> NpmGlobalCli
    SetupCodex --> NpmGlobalCli
    SetupPlugins --> ClaudeSettings : reads enabledPlugins
```

## Notes

- `LabelProjectConfig` keys (in `ProjectConfig.label_projects`) are issue-label names; values are independent project + field defaults (#230).
- `BranchPrefixes` is the canonical internal struct; `VersioningSection` (Format B) deserializes directly into it, while a custom deserializer collapses Format A (`branches: [{prefix, bump}]`) into the same shape (#228).
- `BumpType::Rc` is the default when no branch prefix matches.
- `IssueCommands::link_issue_to_project` accepts a `ProjectConfig` so it can be reused for both default and label-routed links (#230 refactor).
- `MiseConfig` (`<project>/mise.toml`, #325) has the same ownership shape as `ZedProjectSettings`: seeded at scaffold time (core template + `mise_toml_ensure` entries) and then developer-owned, with no edge to `ManifestV2`, `RefreshConfig` or `RefreshState`. The helper scripts that consume it (`setup_mise.sh` etc.) *are* manifest-eligible; the file they read is not.
- In the install-contract diagram, `npm_global_cli.sh` is a library sourced by two entry helpers, not a `post.sh` entry itself; `post.sh` order (mise → Claude Code → Codex → plugins) is enforced by `post_sh_add_block`, not by plugin load order.
- `ZedProjectSettings` (`<project>/.zed/settings.json`, #323) is drawn as a direct child of `DownstreamProject` with no edge to `ManifestV2`, `RefreshConfig` or `RefreshState`: it is written once at scaffold time by `apply_zed_assets` and then wholly developer-owned — not an AI asset (no `refresh.json` mapping) and outside `_manifest_path_eligible`, so no maintenance path reads, rewrites or prunes it. The absence of those edges is the ownership statement.
