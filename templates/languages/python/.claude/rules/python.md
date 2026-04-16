---
paths:
  - "**/*.py"
---

# Python Coding Rules

## Style

- Target Python 3.12+
- Format with `ruff format` (double quotes, spaces, LF line endings)
- Lint with `ruff check` (pycodestyle, Pyflakes, isort, bugbear, comprehensions, pyupgrade)
- Max line width: 100 characters
- snake_case for functions/variables/modules, PascalCase for classes, SCREAMING_SNAKE_CASE for constants

## Type Annotations

- Add type annotations to all function signatures (parameters and return types)
- Use `mypy --strict` for type checking
- Prefer `X | Y` union syntax over `Union[X, Y]` (Python 3.10+)
- Use `collections.abc` types (`Sequence`, `Mapping`) over `typing` equivalents
- Avoid `Any` -- use `object` or generics instead

## Error Handling

- Use specific exception types, never bare `except:`
- Prefer raising domain-specific exceptions over generic `ValueError`/`RuntimeError`
- Use `contextlib.suppress()` for intentionally ignored exceptions
- Always include meaningful error messages in exceptions

## Testing

- Use pytest as the test framework
- Place tests in `tests/unit/`, `tests/integration/`, `tests/e2e/`
- Name test files `test_<module>.py`, test functions `test_<function>_<scenario>`
- Use fixtures (`conftest.py`) for shared test setup
- Use `pytest.raises` for testing exceptions, `pytest.mark.parametrize` for data-driven tests

## Security

- Never use `eval()`, `exec()`, or `__import__()` with untrusted input
- Use `pathlib.Path` for file operations, validate paths before access
- Sanitize all external input (CLI args, environment variables, file content)
- Use `secrets` module for cryptographic randomness, not `random`

## Package Management

- Use `uv` for dependency management and virtual environments
- Define dependencies in `pyproject.toml` (PEP 621)
- Pin exact versions for production dependencies
- Separate dev dependencies under `[project.optional-dependencies] dev`

## Import Order

- Standard library, then third-party, then local (enforced by ruff isort rules)
- Use absolute imports for project modules
- Avoid wildcard imports (`from module import *`)
