# Workflow: #263 feat(setup): support monorepo layout with per-module scaffolds

Implementation steps for the monorepo support feature. Sequenced to land foundation pieces first (helpers + schema), then orchestrator changes, then per-language plugin splits, then docs and verification. Single-project mode must remain byte-identical at every step (NFR-1).

## Implementation Steps

### Step 1 — Add `modules.json` schema templates and shared helpers

- **Action**:
  - Create `templates/core/modules.json.template` with `{ "version": 1, "modules": [] }`.
  - Create `templates/core/module.CLAUDE.md.template` with placeholders `{{MODULE_NAME}}` and `{{MODULE_LANGUAGE}}`.
  - Add to `scripts/lib/common.sh`: `read_modules_json`, `write_modules_json`, `add_module_entry`, `find_module_by_name`, `list_module_names`, `list_existing_compose_services`, `validate_module_name`, `detect_existing_monorepo`. Each conforms to `.claude/rules/shell.md` (set -euo pipefail-safe, quoted vars, `[[ ]]`, `local`, `print_*`).
  - Use `jq` for all JSON read/write; atomic replace via tmp + `mv` (existing pattern).
- **Files**:
  - `scripts/lib/common.sh` (modified)
  - `templates/core/modules.json.template` (new)
  - `templates/core/module.CLAUDE.md.template` (new)
- **Depends on**: nothing (foundation)
- **Done when**:
  - All helpers callable from a throwaway test script with `bash -c 'source scripts/lib/common.sh; <fn> ...'`.
  - `read_modules_json` rejects `version: 2` with the specified error.
  - `add_module_entry` returns `2` on duplicate names.

### Step 2 — Extend `setup.sh` argument parsing and globals

- **Action**:
  - Add globals: `MONOREPO_MODE=false`, `MODULES=()`, `IS_ADD_MODULE_MODE=false`, `ADD_MODULE_NAME=""`, `ADD_MODULE_LANG=""`.
  - Extend `parse_arguments`: handle `--monorepo`, `--module <name>:<lang>` (with `:` split + validation), `--add-module <name>` (require trailing `--lang <lang>`).
  - Add post-parse validation block: detect mutually-exclusive combos (table in `api-spec.md`), reject `--monorepo` + bare `--lang`, etc., and `print_error` + exit 1.
  - Update `show_help` to include the new flags + 4 example invocations (single, monorepo init CLI, monorepo init interactive, add-module).
- **Files**: `setup.sh` (modified)
- **Depends on**: Step 1 (uses `validate_module_name`)
- **Done when**:
  - `./setup.sh --monorepo --module jing:python --module kir:node --dry-run` parses without error and prints the expected configuration.
  - `./setup.sh --monorepo --add-module foo` exits 1 with mutually-exclusive error.
  - `./setup.sh --add-module foo` (no `--lang`, no existing modules.json) exits 1 with the "no modules.json" message.
  - `./setup.sh --help` shows the new flags and examples.
  - `./setup.sh --lang rust --dry-run` (single mode) is byte-identical to today (regression).

### Step 3 — Add interactive prompts and detection in `setup.sh`

- **Action**:
  - Add `prompt_monorepo_mode` to `common.sh` (Step 1 may have already added; otherwise add here).
  - Add `prompt_module_loop` (interactive name + language loop).
  - Add `prompt_add_module` (single name + language prompt).
  - In `main()`, after project name resolution and before language selection:
    1. If `IS_ADD_MODULE_MODE` and CLI provided `name`/`lang` → skip prompt.
    2. Else if `detect_existing_monorepo` succeeds → prompt "Existing monorepo detected. Add a new module? (y/n)" → on `y`, set `IS_ADD_MODULE_MODE=true`, call `prompt_add_module`.
    3. Else if `MONOREPO_MODE` (from `--monorepo`) and no `--module` flags → call `prompt_module_loop`.
    4. Else if neither flag → call `prompt_monorepo_mode`; on `y` call `prompt_module_loop`.
  - In monorepo mode, derive `SELECTED_LANGUAGES` from `MODULES` after the loop.
  - Service selection (`prompt_service_selection`) runs unchanged after this block. In add-module mode, restrict the offered list to `AVAILABLE_SERVICES \ list_existing_compose_services` (FR-10).
- **Files**: `setup.sh`, `scripts/lib/common.sh` (both modified)
- **Depends on**: Step 2
- **Done when**:
  - Interactive run: answering "y" to monorepo + entering 2 modules + selecting PostgreSQL produces the correct in-memory configuration (visible via `--dry-run`).
  - Re-running interactively against a directory with `modules.json` triggers the add-module prompt.
  - `prompt_module_loop` rejects invalid names, re-prompts, and accepts an empty name to terminate.

