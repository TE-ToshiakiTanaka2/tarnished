# Flowchart: #240 Internalize SuperClaude Front-Half Skills as erd: Commands

## erd: Command Invocation Flow

```mermaid
graph TD
    A[User invokes /erd:command] --> B{Which command?}
    B -->|brainstorm| C[/erd:brainstorm]
    B -->|estimate| D[/erd:estimate]
    B -->|research| E[/erd:research]
    B -->|design| F[/erd:design]
    B -->|workflow| G[/erd:workflow]

    C --> C1[sequential-thinking MCP]
    C1 --> C2[Socratic dialogue]
    C2 --> C3[Requirements spec output]

    D --> D1[Codebase analysis]
    D1 --> D2[Size/Priority evaluation]
    D2 --> D3[Estimation report output]

    E --> E1[WebSearch + context7 MCP]
    E1 --> E2[Evidence collection]
    E2 --> E3[Research report output]

    F --> F1[serena MCP: analyze existing structure]
    F1 --> F2[sequential-thinking: design decisions]
    F2 --> F3[Architecture doc output]

    G --> G1[sequential-thinking MCP]
    G1 --> G2[Task decomposition]
    G2 --> G3[Workflow plan output]
```

## Skill Integration Flow

```mermaid
graph TD
    I[/issue skill] --> I1[/erd:brainstorm]
    I1 --> I2[/erd:estimate]
    I2 --> I3[Create GitHub Issue]

    DS[/design skill] --> DS0{External deps?}
    DS0 -->|Yes| DS1[/erd:research]
    DS0 -->|No| DS2[/erd:design]
    DS1 --> DS2
    DS2 --> DS3[/erd:workflow]
    DS3 --> DS4[Generate UML diagrams]
    DS4 --> DS5[Commit artifacts]
```

## Migration Path

```mermaid
graph LR
    SC[SuperClaude /sc:*] -->|Phase 1: Front-half| ERD1[/erd:brainstorm<br>/erd:estimate<br>/erd:research<br>/erd:design<br>/erd:workflow]
    SC -->|Phase 2: Back-half| ERD2[/erd:implement<br>/erd:build<br>/erd:test<br>/erd:analyze<br>...]
    SC -->|Phase 3: Quality| ERD3[/erd:improve<br>/erd:cleanup<br>/erd:reflect<br>...]
    ERD1 --> DONE[SuperClaude fully replaced]
    ERD2 --> DONE
    ERD3 --> DONE
```
