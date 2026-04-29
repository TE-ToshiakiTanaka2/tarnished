# API Specification: #263 feat(setup): support monorepo layout with per-module scaffolds

This issue's public surface is the `setup.sh` CLI grammar, the `scripts/lib/common.sh` shell-function contracts, the language-plugin function contract, and the `modules.json` file schema.

## CLI Surface (`setup.sh`)

### New flags

| Flag | Argument | Repeatable | Mode | Description |
| --- | --- | --- | --- | --- |
| `--monorepo` | (none) | no | init | Enable monorepo mode for fresh init. If `--module` is also given, the module loop is skipped. |
| `--module` | `<name>:<lang>` | yes | init | Define a module. Implies `--monorepo`. |
| `--add-module` | `<name>` | no | add | Add a single module to an existing monorepo. Pair with `--lang <lang>`. Requires CWD to contain `modules.json`. |

### Existing flags (behavior unchanged)

`-h/--help`, `-d/--dry-run`, `-y/--yes`, `--lang <language>` (single mode + add-module mode), `--codex`, `--postgresql`, `--mysql`, `--redis`, `--celery`, `--github-actions`, `--overwrite` — unchanged from current behavior. Single-project flow is byte-for-byte identical (NFR-1).

### Mutually-exclusive combinations (rejected with exit 1)

| Combination | Reason |
| --- | --- |
| `--monorepo --add-module <name>` | Init vs. add are exclusive operations |
| `--module ... --add-module <name>` | `--module` is init-only |
| `--monorepo --lang <lang>` (without `--module`) | In monorepo mode, language is per-module; use `--module name:lang` |
| `--add-module <name>` outside a monorepo (no CWD `modules.json`) | Run with `--monorepo` first |

### Examples

```bash
# Single-project (existing — unchanged)
./setup.sh                                                        # interactive
./setup.sh --lang rust                                            # CLI
./setup.sh --lang python --postgresql -y                          # CLI + auto-confirm

# Monorepo — interactive
./setup.sh                                                        # answer "y" to monorepo prompt
                                                                  # then enter modules in the dialogue loop

# Monorepo — CLI (one-shot init)
./setup.sh --monorepo --module jing:python --module kir:node
./setup.sh --monorepo --module jing:python --module kir:node --postgresql --redis -y

# Monorepo — add a module to an existing one
./setup.sh --add-module anisette --lang python                    # explicit
./setup.sh                                                        # implicit (auto-detected via modules.json)

# Curl-pipe (primary distribution path; FR-12)
curl -fsSL .../setup.sh | bash -s -- --monorepo --module jing:python --module kir:node
curl -fsSL .../setup.sh | bash -s -- --add-module foo --lang python -y
```

## Shell Function Contracts

### `scripts/lib/common.sh` — new helpers

| Function | Signature | Returns | Side effects |
| --- | --- | --- | --- |
| `detect_existing_monorepo` | `detect_existing_monorepo <target_dir>` | `0` if `<target_dir>/modules.json` exists, `1` otherwise | none |
| `prompt_monorepo_mode` | `prompt_monorepo_mode` | echoes `"true"` or `"false"` to stdout | reads from `/dev/tty`; `print_*` helpers to stderr |
| `prompt_module_loop` | `prompt_module_loop` | mutates global `MODULES` array (append) | reads `/dev/tty`; per-iteration prompts; loop ends on empty `name`; `print_warning` on validation fail and re-prompt |
| `prompt_add_module` | `prompt_add_module` | echoes `<name>:<lang>` | reads `/dev/tty`; uses `validate_module_name` |
| `validate_module_name` | `validate_module_name <name>` | `0` if valid, `1` otherwise | none. Regex: `^[a-z][a-z0-9_-]*$`, max 50 chars |
| `read_modules_json` | `read_modules_json <target_dir>` | streams parsed `modules` array on stdout (jq) | exits non-zero on malformed JSON or unsupported `version` |
| `write_modules_json` | `write_modules_json <target_dir> <jq_filter>` | `0` on success | atomic replace via tmp + `mv` |
| `add_module_entry` | `add_module_entry <target_dir> <name> <lang> [<services_csv>]` | `0` on success, `2` if name already exists | mutates `modules.json` via `write_modules_json` |
| `find_module_by_name` | `find_module_by_name <target_dir> <name>` | `0` if present, `1` otherwise | none |
| `list_module_names` | `list_module_names <target_dir>` | newline-separated names on stdout | none |
| `list_existing_compose_services` | `list_existing_compose_services <target_dir>` | newline-separated service ids on stdout | none. Used to compute the un-added subset of `AVAILABLE_SERVICES` for FR-10 |

All new helpers conform to `.claude/rules/shell.md` (`set -euo pipefail`-safe, quoted vars, `[[ ]]`, `local`, `print_*` for output).

### Language plugin contract (additive — `templates/languages/<lang>/plugin.sh`)

```bash
# REQUIRED today, kept verbatim:
plugin_name()                       # echo "<id>"
plugin_description()                # echo "<desc>"
plugin_copy(target_dir)             # root-scoped (e.g. .github/workflows/<lang>-quality-check.yml)
plugin_dockerfile(target_dir)       # appends marker-guarded language block to docker/Dockerfile.dev

# REQUIRED today, becomes a SHIM that delegates to the new pair:
plugin_post_copy(target_dir) {
    local target_dir="$1"
    plugin_post_copy_shared "$target_dir"
    plugin_post_copy_module "$target_dir" "${PROJECT_NAME}"
}

# NEW for language plugins only:
plugin_post_copy_shared(target_dir)
plugin_post_copy_module(target_dir, module_name)
```

| Hook | Arguments | What it MAY touch | What it MUST NOT touch |
| --- | --- | --- | --- |
| `plugin_post_copy_shared` | `target_dir` (= project root) | `target_dir/.devcontainer/`, `target_dir/.claude/`, `target_dir/docker/Dockerfile.dev` (idempotent — marker-guarded), `target_dir/.devcontainer/scripts/post.sh` (marker-guarded) | Module sub-directories |
| `plugin_post_copy_module` | `target_dir` (= `<root>/<module>` in monorepo mode, `<root>` in single mode), `module_name` | Files inside `target_dir`: `pyproject.toml`/`Cargo.toml`/`package.json`, `ruff.toml`/equivalent, `src/<module_name>/`, `tests/`, `<lang>.gitignore`, `CLAUDE.md` for the module | `target_dir/.devcontainer/`, `target_dir/.claude/`, `target_dir/docker/`, root `docker-compose.yml` |

`plugin_post_copy_shared` and `plugin_post_copy_module` MUST both be **idempotent** so that re-running `setup.sh --add-module` for an already-registered language is a no-op for shared assets and obeys `--overwrite` for module assets.

### Non-language plugin contract (`templates/{core,claude,codex,services/<svc>,github-actions/<wf>}/plugin.sh`)

Unchanged. These plugins continue to implement only `plugin_post_copy(target_dir)` and operate on `target_dir = project root` in both modes.

`templates/core/plugin.sh::plugin_post_copy` gains an internal monorepo-mode branch (gated on `${MONOREPO_MODE}`) that writes `modules.json` from the registered `MODULES` array and writes `<module>/CLAUDE.md` per module — this is internal logic, not a contract change.

### Orchestrator dispatch (`setup.sh::execute_plugin_post_copies`)

```
for plugin_path in LOADED_PLUGINS:
    is_lang := [[ "$plugin_path" == */templates/languages/* ]]
    source plugin_path
    if declare -f plugin_interactive_setup && check_tty_available:
        plugin_interactive_setup

    if MONOREPO_MODE && is_lang && declare -f plugin_post_copy_module:
        plugin_post_copy_shared root
        for module in MODULES where lang(module) == lang(plugin):
            mkdir -p root/<module>
            plugin_post_copy_module root/<module> <module>
    else:
        plugin_post_copy root
```

