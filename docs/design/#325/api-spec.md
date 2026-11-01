# API Specification: #325 Replace devcontainer features with mise runtimes, Dockerfile OS packages, and post.sh AI CLI installs

Shell-function and file-format surface introduced or changed by this issue.
No `setup.sh` flag is added or removed. The cumulative surface is in
[`../shared/api-spec.md`](../shared/api-spec.md).

## Endpoints / Functions (delta)

| Name | Method/Signature | Description |
| --- | --- | --- |
| `common.sh::mise_toml_ensure` | `mise_toml_ensure <mise_toml> <section> <key> <toml_value>` | NEW. Idempotent, user-entry-safe insert into `mise.toml` |
| `common.sh::dockerfile_add_os_packages` | `dockerfile_add_os_packages <dockerfile> <block_id> <package>...` | NEW. Marker-guarded apt block above the `SHELL` anchor |
| `common.sh::post_sh_add_block` | `post_sh_add_block <post_sh> <marker_line> [<before_marker_line>...]` (body on stdin) | NEW. Position-aware, marker-guarded `post.sh` block |
| `common.sh::merge_devcontainer_json` | unchanged | CHANGED. `features` merged as an ordinary top-level key |
| `common.sh::show_interactive_mode_error` | unchanged | CHANGED. Option list matches real flags (no `--playwright`) |
| `setup.sh::show_help` | unchanged | CHANGED. Runtimes come from `mise.toml`; latex listed |
| `setup.sh::check_dependencies` | unchanged | CHANGED. Also requires `awk` |
| `setup.sh::execute_plugin_dockerfiles` | `execute_plugin_dockerfiles <target_dir>` | CHANGED. Warns once when the Dockerfile has no `# >>> mise runtimes >>>` |
| `setup_mise.sh::setup_mise` | `setup_mise()` | NEW. `post.sh` entry (FR-9) |
| `setup_claude.sh::setup_claude` | `setup_claude()` | NEW. `post.sh` entry (FR-3) |
| `npm_global_cli.sh::install_npm_global_cli` | `install_npm_global_cli <display_name> <package_spec> <command>` | NEW. Library used by `setup_claude` / `setup_codex` |
| `setup_codex.sh::setup_codex` | `setup_codex()` | CHANGED. Delegates to `install_npm_global_cli` |
| `setup_plugins.sh::setup_plugins` | `setup_plugins()` | CHANGED. Driven by `enabledPlugins` (FR-8) |
| `templates/{python,node,rust,go,deno}/plugin.sh::plugin_post_copy_shared` | unchanged | CHANGED. Calls `mise_toml_ensure`; python loses `plugin_dockerfile` |
| `templates/services/{postgresql,mysql}/plugin.sh::plugin_dockerfile` | `plugin_dockerfile <target_dir>` | NEW hook implementation |
| `templates/core/plugin.sh::plugin_copy` / `plugin_post_copy` | unchanged | CHANGED. Copies `mise.toml`; appends mise + Claude blocks |
| `templates/codex/plugin.sh::plugin_post_copy` | unchanged | CHANGED. No devcontainer merge; block inserted before plugins |
| `templates/claude/plugin.sh::plugin_post_copy` | unchanged | CHANGED. Plugin block through `post_sh_add_block` |

### `mise_toml_ensure`

```text
mise_toml_ensure <mise_toml> <section> <key> <toml_value>
```

| Step | Behaviour |
| --- | --- |
| 1 | Reject `section` ∉ {`tools`, `env`, `settings`}, `key` not matching `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`, or an empty/multi-line `toml_value` → `print_error`, return 1 |
| 2 | File missing → create with the standard header comment |
| 3 | Key present (in `[section]` as bare or quoted (`"` or `'`) key, as a `[section.key]` table, or as top-level `section.key =`) → `print_info "kept existing <section>.<key>"`, return 0, no write |
| 4 | Section present → insert `key = toml_value` after the section's last non-blank line |
| 5 | Section absent → if top-level `section.<k> =` lines exist, insert `section.key = toml_value` after the last of them (a new `[section]` table would redefine them and make the TOML invalid); otherwise append blank line, `[section]`, `key = toml_value` |
| 6 | Write via same-directory `mktemp` + `mv`; failure → remove temp, `print_error`, return 1 |

Callers in plugins use `mise_toml_ensure ... || print_warning "..."` so a
failure never aborts `setup.sh` (which runs under `set -e`). The value is
inserted verbatim; callers single-quote TOML literals.

### `dockerfile_add_os_packages`

```text
dockerfile_add_os_packages <dockerfile> <block_id> <package>...
```

Emits, immediately before the first line matching `^SHELL `:

```dockerfile

# >>> <block_id> os-packages >>>
RUN apt-get update && apt-get install -y --no-install-recommends \
    <package> \
    && rm -rf /var/lib/apt/lists/*
# <<< <block_id> os-packages <<<

```

