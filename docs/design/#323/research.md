# Research: #323 Optional Zed editor support

Issue-specific research (not promoted to `shared/research/` — Zed is relevant
only to this issue's generator surface, and nothing in `erd` or the AI-refresh
pipeline consumes it).

All facts below were verified on **2026-10-17** against the sources named in
each row. Every claim that the design depends on is cited; claims that could
not be verified are listed in "Deliberately not used" with the reason.

## 1. Zed's dev container support

Source: `zed-industries/zed` → `docs/src/dev-containers.md`
(<https://zed.dev/docs/dev-containers>), fetched raw from `main`.

| Fact | Consequence for this design |
| --- | --- |
| "If your repository includes a `.devcontainer/devcontainer.json` file, Zed can open a project inside a development container." | The whole generated `.devcontainer/` layout is reusable as-is; no second config file is needed. |
| Opening such a project shows an automatic prompt; choosing **"Open in Container"** builds the image, launches the container and reopens the project inside it. | The "Next steps" text (FR-5) tells the user to accept that prompt rather than invent a command name. |
| Manual route: command palette → **"Project: Open Remote"** → the dev-container option; or the Remote Projects modal → **"Connect Dev Container"**. | Second line of the Zed "Next steps" block and the `docs/setup.md` instructions. |
| Requires Docker or Podman on `PATH`; Podman needs `"use_podman": true`. BuildKit is used when `docker buildx` is available, overridable with `"dev_container_use_buildkit": false`. | Documented as a prerequisite in `docs/setup.md`; not encoded in any generated file (it is a *user* setting, not a project setting). |
| Extensions are declared under `customizations.zed.extensions` (array of extension IDs), shown side by side with `customizations.vscode` and `customizations.codespaces`. | FR-2's target key. Confirms `vscode` and `zed` coexist in one file, which is why `customizations.vscode` is always kept. |
| "Note that extensions load for the Zed session, so these extensions will exist on your local Zed instances as well." | Argues for a **minimal, high-confidence** extension list: anything we declare is installed into the developer's own Zed, not just the container. This is the main reason the per-flavor lists below are short. |
| "Updates to `devcontainer.json` do not trigger automatic rebuilds or reloads; containers must be manually restarted." (`docker kill <container>` then reopen) | Documented caveat (FR-5). Also the reason no generated script tries to re-run anything on config change. |
| The feature is explicitly marked "still in development". | Documented so a downstream reader understands why `--zed` is opt-in rather than always-on. |

### Compose project name / single-editor constraint

`templates/core/docker-compose.yml` pins `container_name: {{PROJECT_NAME}}`.
VS Code derives its Compose project name from the devcontainer folder
(`<dir>_devcontainer`) while Zed derives it from the devcontainer `name`, so
the two editors would start *different* Compose projects that both try to
create the *same* container name. The second one fails. This is a
documentation-only item (FR-5): do not run VS Code and Zed against the same
project simultaneously. No code change can fix it without renaming containers,
which is out of scope.

### `forwardPorts`

Zed ignores `forwardPorts`. No file under `templates/` or `.devcontainer/` in
this repository sets `forwardPorts` (verified by `grep -rn forwardPorts
templates/ .devcontainer/` → no matches), so the limitation is informational:
it matters only to a developer who later adds the key by hand.

## 2. Verified extension IDs

Existence was checked two ways for every ID used:

1. `curl -fsSL https://raw.githubusercontent.com/zed-industries/extensions/main/extensions.toml`
   and a line-anchored match on the table header (`^\[<id>\]$`).
2. `https://api.zed.dev/extensions?filter=<id>`, which returns the registry's
   own `id`, `name`, `version` and `description`.

| ID | Registry name | Version seen | Description (registry) | Shipped by |
| --- | --- | --- | --- | --- |
| `dockerfile` | Dockerfile | 0.3.0 | "Dockerfile and Docker Compose support." | `templates/core` |
| `toml` | TOML | 1.0.3 | "TOML support." | `languages/rust`, `languages/python` |
| `biome` | Biome | 0.3.1 | "Biome support for Zed" | `languages/node` |
| `deno` | Deno | 0.1.2 | "Deno support." | `languages/deno` |
| `latex` | LaTeX | 0.2.3 | "LaTeX language server and syntax highlighting for Zed." | `languages/latex` |
| `sql` | SQL | 1.1.8 | "SQL language support." | `services/postgresql`, `services/mysql` |

Built into Zed, so **no** extension is declared for them: Rust
(rust-analyzer + Delve-style debugger), Python (basedpyright primary, Ruff for
format/lint), Go (gopls + delve), TypeScript / JavaScript / TSX, JSON, YAML,
Markdown, Git. Sources: `docs/src/languages/{rust,python,go,typescript,javascript}.md`.

### Deliberately not used

| Candidate | Exists in registry? | Why not shipped |
| --- | --- | --- |
| `docker-compose` (0.1.0, "Syntax highlighting for Docker Compose files") | Yes | Redundant: the `dockerfile` extension's own description claims "Dockerfile and Docker Compose support", and YAML highlighting is built in. Shipping both would install two overlapping grammars into the developer's local Zed. |
| `golangci-lint` (0.2.0) | Yes | Its README requires `lsp.golangci-lint.initialization_options.command`, and the correct command differs between golangci-lint **v1** (`--out-format json`) and **v2** (`--output.json.path stdout`). `templates/languages/go/plugin.sh` installs `@latest` (v2 today) while `templates/languages/go/.golangci.yml` is still v1 schema, so either command string would be wrong for some generated project. A guessed command fails silently inside the editor. Reconciling the golangci-lint major is pre-existing work, out of scope here. |
| `crates-lsp`, `cargo-appraiser` | Yes | Would be the analogue of `serayuzgur.crates` (dependency version lens). Neither is needed for correctness, both add a background process, and rust-analyzer already reports Cargo diagnostics. Not worth installing into every developer's local Zed. |
| `postgres-language-server` (0.1.1) | Yes | Needs a live connection string to be useful; the scaffold cannot supply one at generate time. `sql` covers syntax/language support with zero configuration. |
| `make` (1.1.2) | Yes | No generated flavor ships a Makefile. |
| A Claude Code extension | — | Not in the registry: Zed integrates Claude Code natively through its agent panel (ACP), so there is no equivalent of `anthropic.claude-code`. |
| A GitLens / git-graph equivalent | — | Zed's git panel, blame and diff views are built in; the registry has no comparable extension. `git-firefly` only highlights git config/ignore files. |
| A redis extension | — | None found, and the VS Code overlay for `services/redis` also ships an empty `extensions` array. `services/redis` therefore gets no `.zed/` directory at all. |

## 3. Verified `.zed/settings.json` keys

Project settings live in `<project>/.zed/settings.json` (Zed docs,
"Project-based configuration" in the Biome reference and
`docs/src/configuring-zed.md`). The keys this design writes:

| Key | Verified shape | Source |
| --- | --- | --- |
| `terminal.shell` | `"system"`, or `{"program": "sh"}`, or `{"with_arguments": {"program", "args"}}` | `docs/src/reference/all-settings.md` → "Terminal: Shell" |
| `file_scan_exclusions` | Array of globs. Default list is `**/.git`, `**/.svn`, `**/.hg`, `**/.jj`, `**/.sl`, `**/.repo`, `**/CVS`, `**/.DS_Store`, `**/Thumbs.db`, `**/.classpath`, `**/.settings`. **"Use `\"...\"` to add patterns without repeating Zed's defaults. In project settings, it extends the user or parent configuration value. Omit `\"...\"` to replace the inherited list."** "Inherited patterns are inserted at `\"...\"`, and duplicates keep their first occurrence." | `all-settings.md` → "File Scan Exclusions" |
| `languages.Python.formatter` / `code_actions_on_format` | `{"formatter": {"language_server": {"name": "ruff"}}, "code_actions_on_format": {"source.organizeImports.ruff": true}}` — verbatim from the docs' formatting example. Zed runs Ruff as an LSP (`ruff server`); format is a two-phase pipeline (code actions, then formatter). | `docs/src/languages/python.md` → "Code Formatting & Linting" |
| `lsp.rust-analyzer.initialization_options` | Object passed straight through to rust-analyzer; docs show `checkOnSave`, `cargo.allTargets`, `check.workspace` under it. `check.command` is the rust-analyzer manual's option for the check tool, which is how clippy-on-save is selected. | `docs/src/languages/rust.md` + rust-analyzer manual |
| `languages.<Lang>.formatter` = `{"language_server": {"name": "biome"}}` and `code_actions_on_format` = `{"source.fixAll.biome": true, "source.organizeImports.biome": true}` for `JavaScript` / `TypeScript` / `TSX` (and `JSON` / `JSONC` for formatting) | Verbatim from Biome's own Zed reference, including its warning **not** to put `biome` in the top-level `formatter` / `language_servers` keys because it would break Rust/Python. | <https://biomejs.dev/reference/zed/> |
| `lsp.deno.settings.deno.enable` + `languages.{JavaScript,TypeScript,TSX}.language_servers` = `["deno", "!typescript-language-server", "!vtsls", "!eslint"]` + `"formatter": "language_server"` | Verbatim from the Deno page ("you will likely wish to disable the default language servers and enable Deno"). | `docs/src/languages/deno.md` |
| `languages.Go.formatter` = `"language_server"`, `format_on_save` = `"on"`, `lsp.gopls.initialization_options` | gopls is the built-in Go language server and formats with gofmt semantics; `initialization_options` is the documented pass-through (`hints`, `codelenses`, … are shown). `staticcheck` is a documented gopls setting and matches the `staticcheck` linter already enabled in `templates/languages/go/.golangci.yml`. | `docs/src/languages/go.md` + gopls settings docs |
| `lsp.texlab.settings.texlab.build.onSave` | `false` disables the extension's build-and-preview-on-save autoconfig. The wiki also documents `build.executable` / `build.args`, which this design deliberately leaves at texlab's defaults. | `rzukic/zed-latex` wiki → "Build Document / Disable autoconfig" |

### Keys deliberately **not** written

- `lsp.biome.settings.require_config_file: true`. Tempting (it keeps Biome
  inert in projects with no `biome.json`), but Biome resolves its config from
  the *workspace root* and `templates/languages/node` ships `biome.json` as a
  **per-module** file. In a monorepo the root has no `biome.json`, so the flag
  would silently disable Biome for the whole project.
- `texlab` `build.executable` / `build.args`. The VS Code overlay's recipe is
  `latexmk -time %DOC%`; translating argument-for-argument into texlab's
  `%f`-based placeholders is a guess, and with `onSave: false` nothing runs
  automatically anyway.
- Anything under a top-level `formatter` / `language_servers` key, per Biome's
  explicit warning above.

## 4. Repository-side facts that constrain the design

Verified by reading the code, not inferred:

| Fact | Location | Consequence |
| --- | --- | --- |
| `merge_devcontainer_json`'s jq program rebuilds `customizations` as `{vscode: {extensions, settings}}`, so any `customizations.zed` on either side is dropped. It also emits `customizations.vscode` even when neither input has it. | `scripts/lib/common.sh:665-724` | The jq program must gain a `zed` branch; and the branch must be *presence-gated* so today's output stays byte-identical. |
| `templates/core/.devcontainer/` is copied **verbatim** (`copy_dir_with_confirm`), while every language/service `.devcontainer/devcontainer.json` is used **only** as a merge overlay and never copied. | `templates/core/plugin.sh::plugin_copy` vs `templates/languages/*/plugin.sh::plugin_post_copy_shared` | A zed overlay file cannot live under `templates/core/.devcontainer/` — it would be copied into every generated project, breaking NFR-1 by adding a file. This is what forces the new `templates/<flavor>/.zed/` location. |
| `_manifest_path_eligible` is a **positive** allow-list: only `.devcontainer/scripts/*.sh` (except `post.sh`) is maintenance-eligible. | `scripts/lib/common.sh:274-286` | `.zed/settings.json` cannot be manifest-tracked no matter what; no `MANIFEST_EXCLUDE_GLOBS` entry is needed, and `--upgrade` can never overwrite a developer's Zed settings. |
| `manifest_options_valid` validates a fixed list of boolean `scaffold_options` keys. | `scripts/lib/manifest.sh:63-80` | `zed_enabled` must be added to that list or its type is unchecked. |
| Scaffold-time provenance is written from `infer_scaffold_options` (filesystem evidence), not from the in-memory flags. | `setup.sh:2942` | FR-6's "infer from the presence of `.zed/settings.json`" is the only place `zed_enabled` needs to be produced at scaffold time. |
| `copy_with_confirm` does not create parent directories. | `scripts/lib/common.sh:432-485` | The helper must `mkdir -p "<target>/.zed"` before copying. |
| `scaffold_flags_supplied` gates "existing project ⇒ refresh" and lists every scaffold selection flag. | `setup.sh:1700-1706`, used at `setup.sh:2742` | `--zed` must be added, or `setup.sh --zed` inside an existing project would silently run a refresh and ignore the flag. |
| `scripts/verify-mirrors.sh` compares only `.claude/*`, `.agents`, `.codex/config.toml`, `.tarnished/*` and two `.devcontainer/scripts/*.sh` helpers. | `scripts/verify-mirrors.sh:47-98` | Neither `devcontainer.json` nor `.zed/` is a mirrored pair, so NFR-3 holds with no change to the script. |
| `update_gitignore`'s blocks cover `.claude/*`, `.serena/`, `screenshots/` (plus Codex's own blocks). | `scripts/lib/common.sh:1000-1058` | `.zed/` is not ignored, so `.zed/settings.json` is tracked by git in generated projects — the intended outcome for a shared project setting. No gitignore change. |

