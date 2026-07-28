# Workflow: issue

Create a GitHub Issue from a rough requirement while preserving enough context for later design and implementation.

## Inputs

- User requirement or problem statement.
- Existing repository context when relevant.

## Procedure

1. Clarify functional and non-functional requirements with the user. This stage is authored inline by the orchestrator; nothing in it is delegated, because the user is the irreplaceable input.
2. Identify affected layers, risks, dependencies, and edge cases.
3. Estimate size and priority.
4. Create a GitHub Issue with a structured body.
5. Apply labels, assignee, milestone, and project fields when available.

## Output

- GitHub Issue URL and issue number.
- A concise summary of the accepted scope and any unresolved questions.
