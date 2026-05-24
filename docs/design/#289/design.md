# Design: #289 fix(manifest): jq ARG_MAX overflow in manifest_write fails silently on large targets

## Context

The manifest subsystem (#265) is implemented in `scripts/lib/manifest.sh` and
driven by `setup.sh` in two post-scaffold modes:

- **`--create-manifest`** — walks an existing target, hashes every tracked file,
  and writes `.tarnished-manifest.json` (root + per-module for monorepos).
- **`--upgrade`** — reads the old manifest, re-runs the plugin pipeline against a
  staging area, applies the 8-case `manifest_decide` lifecycle, then rewrites the
  manifest with the new version + hashes.

Both modes converge on a single writer, `manifest_write` (`scripts/lib/manifest.sh:104`),
which serializes the global `MANIFEST_TRACKED` map (`{rel_path: sha256, ...}`) into
the manifest's `files` object. The on-disk schema (`shared/data-model.md`) and the
`manifest_write` signature (`shared/api-spec.md`) are unchanged by this issue — this
is a fix to *how* the writer invokes `jq` and *how* its callers honor its exit status.

The relevant invariant from `shared/architecture.md`: manifest writes are **atomic**
(write to `${file}.tmp`, then `mv`), so an interrupted or failed write must leave any
prior manifest intact and must not be reported as success.

## Architecture Overview (delta)

Two coupled defects, both observable in a single run against a large target
(`.../library`, `v0.0.87`, single-mode):

```
scripts/lib/manifest.sh: line 130: /usr/bin/jq: Argument list too long
[ERROR] manifest_write: jq build failed
[OK] wrote .../.tarnished-manifest.json     <-- false success
```

1. **`jq` ARG_MAX overflow (`manifest.sh:130`).** `manifest_write` builds the entire
   files map into a single shell variable `$files_json` and passes it to `jq` as a
   command-line argument via `--argjson files "$files_json"`. The exec argument vector
   is bounded by the kernel `ARG_MAX` (`getconf ARG_MAX`, typically ~2 MiB on Linux,
   counting env + all argv bytes). A large target's files map exceeds it, so `jq`
   never starts: `execve` returns `E2BIG` → `Argument list too long`. `manifest_write`
   then `rm`s its temp file and returns `1`. **No manifest is written.**

2. **Unchecked return code (4 call sites).** Every caller runs `manifest_write` and
   then unconditionally reports success:
   - `setup.sh:1689` — `--create-manifest`, monorepo root scope
   - `setup.sh:1709` — `--create-manifest`, per-module scope
   - `setup.sh:1721` — `--create-manifest`, single-mode scope
   - `setup.sh:2051` — `--upgrade`, per-scope rewrite (followed by
     `manifest_summary_print` → "Manifest updated.")

   The create-manifest sites print `[OK] wrote ...`; the upgrade site lets the summary
   declare "Manifest updated." In all four, a non-zero `manifest_write` is swallowed and
   the process exits `0`, masking the failure and corrupting the downstream `--upgrade`
   contract (it would operate on a missing/stale manifest).

The fix is two-part and the parts are independent: (a) remove the unbounded argument
from the `jq` exec so `manifest_write` succeeds on any tree size; (b) make all four
callers honor the exit status so that *if* a write ever fails again, it fails loudly
with a non-zero exit and no false success line.

## Module Structure (delta)

```
scripts/lib/manifest.sh     # manifest_write: feed files map to jq via stdin, not --argjson
setup.sh                    # 4 manifest_write call sites: guard on return code
tests/manifest.bats         # unit regression: large files map round-trips to valid JSON
tests/setup_create_manifest.bats  # integration: failed write => non-zero exit, no false [OK]
```

No new modules, files, or public symbols are introduced.

## Interface Design (delta)

### Functions

| Name | Signature | Change |
| --- | --- | --- |
| `manifest_write` | `manifest_write <scope_root> <tarnished_version> <tarnished_commit> <scaffold_options_json>` | **Signature unchanged.** Internal: pass the files map to `jq` via **stdin** instead of `--argjson files`. Still returns `0` on success, `1` on jq/IO error, atomic tmp+mv preserved. |

### Caller contract (clarified, not changed)

`manifest_write`'s non-zero return MUST gate the success message at every call site.
The contract always existed; the bug is that no caller honored it. After this issue:

- `--create-manifest` sites: `if manifest_write ...; then print_success "wrote ..."; else print_error ...; return 1; fi`
- `--upgrade` site: a failed `manifest_write` must abort the scope with a non-zero status
  and must not let `manifest_summary_print` imply success.

### Type Definitions (delta)

None. The `.tarnished-manifest.json` schema (`manifest_version`, `tarnished_version`,
`tarnished_commit`, `created_at`, `scaffold_options`, `files`) is byte-for-byte
identical to the pre-fix output (sorted keys preserved). This is a strict requirement,
not an incidental one — see Implementation Notes.

## Data Flow

`manifest_write` builds the JSON from two sources with very different size profiles:

- **Bounded inputs** (`manifest_version`, `tarnished_version`, `tarnished_commit`,
  `created_at`, `scaffold_options`) — a few hundred bytes at most. These stay as
  `--arg` / `--argjson` flags; they cannot overflow `ARG_MAX`.
- **Unbounded input** (`files` map) — grows with the file count of the target. This is
  the only argument that can overflow, so it moves off the command line and onto
  **stdin**, which is not subject to `ARG_MAX`.

New shape (illustrative):

```bash
printf '%s' "$files_json" | jq \
    --argjson manifest_version "$MANIFEST_SUPPORTED_VERSION" \
    --arg tarnished_version "$tarnished_version" \
    --arg tarnished_commit "$tarnished_commit" \
    --arg created_at "$created_at" \
    --argjson scaffold_options "$scaffold_options_json" \
    '{
        manifest_version: $manifest_version,
        tarnished_version: $tarnished_version,
        tarnished_commit: $tarnished_commit,
        created_at: $created_at,
        scaffold_options: $scaffold_options,
        files: .
    }' > "$tmp"
```

`-n` is dropped (input now comes from stdin); the files map becomes the program input
`.`. The atomic `> "$tmp"` then `mv "$tmp" "$file"` flow is unchanged, and the
`if ! ...; then rm -f "$tmp"; print_error; return 1; fi` guard still applies.

See `shared/sequence.md` (`--create-manifest` and `--upgrade` flows) for the updated
error edges that make a failed write abort instead of report success.

## Error Handling

| Condition | Before | After |
| --- | --- | --- |
| Large files map | `jq: Argument list too long`; write fails; `[OK]`/"Manifest updated" still printed; exit 0 | Write succeeds; truthful success line |
| `manifest_write` returns 1 (any cause: jq error, IO error, disk full) | Success message printed anyway; exit 0 | No success line; `print_error` surfaced; non-zero exit propagated from the call site |
| SIGINT mid-write | Atomic tmp+mv leaves prior manifest intact (unchanged) | Unchanged |

## Implementation Notes

- **Output stability is mandatory.** The `files` object must remain sorted by key
  (`_manifest_files_to_json` already sorts via `LC_ALL=C sort`) and the field order
  must match the current `jq` object literal, so existing manifests and CI golden
  comparisons see a byte-identical result. The stdin rewrite must not reorder fields.
- **`scaffold_options_json` stays a flag.** It is bounded and is also consumed as a
  parsed JSON object (`--argjson`); keep it off stdin so stdin carries only the files map.
- **Empty files map.** `_manifest_files_to_json` emits `{}` for an empty map; piping
  `{}` to `jq` with `files: .` must still produce a valid manifest with `"files": {}`.
- **Fourth call site.** `setup.sh:2051` (upgrade) is easy to miss because the success
  signal there is indirect (`manifest_summary_print` → "Manifest updated."). It must be
  guarded too, or large-repo upgrades will keep reporting success after a failed write.
- **Optional perf follow-up (in scope per estimate, low priority).**
  `_manifest_files_to_json` (`manifest.sh:154-176`) spawns two `jq -Rs` processes per
  tracked file to escape key and value. On a multi-thousand-file target that is thousands
  of `jq` forks — slow but correct. A single-pass encoder (one `jq -R` / `jq -Rn` over a
  NUL- or tab-delimited stream, or a `printf %q`-free JSON-escape) would cut process churn,
  provided sorted keys and exact escaping are preserved. Treat as optional; the two
  required fixes do not depend on it.
- **Portability.** Keep to `.claude/rules/shell.md`: `#!/bin/bash`, quoted expansions,
  `[[ ]]`, no `eval`. The stdin pipe and `printf '%s'` are portable across the bash
  versions the project already targets.