| Condition | Result |
| --- | --- |
| Dockerfile missing | `print_warning`, return 0 |
| Exact line `# >>> <block_id> os-packages >>>` present | `print_info` skip, return 0 |
| No `^SHELL ` line | `print_warning` listing the packages to add manually, file unchanged, return 0 |
| awk / `mv` failure | temp removed, `print_error`, return 1 |
| `block_id` not `^[a-z0-9][a-z0-9_-]*$` or no packages | `print_error`, return 1 |

Always marker-guarded, in every setup mode (no legacy byte-identity
obligation, unlike the #263 language blocks).

### `post_sh_add_block`

```text
post_sh_add_block <post_sh> <marker_line> [<before_marker_line>...] <<'EOF'
<body lines>
EOF
```

Generated text (the marker line is passed verbatim, e.g. `# Codex CLI Setup`):

```bash

# -----------------------------------------------------------------------------
<marker_line>
# -----------------------------------------------------------------------------
<body lines>
```

| Condition | Result |
| --- | --- |
| `post_sh` missing | return 0 silently (matches existing plugin behaviour) |
| `grep -qxF <marker_line>` | return 0, no write (idempotent) |
| Any `before_marker_line` present as an exact line | Insert the block before the earliest one. The insertion point moves up over the dashed rule line directly above that marker and over one blank line above the rule, so the inserted block is followed by the existing block's blank + rule + marker |
| None present / none given | Append at end of file |
| Write failure | temp removed, `print_error`, return 1 |

Marker catalog and required order: `# mise Runtime Setup` → `# Claude Code Setup`
→ `# Codex CLI Setup` → `# Claude Code Plugin Setup`.

| Caller | `marker_line` | `before_marker_line`s |
| --- | --- | --- |
| core | `# mise Runtime Setup` | `# Claude Code Setup`, `# Codex CLI Setup`, `# Claude Code Plugin Setup` |
| core | `# Claude Code Setup` | `# Codex CLI Setup`, `# Claude Code Plugin Setup` |
| codex | `# Codex CLI Setup` | `# Claude Code Plugin Setup` |
| claude | `# Claude Code Plugin Setup` | (none — append) |

Core's template `post.sh` must no longer contain a `# Claude Code Setup` line
(its old trailing section is removed), otherwise the guard would skip the
new block.

### `setup_mise`

```text
setup_mise()   # sourced into post.sh; no arguments; always returns 0
```

1. `command -v mise` fails → `[WARN] mise not found` + "rebuild from the
   current docker/Dockerfile.dev, see docs/maintenance.md"; return 0.
2. Project root = `$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)`.
3. None of `mise.toml`, `.mise.toml`, `.tool-versions` in the root → info,
   return 0.
4. `(cd "$root" && mise install)` → success: log; failure: `[WARN]` +
   `cd <root> && mise install`; return 0 either way.

### `install_npm_global_cli`

```text
install_npm_global_cli <display_name> <package_spec> <command>   # always returns 0
```

1. `"<command>" --version` succeeds → log `already installed: <version>`,
   return 0.
2. `command -v npm` fails → `[WARN] npm not found` + `npm install -g <package_spec>`
   hint, return 0.
3. `prefix=$(npm prefix -g)`; prefix exists and is not writable by the current
   user → `[WARN]` "global npm prefix <prefix> is not writable; sudo is never
   used" + hint (install Node through mise: `mise use node@22`), return 0.
4. `npm install -g "<package_spec>"` (never `sudo`) → failure: `[WARN]` +
   manual command, return 0.
5. `hash -r`; if `<command> --version` still fails and `mise` exists, run
   `mise reshim`; still failing → `[WARN]` "installed but not on PATH" + hint;
   return 0.

The file defines only this function and is not called from `post.sh`
directly.

### `setup_claude` / `setup_codex`

```text
setup_claude()  # package spec: ${CLAUDE_CODE_NPM_PACKAGE:-@anthropic-ai/claude-code}, command: claude
setup_codex()   # package spec: ${CODEX_NPM_PACKAGE:-@openai/codex},             command: codex
```

Both source `npm_global_cli.sh` from their own directory; when it is missing
they print `[WARN] npm_global_cli.sh not found` + "run ./setup.sh --upgrade"
and return 0. `setup_claude` also runs `mkdir -p "$HOME/.claude"` (moved from
the removed post.sh section). `setup_codex` keeps its sign-in hint.

### `setup_plugins`

```text
setup_plugins()  # no arguments; always returns 0
# test hook: SETUP_PLUGINS_SETTINGS_FILE overrides <root>/.claude/settings.json
```

| Step | Check | On failure |
| --- | --- | --- |
| 1 | `command -v claude` | warning, return 0 |
| 2 | `command -v jq` | warning, return 0 |
| 3 | settings file exists | warning, return 0 |
| 4 | `jq -r '(.enabledPlugins // {}) \| to_entries[] \| select(.value == true) \| .key'` succeeds | warning "invalid JSON", return 0 |
| 5 | at least one enabled id | warning "no enabledPlugins in .claude/settings.json", return 0 |
| 6 | `is_claude_authenticated` (`[[ -s "$HOME/.claude/.credentials.json" ]]`) | guidance ("run `claude` to log in, then re-run …"), return 0 |
| 7 | `claude plugin list --json \| jq -r '.[].id'` | note; installed set treated as empty |
| 8 | per id: matches `^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$` | warn, skip id |
| 9 | per id not installed: ensure marketplace registered (once per marketplace) | warn, skip ids of that marketplace |
| 10 | `claude plugin install <id> --scope project` | warn, continue |

Marketplace source resolution for step 9: `extraKnownMarketplaces[<mkt>].source`
with `source == "github"` → `claude plugin marketplace add <repo>`;
`source == "git"` → `... add <url>`; absent entry and
`<mkt> == "claude-plugins-official"` → `anthropics/claude-plugins-official`;
anything else → warn and skip. Registration check:
`claude plugin marketplace list` output contains the marketplace name as a
word. `-y` / `--accept-command` are never passed.

Removed: the hard-coded `context7` / `serena` list, the playwright prompt and
its `is_interactive` dependency, `try_install_plugin`'s substring match on
plugin names.

## Input/Output Schemas

### Input

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `mise.toml [tools].<tool>` | TOML string or inline table | Yes (core: `node`) | Runtime version; developer-owned after scaffold |
| `mise.toml [env].<VAR>` | TOML string or `{ value, tools }` table | No | Environment for tools run through mise |
| `.claude/settings.json :: enabledPlugins` | object `{ "<name>@<marketplace>": bool }` | No | Only `true` entries are installed by the fallback |
| `.claude/settings.json :: extraKnownMarketplaces` | object `{ "<marketplace>": { source: { source, repo \| url } } }` | No | Source used to register a marketplace |
| `ARG MISE_VERSION` | string (`YYYY.M.P`, no `v`) | Yes | mise release |
| `ARG MISE_MINISIGN_PUBKEY` | string | Yes | minisign public key for `SHASUMS256.txt.minisig` |
| `ARG GH_KEYRING_FINGERPRINT` | 40-hex string | Yes | Expected fingerprint of the gh apt keyring |
| BuildKit secret `github_token` | string | No | Exposed as `GITHUB_TOKEN` to `mise install` only |
| `CLAUDE_CODE_NPM_PACKAGE`, `CODEX_NPM_PACKAGE` | env, npm spec | No | Override (e.g. pin) the CLI package |

### Output

| Field | Type | Description |
| --- | --- | --- |
| `<project>/mise.toml` | TOML | Generated per the flavor table in design.md |
| `docker/Dockerfile.dev` markers | comment lines | `# >>> mise runtimes >>>` / `# <<< mise runtimes <<<` (core); `# >>> postgresql os-packages >>>`, `# >>> mysql os-packages >>>` (+ closers); latex markers unchanged |
| `post.sh` markers | comment lines | `# mise Runtime Setup`, `# Claude Code Setup` (new), `# Codex CLI Setup`, `# Claude Code Plugin Setup` |
| `.devcontainer/devcontainer.json` | JSON | No `features` key |
| Helper stdout | text | `[WARN] ...` lines with a recovery command; never fatal |

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| Invalid `mise_toml_ensure` arguments | return 1 + `print_error` | Programming error in a plugin; caller downgrades to warning |
| `mise.toml` / Dockerfile / `post.sh` write failure | return 1 + `print_error` | Temp file removed, original untouched |
| Missing `SHELL` anchor | `print_warning`, return 0 | Developer restructured the Dockerfile; manual package list printed |
| Pre-#325 Dockerfile (no mise layer) | `print_warning` once | From `execute_plugin_dockerfiles`; links docs/maintenance.md |
| mise missing / `mise install` failure | `[WARN]`, return 0 | `setup_mise` |
| npm missing / prefix not writable / install failure | `[WARN]`, return 0 | `install_npm_global_cli`; sudo never used |
| Helper library missing | `[WARN]`, return 0 | `setup_claude`, `setup_codex` |
| claude/jq/settings/enabledPlugins/credentials missing | warning or guidance, return 0 | `setup_plugins` |
| Unknown marketplace / malformed id / install failure | warning, continue | `setup_plugins` per id |
| Unsupported CPU architecture at build | build fails (`exit 1` in `RUN`) | Only `amd64`/`arm64` have mise binaries mapped |
| minisign or sha256 mismatch | build fails | Tampered or wrong mise download |
| gh keyring fingerprint mismatch | build fails | Unexpected keyring served |
