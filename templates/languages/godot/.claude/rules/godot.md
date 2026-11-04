---
paths:
  - "**/*.gd"
  - "**/*.cs"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/project.godot"
---

# Godot Coding Rules

## Project Layout

- `project.godot` is the project root; scripts and scenes are addressed as `res://` paths
- `.godot/` is a cache: never edit it and never commit it
- Commit `.import` sidecar files and `export_presets.cfg`
- `addons/` holds third-party code: never reformat or lint it
- Tests live in `res://test/` (GUT)

## GDScript

- Use static typing everywhere: `var speed: float = 3.0`, typed arrays (`Array[Node2D]`), `-> void` return types
- Use `@export` and `@onready` annotations; declare `class_name` when other scripts need the type
- snake_case for functions, variables and signals; PascalCase for classes and enums; SCREAMING_SNAKE_CASE for constants
- Indent with tabs; `gdformat` and `gdlint` (configured by `gdlintrc`) are the authority
- Order members as `gdlintrc` defines: signals, enums, constants, exports, variables, onready variables, then methods

## C#

- Derive from Godot types as `partial` classes; keep the class name equal to the file name
- Use `[Export]` for editor properties; declare signals as delegates named `<Name>EventHandler` with `[Signal]`
- Prefer `GodotObject.IsInstanceValid(node)` over null checks for nodes that may have been freed
- Formatting follows `.editorconfig` (4 spaces); the Claude hook runs `dotnet format whitespace`
- For a full style and analyzer pass run `dotnet format <project>.csproj`
- Rebuild (`dotnet build`) before running the editor or tests after C# changes

## Scenes and Nodes

- Prefer composition over deep inheritance; one script per scene root where possible
- Reference nodes with `%UniqueName` or relative `get_node` paths; avoid hard-coded absolute node paths
- Instantiate scenes through `PackedScene`, not by rebuilding node trees in code

## Signals

- Declare signals at the top of the script, named in the past tense (`health_changed`)
- Connect in code or in the editor, not both
- Disconnect when the emitter or receiver is freed
- Call down the tree, signal up

## Pitfalls

- When editing `.tscn` / `.tres` by hand, keep the `uid` values intact
- `_process` is frame-bound, `_physics_process` is fixed-step: put movement and physics in the latter
- `await` on a node that may be freed needs an `is_instance_valid` check afterwards
- Avoid autoload overuse; pass dependencies explicitly
- Do not split one class between GDScript and C#
- Export templates are version-specific: re-download them after bumping Godot
- Use `--headless` for any Godot run without a display (CI, containers without WSLg)

## Testing

- Use GUT: files named `test_*.gd` that `extends GutTest`, placed under `res://test/`
- Run headless: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -ginclude_subdirs -gexit`
