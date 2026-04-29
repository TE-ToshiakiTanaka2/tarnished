# API Specification: #259 Gitignore whitelist blocks

## Functions / Sections (delta)

| Name | Signature | Description |
| --- | --- | --- |
| `update_gitignore` (`scripts/lib/common.sh`) | `update_gitignore <target_dir>` | Appends three idempotent blocks to `${target_dir}/.gitignore`. Existing `.claude/settings.local.json` line removed. Signature unchanged. |
| Codex plugin gitignore step (`templates/codex/plugin.sh::plugin_post_copy`) | inline shell | Appends one idempotent `.codex/*` whitelist block. Existing `.codex/config.local.toml` line removed. |

## Block Templates (on-disk contract)

The literal text of each block is part of the contract: the marker comment (line 2 of each block, the `#` line) is what `grep -q` keys on. Renaming a marker in a later release will cause the block to be re-appended on existing projects. Only deliberately rename.

### Block 1 — `.claude/*` whitelist (`update_gitignore`, FR-1)

```
<blank line>
# Claude Code (track project configs only)
.claude/*
!.claude/commands/
!.claude/skills/
!.claude/scripts/
!.claude/agents/
!.claude/rules/
!.claude/hooks/
!.claude/settings.json
```

**Idempotency check**: `grep -q "^# Claude Code (track project configs only)$" "$gitignore_file"`

### Block 2 — `.serena/` (`update_gitignore`, FR-2)

```
<blank line>
# Serena MCP working files
.serena/
```

**Idempotency check**: `grep -q "^# Serena MCP working files$" "$gitignore_file"`

### Block 3 — `screenshots/` (`update_gitignore`, FR-3)

```
<blank line>
# Local screenshots (manual UI testing)
screenshots/
```

**Idempotency check**: `grep -q "^# Local screenshots (manual UI testing)$" "$gitignore_file"`

### Block 4 — `.codex/*` whitelist (Codex plugin, FR-4)

```
<blank line>
# Codex CLI (track shared config only)
.codex/*
!.codex/config.toml
```

**Idempotency check**: `grep -q "^# Codex CLI (track shared config only)$" "$gitignore_file"`

## Removed Entries (FR-5)

The following individual lines and their preceding comment headers are removed:

| Removed from | Removed line | Removed comment |
| --- | --- | --- |
| `scripts/lib/common.sh::update_gitignore` | `.claude/settings.local.json` | `# Claude Code local settings (personal preferences)` |
| `templates/codex/plugin.sh::plugin_post_copy` | `.codex/config.local.toml` | `# Codex CLI local settings (personal preferences, API keys)` |

The whitelist blocks subsume these (and more): `.claude/*` ignores `.claude/settings.local.json` since `.claude/settings.json` (without `.local`) is the only allow-listed file; `.codex/*` ignores `.codex/config.local.toml` since only `.codex/config.toml` is allow-listed.

## Idempotency Contract (FR-6, FR-7)

| Property | Behavior |
| --- | --- |
| First run on fresh `.gitignore` | All four blocks (three from `update_gitignore`, one from Codex plugin) are appended. |
| Re-run on already-bootstrapped project | Each `grep -q` succeeds, no block is re-appended. `.gitignore` unchanged byte-for-byte. |
| Run on user-edited `.gitignore` | User-authored content above, between, and below our blocks is preserved. Our blocks are not edited even if their internal `!` lines were modified by the user. |
| Run with Codex plugin not selected | Block 4 is not appended; the Codex plugin's `plugin_post_copy` is simply not invoked. |
| Per-block independence | Removing a single block from `.gitignore` (and its marker) causes only that block to be re-appended on next run; the others are left alone. |

## Output Contract (NFR-3)

`update_gitignore` emits exactly two messages, unchanged from today:

```
[INFO] Updating .gitignore...
[OK] .gitignore updated
```

Codex plugin gitignore step emits no additional messages (also unchanged — the Codex plugin's existing `plugin_post_copy` is silent on the gitignore step).