In single mode the dispatcher takes the `else` branch for all plugins, preserving today's behavior exactly. The `lang(module) == lang(plugin)` filter ensures a language plugin's `_module` runs only for modules that selected it (Python plugin runs `_module` only for Python modules).

## File Schemas

### `modules.json` (root of monorepo target; FR-4)

```json
{
  "version": 1,
  "modules": [
    {
      "name": "jing",
      "path": "jing",
      "language": "python",
      "services": []
    },
    {
      "name": "kir",
      "path": "kir",
      "language": "node",
      "services": []
    }
  ]
}
```

| Field | Type | Required | Constraints |
| --- | --- | --- | --- |
| `version` | integer | yes | Currently `1`. Readers MUST reject unknown majors. |
| `modules` | array | yes | May be empty (no modules yet) but typically ≥1 after init. |
| `modules[].name` | string | yes | `^[a-z][a-z0-9_-]*$`, max 50 chars, unique within file |
| `modules[].path` | string | yes | Relative to repo root. For now equal to `name`; field reserved for future flexibility (e.g., nested layouts) |
| `modules[].language` | string | yes | One of `AVAILABLE_LANGUAGES`: `rust`, `python`, `node`, `deno`, `latex` |
| `modules[].services` | array of string | yes | May be empty. Informational record of which services the module declared at registration time; the actual compose services run project-wide |

**Forward compatibility (NFR-2)**: readers ignore unknown top-level keys and unknown per-module keys. `version: 1 → 2` is the breaking-change escape hatch (e.g., for elsur-style `commands`/`version_file` if those grow typed contracts later).

**Idempotency**: `add_module_entry` rejects an existing `name` with exit code `2`; the caller (interactive `add-module` flow) translates this into the "Overwrite? (y/n)" prompt (FR-9).

### `templates/core/modules.json.template` (NEW)

```json
{
  "version": 1,
  "modules": []
}
```

Minimal seed; `core::plugin_post_copy` reads this, mutates the `modules` array based on the registered `MODULES`, and writes the result.

### `templates/core/module.CLAUDE.md.template` (NEW)

Markdown stub with two placeholders:

```
# {{MODULE_NAME}}

Module language: {{MODULE_LANGUAGE}}

<!-- This file is auto-generated by setup.sh and is safe to edit. -->
```

Substitution happens via `replace_placeholders` extension (existing function gains `MODULE_NAME` / `MODULE_LANGUAGE` substitutions when the function is called for a per-module path) — or, more cleanly, the `core::plugin_post_copy` writes each module's `CLAUDE.md` directly with `sed` substitution at write time, scoped to that module's values. The latter avoids mixing module-scoped placeholders into the global `replace_placeholders` pass.

## Error Responses

| Error | Where | Message (illustrative) | Behavior |
| --- | --- | --- | --- |
| Mutually-exclusive flag combo | `parse_arguments` | `[ERROR] --monorepo and --add-module are mutually exclusive` | exit 1 |
| `--add-module` outside monorepo | `parse_arguments` post-validation | `[ERROR] No modules.json found. Run with --monorepo first.` | exit 1 |
| Unknown `--module` language | `parse_arguments` | `[ERROR] Unknown language 'foo'. Available: rust python node deno latex` | exit 1 |
| Invalid module name | `validate_module_name` | `[WARN] Invalid module name '...'. Must match ^[a-z][a-z0-9_-]*$` | re-prompt (interactive) / exit 1 (CLI) |
| Module name conflict in `add-module` | `add_module_entry` returns 2 | "Module 'jing' already exists. Overwrite? (y/n)" | prompt; `n` = exit 0 (no-op), `y` = re-emit |
| Empty module loop | `prompt_module_loop` | `[WARN] At least one module is required` | re-enter loop |
| Malformed `modules.json` | `read_modules_json` | jq error wrapped: `[ERROR] modules.json parse failed: <jq err>` | exit 1 |
| Unsupported `version` | `read_modules_json` | `[ERROR] Unsupported modules.json version: 2 (max supported: 1)` | exit 1 |

All single-project errors are unchanged.
