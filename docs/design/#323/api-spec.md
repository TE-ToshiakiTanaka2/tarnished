# API Specification: #323 Optional Zed editor support

Delta only. The cumulative surface is in
[shared/api-spec.md](../shared/api-spec.md).

## Endpoints / Functions (delta)

| Name | Method/Signature | Description |
| --- | --- | --- |
| `setup.sh --zed` | CLI boolean flag | Enable Zed editor support for this scaffold run. Additive; `customizations.vscode` is always kept. |
| `scripts/lib/common.sh::merge_devcontainer_json` | `merge_devcontainer_json <base_file> <overlay_file> <output_file>` | **Modified.** Also merges `customizations.zed`; emits the key only when base or overlay declares it. |
| `scripts/lib/common.sh::merge_zed_settings` | `merge_zed_settings <base_file> <overlay_file> <output_file>` | **New.** Deep merge for `.zed/settings.json`. |
| `scripts/lib/common.sh::apply_zed_assets` | `apply_zed_assets <target_dir> <plugin_dir>` | **New.** Installs one flavor's Zed contributions. Only reader of `ZED_ENABLED`. |
| `scripts/lib/manifest.sh::manifest_options_valid` | `manifest_options_valid <scaffold_options_json>` | **Modified.** `zed_enabled` joins the validated boolean keys. |
| `setup.sh::infer_scaffold_options` | `infer_scaffold_options <target_dir> <monorepo_bool> [<single_lang>]` | **Modified.** Emits `zed_enabled`. |
| `setup.sh::populate_setup_state_from_manifest` | `populate_setup_state_from_manifest <manifest_json> <is_root_scope> [<single_lang>] [<module_name>]` | **Modified.** Resets and restores `ZED_ENABLED`. |
| `setup.sh::scaffold_flags_supplied` | `scaffold_flags_supplied` | **Modified.** `ZED_ENABLED == true` counts as a scaffold selection. |

## CLI surface

### `--zed`

```
    --zed               Add Zed editor support (customizations.zed +
                        .zed/settings.json) alongside the VS Code setup
```

Placed immediately after `--codex` in `show_help`'s Options block, and one
example line in the Examples block:

```
    ./setup.sh --lang rust --zed            # Rust, openable in VS Code or Zed
```

Parsing (`parse_arguments`, directly after the `--codex` case):

```bash
            --zed)
                ZED_ENABLED=true
                shift
                ;;
```

### Interactive prompt (FR-1)

Inside the existing `if check_tty_available && [[ "$IS_ADD_MODULE_MODE" != true ]]`
block, after the auto-tag prompt, in the same shape as its two siblings:

```bash
        # Ask about Zed editor support (independent from the AI profile)
        if [[ "$ZED_ENABLED" != true ]]; then
            echo "" > /dev/tty
            echo -n "Enable Zed editor support? (y/n) [n]: " > /dev/tty
            local zed_response
            read -r zed_response < /dev/tty
            if [[ "$zed_response" == "y" || "$zed_response" == "Y" ]]; then
                ZED_ENABLED=true
            fi
        fi
```

Prompt string, exactly: `Enable Zed editor support? (y/n) [n]: `.

### Add-module warning (FR-6)

In the `if [[ "$IS_ADD_MODULE_MODE" == true ]]` warning block, after the
`--codex` case:

```bash
        if [[ "$ZED_ENABLED" == true ]]; then
            print_warning "--zed is ignored in add-module mode (Zed assets were set up by the original --monorepo init)"
            ZED_ENABLED=false
        fi
```

### Setup Configuration summary (FR-1)

One line after `Codex CLI:`, aligned to the existing value column (23):

```
Zed:                  true
```

```bash
    echo "Zed:                  $ZED_ENABLED"
```

### Next steps (FR-5)

Appended to the completion block, emitted only when enabled:

```bash
    echo "Next steps:"
    echo "  1. Open in VS Code: code ."
    echo "  2. Reopen in Container: F1 > Dev Containers: Reopen in Container"
    if [[ "$ZED_ENABLED" == true ]]; then
        echo ""
        echo "Or open in Zed:"
        echo "  1. zed ."
        echo "  2. Accept the \"Open in Container\" prompt"
        echo "     (or run \"Project: Open Remote\" from the command palette)"
        echo ""
        echo "  Zed notes: restart the container manually after editing"
        echo "  devcontainer.json, and do not run VS Code and Zed on the"
        echo "  same project at the same time."
    fi
```

## Function contracts

### `merge_devcontainer_json` (modified)

Signature, inputs, JSONC normalization, temp-file handling and failure
behavior are **unchanged** (see shared api-spec). Only the jq program changes.

Merge semantics after this change:

| Field | Behavior |
| --- | --- |
| Other top-level keys | Deep-merged, overlay wins. *(unchanged)* |
| `features` | Object merge. *(unchanged)* |
| `customizations.vscode.extensions` | Concatenated and `unique`. Always emitted. *(unchanged)* |
| `customizations.vscode.settings` | Object merge. Always emitted. *(unchanged)* |
| `customizations.zed` | **New.** Emitted **only if** `$base.customizations.zed` or `$overlay.customizations.zed` is non-null. When emitted: object merge of the two sides, with `extensions` replaced by the `unique` union of both sides' `extensions`. |
| any other `customizations.*` key (e.g. `codespaces`) | Still dropped. *(unchanged — out of scope)* |

New jq program (replaces lines 676-717 of `scripts/lib/common.sh`):

```jq
.[0] as $base | .[1] as $overlay |
($base.customizations.zed // null) as $base_zed |
($overlay.customizations.zed // null) as $overlay_zed |
($base | del(.features, .customizations)) *
($overlay | del(.features, .customizations)) *
{
    features: (($base.features // {}) * ($overlay.features // {})),
    customizations: (
        {
            vscode: {
                extensions: (($base.customizations.vscode.extensions // []) + ($overlay.customizations.vscode.extensions // []) | unique),
                settings: (($base.customizations.vscode.settings // {}) * ($overlay.customizations.vscode.settings // {}))
            }
        }
        + (if $base_zed == null and $overlay_zed == null then
            {}
          else
            {
                zed: (($base_zed // {}) * ($overlay_zed // {})
                      | .extensions = ((($base_zed // {}).extensions // []) + (($overlay_zed // {}).extensions // []) | unique))
            }
          end)
    )
}
```

Properties:

- **NFR-1**: when neither input has `customizations.zed`, the `+ {}` branch is
  taken and the emitted object is identical to today's, key order included
  (jq preserves insertion order and `{...} + {}` appends nothing).
- **Idempotency**: `unique` union and `*` are both idempotent, so
  `merge(merge(b, o), o) == merge(b, o)` modulo key order, which the existing
  idempotency test already asserts via `jq -S`.
