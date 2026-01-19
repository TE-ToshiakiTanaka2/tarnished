# Claude Command: Issue

This command helps you review development requests and create organized GitHub Issues with proper requirements and work items.

## Usage

To create a GitHub Issue from a development request:

```
/issue
```

## What This Command Does

1. **Confirm the user's request** - Acknowledge and understand what the user wants to accomplish
2. **Explore requirements** - Discover hidden requirements and edge cases through interactive questioning:
   - Clarify ambiguous points
   - Identify potential challenges and considerations
   - Build comprehensive understanding of the request
3. **Summarize requirements** - Organize and consolidate the insights gathered into clear requirements
4. **Present implementation methods** - Propose necessary implementation approaches for the request
5. **Identify work items** - Organize implementation methods and break down into main tasks and subtasks if necessary
6. **Create GitHub Issue** - Create issue with an **English title** and description in the project's preferred language
7. **Configure issue settings** - Set the following after issue creation:
   - **Labels** - Assign based on work type (feature, bugfix, patch, refactor, documentation)
   - **Milestone** - Assign based on target area if applicable
   - **Assignee** - Assign to the user by default unless otherwise specified
8. **Return issue number** - Provide the created issue number
9. **Configure Project fields** (optional) - If `.github/project-automation.yml` exists:
   - Wait for `project-automation` workflow to complete (max 30 seconds)
   - Analyze issue content to determine Size and Priority
   - Set Project custom fields automatically
   - Skip silently if configuration file doesn't exist

## Issue Description Format

The GitHub Issue **title** will be written in **English** for better international collaboration and tracking.

The GitHub Issue **description** will include:

### Overview

Brief description of what needs to be implemented or fixed

### Background

Context and reasoning behind the request

### Requirements

- Clear list of functional requirements
- Technical specifications if applicable
- Acceptance criteria

### Implementation Approach

- Proposed solution approach
- Technical details
- Architecture considerations if needed

### Tasks

- [ ] Main task items
- [ ] Subtasks if applicable
- [ ] Testing requirements
- [ ] Documentation updates if needed

### Notes

Any additional considerations, dependencies, or related issues

## Best Practices

- **English titles**: Always use English for issue titles to ensure international accessibility and searchability
- **Clear requirements**: Ensure all requirements are clearly documented before creating the issue
- **Proper decomposition**: Break down complex requests into manageable subtasks
- **Accurate labeling**: Use appropriate labels based on work type
- **Comprehensive description**: Include all necessary information for developers to understand and implement the request

## Project Field Configuration (Optional)

If your project uses GitHub Projects with the `project-automation` workflow, the `/issue` command can automatically configure custom fields.

### Prerequisites

- `.github/project-automation.yml` must exist with project configuration:
  ```yaml
  project:
    type: user  # or 'organization'
    owner: "OWNER_NAME"
    number: PROJECT_NUMBER
  ```
- GitHub Actions `project-automation` workflow must be configured
- Project must have Size and/or Priority fields defined

### Size Judgment Guidelines

| Size | Criteria |
|------|----------|
| **XS** | Single file, config-only changes |
| **S** | 1-2 files, simple changes |
| **M** | 3-5 files, moderate complexity |
| **L** | Multiple files/components |
| **XL** | Architecture changes, major refactoring |

### Priority Judgment Guidelines

| Priority | Criteria |
|----------|----------|
| **High** | Bug fix, security-related, blocker |
| **Medium** | Normal feature, improvement |
| **Low** | Documentation, refactoring, nice-to-have |

**Automatic Mappings**:
- Label `bugfix` → Priority: High
- Label `feature` → Priority: Medium
- Label `documentation` → Priority: Low

### Error Handling

- If `project-automation.yml` doesn't exist: Skip silently
- If Actions timeout (>30s): Display warning, skip configuration
- If field not found: Skip with warning

## Example Workflow

1. User presents: "Add a new feature to handle user settings"
2. Confirm understanding of the request
3. Explore requirements through questions:
   - "What settings should be included?"
   - "Should settings persist across sessions?"
   - "What's the default behavior?"
4. Summarize all discovered requirements
5. Identify implementation needs
6. Create GitHub Issue with:
   - **Title (English)**: "Add user settings management feature"
   - **Description**: Detailed requirements
7. Configure issue settings (labels, assignee)
8. Return issue number for tracking
9. Configure Project fields (if `project-automation.yml` exists)

## Integration with Other Commands

This command creates issues that will be processed by:

- `/implement` - Implement the created issue
- `/pr` - Create pull request after implementation

ARGUMENTS:
