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

## Roles

Read `.claude/skills/_shared/delegation/SKILL.md` for the role vocabulary and stage ownership; where the two disagree with `.tarnished/workflows/issue.md`, the skills are authoritative.

This stage is authored **inline by the orchestrator**, and nothing in it is delegated. The requirements dialogue is the one place where the user is the irreplaceable input, and the estimation, implementation approach, and task breakdown are written in the same session that held that dialogue — which is why they need no separate check that they match what was asked.

## erd Command Invocation

Invoke each erd command by the first available route:

1. `Read(".claude/commands.local/erd/<command>.md")` — the project's overlay, when one exists
2. `Skill(erd:<command>)` — loads the base instructions into the current turn
3. `Read(".claude/commands/erd/<command>.md")` — the base copy, when the Skill route is unavailable

The overlay is checked first because it is the only route guaranteed to honor a project's customization. `commands.local/` is where a project overrides an erd command, and taking the Skill route without looking would silently run the base version instead.

## What This Skill Does

### Phase 1: Requirement Understanding and Discovery

1. **Confirm user request** - Understand what the user wants to accomplish
2. **Load `/erd:brainstorm`**:
   - Discover hidden requirements, edge cases, technical constraints, and non-functional requirements through Socratic dialogue
   - When a question has a small set of concrete answers — which layer to change, which of two approaches, in or out of scope — ask it as a structured choice rather than as free text. Keep open-ended prose for questions that genuinely have no enumerable answer
3. **Organize requirements** - Structure and summarize discovered requirements; iterate with the user until approved. This loop is the stage's quality gate: the user approves the summary directly, so the scope is settled by the person who owns it rather than inferred afterwards

### Phase 2: Estimation

4. **Load `/erd:estimate`**:
   - Determine Size and Priority using the criteria tables below, identify risks, dependencies, and affected layers

### Phase 3: Issue Creation and Configuration

5. **Create GitHub Issue** - Follow `_shared/issue` procedure with the prepared parameters:
   - `title`: English title from brainstorm/estimation results
   - `body`: Issue body formatted per the Issue Description Format below
   - `labels`: Determined from issue type (feature, bugfix, refactor, etc.)
   - `size`: From `/erd:estimate` results (XS/S/M/L/XL)
   - `priority`: `P0` / `P1` / `P2`. `/erd:estimate` reports High/Medium/Low; map it here — High → `P0`, Medium → `P1`, Low → `P2`. This mapping exists only at the erd boundary: everything written into the issue, including the body and the criteria table below, uses P-values
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
- **Priority**: P0/P1/P2
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

| Priority | Criteria                                 |
| -------- | ---------------------------------------- |
| **P0**   | Bug fix, security-related, blocker       |
| **P1**   | Normal feature addition, improvement     |
| **P2**   | Documentation, refactoring, nice-to-have |

## Reporting

Report the issue number and URL, the label, milestone, and assignee actually set, the estimation results (size, priority, affected layers, risk), any metadata operation that failed non-blockingly, any question left unresolved, and the next command.

## Integration

- **Next step**: Design with `/design <issue_number>`
- **Typical workflow**: **`/issue`** → `/design` → `/implement` → `/review` → `/pr`

ARGUMENTS:
$ARGUMENTS