### Step 4 — Refactor language plugins to split `plugin_post_copy`

- **Action**: For each of `python`, `rust`, `node`, `deno`, `latex`:
  - Identify lines in `plugin_post_copy` that touch `${target_dir}/.devcontainer/`, `${target_dir}/.claude/`, `${target_dir}/.devcontainer/scripts/post.sh` → move to new `plugin_post_copy_shared(target_dir)`.
  - Identify lines that touch `${target_dir}/<lang-config>` (e.g., `pyproject.toml`, `Cargo.toml`, `package.json`, `ruff.toml`, etc.), `${target_dir}/src/`, `${target_dir}/tests/` → move to new `plugin_post_copy_module(target_dir, module_name)`.
  - Replace any `${target_dir}/src/${PROJECT_NAME}` paths with `${target_dir}/src/${module_name}` in `_module`, where `module_name` is the second arg.
  - Wrap `plugin_dockerfile`'s appended language block with marker comments: `# >>> <lang> toolchain >>>` / `<<< <lang> toolchain <<<`. Add a `grep -q` guard at function entry so re-running is idempotent.
  - Wrap `plugin_post_copy_shared`'s `post.sh` appends in marker comments analogously.
  - Replace the existing `plugin_post_copy` body with the shim that calls `_shared` then `_module "$1" "${PROJECT_NAME}"`.
- **Files**:
  - `templates/languages/python/plugin.sh`
  - `templates/languages/rust/plugin.sh`
  - `templates/languages/node/plugin.sh`
  - `templates/languages/deno/plugin.sh`
  - `templates/languages/latex/plugin.sh`
- **Depends on**: nothing (can run in parallel with Steps 1–3)
- **Done when**:
  - Single-project regression: `./setup.sh --lang <each language> -y --overwrite` in a fresh dir produces a project that is byte-identical to today (use `git diff --no-index` against a baseline produced from `develop`).
  - `plugin_dockerfile` is idempotent: running `setup.sh --lang python -y --overwrite` twice produces no duplicate Python toolchain block.

### Step 5 — Extend orchestrator dispatch in `setup.sh`

- **Action**:
  - Modify `execute_plugin_post_copies(target_dir)`:
    - For each `plugin_path` in `LOADED_PLUGINS`:
      - Compute `is_lang := [[ "$plugin_path" == */templates/languages/* ]]`.
      - Source plugin; run `plugin_interactive_setup` if applicable (existing behavior).
      - If `MONOREPO_MODE && is_lang && declare -f plugin_post_copy_module > /dev/null`:
        - Call `plugin_post_copy_shared "$target_dir"`.
        - Compute the plugin's language id from the parent directory name (`basename "$(dirname "$plugin_path")"`).
        - For each module in `MODULES` whose language matches: `mkdir -p "$target_dir/$module_name"`; `plugin_post_copy_module "$target_dir/$module_name" "$module_name"`.
      - Else: call `plugin_post_copy "$target_dir"` (single mode + non-language plugins).
  - Unset plugin functions between iterations as today.
- **Files**: `setup.sh` (modified)
- **Depends on**: Steps 2, 3, 4
- **Done when**:
  - Monorepo init with `--module jing:python --module kir:node` produces `jing/` and `kir/` with the expected scaffolds, plus a single shared `.devcontainer/Dockerfile.dev` with both Python and Node toolchain blocks.
  - Single-mode regression unchanged.

### Step 6 — Wire monorepo writes into `core` plugin

- **Action**:
  - Modify `templates/core/plugin.sh::plugin_post_copy(target_dir)`:
    - Existing root-asset copy (Dockerfile, devcontainer, .claude, docker-compose) unchanged.
    - If `MONOREPO_MODE`:
      - Copy `modules.json.template` → `target_dir/modules.json` (only if not already present — supports add-module).
      - For each module in `MODULES`: `add_module_entry` (in init mode, all modules; in add-module mode, just the new one); write `target_dir/<module>/CLAUDE.md` from `module.CLAUDE.md.template` with `MODULE_NAME` / `MODULE_LANGUAGE` substituted via `sed`.
- **Files**: `templates/core/plugin.sh` (modified)
- **Depends on**: Steps 1, 5
- **Done when**:
  - After monorepo init, `modules.json` lists all modules; each `<module>/CLAUDE.md` exists with correct substitutions.
  - After add-module, `modules.json` gains the new entry without disturbing existing ones; new `<module>/CLAUDE.md` written.

