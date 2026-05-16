# Workflow: #284 devcontainer JSONC merge support

## Implementation Steps

### Step 1: Add JSONC normalization helpers

- **Action**: Add private `_strip_json_comments` and `_jsonc_to_json_file`
  helpers in `scripts/lib/common.sh` near the JSON utility section.
- **Files**: `scripts/lib/common.sh`
- **Depends on**: None.
- **Done when**: Strict JSON and JSON with `//` or `/* */` comments can be
  converted to strict JSON without changing comment markers inside strings.

### Step 2: Route `merge_devcontainer_json` through normalization

- **Action**: Update `merge_devcontainer_json` to normalize `base_file` and
  `overlay_file` into internal temp files before invoking the existing `jq -s`
  merge expression.
- **Files**: `scripts/lib/common.sh`
- **Depends on**: Step 1.
- **Done when**: The Rust plugin path can merge into a commented target
  devcontainer file and still produces strict merged JSON.

### Step 3: Add cleanup on merge failure

- **Action**: Ensure internal temp files and the caller-provided `output_file`
  are removed on normalization or merge failure.
- **Files**: `scripts/lib/common.sh`
- **Depends on**: Step 2.
- **Done when**: A failing merge does not leave
  `.devcontainer/devcontainer.json.tmp` or helper temp files behind.

### Step 4: Add regression tests

- **Action**: Add Bats coverage for `merge_devcontainer_json` with a commented
  base devcontainer file.
- **Files**: Prefer a focused helper test file under `tests/`; otherwise add a
  small case to the nearest existing Bats test that already sources
  `scripts/lib/common.sh`.
- **Depends on**: Steps 1-3.
- **Done when**: Tests verify feature merge, extension dedupe, settings merge,
  URL preservation, and output strict-JSON validity with `jq empty`.

### Step 5: Run focused validation

- **Action**: Run the new/changed Bats test file and a strict JSON smoke test
  for existing behavior.
- **Files**: None.
- **Depends on**: Step 4.
- **Done when**: The focused Bats tests pass.

## Task Dependencies

- Step 2 depends on Step 1 because merge behavior should not duplicate parsing
  logic.
- Step 3 should be implemented with Step 2 so failure cleanup is part of the
  new code path from the beginning.
- Step 4 depends on Steps 1-3 because it should exercise the public
  `merge_devcontainer_json` contract, not the private helpers directly unless
  a private-helper unit test is useful for edge cases.

## Test Strategy

### Unit / Helper Tests

- Base devcontainer contains inline `//` comments in the extensions array.
- Base devcontainer contains a block comment outside a string.
- Base devcontainer contains a setting value with `https://example.com` and a
  string containing `//` that must survive unchanged.
- Overlay adds a feature, extensions, and VS Code settings.
- Output is accepted by `jq empty`.
- Re-running `merge_devcontainer_json` with the merged output and the same
  overlay is idempotent for feature keys and extension arrays.

### Failure Tests

- Missing base file returns non-zero and prints the existing missing-file
  message.
- Invalid JSON after comment stripping returns non-zero and removes the output
  file.
- Unterminated block comment returns non-zero and removes the output file.

### Integration Smoke

- Source `templates/languages/rust/plugin.sh` against a scratch target whose
  `.devcontainer/devcontainer.json` includes the same style of inline comments
  seen in the issue.
- Run `plugin_post_copy_shared "$scratch"`.
- Verify the Rust feature and Rust extensions exist in the target
  devcontainer file.

## Edge Cases

- `//` appears inside a URL string.
- Escaped quote appears inside a string before a comment marker.
- Comment-only lines inside an object or array.
- Block comments spanning multiple lines.
- Existing strict JSON input still follows the old behavior.
