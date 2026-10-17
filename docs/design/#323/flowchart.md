# Flowchart: #323 Optional Zed editor support

## `ZED_ENABLED` resolution

Where the single boolean comes from, and the two places it is forced back off.

```mermaid
graph TD
    A[setup.sh invoked] --> B{--zed passed?}
    B -->|yes| C[ZED_ENABLED=true]
    B -->|no| D[ZED_ENABLED=false]
    C --> E{existing Tarnished project<br/>and not add-module?}
    D --> E
    E -->|yes| F["scaffold_flags_supplied is true<br/>→ error: use --refresh / --add-module<br/>exit 1"]
    E -->|no| G{TTY available<br/>and not add-module?}
    G -->|no| I{add-module mode?}
    G -->|yes| H{ZED_ENABLED<br/>already true?}
    H -->|yes| I
    H -->|no| H2["prompt: Enable Zed editor support? (y/n) [n]"]
    H2 -->|y or Y| H3[ZED_ENABLED=true] --> I
    H2 -->|anything else| I
    I -->|yes| J["print_warning '--zed is ignored in add-module mode'<br/>ZED_ENABLED=false"]
    I -->|no| K["Setup Configuration prints 'Zed: $ZED_ENABLED'"]
    J --> K
    K --> L{--dry-run?}
    L -->|yes| M[exit 0 — nothing written, no .zed/]
    L -->|no| N[plugin pipeline runs]
```

## `apply_zed_assets <target_dir> <plugin_dir>`

Called once per participating plugin. Both guards at the top are what make the
non-`--zed` path a pure no-op, and both failure branches leave the live file
exactly as it was.

```mermaid
graph TD
    A["apply_zed_assets(target_dir, plugin_dir)"] --> B{"ZED_ENABLED == true?"}
    B -->|no| Z[return 0]
    B -->|yes| C{"plugin_dir/.zed/ exists?"}
    C -->|no| Z
    C -->|yes| D{".zed/devcontainer.json<br/>AND target devcontainer.json<br/>both exist?"}
    D -->|no| G
    D -->|yes| E["merge_devcontainer_json(target, overlay, tmp)"]
    E -->|ok| E1["mv tmp target<br/>print_success"] --> G
    E -->|fail| E2["rm -f tmp<br/>print_warning<br/>target unchanged"] --> G
    G{".zed/settings.json<br/>fragment exists?"}
    G -->|no| Z
    G -->|yes| H["mkdir -p target_dir/.zed"]
    H --> I{"target .zed/settings.json<br/>already exists?"}
    I -->|no| J["copy_with_confirm(fragment, target)<br/>first contributor wins — FR-3"] --> Z
    I -->|yes| K["merge_zed_settings(target, fragment, tmp)"]
    K -->|ok| K1["mv tmp target<br/>print_success"] --> Z
    K -->|fail| K2["rm -f tmp<br/>print_warning<br/>target unchanged"] --> Z
```

## `merge_devcontainer_json` — `customizations.zed` emission

The decision that carries NFR-1. The `vscode` subtree is built exactly as
before, in every branch.

```mermaid
graph TD
    A[jq program] --> B["$base_zed = base.customizations.zed // null<br/>$overlay_zed = overlay.customizations.zed // null"]
    B --> C["build { vscode: { extensions: unique union, settings: object merge } }"]
    C --> D{"$base_zed == null<br/>AND $overlay_zed == null?"}
    D -->|yes| E["+ {} → no 'zed' key emitted<br/>output byte-identical to pre-#323"]
    D -->|no| F["+ { zed: ($base_zed // {}) * ($overlay_zed // {}) }"]
    F --> G["zed.extensions = unique(base.zed.extensions // [] + overlay.zed.extensions // [])"]
    E --> H[customizations object]
    G --> H
```
