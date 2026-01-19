# Claude Command: Issue

This command helps you review development requests and create organized GitHub Issues with proper requirements and work items for the Devcontainer boilerplate project.

**Environment**: Devcontainer Boilerplate

## Usage

To create a GitHub Issue from a development request:

```
/issue
```

## What This Command Does

This command orchestrates a structured workflow by delegating to SuperClaude commands:

1. **Confirm the user's request** - Acknowledge and understand what the user wants to accomplish
2. **Execute /sc:brainstorm** - Delegate to brainstorming skill for requirements discovery through Socratic dialogue:
   - Discover hidden requirements and edge cases
   - Clarify ambiguous points through interactive questioning
   - Identify potential challenges and considerations
   - Build comprehensive understanding of the request
3. **Summarize brainstorming results** - Organize and consolidate the insights gathered from the brainstorming session into clear requirements
4. **Present implementation methods** - Propose necessary implementation approaches for the request
5. **Identify work items** - Organize implementation methods and break down into main tasks and subtasks if necessary
6. **Create GitHub Issue** - Delegate to `/sc:git` for issue creation with an **English title** and Japanese description. If subtasks exist, create the main issue first, then add subtasks as children
7. **Add documentation comment** - For complex issues, add a comment with documentation notes (design overview, implementation plan, decisions) that subsequent commands can use to create actual documentation files
8. **Configure issue settings** - Set the following after issue creation:
   - **Labels** - Assign based on work type:
     - `feature` - for new feature additions
     - `patch` - for small changes and improvements
     - `bugfix` - for bug fixes
     - `refactor` - for code refactoring
     - `documentation` - for documentation modifications
   - **Milestone** - Assign based on target area:
     - `core` - Docker/Devcontainer infrastructure, setup.sh, common settings
     - `github-actions` - CI/CD workflows
     - `claude-code` - Claude Code settings, commands, skills
     - `python` - Python language template
     - `node` - Node.js/TypeScript template
     - `rust` - Rust template
     - `deno` - Deno template
   - **Assignee** - Assign to the user by default unless otherwise specified
9. **Return issue number** - Provide the created issue number (parent issue number if subtasks exist)
10. **🔴 CRITICAL: Configure Project fields** - This step is **MANDATORY** when `.github/project-automation.yml` exists:
    - Wait for `project-automation` workflow to complete (max 30 seconds polling)
    - Retrieve Project field information via GraphQL
    - Analyze issue content to determine appropriate values for Size, Priority, etc.
    - Set field values automatically without user confirmation
    - Report the configured field values
    - **Skip this step ONLY if** `.github/project-automation.yml` does not exist

> ⚠️ **IMPORTANT**: Steps 1-9 are NOT complete without Step 10. Always check for `project-automation.yml` and configure Project fields if it exists.

## SuperClaude Command Delegation

| Phase                  | Delegated Command | Purpose                                            |
| ---------------------- | ----------------- | -------------------------------------------------- |
| Requirements Discovery | `/sc:brainstorm`  | Interactive Socratic dialogue for deep exploration |
| Issue Creation         | `/sc:git`         | Git and GitHub operations                          |

## Important: Scope Limitations

**This command is responsible ONLY for creating GitHub Issues.** The scope of this command includes:

- Understanding and analyzing the user's request
- Executing /sc:brainstorm to discover and clarify requirements
- Organizing requirements and specifications
- Creating well-structured GitHub Issues
- Adding documentation notes as issue comments (for subsequent commands to use)
- Configuring issue settings (labels, milestone, assignee)
- Configuring Project custom fields (Size, Priority) based on issue analysis
- Returning the issue number

**This command does NOT include:**

- Implementing the requested features or fixes
- Writing any code beyond the issue creation
- Making changes to the project files
- Running tests or builds

After the issue is created and the issue number is returned, the command execution is complete. Any implementation work should be done separately after the issue creation, either by the user or through a different command/workflow.

## Classification System

### Milestones (Target Area)

Issues are categorized by milestone based on the target area:

| Milestone | Description |
|-----------|-------------|
| `core` | Docker/Devcontainer infrastructure, setup.sh, common settings |
| `github-actions` | CI/CD workflows |
| `claude-code` | Claude Code settings, commands, skills |
| `python` | Python language template |
| `node` | Node.js/TypeScript template |
| `rust` | Rust template |
| `deno` | Deno template |

