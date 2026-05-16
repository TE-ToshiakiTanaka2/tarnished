# /erd:brainstorm - Interactive Requirements Discovery

Discover and refine requirements through Socratic dialogue and structured exploration.

## Usage

```
/erd:brainstorm [topic or idea]
```

## MCP Tools

- **context7**: `resolve-library-id`, `query-docs` -- for verifying technical feasibility and checking library capabilities during requirements exploration

## Behavioral Flow

1. **Understand**: Confirm the user's intent and context
2. **Explore**: Ask targeted questions to uncover hidden requirements using Socratic dialogue
3. **Analyze**: Systematically evaluate requirements from multiple perspectives (see checklist below)
4. **Organize**: Structure discovered requirements into a clear specification
5. **Validate**: Present requirements summary and confirm with user; iterate if needed

## Exploration Checklist

Explore requirements from each of these perspectives:

- **Functional requirements**: What should the system do? What are the acceptance criteria?
- **Non-functional requirements**: Performance targets, security constraints, maintainability goals
- **Architecture**: Which layers are affected? What modules need changes?
- **User experience**: CLI interface, error messages, output format, accessibility
- **Data model**: New or modified entities, relationships, migrations, schema changes
- **Edge cases**: Boundary conditions, error scenarios, concurrent access

## Key Principles

- Ask **one focused question at a time** -- don't overwhelm with multiple questions
- Reason through complex requirement spaces internally before asking
- Build on user answers progressively -- each question should deepen understanding
- Identify **assumptions** explicitly and validate them with the user
- When the user's answer reveals new scope, acknowledge it and explore further

## Output

After exploration is complete, produce a requirements specification:

```markdown
## Requirements Summary

### Functional Requirements
- FR-1: [requirement] -- [acceptance criteria]
- FR-2: ...

### Non-Functional Requirements
- NFR-1: [requirement] -- [criteria]

### Constraints
- [technical or business constraints]

### Open Questions
- [unresolved items for user decision]
```

## CRITICAL BOUNDARIES

**STOP AFTER REQUIREMENTS DISCOVERY**

This command produces a REQUIREMENTS SPECIFICATION ONLY.

**Will NOT**:
- Create architecture diagrams or system designs (use `/erd:design`)
- Generate implementation code
- Make architectural decisions
- Design database schemas or API contracts
- Create technical specifications beyond requirements

**Next Step**: After brainstorm completes, use `/erd:design` for architecture or `/erd:estimate` for sizing.