### Step 7 — Idempotency hardening + add-module path

- **Action**:
  - Verify `merge_devcontainer_json` and `merge_*_json` helpers in `common.sh` are idempotent for add-module re-runs (they should be; if not, add early-out guards).
  - Verify the marker-guarded `Dockerfile.dev` blocks (Step 4) skip on re-run.
  - Verify the marker-guarded `post.sh` blocks skip on re-run.
  - Add explicit conflict prompt logic in `main()` for add-module: before `add_module_entry`, call `find_module_by_name`; on hit, prompt overwrite (FR-9). Default `n`.
  - Wire `--overwrite` flag to bypass the prompt.
- **Files**: `setup.sh` (modified); possibly `scripts/lib/common.sh`
- **Depends on**: Steps 4, 5, 6
- **Done when**:
  - `./setup.sh --add-module jing --lang python` against an existing monorepo with jing already registered prompts overwrite. Answering `n` exits 0 with no diff. Answering `y` (or passing `--overwrite -y`) regenerates the module files.
  - Two consecutive add-module invocations for distinct modules produce a clean `modules.json` with both entries and no duplicate Dockerfile/post.sh blocks.

### Step 8 — Documentation

- **Action**:
  - Update `README.md`: add a "Monorepo support" section with example commands (single + monorepo + add-module + curl-pipe).
  - Update `setup.sh --help` (already done in Step 2 but verify final wording).
  - Update `CLAUDE.md` if monorepo concepts need to be surfaced for Claude Code workflows.
- **Files**: `README.md`, `setup.sh` (`show_help`), optionally `CLAUDE.md`
- **Depends on**: Steps 2–7 stable
- **Done when**: README has accurate, copy-pasteable examples; `--help` text reflects the final flag set.

### Step 9 — Manual verification matrix

- **Action**: Run the verification matrix below against a clean target directory (`mkdir /tmp/sandbox && cd /tmp/sandbox && git init`).
- **Files**: none (verification only)
- **Depends on**: all prior steps
- **Done when**: every row passes; any failures trigger return to the relevant step.

## Task Dependencies

```
Step 1 (foundation: helpers + templates)
  ↓
Step 2 (setup.sh args + globals) ──── Step 4 (language plugin split — independent, parallelizable)
  ↓                                     ↓
Step 3 (interactive prompts + main flow branching)
  ↓
Step 5 (orchestrator dispatch) ←──── Step 4 must be done
  ↓
Step 6 (core plugin: modules.json + per-module CLAUDE.md)
  ↓
Step 7 (idempotency + add-module conflict path)
  ↓
Step 8 (docs)
  ↓
Step 9 (manual verification)
```

Steps 1 and 4 can be developed in parallel (independent files). All other steps are sequential because Step 5's dispatch logic depends on the language-plugin function split being in place, and Step 6's `add_module_entry` calls depend on Step 1's helpers.

## Test Strategy

The repo today has integration tests for the Rust crate (`tests/`) and no automated tests for `setup.sh`. This issue stays in line with that — verification is **manual**, executed against ephemeral sandbox directories. A future issue could add a shell-test framework (bats, etc.) but is out of scope here.

### Manual verification matrix