## 5. Prototype verification of the two jq programs

Both jq programs in [api-spec.md](./api-spec.md) were executed against real
template inputs during design (jq 1.7, the version already required by
`setup.sh`). Results:

| Property | Check | Result |
| --- | --- | --- |
| NFR-1 byte-identity | `diff` of the current program's output vs. the new program's output for `templates/core/.devcontainer/devcontainer.json` (placeholders rendered) merged with `templates/languages/rust/.devcontainer/devcontainer.json` | identical, byte for byte |
| NFR-1 byte-identity, synthetic | same `diff` on a base/overlay pair with `features` + `customizations.vscode` only | identical |
| Zed emission | overlay-only `customizations.zed` → key appears; neither side → key absent | as specified |
| Carry-through | base has `zed`, overlay does not → base `zed` survives | as specified |
| `extensions` union | `["dockerfile"]` + `["toml"]` → `["dockerfile","toml"]` | as specified |
| `merge_devcontainer_json` idempotency | `merge(merge(b,o),o)` vs `merge(b,o)` under `jq -S` | identical |
| `merge_zed_settings` composition | core base + rust fragment + python fragment | `terminal`, `lsp.rust-analyzer`, `languages.Python` all present; `file_scan_exclusions` the union |
| `merge_zed_settings` idempotency | re-merging the rust fragment into the composed result | byte-identical output |
| Developer-key survival | a base with `theme` and a custom exclusion merged with the python fragment | `theme` and the custom glob preserved; `format_on_save` taken from the overlay |
| `"..."` sentinel placement | after `unique` sorting of `["**/node_modules","**/target","**/dist","**/coverage","..."]` | `"..."` sorts **last** (`*` = 0x2A < `.` = 0x2E), i.e. it stays where it was authored |

The FR-7 content given for this repository's `/.zed/settings.json` in
api-spec.md is the literal output of `merge_zed_settings(core base, rust
fragment)`, key order included, so the dogfooded file and the generated one
cannot drift by construction.
