---
name: issue
description: Create a GitHub Issue from requirements. Handles requirement discovery, implementation planning, sizing, and Issue creation with project field configuration.
argument-hint: [description of what you want to build]
disable-model-invocation: true
---

# Issue Creation Skill

GitHub Issue creation skill for CLI projects. Handles requirement discovery, Issue creation, and implementation sizing.

## What This Skill Does

### Phase 1: Requirement Understanding and Discovery

1. **Confirm user request** - Understand what the user wants to accomplish
2. **Deep requirement analysis** - Dig deeper into requirements:
   - Discover hidden requirements
   - Identify edge cases
   - Confirm technical constraints
   - Consider CLI UX aspects
3. **Organize requirements** - Structure and summarize discovered requirements

### Phase 2: Implementation Planning

4. **Consider implementation approach** - Propose implementation strategy:
   - Design CLI arguments
   - Plan module structure
5. **Break down work items** - Decompose into tasks and subtasks
6. **Estimate implementation size** - Determine Size and Priority

### Phase 3: Issue Creation and Configuration

7. **Create GitHub Issue** - English title with detailed description
8. **Configure Issue settings** - Set Labels, Milestone, Assignee
9. **Set Project fields** - Automatically set Size and Priority (if project.yml exists)
10. **Return Issue number**

## Requirement Analysis Perspectives

Explore requirements from these perspectives:

- **Functional requirements**: What to achieve
- **Non-functional requirements**: Performance, security, maintainability
- **CLI UX**: Argument design, help messages, output format

## Issue Description Format

**Title**: Written in English

**Body**:

```markdown
## Overview

Summary of implementation

## Background

Context and purpose

## Requirements

### Functional Requirements

- Functional requirements list
- Acceptance criteria

### Non-Functional Requirements

- Performance requirements
- Security considerations

## Implementation Approach

- Proposed implementation approach
- Architecture considerations

## Tasks

- [ ] Main task
  - [ ] Subtask
- [ ] Create tests
- [ ] Update documentation

## Estimation

- **Size**: XS/S/M/L/XL
- **Priority**: High/Medium/Low
- **Estimated Complexity**: Brief reasoning
```

## Size Criteria

| Size   | Criteria                                         |
| ------ | ------------------------------------------------ |
| **XS** | Config-only changes, minor fixes within 1 file   |
| **S**  | 1-2 files, single command/feature addition       |
| **M**  | 3-5 files, changes spanning multiple modules     |
| **L**  | Multiple components, new CLI subcommand addition |
| **XL** | Architecture changes, major refactoring          |

## Priority Criteria

| Priority   | Criteria                                 |
| ---------- | ---------------------------------------- |
| **High**   | Bug fix, security-related, blocker       |
| **Medium** | Normal feature addition, improvement     |
| **Low**    | Documentation, refactoring, nice-to-have |

## Workflow Example

1. User: "I want to add a feature to load configuration files"
2. Deep requirement analysis:
   - "Which format? JSON/TOML/YAML?"
   - "What's the default path?"
   - "Need environment variable override?"
   - "Validation required?"
3. Organize requirements
4. Determine size: Size=M, Priority=Medium
5. Create GitHub Issue
6. Set Project fields

## Completion Output

```
Issue Created: #XX

Settings:
- Label: feature
- Milestone: v1.0
- Assignee: @username

Project Fields:
- Size: M (3-5 files, config loading + validation)
- Priority: Medium (normal feature addition)

Ready for /implement #XX
```

## Integration

- **Next step**: Start implementation with `/implement <issue_number>`
- **Final step**: Create Pull Request with `/pr`

ARGUMENTS:
$ARGUMENTS
