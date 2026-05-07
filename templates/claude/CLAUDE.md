# {{PROJECT_NAME}}

This file provides context to Claude Code about the project structure and development conventions.

## Project Overview

{{PROJECT_NAME}} is a project built using Devcontainer for consistent development environments.

## Technology Stack

- **Container**: Docker with Devcontainer
- **Version Control**: Git with GitHub
- **AI Profile**: `{{AI_PROFILE}}`
- **Primary Agent**: {{AI_PRIMARY_AGENT}}
- **Review Agent**: {{AI_REVIEW_AGENT}}

## Directory Structure

```
{{PROJECT_NAME}}/
├── .devcontainer/          # Devcontainer configuration
│   ├── devcontainer.json   # VS Code Devcontainer settings
│   └── scripts/            # Setup scripts
├── .tarnished/             # Shared Claude/Codex workflow source
│   ├── agent-profile.json  # Selected primary/review agent profile
│   └── workflows/          # Agent-neutral lifecycle documentation
├── .claude/                # Claude Code configuration
│   ├── commands/erd/       # erd commands (brainstorm, estimate, etc.)
│   ├── skills/             # Custom skills (slash commands)
│   │   ├── issue/          # Issue creation skill
│   │   ├── design/         # Architecture design skill
│   │   ├── implement/      # Implementation skill
│   │   ├── review/         # Cross-agent review skill
│   │   └── pr/             # Pull Request skill
│   ├── scripts/            # Helper scripts
│   └── settings.json       # Claude Code settings
├── docker/                 # Docker configuration
│   └── Dockerfile.dev      # Development Dockerfile
├── docker-compose.yml      # Docker Compose configuration
├── AGENTS.md               # Codex entrypoint when Codex is enabled
└── CLAUDE.md               # This file
```

## Coding Conventions

### General

- Write clear, self-documenting code
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic only

### Git Workflow

- Use conventional commit format with emojis:
  - `feat:` for new features
  - `fix:` for bug fixes
  - `refactor:` for code refactoring
  - `docs:` for documentation changes
  - `test:` for test additions/modifications
  - `chore:` for maintenance tasks

### Branch Naming

- `feature/{user}/#{issue}/{description}` for new features
- `bugfix/{user}/#{issue}/{description}` for bug fixes
- `refactor/{user}/#{issue}/{description}` for refactoring

## Development Commands

### Docker

```bash
# Build the development image
docker-compose build

# Start the container
docker-compose up -d

# Stop the container
docker-compose down
```

### Claude Code

Claude Code skills are the Claude-specific projection of the shared workflow source in `.tarnished/workflows/`. Detailed `erd:*` behavior is also available in `.tarnished/workflows/erd/*` for Codex-readable reuse. When changing workflow behavior, update the shared workflow source first, then keep `.claude/skills/*`, `.claude/commands/erd/*`, and Codex-facing `AGENTS.md` aligned.

When Claude Code is the primary agent, drive the full lifecycle below. When Claude Code is the configured review agent, focus on `.tarnished/workflows/review.md` and provide independent review feedback without taking over implementation unless the user asks.

Available skills (slash commands):

- `/issue` - Create a GitHub Issue from requirements (uses erd:brainstorm, erd:estimate)
- `/design <issue_number>` - Design architecture with UML diagrams (uses erd:research, erd:design, erd:workflow)
- `/implement <issue_number>` - Implement a GitHub Issue (uses erd:implement, erd:build, erd:test)
- `/review` - Cross-agent code review using the configured review workflow
- `/pr [--merge]` - Create a Pull Request (uses erd:analyze, erd:improve, erd:cleanup, erd:reflect)

Available erd commands (callable independently):

- `/erd:brainstorm` - Interactive requirements discovery
- `/erd:estimate` - Development estimation (Size/Priority/Risk)
- `/erd:research` - External library/API research
- `/erd:design` - Architecture and component design
- `/erd:workflow` - Implementation workflow planning
- `/erd:index-repo` - Repository indexing for token reduction
- `/erd:implement` - Feature implementation
- `/erd:build` - Build verification
- `/erd:test` - Test execution and coverage
- `/erd:analyze` - Code quality/security/performance analysis
- `/erd:improve` - Code quality improvements
- `/erd:cleanup` - Dead code removal and cleanup
- `/erd:troubleshoot` - Issue diagnosis and root cause analysis
- `/erd:reflect` - CI result validation and PR quality assessment

**Typical workflow**: `/issue` → `/design` → `/implement` → `/review` → `/pr`

## Important Notes

- This project uses Devcontainer for development environment consistency
- All development should be done inside the container
- The `.claude/settings.json` file contains security restrictions for Claude Code

## References

- [Devcontainer Documentation](https://containers.dev/)
- [Claude Code Documentation](https://claude.com/claude-code)
