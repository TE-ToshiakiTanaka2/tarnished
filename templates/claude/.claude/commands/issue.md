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

## Integration with Other Commands

This command creates issues that will be processed by:

- `/implement` - Implement the created issue
- `/pr` - Create pull request after implementation

ARGUMENTS:
