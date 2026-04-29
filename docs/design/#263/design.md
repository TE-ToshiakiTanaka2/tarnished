# Design: #263 feat(setup): support monorepo layout with per-module scaffolds

## Context

This issue extends `setup.sh` and the `templates/*/plugin.sh` family. The relevant slice of the project today (from `shared/architecture.md`):

- `setup.sh` is the orchestrator. It parses CLI flags, prompts the user, loads plugins (`templates/{core,claude,codex,languages/<lang>,services/<svc>,github-actions/<wf>}/plugin.sh`), and dispatches three plugin hooks per loaded plugin: `plugin_copy`, `plugin_dockerfile`, `plugin_post_copy` (preceded by `plugin_interactive_setup` if defined). Hook input is always `target_dir`, the project root.
- `scripts/lib/common.sh` is the shared shell library: TTY detection, output helpers (`print_*`), file copy with overwrite confirmation, JSON merge (`merge_devcontainer_json`, `merge_docker_compose_services`), gitignore seeding (`update_gitignore`).
- A "single-project" target produced today contains: `.devcontainer/`, `.claude/`, `docker/Dockerfile.dev`, `docker-compose.yml`, `CLAUDE.md`, `.gitignore`, plus whatever language scaffold (`pyproject.toml`/`Cargo.toml`/`package.json` + `src/` + `tests/`) and service overlay each selected plugin emits — all flat at the project root.
- Service templates already prefix everything with `{{PROJECT_NAME}}` (verified: `templates/services/postgresql/docker-compose.postgresql.yml` defines `{{PROJECT_NAME}}-db` and the matching `DATABASE_URL` host). So **the project-name prefix is the existing convention**; no service-plugin change is required to satisfy FR-6.
- The `core` docker-compose template defines a single dev service named `{{PROJECT_NAME}}` and mounts the project root as `/workspace`.
- `setup.sh` ends with `replace_placeholders(target_dir, project_name)` which sed-substitutes `{{PROJECT_NAME}}` repo-wide.

This issue introduces a second target shape — a **monorepo** with N module sub-directories, each carrying its own language scaffold, registered in a root `modules.json`. Single-project shape and behavior are preserved unchanged (NFR-1).

## Architecture Overview (delta)

Three new concepts enter `setup.sh`:

1. **Mode** — orthogonal to language/service selection. `MONOREPO_MODE = false | true`. Default `false`. Set by `--monorepo` flag, by interactive answer to "Monorepo configuration? (y/n)", or implicitly by `--add-module` / by detection of a pre-existing root `modules.json`.

2. **Module set** — present only in monorepo mode. An ordered list of `(name, language)` pairs collected from `--module name:lang` flags or from the interactive module dialogue loop. Persisted to a root `modules.json`. The set of distinct languages across modules becomes `SELECTED_LANGUAGES` for plugin loading (so the union of toolchains lands in the shared root devcontainer per FR-5).

3. **Plugin scope** — language plugins gain a two-function interface (`plugin_post_copy_module` + `plugin_post_copy_shared`). The existing `plugin_post_copy` becomes a backward-compat shim that calls both with `target_dir`. The orchestrator dispatches differently per mode:
   - Single mode: call `plugin_post_copy(root)` exactly as today.
   - Monorepo mode: call `plugin_post_copy_shared(root)` once per language plugin, then `plugin_post_copy_module(root/<module>, <module>)` once per module that uses that language.

Service plugins, `core`, `claude`, `codex`, and `github-actions/*` plugins remain single-hook (`plugin_post_copy(root)` only). They are mode-agnostic because they only ever touch root-level assets, and the `{{PROJECT_NAME}}` placeholder substitution already produces monorepo-correct names.

The orchestrator change is centralized in `execute_plugin_post_copies` (`setup.sh`). The dispatch logic looks up "is this a language plugin?" via the convention "the plugin path contains `/templates/languages/`" — we already track `LOADED_PLUGINS` as full paths, so no metadata expansion is required.

## Module Structure (delta)

```
.
├── setup.sh                          # adds: monorepo flag, module loop, add-module subflow,
│                                     #   modules.json bootstrap, post-copy dispatcher branching
├── scripts/lib/common.sh             # adds: modules.json helpers, prompt_module_loop,
│                                     #   prompt_add_module, validate_module_name,
│                                     #   detect_existing_monorepo, prompt_monorepo_mode
├── templates/
│   ├── core/
│   │   ├── plugin.sh                 # adds: monorepo-mode branch in plugin_post_copy that
│   │   │                             #   seeds modules.json from the registered modules and
│   │   │                             #   writes per-module CLAUDE.md from the new template
│   │   ├── modules.json.template     # NEW: empty registry seed `{ "version": 1, "modules": [] }`
│   │   └── module.CLAUDE.md.template # NEW: per-module CLAUDE.md stub with placeholders
│   │                                 #   {{MODULE_NAME}}, {{MODULE_LANGUAGE}}
│   └── languages/{python,rust,node,deno,latex}/plugin.sh
│                                     # split plugin_post_copy → _shared + _module
│                                     # _module receives (target_dir, module_name)
│                                     # legacy plugin_post_copy retained as shim that calls both
└── docs/design/#263/                 # this issue's design artifacts
```

`templates/services/{postgresql,mysql,redis,celery}/plugin.sh` are **not** modified — the existing `{{PROJECT_NAME}}-<svc>` convention satisfies FR-6 in both modes.

A monorepo target produced by this issue looks like:

```
<project>/
├── .devcontainer/                   # shared (root)
├── .claude/                         # shared (root)
├── docker/Dockerfile.dev            # shared, union of all module-language toolchains
├── docker-compose.yml               # shared; dev service `<project>`, optional `<project>-db`/`-redis`/...
├── CLAUDE.md                        # shared; project-wide context
├── modules.json                     # NEW: registry
├── jing/                            # module (e.g. python)
│   ├── pyproject.toml, ruff.toml
│   ├── src/jing/__init__.py
│   ├── tests/{unit,integration,e2e}/
│   └── CLAUDE.md
├── kir/                             # module (e.g. node)
│   ├── package.json, biome.json, tsconfig.json
│   ├── src/, tests/
│   └── CLAUDE.md
└── .gitignore                       # shared (root)
```

## Interface Design (delta)

### CLI surface (`setup.sh`)

| Flag | Mode | Repeatable | Effect |
| --- | --- | --- | --- |
| `--monorepo` | init | no | Force monorepo mode for fresh init. Implies the module dialogue loop unless `--module` is also given. |
| `--module <name>:<lang>` | init | yes | Define a module (init mode). Implies `--monorepo`. Disables interactive module loop. |
| `--add-module <name>` | add | no | Add a module to an existing monorepo. Requires CWD to contain `modules.json`. Pair with `--lang`. |
| `--lang <lang>` | both | yes (init), once (add) | In single mode and add-module mode: language. In monorepo init: **rejected** (use `--module` instead) — usage error. |

Mutually exclusive combinations rejected with a clear `print_error` + non-zero exit:

- `--monorepo` + `--add-module`
- `--module` + `--add-module`
- `--monorepo` + bare `--lang` (without paired `--module`)

Existing flags (`--postgresql`, `--mysql`, `--redis`, `--celery`, `--codex`, `--github-actions`, `--overwrite`, `-d/--dry-run`, `-y/--yes`) are mode-agnostic and continue to work as today.

### Shell function contracts

New helpers in `scripts/lib/common.sh`:

| Function | Signature | Purpose |
| --- | --- | --- |
| `detect_existing_monorepo` | `detect_existing_monorepo <target_dir> -> exit 0 if modules.json present` | Branch trigger for FR-8 |
| `prompt_monorepo_mode` | `prompt_monorepo_mode -> echoes "true"/"false"` (uses `/dev/tty`) | FR-1 |
| `prompt_module_loop` | `prompt_module_loop -> populates global MODULES array as `name:lang` strings`  | FR-2 |
| `prompt_add_module` | `prompt_add_module -> echoes "name:lang"` | FR-8 interactive entry |
| `validate_module_name` | `validate_module_name <name> -> exit 0/1` | Lowercase, alnum + `-`/`_`, no leading digit |
| `read_modules_json` | `read_modules_json <target_dir> -> jq stream of registry` | Reader for FR-9, FR-10 |
| `write_modules_json` | `write_modules_json <target_dir> <jq_filter>` | Atomic replace via `jq` + tmp + `mv` |
| `add_module_entry` | `add_module_entry <target_dir> <name> <lang> [<services>]` | Idempotent insert; if name exists, return non-zero (caller handles overwrite prompt) |
| `find_module_by_name` | `find_module_by_name <target_dir> <name> -> exit 0 if present` | FR-9 conflict check |
| `list_module_names` | `list_module_names <target_dir>` | Used by orchestrator dispatcher |
| `list_existing_compose_services` | `list_existing_compose_services <target_dir>` | FR-10 — diff against AVAILABLE_SERVICES |

New language plugin contract (additive — old plugins keep working unchanged):

```bash
# REQUIRED today (kept):
plugin_name()               # echo "<id>"
plugin_description()        # echo "<desc>"
plugin_copy(target_dir)
plugin_dockerfile(target_dir)
plugin_post_copy(target_dir)        # backward-compat shim — language plugins reimplement as:
                                    #   plugin_post_copy_shared "$1"
                                    #   plugin_post_copy_module "$1" "${PROJECT_NAME}"

# NEW for language plugins (only language plugins implement these):
plugin_post_copy_shared(target_dir)
plugin_post_copy_module(target_dir, module_name)
```