### Labels (Work Type)

Labels indicate the type of work:

| Label | Description |
|-------|-------------|
| `feature` | New feature addition |
| `bugfix` | Bug fix |
| `patch` | Small changes and improvements |
| `refactor` | Code refactoring |
| `documentation` | Documentation modifications |

## Issue Description Format

The GitHub Issue **title** will be written in **English** for better international collaboration and tracking.

The GitHub Issue **description** will be written in **Japanese** and include:

### 概要 (Overview)

Brief description of what needs to be implemented or fixed

### 背景 (Background)

Context and reasoning behind the request

### 要件 (Requirements)

- Clear list of functional requirements
- Technical specifications if applicable
- Acceptance criteria

### 実装方法 (Implementation Approach)

- Proposed solution approach
- Technical details
- Architecture considerations if needed

### タスク (Tasks)

- [ ] Main task items
- [ ] Subtasks if applicable
- [ ] Testing requirements
- [ ] Documentation updates if needed

### 備考 (Notes)

Any additional considerations, dependencies, or related issues

## Documentation Integration

For complex issues, add documentation as **GitHub Issue comments** (actual documentation files will be created by subsequent commands):

| Issue Type          | Comment Content                                            |
| ------------------- | ---------------------------------------------------------- |
| Architecture/Design | Design overview, component diagrams, technical decisions   |
| Implementation Plan | Step-by-step implementation approach, dependencies         |
| Major Decision      | Context, options considered, rationale for chosen approach |

**Comment Format:**

```markdown
## 📄 ドキュメント情報 (Documentation Notes)

### 設計概要 (Design Overview)

[Design details to be documented]

### 実装計画 (Implementation Plan)

[Implementation steps to be documented]

### 決定事項 (Decisions)

[Key decisions to be documented]
```

This information will be used by subsequent commands (e.g., `/implement`) to create actual documentation files.

## Project Field Configuration

After issue creation, if `.github/project-automation.yml` exists, configure Project custom fields automatically.

### Prerequisites

- `.github/project-automation.yml` must exist with project configuration
- GitHub Actions `project-automation` workflow must be configured
- Project must have Size and/or Priority fields defined

### Workflow

1. **Wait for Actions completion** (max 30 seconds):
   ```bash
   # Poll for project-automation workflow completion
   gh run list --workflow=project-automation.yml --limit=1 --json status,conclusion
   ```

2. **Read project configuration**:
   ```yaml
   # From .github/project-automation.yml
   project:
     type: user  # or 'organization'
     owner: "OWNER_NAME"
     number: PROJECT_NUMBER
   ```

3. **Retrieve Project fields via GraphQL**:
   ```bash
   gh api graphql -f query='
     query($owner: String!, $number: Int!) {
       user(login: $owner) {
         projectV2(number: $number) {
           id
           fields(first: 20) {
             nodes {
               ... on ProjectV2SingleSelectField {
                 id
                 name
                 options { id name }
               }
             }
           }
         }
       }
     }
   ' -f owner="OWNER" -F number=PROJECT_NUMBER
   ```

4. **Analyze issue and determine field values** (see guidelines below)

5. **Set field values via GraphQL**:
   ```bash
   gh api graphql -f query='
     mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
       updateProjectV2ItemFieldValue(input: {
         projectId: $projectId
         itemId: $itemId
         fieldId: $fieldId
         value: { singleSelectOptionId: $optionId }
       }) {
         projectV2Item { id }
       }
     }
   ' -f projectId="PROJECT_ID" -f itemId="ITEM_ID" -f fieldId="FIELD_ID" -f optionId="OPTION_ID"
   ```

### Size Judgment Guidelines

Analyze the issue content to determine implementation size:

| Size | Criteria | Examples |
|------|----------|----------|
| **XS** | Single file, config-only changes | Fix typo, update version number |
| **S** | 1-2 files, simple changes | Add simple validation, small bug fix |
| **M** | 3-5 files, moderate complexity | Add new command, integrate new feature |
| **L** | Multiple files/components | New template, multi-file refactoring |
| **XL** | Architecture changes, major refactoring | Plugin system, major restructure |

**Factors to Consider**:
- Number of tasks listed in the issue
- Technical complexity described
- Estimated number of files to modify
- Dependencies on external systems
- Testing requirements

### Priority Judgment Guidelines

Analyze the issue content to determine priority:

