---
name: issue
description: Create a GitHub Issue from requirements through brainstorming, estimation, and structured Issue creation. Uses erd commands (erd:brainstorm, erd:estimate).
argument-hint: ""
disable-model-invocation: true
---

# Skill: Issue

GitHub Issue creation skill for projects. Handles requirement discovery through brainstorming, expert review, estimation, and Issue creation.

This skill is the Claude Code projection of `.tarnished/workflows/issue.md`. Keep the shared workflow source and this tool-specific entrypoint aligned.

## Usage

```
/issue
```

## erd Command Invocation

All erd commands in this skill MUST be loaded via the **Read tool** and followed inline:

```
Read(".claude/commands/erd/<command>.md") → follow instructions inline
```

Do NOT use the Skill tool to invoke erd commands. Loading via Read keeps the entire workflow in a single turn, preventing flow interruption between phases.

## What This Skill Does

### Phase 1: Requirement Understanding and Discovery

1. **Confirm user request** - Understand what the user wants to accomplish
2. **Load `/erd:brainstorm` and follow inline** - `Read(".claude/commands/erd/brainstorm.md")`:
   - Discover hidden requirements, edge cases, technical constraints, and non-functional requirements through Socratic dialogue
3. **Organize requirements** - Structure and summarize discovered requirements; iterate with the user until approved

### Phase 2: Estimation

4. **Load `/erd:estimate` and follow inline** - `Read(".claude/commands/erd/estimate.md")`:
   - Determine Size and Priority using the criteria tables below, identify risks, dependencies, and affected layers

### Phase 3: Issue Creation and Configuration

5. **Create GitHub Issue** - Follow `_shared/issue` procedure with the prepared parameters:
   - `title`: English title from brainstorm/estimation results
   - `body`: Issue body formatted per the Issue Description Format below
   - `labels`: Determined from issue type (feature, bugfix, refactor, etc.)
   - `size`: From `/erd:estimate` results (XS/S/M/L/XL)
   - `priority`: Mapped from `/erd:estimate` Priority — High → `P0`, Medium → `P1`, Low → `P2` (the project field accepts only P-values)
   - See `_shared/issue/SKILL.md` for full procedure (Issue creation, milestone, project fields)
6. **Return Issue number**

## erd Commands Used

| Command | Purpose | Phase |
| --- | --- | --- |
| `/erd:brainstorm` | Interactive requirements discovery through Socratic dialogue | Phase 1 |
| `/erd:estimate` | Development estimates with intelligent analysis | Phase 2 |

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
