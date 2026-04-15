# Flowchart: #242 _shared Skill Reference Flow

```mermaid
graph TD
    subgraph "_shared/branch"
        B1[Fetch issue metadata] --> B2[Determine label priority]
        B2 --> B3[Get assignee]
        B3 --> B4[Normalize title to kebab-case]
        B4 --> B5{Existing branch?}
        B5 -->|Yes| B6[Checkout existing]
        B5 -->|No| B7[Create from develop]
    end

    subgraph "_shared/issue"
        I1[Determine assignee] --> I2[gh issue create]
        I2 --> I3{Success?}
        I3 -->|No| I4[STOP: report error]
        I3 -->|Yes| I5[Set milestone]
        I5 --> I6[Add to project]
        I6 --> I7[Set Size/Priority fields]
        I7 --> I8[Return issue number + URL]
    end

    subgraph "Calling Skills"
        D[/design Phase 1] --> B1
        IM[/implement Phase 1] --> B1
        IS[/issue Phase 3] --> I1
    end
```