| # | Scenario | Command | Expected |
| --- | --- | --- | --- |
| V1 | Single regression — Rust | `./setup.sh --lang rust -y --overwrite` | Identical to baseline (no diff vs `develop` output) |
| V2 | Single regression — Python | `./setup.sh --lang python -y --overwrite` | Identical to baseline |
| V3 | Single regression — Node | `./setup.sh --lang node -y --overwrite` | Identical to baseline |
| V4 | Single regression — Deno | `./setup.sh --lang deno -y --overwrite` | Identical to baseline |
| V5 | Single regression — LaTeX | `./setup.sh --lang latex -y --overwrite` | Identical to baseline |
| V6 | Single + service — Python + PostgreSQL | `./setup.sh --lang python --postgresql -y --overwrite` | Identical to baseline; `docker compose up` still works |
| V7 | Single + Codex + GH Actions | `./setup.sh --lang rust --codex --github-actions -y --overwrite` | Identical to baseline |
| V8 | Monorepo init — interactive (2 modules, 1 service) | `./setup.sh` then `myapp` → `y` (monorepo) → `jing:python`, `kir:node`, empty → `postgresql` → confirm | `jing/`, `kir/`, `modules.json`, single `.devcontainer/`, `myapp-db` in compose, both Python and Node in Dockerfile |
| V9 | Monorepo init — CLI | `./setup.sh --monorepo --module jing:python --module kir:node --postgresql -y` | Same outcome as V8 |
| V10 | Monorepo init — single module | `./setup.sh --monorepo --module foo:python -y` | `foo/`, modules.json with one entry |
| V11 | Add module — interactive (auto-detect) | After V8, run `./setup.sh` in same dir → "y" to add → `anisette` + `python` → no new services | `anisette/` created, modules.json gains entry, no duplicate Dockerfile/post.sh blocks |
| V12 | Add module — CLI | After V8, `./setup.sh --add-module anisette --lang python -y` | Same outcome as V11 |
| V13 | Add module — conflict, decline | After V8, `./setup.sh --add-module jing --lang python` → answer `n` | Exit 0, no diff |
| V14 | Add module — conflict, accept (overwrite) | After V8, `./setup.sh --add-module jing --lang python --overwrite -y` | `jing/` regenerated; modules.json entry replaced |
| V15 | Add module — adds new service only | After V8, `./setup.sh --add-module foo --lang python --redis -y` | `myapp-redis` added to compose; `myapp-db` unchanged |
| V16 | Reject — `--monorepo --add-module` | `./setup.sh --monorepo --add-module foo --lang python` | Exit 1 with mutually-exclusive error |
| V17 | Reject — `--monorepo --lang` (no `--module`) | `./setup.sh --monorepo --lang python` | Exit 1 with usage error |
| V18 | Reject — `--add-module` without monorepo | (in empty dir) `./setup.sh --add-module foo --lang python` | Exit 1 with "no modules.json" message |
| V19 | Reject — invalid module name | `./setup.sh --monorepo --module 1bad:python` | Exit 1 with validation error |
| V20 | Curl pipe — monorepo init | `mkdir /tmp/c && cd /tmp/c && git init && curl -fsSL <repo>/setup.sh \| bash -s -- --monorepo --module jing:python --module kir:node -y` | Same outcome as V9 |
| V21 | Curl pipe — add-module | (after V20) `curl -fsSL <repo>/setup.sh \| bash -s -- --add-module foo --lang python -y` | Same outcome as V12 |
| V22 | `docker compose up` — monorepo with PostgreSQL | After V8, `docker compose up -d` then `docker compose exec myapp psql -h myapp-db -U postgres -d myapp -c '\\l'` | Connection succeeds |
| V23 | Idempotency — re-run init | After V9, run V9 again with `--overwrite -y` | Files regenerated; no duplicate blocks anywhere |
| V24 | `modules.json` — unsupported version | Manually set `version: 2` in modules.json then run `./setup.sh --add-module foo --lang python` | Exit 1 with "Unsupported modules.json version" |

### Unit-test-shaped checks (manual sourcing)

For the new `common.sh` helpers, run quick sanity checks:

```bash
source scripts/lib/common.sh

validate_module_name "good-name" && echo OK
validate_module_name "1bad" || echo OK   # rejected
validate_module_name "Bad" || echo OK    # rejected (uppercase)

mkdir -p /tmp/m && echo '{"version":1,"modules":[]}' > /tmp/m/modules.json
add_module_entry /tmp/m foo python && echo OK
add_module_entry /tmp/m foo python ; [[ $? -eq 2 ]] && echo OK   # duplicate
find_module_by_name /tmp/m foo && echo OK
list_module_names /tmp/m   # → "foo"
```

### Edge cases explicitly verified

- Empty `MODULES` after monorepo prompt: re-loop until ≥1 module is given.
- Module name with `:` in it: rejected by `validate_module_name`.
- Re-running `--add-module` for a module whose language plugin's shared block is already in `Dockerfile.dev`: marker guard prevents duplicate.
- `--celery` in monorepo mode without any Python module: warning that Python toolchain is added but unused; user can declare a Python module afterwards via add-module.
- `latex` language in monorepo mode: works mechanically; flagged as "experimental" in `--help`.

## Out of scope (deferred to follow-up issues)

- Per-module `.devcontainer/<module>/devcontainer.json` (elsur-style "Reopen in Container per module").
- GitHub Actions matrix workflows driven by `modules.json` (separate issue).
- Per-module independent docker-compose service stacks (e.g., `<module>-db` per module). The current model is one shared `<project>-db` per project.
- Migration tooling for existing single-project setups → monorepo conversion.
- Module rename / remove / language-change subcommands.
