---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Coding Rules

## Style

- Target ES2022, use Node16 module resolution
- Format and lint with Biome (indentStyle=space, indentWidth=2, lineWidth=100, LF, double quotes, semicolons always)
- camelCase for functions/variables, PascalCase for types/classes/interfaces, SCREAMING_SNAKE_CASE for constants
- Use `import type` for type-only imports (enforced by Biome)

## Type Safety

- Enable strict mode with: `noUncheckedIndexedAccess`, `noImplicitOverride`, `noPropertyAccessFromIndexSignature`, `exactOptionalPropertyTypes`
- Never use `any` -- prefer `unknown` for untyped external data, then narrow
- Use discriminated unions over type assertions
- Prefer `readonly` arrays and properties where mutation is not needed
- Use `satisfies` operator for type validation without widening

## Error Handling

- Define typed error classes extending `Error` with a `code` discriminant
- Use `Result<T, E>` pattern (or neverthrow) for expected failures
- Reserve `throw` for truly exceptional conditions
- Always type catch variables as `unknown` and narrow before use

## Testing

- Use Vitest as the test framework
- Place tests in `tests/unit/`, `tests/integration/`, `tests/e2e/`
- Name test files `<module>.test.ts`
- Use `describe`/`it` blocks with descriptive names
- Prefer `toStrictEqual` over `toEqual` for object comparisons

## Security

- Never use `eval()`, `Function()`, or dynamic `import()` with untrusted strings
- Validate all external input at system boundaries (API routes, CLI args)
- Use `zod` or similar for runtime schema validation
- Escape HTML output to prevent XSS

## Package Management

- Use pnpm as the package manager
- Define scripts in `package.json` for all common operations
- Keep `devDependencies` separate from `dependencies`
- Use exact versions for production dependencies

## Import Organization

- Organize imports with Biome (auto-sorted)
- Group: built-in modules, external packages, internal modules
- Avoid circular imports -- use barrel files (`index.ts`) sparingly