- **Carry-through**: a `zed` subtree present only in the base survives (a
  language overlay with no Zed data cannot erase core's Zed extensions).

### `merge_zed_settings` (new)

```bash
# Merge Zed project settings (.zed/settings.json) with deep object merge and
# set-union array merge. Inputs may be strict JSON or JSONC (// and /* */);
# the merged output is strict JSON and comments are not preserved.
# Usage: merge_zed_settings <base_file> <overlay_file> <output_file>
# Returns: 0 on success; 1 on missing base, unparseable input, or jq failure.
merge_zed_settings() {
    local base_file="$1"
    local overlay_file="$2"
    local output_file="$3"
    ...
}
```

Behavior:

| Condition | Result |
| --- | --- |
| `base_file` missing | `print_error "Base file not found: $base_file"`; remove `output_file`; return 1. |
| `overlay_file` missing | `cp "$base_file" "$output_file"`; return 0. (Same accommodation `merge_claude_settings` makes.) |
| Either input unparseable after comment stripping | `_jsonc_to_json_file` prints the error; temps and `output_file` removed; return 1. |
| jq merge fails | `print_error "Failed to merge Zed settings files"`; temps and `output_file` removed; return 1. |
| Success | Strict JSON written to `output_file`; temps removed; return 0. |

Merge rule (jq), applied recursively from the two document roots:

```jq
def zedmerge($a; $b):
    if ($a | type) == "object" and ($b | type) == "object" then
        reduce (($a | keys_unsorted) + ($b | keys_unsorted))[] as $k
            ({};
             .[$k] = (if ($a | has($k)) and ($b | has($k)) then zedmerge($a[$k]; $b[$k])
                      elif ($a | has($k)) then $a[$k]
                      else $b[$k] end))
    elif ($a | type) == "array" and ($b | type) == "array" then
        ($a + $b | unique)
    else
        $b
    end;
zedmerge(.[0]; .[1])
```

| Input pair | Result |
| --- | --- |
| object / object | Key-wise recursive merge. Base key order is preserved; overlay-only keys are appended. |
| array / array | `unique` union — deduplicated and sorted. |
| scalar / anything, or mismatched types | Overlay value wins. |
| key only in base | Preserved untouched (developer additions survive). |
| key only in overlay | Added. |

Idempotency: re-merging the same overlay changes nothing — unions are
already-complete sets, `zedmerge` on equal objects is the identity, and key
order is stable because base order is preserved. This is what NFR-2's
"identical bytes on re-run" asserts.

### `apply_zed_assets` (new)

```bash
# Install one template flavor's Zed contributions into the target project.
# No-op unless Zed support is enabled for this run and the flavor ships a
# .zed/ directory. Always returns 0: a Zed failure must never abort a
# scaffold, and it must never damage the live files.
# Usage: apply_zed_assets <target_dir> <plugin_dir>
apply_zed_assets() {
    local target_dir="$1"
    local plugin_dir="$2"

    [[ "${ZED_ENABLED:-false}" == true ]] || return 0
    [[ -d "${plugin_dir}/.zed" ]] || return 0

    local overlay="${plugin_dir}/.zed/devcontainer.json"
    local target_devcontainer="${target_dir}/.devcontainer/devcontainer.json"
    local temp_file

    if [[ -f "$overlay" ]] && [[ -f "$target_devcontainer" ]]; then
        print_info "Merging Zed devcontainer customizations..."
        temp_file="${target_devcontainer}.zed.tmp"
        if merge_devcontainer_json "$target_devcontainer" "$overlay" "$temp_file"; then
            mv "$temp_file" "$target_devcontainer"
            print_success "Zed devcontainer customizations merged"
        else
            rm -f "$temp_file"
            print_warning "Zed devcontainer merge failed; $target_devcontainer unchanged"
        fi
    fi

    local fragment="${plugin_dir}/.zed/settings.json"
    local target_settings="${target_dir}/.zed/settings.json"

    if [[ -f "$fragment" ]]; then
        mkdir -p "${target_dir}/.zed"
        if [[ -f "$target_settings" ]]; then
            print_info "Merging Zed project settings..."
            temp_file="${target_settings}.tmp"
            if merge_zed_settings "$target_settings" "$fragment" "$temp_file"; then
                mv "$temp_file" "$target_settings"
                print_success "Zed project settings merged"
            else
                rm -f "$temp_file"
                print_warning "Zed settings merge failed; $target_settings unchanged"
            fi
        else
            # Normalize the fragment through a self-merge (merging a document
            # with itself is a no-op on content but sorts and dedups its
            # arrays) before installing it, so a later plugin_post_copy
            # re-run that merges the same fragment again produces identical
            # bytes. Falls back to a raw copy if normalization fails.
            local normalized="${target_settings}.seed.tmp"
            local seeded=false
            if merge_zed_settings "$fragment" "$fragment" "$normalized"; then
                copy_with_confirm "$normalized" "$target_settings" && seeded=true
                rm -f "$normalized"
            else
                rm -f "$normalized"
                copy_with_confirm "$fragment" "$target_settings" && seeded=true
            fi
            if [[ "$seeded" == true ]]; then
                print_success "Created .zed/settings.json"
            else
                print_warning "Failed to create $target_settings"
            fi
        fi
    fi

    return 0
}
```

Contract notes:

- Reads `ZED_ENABLED` with a `:-false` default, so sourcing `common.sh` and a
  plugin in isolation (as `tests/plugin_idempotency.bats` does) behaves as
  Zed-off without `set -u` trouble.
- `mkdir -p` is required: `copy_with_confirm` does not create parents.
- The first contributor does not copy the fragment's raw bytes: it
  self-merges the fragment through `merge_zed_settings` first (sorting and
  deduplicating its arrays) and installs that normalized result, so a second
  `plugin_post_copy` run — which merges the same fragment again — produces
  byte-identical output instead of reordering arrays on every run. The raw
  copy is only a fallback, taken if the self-merge itself fails. Later
  contributors merge their fragment into this normalized file.
- `copy_with_confirm`'s return value is checked on both the normalized path
  and the raw-copy fallback. A bare, unchecked call is a statement under
  `setup.sh`'s `set -e`, so a failure (unsafe destination, non-regular
  source, `cp` error) would otherwise abort the whole scaffold; checking it
  instead prints a warning naming the target and returns 0.
