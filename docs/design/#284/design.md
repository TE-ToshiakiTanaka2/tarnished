# Design: #284 fix(setup): allow devcontainer JSON merge when target contains comments

## Context

This issue acts on the shell setup layer documented in
`../shared/architecture.md`:

- `setup.sh` orchestrates plugin loading and post-copy dispatch.
- `scripts/lib/common.sh` owns shared helpers used by every plugin,
  including `merge_devcontainer_json`.
- Language plugins such as `templates/languages/rust/plugin.sh` call
  `merge_devcontainer_json` during `plugin_post_copy_shared` to merge
  devcontainer features, VS Code extensions, and VS Code settings.
- Service plugins also call `merge_devcontainer_json` for feature or
  customization overlays, but some of them perform separate direct `jq`
  mutations before that merge.

The existing project-wide contract says JSON merges are structurally
idempotent. The current implementation shells out to `jq -s` directly
against the target `.devcontainer/devcontainer.json`. That is correct for
strict JSON, but devcontainer files are commonly edited as JSON with
comments. The observed failure comes from inline `//` comments in the
target workspace devcontainer:

```jsonc
"tamasfe.even-better-toml", // TOML file support
"rust-lang.rust-analyzer", // Rust language support
```

`jq` rejects this input before `merge_devcontainer_json` can apply the Rust
overlay. The Rust overlay file itself is valid JSON.

## Architecture Overview (delta)

Add a devcontainer-specific normalization step inside
`scripts/lib/common.sh` before `merge_devcontainer_json` invokes `jq`.
The normalization accepts strict JSON plus JavaScript-style comments
outside string literals, writes temporary strict JSON, and feeds those
temporary files to the existing `jq` merge expression.

The output of `merge_devcontainer_json` remains strict JSON. Comments from
the source devcontainer file are not preserved. This is acceptable for this
issue because the setup path already rewrites merge targets through `jq`,
which formats the whole object. Preserving comments would require a
structure-aware JSONC patcher and would be a larger feature.

The comment removal must be stateful:

- Strip `// line comments` only outside strings.
- Strip `/* block comments */` only outside strings.
- Preserve `//` and `/*` sequences inside JSON strings, including URLs such
  as `"https://example.com"`.
- Preserve escaped quotes inside strings.

Trailing comma support is intentionally out of scope. The issue is about
comments; accepting trailing commas would need extra grammar handling and a
broader JSONC compatibility decision.

## Module Structure (delta)

```text
scripts/
└── lib/
    └── common.sh                  # modified
        ├── _strip_json_comments   # new private helper
        ├── _jsonc_to_json_file    # new private helper
        └── merge_devcontainer_json
```

Test changes:

```text
tests/
└── plugin_idempotency.bats        # or a new common-json test file
```

The preferred test location is a focused common-helper test if one exists or
is created. If the implementation keeps tests in the existing Bats layout,
add a small helper-level case near the plugin idempotency coverage rather
than expanding a service-specific fixture.

## Interface Design (delta)

### Public shell functions

| Name | Signature | Description |
| --- | --- | --- |
| `merge_devcontainer_json` | `<base_file> <overlay_file> <output_file>` | Existing public helper. Now accepts base and overlay files that are strict JSON or comment-bearing devcontainer JSONC. Writes strict merged JSON to `output_file`. |

### Private shell helpers

| Name | Signature | Description |
| --- | --- | --- |
| `_strip_json_comments` | `<input_file>` | Streams input with `//` and `/* */` comments removed only when outside string literals. |
| `_jsonc_to_json_file` | `<input_file> <output_file>` | Converts JSONC to strict JSON, validates with `jq empty`, and writes normalized JSON to `output_file`. |

The helper names are private by convention and should stay inside
`common.sh`. Other plugins should continue to use the public
`merge_devcontainer_json` contract.

## Data Flow

1. A plugin computes `target_devcontainer`, `plugin_devcontainer`, and a
   caller-owned temp output path.
2. `merge_devcontainer_json` validates that both input files exist.
3. The helper creates internal temp files with `mktemp`.
4. Each input is normalized through `_jsonc_to_json_file`.
5. The existing `jq -s` merge expression runs against normalized strict JSON.
6. On success, strict JSON is written to the caller-provided output file.
7. On any failure, internal temps and the caller output are removed before
   returning non-zero.

## Error Handling

- Missing input files continue to use the existing `print_error` messages.
- Comment normalization failure prints which file failed and returns non-zero.
- `jq empty` validation failure prints an actionable message that points to
  the original input file.
- Merge failure removes the caller-provided output file so plugin callers do
  not leave stale `.devcontainer/devcontainer.json.tmp` files behind.
- Callers keep the existing `merge_devcontainer_json ...; mv ...` pattern.
  Under `set -e`, a real parse or merge failure still stops that plugin path.

## Implementation Notes

- Do not use a regex-only or `sed 's,//.*$,,'` implementation. That corrupts
  valid string values such as URLs.
- Use `awk` for the small state machine because it is already used elsewhere
  in the setup shell layer and avoids adding a new runtime dependency.
- Keep `merge_json_files`, `merge_claude_settings`, and
  `merge_claude_settings_hooks` strict JSON for now. The bug is localized to
  devcontainer files, where comments are common.
- Direct service-plugin mutations such as
  `jq '.runServices += [...]' "$target_devcontainer"` remain strict JSON in
  this issue. They are not part of the observed Rust failure. If users hit the
  same JSONC problem with service-only setup paths, promote the normalizer into
  a public `apply_devcontainer_jq_filter` helper in a follow-up issue.
- Regression tests should include a string containing `https://` and `//` in a
  setting value to prove the comment stripper is not line-oriented.