Service / core / claude / codex / github-actions plugins do **not** implement `_shared` / `_module` — orchestrator detects their absence via `declare -f plugin_post_copy_module` and falls back to `plugin_post_copy(target_dir)` for those plugins in both modes.

### `modules.json` schema

```json
{
  "version": 1,
  "modules": [
    {
      "name": "jing",
      "path": "jing",
      "language": "python",
      "services": []
    }
  ]
}
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `version` | integer | yes | Schema version. Starts at `1`. Bumped on breaking change; readers must reject unknown majors. |
| `modules[].name` | string | yes | Module identifier. Matches `^[a-z][a-z0-9_-]*$`. Unique within file. |
| `modules[].path` | string | yes | Directory path relative to repo root. Equal to `name` for now (kept as separate field for future flexibility). |
| `modules[].language` | string | yes | One of the `AVAILABLE_LANGUAGES` ids. |
| `modules[].services` | array of string | yes (may be empty) | Services this module declared at registration time (informational; the actual compose runs project-wide). |

Future-extensible (NFR-2): readers ignore unknown top-level keys and unknown per-module keys. Adding fields like `commands`, `version_file`, `package` (à la elsur) is non-breaking. The `version` field is the breaking-change escape hatch.

## Data Flow

### One-shot monorepo init (interactive)

```
1. main() → parse_arguments → MONOREPO_MODE=false (default)
2. project name resolved (existing flow)
3. NEW: prompt_monorepo_mode → MONOREPO_MODE=true
4. NEW: prompt_module_loop → MODULES=("jing:python" "kir:node")
5. NEW: derive SELECTED_LANGUAGES = unique(language_of(m) for m in MODULES) = ("python" "node")
6. prompt_service_selection (existing) → SELECTED_SERVICES=("postgresql")
7. confirm + load plugins (existing — both python & node language plugins, postgres service plugin)
8. execute_plugin_copies(target_dir) — existing
9. execute_plugin_dockerfiles(target_dir) — existing; produces union Dockerfile (FR-5)
10. NEW: execute_plugin_post_copies in monorepo mode:
    For each loaded plugin:
        if is_language_plugin(p) and MONOREPO_MODE:
            plugin_post_copy_shared(root)
            for module in MODULES where lang(module) == lang(p):
                mkdir -p root/<module>
                plugin_post_copy_module(root/<module>, <module>)
        else:
            plugin_post_copy(root)
11. NEW: core plugin's plugin_post_copy (in monorepo mode) writes modules.json
    from MODULES and writes <module>/CLAUDE.md per registered module
12. replace_placeholders(target_dir, project_name) — existing
13. update_gitignore — existing
```

### Add-module (interactive)

```
1. main() → parse_arguments → no relevant flags
2. NEW: detect_existing_monorepo(cwd) → returns 0
3. NEW: prompt: "Existing monorepo detected. Add a new module? (y/n)"
4. If y: prompt for name + language → MODULES=("foo:python")
5. NEW: find_module_by_name(cwd, "foo") → if present, prompt overwrite (FR-9). On 'n', exit 0.
6. NEW: list_existing_compose_services(cwd) → diff against AVAILABLE_SERVICES → prompt only the unselected (FR-10)
7. Load only the language plugin for "foo" (python) and any newly-selected services
8. execute_plugin_dockerfiles — runs (idempotent: language toolchain block guarded by marker comment;
   if absent it appends, if present it skips — same pattern as update_gitignore)