- Returns 0 unconditionally, matching the non-fatal convention used across
  plugin hooks.

### Plugin call sites

Exactly one line per plugin, with no conditional in the plugin:

| Plugin | Function | Position |
| --- | --- | --- |
| `templates/core/plugin.sh` | `plugin_post_copy` | After the `post.sh` refresh-wiring block. |
| `templates/languages/{rust,python,node,deno,go,latex}/plugin.sh` | `plugin_post_copy_shared` | After the existing `merge_devcontainer_json` block. **Not** in `plugin_post_copy_module` — `.zed/` is a root asset and the module hook must not touch root paths. |
| `templates/services/{postgresql,mysql,redis}/plugin.sh` | `plugin_post_copy` | After the existing `merge_devcontainer_json` block. |

```bash
    # Zed editor assets (no-op unless --zed was selected)
    apply_zed_assets "$target_dir" "$PLUGIN_DIR"
```

`templates/languages/rust/plugin.sh::plugin_post_copy_shared` contains an
early `return` in its `post.sh` marker branch (when the block is already
present). The `apply_zed_assets` call must therefore be placed **before** that
branch, not at the end of the function, or an add-module/upgrade re-run would
skip it. The same check applies to any language plugin whose shared hook can
return early.

## Input/Output Schemas

### `scaffold_options.zed_enabled`

#### Input (read)

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `.scaffold_options.zed_enabled` | boolean | No | Absent in every pre-#323 manifest. Read as `// false` by `populate_setup_state_from_manifest`. Validated as a boolean *if present* by `manifest_options_valid`. |

#### Output (write)

`infer_scaffold_options` gains:

```bash
    local zed=false
    [[ -f "$target_dir/.zed/settings.json" ]] && zed=true
```

and emits it through the existing `jq -n` call:

```
        --argjson zed "$zed"
        ...
            codex_enabled: $codex,
            zed_enabled: $zed,
            monorepo: $monorepo
```

`manifest_options_valid` boolean key list becomes:

```jq
        (. as $options | ["github_actions_enabled", "auto_tag_enabled",
            "codex_enabled", "zed_enabled", "monorepo"] | all(.[]; . as $key |
                ($options | has($key) | not) or ($options[$key] | type == "boolean")))
```

`populate_setup_state_from_manifest` gains `ZED_ENABLED=false` in the reset
block and:

```bash
    ZED_ENABLED=$(echo "$manifest_json" | jq -r '.scaffold_options.zed_enabled // false')
```

### `templates/<flavor>/.zed/devcontainer.json`

Devcontainer merge overlay. Only top-level key is `customizations`, whose only
key is `zed`. Comments permitted.

```json
{
  "customizations": {
    "zed": {
      "extensions": [
        "dockerfile"
      ]
    }
  }
}
```

Per-flavor contents (IDs verified in [research.md](./research.md) §2):

