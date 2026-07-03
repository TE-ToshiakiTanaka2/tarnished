# Design: #304 Modernize AI workflow skills, erd commands, and automation

## Context

The repo ships a 5-stage AI development lifecycle (`issue -> design -> implement -> review -> pr`) expressed in three layers: `.tarnished/workflows/*.md` (agent-neutral summaries, declared canonical), `.claude/skills/*/SKILL.md` (the operational spec), and `.agents/skills/*` (Codex pointers). Detailed sub-behavior lives in 14 `erd:*` command docs mirrored byte-identically across `.claude/commands/erd/`, `.tarnished/workflows/erd/`, and `templates/claude/.claude/commands/erd/`. Distribution to downstream projects happens via `setup.sh` plugins at scaffold time and `refresh-assets.sh` (paths whitelisted in `.tarnished/refresh.json`) at container start.

## Assessment verdict

The lifecycle stages and the `docs/design/shared/` snapshot + `docs/design/#{issue}/` delta artifact model are **valid** — they match the strongest convergent 2026 pattern (spec-driven development: persistent per-feature artifacts, staged gates, fresh-context review). The defects are structural, not conceptual:

| # | Defect | Evidence |
| --- | --- | --- |
| 1 | Canonicity inversion: declared source (`.tarnished/workflows`) is 25 lines/stage; real spec is `.claude/skills` (up to 516 lines) | `.tarnished/workflows/README.md:3` vs `.claude/skills/design/SKILL.md` |
| 2 | erd docs predate the skills standard: zero frontmatter, no `$ARGUMENTS`, internal contradictions | all 14 files; build/cleanup/improve/test/reflect issues |
| 3 | MCP references (serena/context7/playwright) have no availability guarantee and no fallback; Codex config declares no MCP at all | `setup_plugins.sh` best-effort; `.codex/config.toml` |
| 4 | `/review` hard-requires Codex CLI, ignores `agent-profile.json`, hardcodes `develop` merge base | `.claude/skills/review/SKILL.md:16-29,57-58` |
| 5 | Mirror invariants maintained by hand; `refresh.json` omits `.tarnished/workflows/erd` so downstream drift is structural | 3 of last 5 PRs were parity repairs |
| 6 | Automation gaps: auto-tag race (#303), integration tests skip PRs, review stage invisible to GitHub, no claude-code-action | `.github/workflows/*` |

## Decisions (delta)

### D1. Source-of-truth graph made explicit (no relocation)

`.claude/commands/erd/` stays where it is (Claude Code merged commands into skills; commands are not deprecated and relocation would break `refresh.json`, `plugin.sh` generation, and the `/erd:` namespace). Instead:

- `.tarnished/workflows/README.md` is rewritten to describe the real graph: lifecycle *contracts* in `.tarnished/workflows/*.md`, operational spec in `.claude/skills/`, erd detail in `.claude/commands/erd/` with the other two erd trees as generated/mirrored projections.
- New `scripts/verify-mirrors.sh` encodes every byte-identity invariant; new CI job runs it on PRs.

### D2. erd command modernization (14 files)

- Frontmatter added: `description` (third person, what + when, trigger keywords), `argument-hint`. No `allowed-tools` (files are also consumed via Read-inline where frontmatter is inert; permission grants belong to the calling skill).
- Every `## MCP Tools` section gains a fallback sentence: built-in Grep/Glob/Read/WebSearch when a listed server is unavailable.
- Contradiction fixes: `build` escalates config/dependency failures to `erd:troubleshoot` instead of dead-ending; `cleanup` = removal-only, `improve` = enhancement-only (overlapping auto-fix items de-duplicated); `test` owns authoring missing tests (was: refused, while `implement` expected it); `reflect` gains concrete `gh pr checks` / `gh run view --log-failed` mechanics; `design`/`workflow` name `erd:implement` as the next step; `test` no longer references Claude-only `/pr`; `index-repo` size units unified.

### D3. Lifecycle skill slimming (progressive disclosure)

Remove per-skill content that restates erd files or other skills (the drift surface that caused the July parity repairs): "Leveraging erd:X" sections that duplicate erd bodies, per-skill Mermaid diagrams that restate the phase list, and branch-naming restatements (now referenced from `_shared/branch`). Keep: phase sequences, decision rules (research destination, UML routing, snapshot discipline NFR-1), artifact contracts, commit/PR format contracts, output templates.

### D4. `/review` reviewer-resolution ladder

1. Read `.tarnished/agent-profile.json` review agent if present and actionable.
2. Codex CLI (`codex exec` custom prompt, or `codex review` with `--builtin`) when installed — unchanged behavior.
3. **New fallback**: Claude-native independent review via the new read-only `code-reviewer` subagent (`.claude/agents/code-reviewer.md`) — fresh context, diff + design doc + rubric in, findings out; main context applies fixes.

The merge base derives from an explicit `[target_branch]` argument (default `develop`) instead of a hardcoded branch. Review criteria live once in the skill and are shared verbatim with the CI reviewer (D6).

### D5. MCP posture

- gh CLI remains the GitHub interface (official guidance; no GitHub MCP server).
- serena/context7 stay plugin-delivered; skills/erd docs get graceful degradation language instead of a duplicate `.mcp.json` (which would double-register tools when plugins are present).
- Codex config gains `[mcp_servers.context7]` so the Codex-projected erd docs stop referencing tools Codex cannot have.

### D6. GitHub Actions

- `auto-tag.yml`: `concurrency: auto-tag-${{ github.ref }}` (fixes #303 race) and explicit exit-code capture so erd errors are printed before the step fails.
- `rust-quality-check.yml`: integration tests run on PRs too (the `/pr` CI gate was weaker than the push gate).
- New `asset-parity.yml`: runs `scripts/verify-mirrors.sh` on every PR.
- New `claude-code-review.yml` (reusable + `pull_request`): first-pass PR review via `anthropics/claude-code-action@v1`, sticky comment, design-doc-aware prompt, guarded to no-op when `ANTHROPIC_API_KEY` is absent. Caller template under `templates/github-actions/claude-review/`. This gives the review stage a GitHub-side representation.

### D7. Refresh/manifest wiring

- `refresh.json` (workspace + agent-workflows template) gains: `.tarnished/workflows/erd` (src `templates/claude/.claude/commands/erd` — same source scaffold generation uses) and `.claude/agents` (src `templates/claude/.claude/agents`).
- `.agents/skills` (Codex) is deliberately NOT refresh-managed: `refresh-assets.sh` creates missing dst dirs, which would inject Codex assets into Claude-only projects. Documented as scaffold-frozen.
- `scripts/lib/common.sh::MANIFEST_EXCLUDE_GLOBS` extended to match (both `dir` and `dir/*` forms plus `.local` overlays); the existing `refresh_assets.bats` cross-check invariant covers the new entries without test changes.
- Delivery caveat: `refresh.json` is not itself refresh-managed, so projects scaffolded before this change must adopt the new managed-path entries once (documented in AGENTS.md section 6); until then their `.tarnished/workflows/erd` stays scaffold-frozen and `/review` uses its general-purpose-subagent fallback in place of the not-yet-delivered `code-reviewer` agent.
- `templates/claude/plugin.sh` copies the new `.claude/agents/` directory.

## Considered and rejected

- **PreToolUse hook gating `git commit`/`gh pr create` on design/review artifacts** — design is intentionally optional for XS work; a hard gate would fight the lifecycle's own flexibility. Revisit if skipped-design incidents occur.
- **GitHub MCP server** — gh CLI is more context-efficient and already pervasive in the skills.
- **Relocating erd commands into `.claude/skills/erd/`** — no functional gain; breaks refresh whitelist, scaffold generation, and namespace.
- **spec-kit adoption** — its artifact/gate structure is already present in `docs/design/`; wholesale adoption adds a Python CLI dependency and 8 overlapping commands.

## Error Handling

- `verify-mirrors.sh` reports each divergent pair with a `diff -r` excerpt and exits non-zero; CI surfaces it as a failed check.
- `claude-code-review.yml` skips (success, with notice) when the API key secret is missing, so forks and downstream projects without keys stay green.

## Implementation Notes

- Mirror updates are performed by editing the live tree and `cp -r`-ing to mirrors, then running `scripts/verify-mirrors.sh`.
- No Rust source changes; bats suites and mirror verification are the regression net.
