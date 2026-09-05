# Class Diagram (Project-wide)

Cumulative class/type diagram for the Rust CLI and shell maintenance metadata. Snapshot — overwritten on every `/design` (NFR-1).

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

## Notes

- `LabelProjectConfig` keys (in `ProjectConfig.label_projects`) are issue-label names; values are independent project + field defaults (#230).
- `BranchPrefixes` is the canonical internal struct; `VersioningSection` (Format B) deserializes directly into it, while a custom deserializer collapses Format A (`branches: [{prefix, bump}]`) into the same shape (#228).
- `BumpType::Rc` is the default when no branch prefix matches.
- `IssueCommands::link_issue_to_project` accepts a `ProjectConfig` so it can be reused for both default and label-routed links (#230 refactor).
