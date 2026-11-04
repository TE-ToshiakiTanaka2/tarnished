# Orchestrator Review: #331 Add Godot (GDScript + C#) language flavor with WSLg GUI overlay and headless CI

Review of the designer's artifacts against the issue's Requirements (FR-1..FR-12, NFR-1..NFR-5, Constraints, OQ-1..OQ-3). Authoring was delegated to the `designer` subagent; this review and the commit are the orchestrator's.

## Rounds

| Round | Outcome |
| --- | --- |
| 0 | One blocking finding (below); all other decisions accepted |
| 1 | Finding resolved; artifacts cleared for commit |

Cap (2 returns) not reached.

## Blocking finding (round 0, resolved in round 1)

**FR-8 / D9 — non-interactive GUI opt-in could not work.** The original contract resolved `GODOT_GUI` only inside `plugin_interactive_setup`, but `setup.sh` (`execute_plugin_post_copies`) calls that hook only when `check_tty_available` succeeds. In every non-TTY run (CI, `curl … | bash`, the scaffold-build leg, bats) `GODOT_GUI=true` would have been silently ignored and the scaffold left headless; the design's own bats case for `GODOT_GUI=true` would have failed.

**Revision accepted:** a non-prompting resolver `_godot_resolve_gui_choice` (env var → already-listed entry → staging/`-y`/no-TTY ⇒ off) is called from `plugin_post_copy_shared` whenever the choice is undecided; `plugin_interactive_setup` calls the same resolver and adds only the prompt. `GODOT_GUI_ENABLED` is reset at source time. design.md, api-spec.md, flowchart.md, workflow.md and the shared api-spec.md / sequence.md were corrected consistently.

## Decisions the issue did not settle — accepted

- **OQ-1 (D1)**: Godot .NET build via mise `github` backend + `[tool_alias] godot`, verified by an actual install with the pinned mise (`4.7.2.stable.mono`). Keeps the runtime out of the Dockerfile per #325.
- **OQ-2 (D2)**: `godot 4.7.2-stable`, `dotnet 10.0.403`, `gdtoolkit 4.5.0`; re-checked for newer patches at implementation time.
- **OQ-3 (D3)**: `dotnet format whitespace` for the `*.cs` hook; exact CLI syntax is verified at workflow step 2.
- **D8 — deviation from FR-8's literal wording** ("merged the same way service plugins merge compose files"). Accepted: the existing compose merge replaces the service's `volumes` array (dropping the `/workspace` mount), and a merged `/dev/dxg` device would stop the container from starting on non-WSLg hosts, which contradicts FR-8's own acceptance and NFR-4. The overlay stays a separate file and is activated by listing it in `dockerComposeFile`, which matches the issue's Implementation Approach.
- **D9**: opt-in via prompt / `GODOT_GUI` env, no new `setup.sh` flag.
- **D5**: additive `common.sh` changes (`tool_alias` section in `mise_toml_ensure`, new `mise_toml_has_key`, overlay added to `replace_placeholders`). NFR-3 is guarded by workflow step 9.
- **D11**: `/usr/lib/wsl` mount + `LD_LIBRARY_PATH`, beyond FR-8's list, because `/dev/dxg` is unusable without them.
- **D16**: `dotnet build` inside the test job keeps FR-9's three jobs.
- **D22**: `scaffold-build.yml` leg + `smoke-runtimes.sh` checks automate the NFR-4 acceptance; accepted as a small scope addition.
- **D23**: no mirrored assets; `verify-mirrors.sh` unchanged.

## Noted, not blocking

- WSLg Vulkan on Debian trixie is CPU-only (lavapipe); GPU means the Compatibility renderer. Documented in docs plan.
- Docker Desktop WSLg paths are unverified; overlay paths are overridable.
- Pre-existing, out of scope: the root AI refresh replaces `.claude/settings.json` with the claude template, which carries no language hooks. This affects every language flavor today and deserves its own issue.

## Requirement coverage

Every FR/NFR is traced in design.md "Requirement traceability"; no requirement was dropped or narrowed. FR-11 (tooling-only scaffold) and the no-`features` constraint are asserted by tests in workflow.md.
