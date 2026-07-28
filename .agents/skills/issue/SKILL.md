---
name: issue
description: Create a GitHub Issue from requirements using the Tarnished lifecycle. Use when the user says issue, /issue, $issue, issue化, GitHub Issue作成, or asks to start work from a rough requirement.
---

# Issue

## Overview

Create a GitHub Issue from a rough requirement while preserving the same behavior as Claude Code's `/issue` skill.

## Procedure

1. Read `.tarnished/workflows/issue.md`.
2. If present, read `.claude/skills/issue/SKILL.md` as the detailed compatibility reference, but translate Claude-specific instructions into normal Codex file reads and commands.
3. Run requirement discovery using `.tarnished/workflows/erd/brainstorm.md` when the scope is unclear. This stage is authored inline; nothing in it is delegated, because the user is the irreplaceable input.
4. Run estimation using `.tarnished/workflows/erd/estimate.md`.
5. Create the issue with `gh issue create` or the available GitHub connector.
6. Apply labels, assignee, milestone, and project fields when the repository supports them.

## Output

Return the issue number, issue URL, labels, size, priority, unresolved questions, and the next command:

```text
Ready for $design <issue_number>
```

Do not create a branch or edit production code in this skill.
