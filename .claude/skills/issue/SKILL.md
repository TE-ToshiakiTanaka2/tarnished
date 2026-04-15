---
name: issue
description: Create a GitHub Issue from requirements through brainstorming, estimation, and structured Issue creation. Uses erd commands (erd:brainstorm, erd:estimate).
argument-hint: ""
disable-model-invocation: true
---

# Skill: Issue

GitHub Issue creation skill for projects. Handles requirement discovery through brainstorming, expert review, estimation, and Issue creation.

## Usage

```
/issue
```

## erd Command Invocation

All erd commands in this skill MUST be invoked explicitly using the **Skill tool**:

```
Skill(skill: "erd:<command>", args: "<arguments>")
```

Do NOT simply read and follow the erd command's markdown instructions inline. Each erd command must be invoked as a separate Skill tool call to ensure proper execution context.

## What This Skill Does

### Phase 1: Requirement Understanding and Discovery

1. **Confirm user request** - Understand what the user wants to accomplish
2. **Invoke `/erd:brainstorm` via Skill tool** - `Skill(skill: "erd:brainstorm", args: "<user's requirements description>")`:
   - Discover hidden requirements through Socratic dialogue
   - Identify edge cases and boundary conditions
   - Confirm technical constraints
   - Explore non-functional requirements (performance, security, maintainability)
3. **Organize requirements** - Structure and summarize discovered requirements

### Phase 2: Estimation

4. **Invoke `/erd:estimate` via Skill tool** - `Skill(skill: "erd:estimate", args: "<organized requirements summary>")`:
   - Determine Size (XS/S/M/L/XL) based on scope and complexity
   - Determine Priority (High/Medium/Low) based on impact and urgency
   - Identify risks and dependencies
   - Estimate affected layers

### Phase 3: Issue Creation and Configuration

5. **Create GitHub Issue** - Follow `_shared/issue` procedure with the prepared parameters:
   - `title`: English title from brainstorm/estimation results
   - `body`: Issue body formatted per the Issue Description Format below
   - `labels`: Determined from issue type (feature, bugfix, refactor, etc.)
   - `size`: From `/erd:estimate` results (XS/S/M/L/XL)
   - `priority`: From `/erd:estimate` results (P0/P1/P2)
   - See `_shared/issue/SKILL.md` for full procedure (Issue creation, milestone, project fields)
6. **Return Issue number**

## erd Skills Used

| Skill | Purpose | Phase |
| --- | --- | --- |
| `/erd:brainstorm` | Interactive requirements discovery through Socratic dialogue | Phase 1 |
| `/erd:estimate` | Development estimates with intelligent analysis | Phase 2 |

## Leveraging erd:brainstorm

Use `/erd:brainstorm` to explore requirements from these perspectives:

- **Functional requirements**: What to achieve, acceptance criteria
- **Non-functional requirements**: Performance, security, maintainability
- **Architecture**: Which layer(s) are affected
- **User experience**: UI/UX considerations, accessibility
- **Data model**: New or modified entities, relationships, migrations

## Leveraging erd:estimate

Use `/erd:estimate` to produce a structured estimation:

- **Size**: Based on file count, module span, and complexity
- **Priority**: Based on impact, urgency, and dependencies
- **Risk factors**: Technical unknowns, external dependencies
- **Breakdown**: Per-layer effort distribution

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
- **Affected Layers**: Brief description
- **Risk Factors**: Brief description
- **Estimated Complexity**: Brief reasoning
```

## Size Criteria

| Size   | Criteria                                         |
| ------ | ------------------------------------------------ |
| **XS** | Config-only changes, minor fixes within 1 file   |
| **S**  | 1-2 files, single feature addition               |
| **M**  | 3-5 files, changes spanning multiple modules     |
| **L**  | Multiple components, new major feature            |
| **XL** | Architecture changes, major refactoring          |

## Priority Criteria

| Priority   | Criteria                                 |
| ---------- | ---------------------------------------- |
| **High**   | Bug fix, security-related, blocker       |
| **Medium** | Normal feature addition, improvement     |
| **Low**    | Documentation, refactoring, nice-to-have |

## Workflow

```mermaid
graph TD
    A[Confirm user request] --> B[Execute erd:brainstorm]
    B --> C[Organize requirements]
    C --> D{User feedback}
    D -->|Adjustments needed| B
    D -->|Approved| E[Execute erd:estimate]
    E --> F[Create GitHub Issue]
    F --> G[Configure settings]
    G --> H[Return Issue number]
```

## Completion Output

```
Issue Created: #XX

Settings:
- Label: feature
- Milestone: v1.0
- Assignee: @username

Estimation (erd:estimate):
- Size: M (3-5 files, spanning multiple modules)
- Priority: Medium (normal feature addition)
- Affected Layers: ...
- Risk: Low

Ready for /design XX
```

## Integration

- **Next step**: Design with `/design <issue_number>`
- **Typical workflow**: **`/issue`** → `/design` → `/implement` → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
