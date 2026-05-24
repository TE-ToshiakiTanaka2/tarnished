# Workflow: #289 fix(manifest): jq ARG_MAX overflow in manifest_write

## Implementation Steps

1. **Fix the writer (`scripts/lib/manifest.sh:104-151`).**
   Rework the `jq -n ... --argjson files "$files_json"` call so the files map is fed
   to `jq` via stdin (`printf '%s' "$files_json" | jq ... 'files: .'`). Keep all bounded
   inputs as `--arg`/`--argjson`. Preserve the atomic `> "$tmp"` → `mv "$tmp" "$file"`
   flow and the `rm -f "$tmp"; print_error; return 1` failure guard.

2. **Guard the create-manifest call sites (`setup.sh:1689`, `1709`, `1721`).**
   Wrap each `manifest_write` so `print_success "wrote ..."` runs only on success;
   on failure, `print_error` and propagate a non-zero return out of `run_create_manifest`.

3. **Guard the upgrade call site (`setup.sh:2051`).**
   Make a failed `manifest_write` abort the scope with non-zero status before
   `manifest_summary_print` can imply "Manifest updated."

4. **Unit regression test (`tests/manifest.bats`).**
   Add a test that loads `MANIFEST_TRACKED` with a large number of entries (enough to
   have previously overflowed the old `--argjson` path), calls `manifest_write`, and
   asserts: (a) exit 0, (b) `jq -e .` parses the result, (c) every key is present with
   its hash, (d) keys are sorted, (e) the empty-map case yields `"files": {}`.

5. **Integration test (`tests/setup_create_manifest.bats`).**
   Add a test that forces `manifest_write` to fail (e.g. stub `jq`/make the target
   unwritable) and asserts the run exits non-zero and prints **no** `[OK] wrote` line.
   Optionally assert a large synthetic tree produces a valid manifest end-to-end.

6. **(Optional) Perf cleanup of `_manifest_files_to_json`.**
   Replace the per-file `jq -Rs` key/value escaping with a single-pass encoder if it
   can be done without changing output bytes (sorted keys, identical escaping).

7. **Quality checks.** Run the bats suite and shellcheck; confirm no regression in the
   existing `tests/manifest.bats` / `tests/setup_create_manifest.bats` / `tests/setup_upgrade.bats`.

## Task Dependencies

- Steps 1 and 2-3 are independent (writer fix vs. caller guards) but ship together.
- Step 4 depends on Step 1 (verifies the stdin path).
- Step 5 depends on Steps 2-3 (verifies the caller guard / loud failure).
- Step 6 depends on Step 1 and must not change Step 4's asserted output bytes.
- Step 7 depends on all code + test steps.

## Test Strategy

- **Unit (`tests/manifest.bats`):**
  - Large files map (e.g. ≥ a few thousand synthetic `path → hash` entries, or entries
    long enough that the concatenated `--argjson` value would exceed a chosen threshold)
    round-trips to valid, parseable JSON.
  - Output keys are sorted (`LC_ALL=C`) and field order matches the schema.
  - Empty `MANIFEST_TRACKED` → `"files": {}`.
  - Byte-stability: same input produces identical output across runs.
- **Integration (`tests/setup_create_manifest.bats`):**
  - Forced write failure → command exits non-zero, no `[OK] wrote` emitted, prior
    manifest (if any) left intact.
  - Happy path on a synthetic tree → valid `.tarnished-manifest.json` with correct hashes.
- **Edge cases:**
  - Paths containing spaces / unicode / special chars still escape correctly via stdin.
  - Single-mode vs. monorepo root vs. per-module scopes all honor the return code.
  - `--dry-run` paths unaffected (no write attempted).
- **Portability:** tests must pass under both TTY and piped (`-y`) invocation per
  `.claude/rules/shell.md`; avoid hard-coding a platform-specific `ARG_MAX` value — size
  the fixture generously rather than to an exact limit so the test is not flaky across
  kernels.
