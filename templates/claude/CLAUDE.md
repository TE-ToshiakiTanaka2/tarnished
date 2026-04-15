# {{PROJECT_NAME}}

This file provides context to Claude Code about the project structure and development conventions.

## Project Overview

{{PROJECT_NAME}} is a project built using Devcontainer for consistent development environments.

## Technology Stack

- **Container**: Docker with Devcontainer
- **Version Control**: Git with GitHub
- **AI Assistant**: Claude Code

## Directory Structure

```
{{PROJECT_NAME}}/
├── .devcontainer/          # Devcontainer configuration
│   ├── devcontainer.json   # VS Code Devcontainer settings
│   └── scripts/            # Setup scripts
├── .claude/                # Claude Code configuration
│   ├── commands/erd/       # erd commands (brainstorm, estimate, etc.)
│   ├── skills/             # Custom skills (slash commands)
│   │   ├── issue/          # Issue creation skill
│   │   ├── design/         # Architecture design skill
│   │   ├── implement/      # Implementation skill
│   │   ├── review/         # Code review skill (via Codex)
│   │   └── pr/             # Pull Request skill
│   ├── scripts/            # Helper scripts
│   └── settings.json       # Claude Code settings
├── docker/                 # Docker configuration
│   └── Dockerfile.dev      # Development Dockerfile
├── docker-compose.yml      # Docker Compose configuration
└── CLAUDE.md              # This file
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

Available skills (slash commands):

- `/issue` - Create a GitHub Issue from requirements (uses erd:brainstorm, erd:estimate)
- `/design <issue_number>` - Design architecture with UML diagrams (uses erd:research, erd:design, erd:workflow)
- `/implement <issue_number>` - Implement a GitHub Issue (uses erd:implement, erd:build, erd:test)
- `/review` - Code review via Codex CLI (requires codex)
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
