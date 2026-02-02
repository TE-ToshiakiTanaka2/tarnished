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
│   ├── commands/           # Custom slash commands
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

Available custom commands:

- `/issue` - Create a GitHub Issue from requirements
- `/implement <issue_number>` - Implement a GitHub Issue
- `/pr` - Create a Pull Request

## Important Notes

- This project uses Devcontainer for development environment consistency
- All development should be done inside the container
- The `.claude/settings.json` file contains security restrictions for Claude Code

## References

- [Devcontainer Documentation](https://containers.dev/)
- [Claude Code Documentation](https://claude.com/claude-code)
