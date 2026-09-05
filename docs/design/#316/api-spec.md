# API Specification: #316 Safe AI foundation maintenance

## CLI additions and changed behavior

| Interface | Contract |
| --- | --- |
| `setup.sh --refresh [-y] [--dry-run]` | AI maintenance using the current setup checkout's updater and distribution, with explicit downstream root; no scaffold pipeline |
| Bare setup on existing Tarnished target | Same as refresh; explicit add-module remains separate |
| `setup.sh --create-manifest [--from-version <ref>]` | Compare eligible staged distribution candidates; never inventory downstream files as owned |
| `setup.sh --upgrade [existing upgrade options]` | Only proven runtime helper files; no project configuration merges or scaffold seeds |
| `refresh-assets.sh --project-root <absolute-path>` | Explicit target for setup-driven invocation; existing root discovery remains default for installed script |
| `refresh-assets.sh --source-dir <absolute-path>` | Read the supplied Tarnished distribution without fetching/resetting it; setup supplies its current checkout |

Both refresh options require arguments and validated ordinary directories. `--source-dir` must not overlap the target; it is read-only and may contain local source changes for deterministic tests. Existing `--config`, `--force-pull`, `--quiet`, `--dry-run` remain. The runtime script preserves its nonfatal warning contract. Dry-run missing upstream state is reported as an incomplete preview.

## Persisted schemas

Manifest v2 retains `tarnished_version`, `tarnished_commit`, `created_at`, `scaffold_options`, and `files: {path: "sha256:<64 lowercase hex>"}`. Read v1 only for conservative migration. `files` hashes mean installed/matched baselines; preserve them on conflicts or user deletion. Empty maps are valid. Optional `deleted_paths: [relative_path]` stores legacy deletion intent separately from proven `files` baselines. These eligible paths remain absent across repeated upgrade/bootstrap/refresh runs until the developer restores an exact distributed file for adoption; a tombstone grants no overwrite or prune authority. Do not rewrite equivalent state to change timestamps.

Refresh state at `.tarnished/refresh-state.json`:

```json
{
  "schema_version": 1,
  "entries": {
    ".agents/skills/flow/SKILL.md": {
      "mapping": {
        "repo": "https://github.com/TE-ToshiakiTanaka2/tarnished.git",
        "src": "templates/codex/.agents/skills",
        "dst": ".agents/skills",
        "overlay": ".agents/skills.local"
      },
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "origin": "upstream",
      "commit": "example-source-commit"
    }
  }
}
```

`origin` is `upstream` or `overlay`. Keys, nested `mapping` values, unprefixed 64-character SHA-256 hex digests, and origins are validated before use. The all-zero digest above illustrates valid syntax; actual records contain the installed content digest. Mapping identity includes source and destination plus repository; unrelated source/config changes do not authorize deleting former destinations. State is local metadata; it never joins either distributed asset inventory.

`refresh.json` remains schema 1 with optional `use_default_managed_paths: boolean`. Absence/false preserves the explicit project's `managed_paths`, including empty arrays. True selects the current upstream default `managed_paths` catalog, falling back with a warning to the project snapshot when the catalog is unavailable. It does not replace upstream/cache settings or profile choices.

## Internal contracts

| Boundary | Required behavior |
| --- | --- |
| Copy recording | Record successful eligible writes only; rehash that finite set after transformation |
| Bootstrap inventory | Enumerate private staged distribution; inspect only its eligible target counterparts |
| Eligibility | Positive runtime helper policy plus exclusion precedence; application/configuration/AI-refresh paths cannot enter manifest decisions |
| Path join/apply | Require validated relative path, no symlink components/leaf, file type compatibility, and root containment immediately before write/delete |
| State apply | Advance entry only after successful installation or exact match; preserve old entry on conflict/failure |
| Config adoption | New/missing config or exact known default mapping migration only; custom mapping lists are authoritative |
| Summary | Counts plus conflicting/unknown/removed/unsafe paths and concrete recovery source/target references |

Keep `manifest_decide(old,current,new)` as the pure trusted-baseline state machine where useful; migration/eligibility must strip untrusted claims before calling it. Apply equivalent decisions to runtime effective upstream/overlay candidates, with overlay-origin deletion protection. Shared existing plugin function signatures do not change.

## Host boundary and write verification

Shell maintenance requires Bash 4.4+. Explicit roots may canonicalize host ancestors once with portable `pwd -P` traversal; reject symlink root leaves and every symlink below the resulting physical roots. Compare overlap on physical roots before setup refresh writes. Never canonicalize an individual managed path to bypass its checks. BSD utility compatibility uses `shasum` when needed and portable atomic ordinary-file renames with expected-current checks before mutation plus installed-content verification. Dry-run Git inspection suppresses optional index/lock writes.
