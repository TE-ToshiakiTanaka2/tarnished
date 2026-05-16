# API Specification: #284 fix(setup): allow devcontainer JSON merge when target contains comments

## Shell Helper Surface (delta)

### `scripts/lib/common.sh::merge_devcontainer_json`

Existing signature remains unchanged:

```bash
merge_devcontainer_json <base_file> <overlay_file> <output_file>
```

Inputs:

| Argument | Type | Required | Description |
| --- | --- | --- | --- |
| `base_file` | path | yes | Existing target `.devcontainer/devcontainer.json`. May be strict JSON or JSON with `//` / `/* */` comments. |
| `overlay_file` | path | yes | Plugin overlay devcontainer JSON. May be strict JSON or JSON with `//` / `/* */` comments. |
| `output_file` | path | yes | Destination for merged strict JSON. Removed on failure. |

Output:

| Field | Type | Description |
| --- | --- | --- |
| stdout | JSON | None on success. Existing `jq` output is redirected to `output_file`. |
| stderr | text | Existing `print_error` diagnostics on missing files, normalization failures, validation failures, or merge failures. |
| exit status | integer | `0` on success, non-zero on missing file, invalid JSON/JSONC, comment normalization failure, or merge failure. |

Behavior:

1. Verify `base_file` and `overlay_file` exist.
2. Normalize both files from JSONC-compatible input to strict JSON using
   private temp files.
3. Run the existing merge expression against normalized files:

   ```jq
   .[0] as $base | .[1] as $overlay |
   ($base | del(.features, .customizations)) *
   ($overlay | del(.features, .customizations)) *
   {
       features: (($base.features // {}) * ($overlay.features // {})),
       customizations: {
           vscode: {
               extensions: (($base.customizations.vscode.extensions // []) + ($overlay.customizations.vscode.extensions // []) | unique),
               settings: (($base.customizations.vscode.settings // {}) * ($overlay.customizations.vscode.settings // {}))
           }
       }
   }
   ```

4. Write strict JSON to `output_file`.
5. Remove all internal temp files on success and failure.

Compatibility:

- Existing callers do not change.
- Strict JSON inputs continue to work.
- Output remains strict JSON, not JSONC.
- Existing merge idempotency is preserved because the `jq` merge expression is
  unchanged.

### Private helper: `_strip_json_comments`

```bash
_strip_json_comments <input_file>
```

Streams `input_file` to stdout with comments removed. The helper is private to
`common.sh` and must not be called by plugins.

Recognized comments:

| Syntax | Removed when |
| --- | --- |
| `// comment` | Outside a string literal, through end of line. |
| `/* comment */` | Outside a string literal, until the first closing `*/`. |

String handling:

- `"` toggles string mode only when not escaped.
- `\\` escapes the next character while inside a string.
- Comment markers inside strings are preserved.

### Private helper: `_jsonc_to_json_file`

```bash
_jsonc_to_json_file <input_file> <output_file>
```

Converts a strict-JSON-or-commented-JSON input file into strict JSON at
`output_file`.

Validation:

- Runs `_strip_json_comments`.
- Runs `jq empty "$output_file"` after stripping.
- Returns non-zero and removes `output_file` if validation fails.

## Error Responses

| Error | Detection | Response |
| --- | --- | --- |
| Base file missing | `[[ ! -f "$base_file" ]]` | `print_error "Base file not found: $base_file"` and return `1`. |
| Overlay file missing | `[[ ! -f "$overlay_file" ]]` | `print_error "Overlay file not found: $overlay_file"` and return `1`. |
| Unterminated block comment | `_strip_json_comments` reaches EOF while in block-comment mode | `print_error "Invalid devcontainer JSON comments: <file>"`, remove temps/output, return `1`. |
| Invalid JSON after comment stripping | `jq empty` fails | `print_error "Invalid devcontainer JSON after removing comments: <file>"`, remove temps/output, return `1`. |
| Merge expression failure | final `jq -s` fails | existing `print_error "Failed to merge devcontainer JSON files"`, remove temps/output, return `1`. |

## Non-Goals

- Preserve comments in the merged output.
- Accept trailing commas.
- Change generic `merge_json_files`.
- Change direct service-plugin `jq` mutations that do not call
  `merge_devcontainer_json`.
