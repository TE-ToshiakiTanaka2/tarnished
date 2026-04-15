# /erd:estimate - Development Estimation

Provide structured development estimates for tasks, features, or projects.

## Usage

```
/erd:estimate [target task or feature description]
```

## Behavioral Flow

1. **Analyze scope**: Examine the target's complexity factors, dependencies, and affected layers
2. **Assess codebase**: Use Read/Grep/Glob to analyze relevant code and count affected files/modules
3. **Determine Size**: Apply size criteria based on file count, module span, and complexity
4. **Determine Priority**: Evaluate impact, urgency, and dependency relationships
5. **Identify risks**: Technical unknowns, external dependencies, integration complexity
6. **Present report**: Deliver structured estimation with breakdown

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

## Analysis Method

1. **File count**: Count files that need creation or modification
2. **Module span**: How many distinct modules/packages are affected
3. **Complexity factors**:
   - New abstractions or interfaces required
   - External dependency integration
   - Cross-cutting concerns (error handling, logging, config)
   - Test coverage requirements
4. **Risk assessment**:
   - Technical unknowns (unfamiliar APIs, new patterns)
   - External dependencies (third-party services, libraries)
   - Integration points (existing system contracts)

## Output

```markdown
## Estimation Report

- **Size**: [XS/S/M/L/XL] -- [reasoning]
- **Priority**: [High/Medium/Low] -- [reasoning]
- **Affected Layers**: [list of affected components/modules]
- **Risk Factors**: [identified risks]
- **Estimated Complexity**: [brief analysis]

### Breakdown
| Component | Files | Effort | Notes |
| --- | --- | --- | --- |
| [component] | [count] | [low/med/high] | [details] |
```

## CRITICAL BOUNDARIES

**STOP AFTER ESTIMATION**

This command produces an ESTIMATION REPORT ONLY.

**Will NOT**:
- Execute work based on estimates
- Create implementation timelines
- Start implementation tasks
- Make commitments on behalf of user

**Next Step**: After estimation, use `/erd:workflow` for planning or proceed to implementation.
