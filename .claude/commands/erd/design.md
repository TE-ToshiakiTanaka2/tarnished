# /erd:design - Architecture and Component Design

Design system architecture, APIs, and component interfaces with comprehensive specifications.

## Usage

```
/erd:design [target system or component]
```

## MCP Tools

- **serena**: `find_symbol`, `get_symbols_overview`, `find_file`, `search_for_pattern`, `list_dir` -- for understanding existing architecture, finding related symbols, and analyzing current codebase structure
- **sequential-thinking**: `sequentialthinking` -- for evaluating design trade-offs, reasoning through architectural decisions, and validating design coherence

## Behavioral Flow

1. **Analyze context**: Use serena to understand the existing codebase structure and relevant symbols
2. **Identify constraints**: Determine what must be preserved (existing APIs, conventions, dependencies)
3. **Design**: Create comprehensive specifications following the output template
4. **Validate**: Ensure design is consistent with existing patterns and meets requirements
5. **Document**: Generate clear design documentation

## Design Approach

### Before designing:
1. Use `get_symbols_overview` to understand existing module structure
2. Use `find_symbol` to examine related interfaces and types
3. Use `search_for_pattern` to identify conventions already in use
4. Use `sequential-thinking` to reason through design trade-offs

### Design considerations:
- **Consistency**: Follow existing patterns and conventions in the codebase
- **Simplicity**: Prefer straightforward designs over clever abstractions
- **Extensibility**: Design for reasonable future needs without over-engineering
- **Testability**: Ensure components can be tested in isolation

## Output

```markdown
# Design: [target]

## Architecture Overview
Brief description of the overall approach.

## Module Structure
project/
├── existing/        # Existing module (modified)
│   └── file.ext     # Changes: <brief description>
└── new_module/      # New module
    ├── mod.ext      # Module entry point
    └── types.ext    # Type definitions

## Interface Design

### Public API / Functions
| Name | Signature | Description |
| --- | --- | --- |
| function_name | (args) -> ReturnType | Description |

### Type Definitions
- New types, structs, interfaces, enums
- Validation rules and constraints

## Data Flow
How data moves through the system.

## Error Handling
- Error types and hierarchy
- Recovery strategies

## Implementation Notes
- Key decisions and rationale
- Edge cases to handle
- Performance considerations
```

## CRITICAL BOUNDARIES

**STOP AFTER DESIGN SPECIFICATION**

This command produces a DESIGN DOCUMENT ONLY.

**Will NOT**:
- Generate actual implementation code (use implementation phase)
- Modify existing system architecture without explicit approval
- Create designs that violate established architectural constraints

**Next Step**: After design is approved, use `/erd:workflow` to plan implementation steps.