| Flavor | `customizations.zed.extensions` |
| --- | --- |
| `core` | `["dockerfile"]` |
| `languages/rust` | `["toml"]` |
| `languages/python` | `["toml"]` |
| `languages/node` | `["biome"]` |
| `languages/deno` | `["deno"]` |
| `languages/go` | *(no `devcontainer.json` — settings fragment only)* |
| `languages/latex` | `["latex"]` |
| `services/postgresql` | `["sql"]` |
| `services/mysql` | `["sql"]` |
| `services/redis` | *(no `.zed/` directory at all)* |

### `templates/<flavor>/.zed/settings.json`

Fragment merged into `<target>/.zed/settings.json`. Strict JSON.

`templates/core/.zed/settings.json` — the base file, installed by copy (FR-3):

```json
{
  "terminal": {
    "shell": {
      "program": "bash"
    }
  },
  "file_scan_exclusions": [
    "**/node_modules",
    "**/target",
    "**/dist",
    "**/coverage",
    "..."
  ]
}
```

`templates/languages/rust/.zed/settings.json`:

```json
{
  "file_scan_exclusions": [
    "**/target"
  ],
  "lsp": {
    "rust-analyzer": {
      "initialization_options": {
        "check": {
          "command": "clippy"
        }
      }
    }
  }
}
```

`templates/languages/python/.zed/settings.json`:

```json
{
  "file_scan_exclusions": [
    "**/__pycache__",
    "**/.mypy_cache",
    "**/.pytest_cache",
    "**/.ruff_cache",
    "**/*.egg-info"
  ],
  "languages": {
    "Python": {
      "format_on_save": "on",
      "formatter": {
        "language_server": {
          "name": "ruff"
        }
      },
      "code_actions_on_format": {
        "source.organizeImports.ruff": true
      }
    }
  }
}
```

`templates/languages/node/.zed/settings.json`:

```json
{
  "file_scan_exclusions": [
    "**/node_modules",
    "**/dist",
    "**/coverage"
  ],
  "languages": {
    "JavaScript": {
      "format_on_save": "on",
      "formatter": { "language_server": { "name": "biome" } },
      "code_actions_on_format": {
        "source.fixAll.biome": true,
        "source.organizeImports.biome": true
      }
    },
    "TypeScript": {
      "format_on_save": "on",
      "formatter": { "language_server": { "name": "biome" } },
      "code_actions_on_format": {
        "source.fixAll.biome": true,
        "source.organizeImports.biome": true
      }
    },
    "TSX": {
      "format_on_save": "on",
      "formatter": { "language_server": { "name": "biome" } },
      "code_actions_on_format": {
        "source.fixAll.biome": true,
        "source.organizeImports.biome": true
      }
    },
    "JSON": {
      "formatter": { "language_server": { "name": "biome" } }
    },
    "JSONC": {
      "formatter": { "language_server": { "name": "biome" } }
    }
  }
}
```

`templates/languages/deno/.zed/settings.json`:

```json
{
  "file_scan_exclusions": [
    "**/coverage"
  ],
  "lsp": {
    "deno": {
      "settings": {
        "deno": {
          "enable": true
        }
      }
    }
  },
  "languages": {
    "JavaScript": {
      "language_servers": ["deno", "!typescript-language-server", "!vtsls", "!eslint"],
      "formatter": "language_server",
      "format_on_save": "on"
    },
    "TypeScript": {
      "language_servers": ["deno", "!typescript-language-server", "!vtsls", "!eslint"],
      "formatter": "language_server",
      "format_on_save": "on"
    },
    "TSX": {
      "language_servers": ["deno", "!typescript-language-server", "!vtsls", "!eslint"],
      "formatter": "language_server",
      "format_on_save": "on"
    }
  }
}
```

`templates/languages/go/.zed/settings.json`:

```json
{
  "languages": {
    "Go": {
      "format_on_save": "on",
      "formatter": "language_server"
    }
  },
  "lsp": {
    "gopls": {
      "initialization_options": {
        "staticcheck": true
      }
    }
  }
}
```