9. execute_plugin_post_copies in monorepo mode (one module, one language)
10. add_module_entry to modules.json (or replace if overwrite confirmed)
11. update_gitignore (idempotent)
```

The language plugin `_shared` hook is structured to be **idempotent** in monorepo mode: it patches `.devcontainer/devcontainer.json` and `.claude/settings.json` via the existing `merge_devcontainer_json` / `merge_*` helpers (which already merge rather than overwrite), and `.devcontainer/scripts/post.sh` lines are guarded by marker comments analogous to `update_gitignore`'s block-level idempotency (architecture.md "Cross-cutting Concerns"). This means add-module re-running for an already-registered language is a no-op for shared assets.

### Idempotency contract for add-module (NFR-3)

| Asset | Mechanism |
| --- | --- |
| `modules.json` | `add_module_entry` rejects duplicates; explicit overwrite prompt |
| `<module>/` files | `copy_with_confirm` already prompts (or honors `--overwrite`) |
| Root `Dockerfile.dev` language block | Marker comment guard (`# >>> python (uv) toolchain >>>` / `<<< python (uv) toolchain <<<`) — appended by `plugin_dockerfile` only if marker absent |
| Root `.devcontainer/devcontainer.json` | `merge_devcontainer_json` merges arrays/objects, no duplicates |
| Root `.claude/settings.json` | `merge_*` helper, idempotent |
| Root `post.sh` language block | Marker comment guard, mirroring the existing `# PostgreSQL Client Setup` pattern in `templates/services/postgresql/plugin.sh` |
| `docker-compose.yml` services | `merge_docker_compose_services` is already idempotent for service plugins; for add-module language plugins it is a no-op (no compose entries) |
| `.gitignore` blocks | Existing block-level idempotency in `update_gitignore` (#259) |

The marker-comment pattern for `Dockerfile.dev` and `post.sh` is the only **new** idempotency contract in this issue; all other guards already exist in the codebase.

## Error Handling

| Error | Source | Behavior |
| --- | --- | --- |
| Mutually-exclusive flag combo (`--monorepo` + `--add-module`, etc.) | `parse_arguments` | `print_error` with usage hint; exit 1 |
| `--add-module` outside a monorepo (no `modules.json`) | `parse_arguments` post-validation | `print_error "Run with --monorepo first"`; exit 1 |
| `--module name:lang` with unknown `lang` | `parse_arguments` | `print_error` listing `AVAILABLE_LANGUAGES`; exit 1 |
| Module name fails `validate_module_name` | `prompt_module_loop` / `parse_arguments` | `print_warning`, re-prompt (interactive) or exit 1 (CLI) |
| Module name conflict in `add-module` | `add_module_entry` | Bubble up; caller prompts overwrite (FR-9); on `n`, return 0 (no-op) |
| `modules.json` malformed (manual edit) | `read_modules_json` | `print_error` with `jq` error; exit 1 |
| `modules.json` `version` newer than supported | `read_modules_json` | `print_error "Unsupported modules.json version: <N>; please upgrade setup.sh"`; exit 1 |
| Empty module loop in interactive monorepo init | `prompt_module_loop` | `print_warning "At least one module is required"`; re-enter loop |
| `jq` missing | `check_dependencies` (existing) | Existing fail-fast; no change |

All single-project-mode errors are unchanged (NFR-1).

## Implementation Notes

- **Plugin scope detection** uses a path-substring check: `[[ "$plugin_path" == */templates/languages/* ]]`. This is robust because `LOADED_PLUGINS` already stores absolute paths, and language plugins live under exactly that directory by convention. No new metadata is introduced.
- **Backward-compat shim**: each language plugin's existing `plugin_post_copy` becomes a 2-line wrapper:
  ```bash
  plugin_post_copy() {
      local target_dir="$1"
      plugin_post_copy_shared "$target_dir"
      plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
  }
  ```
  This guarantees that even if `setup.sh` is replaced with an older version, language plugins still work in single mode.
- **`PROJECT_NAME` as the default `module_name` in single mode** preserves the existing `src/${PROJECT_NAME}/__init__.py` convention. In monorepo mode, `module_name` becomes the module id (e.g., `src/jing/__init__.py` for the jing module).
- **`modules.json` writes** go through a `jq | mv` atomic replace pattern to avoid half-written files if the user `^C`s mid-write — mirrors the `temp_file` + `mv` approach used throughout the existing service plugins.
- **`MODULES` array shape** in setup.sh: `MODULES=("jing:python" "kir:node")`. Internal helpers split on `:` (POSIX-safe; module names are validated to disallow `:`). This avoids needing a parallel array and matches the `--module` flag grammar 1:1.
- **Schema versioning** (`version: 1`): rejecting unknown majors at read time gives us a clean upgrade path if elsur-style fields like `commands` need typed contracts later.
- **Edge case — `--celery` in monorepo mode**: Celery already auto-includes Redis and Python (existing logic in `parse_arguments`/`prompt_service_selection`). In monorepo mode, the auto-included Python is added to `SELECTED_LANGUAGES`, but no module necessarily uses Python yet — so the user must declare a Python module explicitly, otherwise `plugin_post_copy_module` runs zero times for Python. The `plugin_post_copy_shared` for Python still runs (toolchain in shared Dockerfile is fine to have unused). Document this in `--help` text.
- **Edge case — `latex` plugin in monorepo mode**: LaTeX modules don't fit the `pyproject.toml`-style scaffold split. Initial implementation treats `latex` like any other language but flags this in `--help` as "experimental in monorepo mode". Refinement deferred.
- **Out of scope (deferred)**:
  - Per-module `.devcontainer/<module>/devcontainer.json` (the elsur "Reopen in Container per module" experience).
  - GitHub Actions matrix workflows driven by `modules.json`.
  - Per-module language switch (a single module changing language post-init).
- **Verification strategy**: a manual matrix in `workflow.md` covers single-project regression for each of the 5 languages, monorepo init for representative combos (python+node, python only, rust only), add-module on an existing monorepo, conflict overwrite, and the curl-pipe path.
