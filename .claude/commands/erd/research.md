# /erd:research - External Research

Research external libraries, APIs, patterns, and technologies with evidence-based analysis.

## Usage

```
/erd:research [topic or query]
```

## MCP Tools

- **context7**: `resolve-library-id`, `query-docs` -- for looking up library documentation, API references, and framework-specific patterns

## Behavioral Flow

1. **Understand**: Assess query scope and identify what information is needed
2. **Plan**: Determine search strategy and information sources
3. **Execute**: Gather information using WebSearch and context7
4. **Validate**: Cross-reference findings, check source credibility
5. **Synthesize**: Organize findings into a structured report

## Research Strategy

### For library/framework research:
1. Use **context7** `resolve-library-id` to find the library
2. Use **context7** `query-docs` to retrieve relevant documentation
3. Supplement with **WebSearch** for community best practices and known issues

### For API/integration research:
1. Use **WebSearch** to find official documentation and guides
2. Look for authentication patterns, rate limits, error handling
3. Find community examples and known pitfalls

### For pattern/architecture research:
1. Use **WebSearch** for established patterns and industry best practices
2. Compare multiple approaches with trade-off analysis
3. Look for real-world adoption and lessons learned

## Key Principles

- **Evidence-based**: Every finding should reference a source
- **Practical**: Focus on actionable information relevant to the project
- **Balanced**: Present trade-offs, not just advantages
- **Current**: Prefer recent sources; note when information may be outdated

## Output

```markdown
## Research Report: [topic]

### Executive Summary
[2-3 sentence overview of key findings]

### Findings

#### [Finding 1]
- **Details**: [description]
- **Source**: [reference]
- **Relevance**: [how it applies to our project]

#### [Finding 2]
...

### Comparison (if applicable)
| Option | Pros | Cons | Fit |
| --- | --- | --- | --- |
| [option] | [advantages] | [disadvantages] | [suitability] |

### Recommendations
- [actionable recommendations for human decision]

### Sources
- [list of references]
```

## CRITICAL BOUNDARIES

**STOP AFTER RESEARCH REPORT**

This command produces a RESEARCH REPORT ONLY.

**Will NOT**:
- Implement findings or recommendations
- Write code based on research
- Make architectural decisions
- Create system changes based on research

**Next Step**: After research completes, use `/erd:design` for architecture or discuss findings with the user.
