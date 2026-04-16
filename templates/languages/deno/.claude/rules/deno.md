---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# Deno Coding Rules

## Style

- Format with `deno fmt` (spaces, lineWidth=100, indentWidth=2, semicolons, double quotes)
- Lint with `deno lint` (recommended rules + ban-untagged-todo, no-console, no-eval, eqeqeq)
- Use TypeScript strict mode with `noUncheckedIndexedAccess` and `noImplicitOverride`
- camelCase for functions/variables, PascalCase for types/classes/interfaces, SCREAMING_SNAKE_CASE for constants

## Deno Runtime

- Use Deno-native APIs (`Deno.readTextFile`, `Deno.env.get`) instead of Node.js compatibility layers
- Import from `jsr:` or `https://deno.land/std` -- avoid npm imports unless necessary
- Use `import.meta.main` for entry point detection
- Declare permissions explicitly: `--allow-read`, `--allow-net`, etc.

## Error Handling

- Use `Result`-like patterns: return `T | Error` or throw typed errors
- Catch specific error types, never bare `catch (e) {}`
- Use `using` keyword with disposable resources (Deno 1.38+)
- Provide meaningful error messages with context

## Testing

- Use `Deno.test()` for all tests
- Place tests in `tests/unit/`, `tests/integration/`, `tests/e2e/`
- Name test files `<module>_test.ts`
- Import assertions from `jsr:@std/assert`
- Use `Deno.test` steps for subtests
- Run coverage with `deno test --coverage`

## Security

- Never use `eval()` or `new Function()` with untrusted input
- Always specify minimal permissions in `deno.json` tasks
- Validate all external input (URL params, file content, environment variables)
- Use `crypto.subtle` for cryptographic operations

## Module System

- Use explicit file extensions in imports: `import { foo } from "./bar.ts"`
- Prefer named exports over default exports
- Configure import maps in `deno.json` for aliasing
- Keep `deno.json` as the single source of configuration