`templates/languages/latex/.zed/settings.json`:

```json
{
  "file_scan_exclusions": [
    "**/.intermediates",
    "**/output"
  ],
  "lsp": {
    "texlab": {
      "settings": {
        "texlab": {
          "build": {
            "onSave": false
          }
        }
      }
    }
  }
}
```

### Generated `<target>/.devcontainer/devcontainer.json` (with `--zed`, Rust + PostgreSQL)

```json
  "customizations": {
    "vscode": {
      "extensions": [ ... unchanged, sorted ... ],
      "settings": { ... unchanged ... }
    },
    "zed": {
      "extensions": [
        "dockerfile",
        "sql",
        "toml"
      ]
    }
  }
```

Without `--zed` the `zed` key is absent and the rest is byte-identical to
today's output.

### FR-7: this repository's own files

`/.devcontainer/devcontainer.json` gains, inside the existing
`customizations` object, after `vscode`:

```json
    "zed": {
      "extensions": [
        "dockerfile",
        "toml"
      ]
    }
```

(core's `dockerfile` + rust's `toml`: this repository is a Rust project with
`docker/Dockerfile.dev` and `docker-compose.yml`.)

New `/.zed/settings.json` — exactly what the generator would produce for a
Rust project (core base merged with the rust fragment; arrays unioned and
sorted by `merge_zed_settings`):

```json
{
  "terminal": {
    "shell": {
      "program": "bash"
    }
  },
  "file_scan_exclusions": [
    "**/coverage",
    "**/dist",
    "**/node_modules",
    "**/target",
    "..."
  ],
  "lsp": {
    "rust-analyzer": {
      "initialization_options": {
        "check": {
          "command": "clippy"
        }
      }
    }
  }
}
```

This file is hand-applied (the plugin runtime is not run against the
workspace), following the workspace-Codex dogfooding convention from #261. It
is **not** a `verify-mirrors.sh` pair: it is a merge result, not a copy of any
single template file.

## Error Handling

| Error | Code/Type | Description |
| --- | --- | --- |
| Zed devcontainer overlay merge failure | shell warning, `apply_zed_assets` returns 0 | `merge_devcontainer_json` rejected the flavor's `.zed/devcontainer.json`; temp removed, live devcontainer untouched. |
| Zed settings merge failure | shell warning, `apply_zed_assets` returns 0 | Developer's `.zed/settings.json` is invalid even after comment stripping, or jq failed; temp removed, live file untouched. |
| `--zed` in add-module mode | shell warning, flag reset to false | Mirrors `--codex` (`setup.sh` add-module warning block). |
| `--zed` against an existing Tarnished project | shell error, exit 1 | `scaffold_flags_supplied` includes `ZED_ENABLED`, so the existing "Existing Tarnished project: use --refresh …" error fires instead of silently refreshing. |
| `zed_enabled` present but not a boolean in a manifest | shell error, exit 1 | `manifest_options_valid` rejects the manifest (`manifest_read` → "Invalid manifest scaffold options"). |

## Out of scope / explicitly unchanged

- `templates/agent-workflows/.tarnished/refresh.json` and
  `templates/core/.devcontainer/scripts/refresh-assets.sh`: `.zed/` is not an
  AI asset and is **not** added to `managed_paths[]`.
- `scripts/lib/common.sh::MANIFEST_EXCLUDE_GLOBS`: no new entry. `.zed/` is
  already outside the positive eligibility allow-list
  (`_manifest_path_eligible`), so `--create-manifest`, `--upgrade` and
  `--prune` never see it.
- `scripts/verify-mirrors.sh`: no new pair (NFR-3).
- `scripts/lib/common.sh::update_gitignore`: no new block; `.zed/` stays
  tracked by git.
- `scripts/lib/common.sh::replace_placeholders`: no Zed file carries
  `{{...}}` placeholders, so its hard-coded file list is unchanged.
- `templates/{claude,codex,agent-workflows,github-actions/*}`: no `.zed/`
  directory. `apply_zed_assets` is generic, so adding one later is additive.
