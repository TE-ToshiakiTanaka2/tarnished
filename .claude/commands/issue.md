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

## Integration with Other Commands

This command creates issues that will be processed by:

- `/implement` - Implement the created issue
- `/pr` - Create pull request after implementation

The documentation notes added as comments will be used by:

- `/sc:design` - Create formal design documents
- `/sc:workflow` - Create implementation workflow documents