| Priority | Criteria | Indicators |
|----------|----------|------------|
| **High** | Urgent, blocking, security | `bugfix` label, security keywords, blocker |
| **Medium** | Normal feature/improvement | `feature` label, standard development |
| **Low** | Nice-to-have, documentation | `documentation` label, refactoring |

**Automatic Mappings**:
- Label `bugfix` → Priority: High
- Label `feature` → Priority: Medium
- Label `documentation` → Priority: Low
- Label `patch` → Priority: Medium
- Label `refactor` → Priority: Low

**Keywords for High Priority**:
- "urgent", "critical", "blocker", "security", "broken", "crash"

### Error Handling

| Scenario | Behavior |
|----------|----------|
| `project-automation.yml` not found | Skip Project field configuration silently |
| Actions timeout (>30 seconds) | Display warning, skip configuration |
| Actions failure | Display error message, skip configuration |
| Field not found in Project | Skip that specific field with warning |
| GraphQL API error | Display error, skip configuration |

### Output Format

After successful configuration:
```
Project Fields Configured:
- Size: M (based on 5 tasks, moderate complexity)
- Priority: Medium (feature label, normal development)
```

## Best Practices

- **English titles**: Always use English for issue titles to ensure international accessibility and searchability
- **Clear requirements**: Ensure all requirements are clearly documented before creating the issue
- **Proper decomposition**: Break down complex requests into manageable subtasks
- **Accurate milestone assignment**: Set milestones based on the target area (core, github-actions, claude-code, or language templates)
- **Accurate labeling**: Use appropriate labels based on work type (feature, bugfix, patch, refactor, documentation)
- **Comprehensive description**: Include all necessary information for developers to understand and implement the request
- **Japanese formatting**: Write descriptions in clear, professional Japanese (while keeping titles in English)
- **Add documentation comments**: For complex issues, add documentation notes as comments for subsequent commands to create actual files

## Example Workflow

1. User presents: "setup.shに対話形式の言語選択機能を追加したい"
2. Confirm understanding of the request
3. **Execute /sc:brainstorm** to explore requirements:
   - "どの言語をサポートしますか？（Python, Node.js, Rust, Deno?）"
   - "デフォルトの言語は設定しますか？"
   - "引数指定でのスキップは必要ですか？"
   - "エラーハンドリングはどうしますか？"
4. **Summarize brainstorming results** - Consolidate all discovered requirements
5. Identify implementation needs (dialog flow, language detection, file copying, etc.)
6. Break down into tasks (prompt implementation, language configs, test cases, etc.)
7. Create main issue with:
   - **Title (English)**: "Add interactive language selection to setup.sh"
   - **Description (Japanese)**: Detailed requirements in Japanese (including brainstorming insights)
8. **Add documentation comment** to the issue:
   - Design overview (dialog flow, user experience)
   - Implementation plan (phases, dependencies)
   - Key decisions (prompt style, default behavior)
9. Configure issue settings:
   - Label as `feature`
   - Set milestone to `core`
   - Assign to user
10. Create subtasks if needed
11. Return issue number for tracking
12. **Configure Project fields** (if `project-automation.yml` exists):
    - Wait for `project-automation` Actions to complete
    - Analyze issue content and set Size: M (based on task count and complexity)
    - Set Priority: Medium (based on `feature` label)
    - Report configured values

## Completion Checklist

Before reporting the issue number to the user, verify ALL steps are completed:

- [ ] Issue created with English title and Japanese description
- [ ] Labels assigned (feature/bugfix/patch/refactor/documentation)
- [ ] Milestone assigned (core/github-actions/claude-code/python/node/rust/deno)
- [ ] Assignee set
- [ ] Documentation comment added (if complex issue)
- [ ] **🔴 Project fields configured (Size & Priority)** - If `project-automation.yml` exists

**Final Output Must Include:**
```
✅ Issue Created: #XX

Settings:
- Label: feature
- Milestone: core
- Assignee: @username

Project Fields Configured:  ← THIS SECTION IS REQUIRED
- Size: M (reason)
- Priority: P1 (reason)
```

If Project fields section is missing, the command is NOT complete.

## Integration with Other Commands

This command creates issues that will be processed by:

- `/implement` - Implement the created issue
- `/pr` - Create pull request after implementation

The documentation notes added as comments will be used by:

- `/sc:design` - Create formal design documents
- `/sc:workflow` - Create implementation workflow documents
