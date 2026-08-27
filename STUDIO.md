# ELIS Workshop

ELIS Workshop is the native map and level authoring half of ELIS. The executable
remains `zig-out/bin/elis-studio`, separate from the Lupinho-compatible
`zig-out/bin/elis` simulator. Its Playful and Studio presentations are two views
of the same project—not separate beginner and expert file formats.

## Design boundary

The workflow takes ZYLVE World Studio's directness and mode-aware controller
edges, DINX's authoritative source/history/validation boundaries, ZNAP's clear
workspace and dirty-state ownership, and PIWEBQOL's responsive density,
minimum-size, reduced-motion, and input-equivalence policies.

Studio does not modify the indexed simulator framebuffer, Lua globals, palette,
input state, or timing. Export is an explicit file operation. Preview is an
editor map preview, not a claim that game-specific mechanics are running.

## Authoring model

- Projects are bounded from 4×4 through 64×64 cells with tile sizes from 1 to
  64 pixels.
- The strict visual order is `background`, `terrain`, `objects`, then
  `foreground`.
- Every layer owns an independent Lupi tileset name. A `--game-root` workspace
  reads compatible bitmap choices from `lupi_manifest.txt`; only assets matching
  the project's square tile size appear in the shelf. Session controls can hide
  a visual layer or lock it against painting without changing saved/exported data.
- The source project retains tile IDs from 0 through 1023; `65535` represents
  an empty cell and exports as `-1`.
- Line and rectangle gestures use bounded integer rasterization and commit as
  one undoable command on release. Rectangles are outlines by default; Shift
  fills them. Right-button gestures erase with the same preview and history path.
- Rectangle selection captures a bounded, active-layer stamp containing both
  rendered tile IDs and semantic smart-terrain bases. Stamping clips safely at
  map edges, coalesces into one undoable command, and refreshes neighboring
  smart-terrain joins without changing the source selection. Horizontal flip,
  vertical flip, and clockwise rotation rearrange stamp cells without mutating
  source tiles or pretending to mirror directional tile artwork.
- Smart terrain stores the authored material base separately from rendered
  tiles. Each material occupies 16 consecutive tiles. Cardinal neighbors form
  a deterministic mask: north `1`, east `2`, south `4`, west `8`; the rendered
  tile is `base + mask`. Painting or erasing refreshes the cell and four direct
  neighbors inside the same undoable stroke.
- Map resize/rebase supports nine content anchors from top-left through
  bottom-right. The inspector reports clipped content and spawn/goal markers
  before apply. Resizing preserves all in-bounds authored grids, refreshes smart
  terrain at new edges, and is one operation in the shared undo/redo history.
- Blank, Platformer, Arena, and Puzzle templates preserve project dimensions and
  layer tileset assignments while replacing authored map and schema content.
  Applying from the top-level panel is undoable; `--template=` selects a preset
  only when creating a project at a path that does not yet exist.
- Collision is an editor/runtime metadata mask rather than a visible layer.
- Player spawn and goal are typed markers, not magic tile IDs.
- A dedicated LDtk-style entity grid stores at most one typed instance per cell:
  enemy, pickup, trigger, or decoration. Each project-defined slot has a bounded
  name and up to four named `unsigned`, `toggle`, or `tile` fields with defaults
  and bounds. The schema editor renames types and fields, adds or removes trailing
  fields, cycles field kinds, and edits defaults/ranges through the shared
  undo/redo history. Non-decoration entities on collision produce a warning.
- `.elisworld` v4 is a versioned checksummed binary source artifact containing
  per-layer assets, semantic terrain, and typed entities. Saves write a sibling
  temporary file, sync it, and atomically rename it into place. Version-one
  projects gain independent layer tilesets; v1 and v2 migrate with an empty
  entity grid, while v3 promotes its old value to field zero. Older formats
  never invent authored schema or entity data.
- Exported Lua exposes official codec-style per-layer tables as
  `project.background`, `project.terrain`, `project.objects`, and
  `project.foreground`; games call them with `ui.map` in the desired order.
  `project.map` retains ELIS's deterministic combined-layer extension. Collision,
  markers, entities, editor identity, and schema remain reserved metadata.

## Validation

The issue panel checks:

- whether the current project is eligible for fail-closed Lupi export;
- required player spawn and goal markers;
- whether either marker occupies a blocked cell;
- four-neighbor critical-path reachability through the collision mask;
- whether the background layer is empty.

Preview mode refuses maps with spatial errors. Lua export additionally requires
manifest-backed exact-length square tilesets, existing tile IDs, the official
49,152-pixel tileset ceiling, at most 518,400 sampled tile pixels per `ui.map`
call, at most 4,096 conservatively weighted Lua data entries, and at most 128 KiB
of generated Lua source. Visual, collision, and smart-terrain tables export
sparsely; absent collision/smart entries mean false/empty. Without a valid
manifest, the source can still be saved but export is blocked.

A successful `LUPI-SAFE EXPORT: PASS` therefore guarantees that Workshop's
unchanged generated module satisfies ELIS's fail-closed console admission
profile. It does not cover arbitrary hand-written Lua, extra/repeated map calls,
animation, audio, or physical-device frame rate; adding those changes the
program and requires a new bounded package check plus on-device performance
proof.

## Controls

| Input | Action |
|---|---|
| Left mouse drag | Apply active brush/tool; drag while Select Stamp is active to capture a rectangle |
| Right mouse drag | Erase tile or clear collision |
| Mouse wheel, `[` / `]` | Previous/next tile |
| `B T E F P C S G I R M L D N` | Pencil, smart terrain, erase, fill, pick, collision, spawn, goal, entity, select stamp, paint stamp, line, rectangle, resize |
| `1`–`4` | Select ordered visual layer |
| Shift+`1`–`4` / Alt+`1`–`4` | Toggle session visibility / painting lock for a visual layer |
| `,` / `.` | Previous/next compatible layer tileset |
| Tab | Switch Playful/Studio presentation |
| Arrow keys | Move the grid cursor |
| Space/Enter, Delete | Apply or erase at cursor |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+C / Ctrl+V | Capture current selection / switch to the captured stamp |
| `H` / `V` / `O` | Flip stamp horizontally / vertically / rotate clockwise |
| Shift+rectangle drag | Draw a filled rectangle instead of an outline |
| `Q`, `-`, `+` | Cycle entity schema and edit its selected field; in Resize, cycle anchor and change width |
| Shift+`I` / Escape | Open / close entity schema-definition mode |
| `[` / `]` while Entity is active | Select the previous / next schema field |
| Enter / Shift+Enter in schema mode | Rename selected field / entity type |
| `K`, Insert, Delete in schema mode | Cycle field kind, add field, remove last field |
| `-` / `+`, with Shift or Alt | Edit schema default, minimum, or maximum |
| Shift+`-` / Shift+`+` | Decrease / increase resize height |
| Ctrl+S | Save `.elisworld` project |
| F5 | Export Lua map |
| F6 / F7 | Enter preview / return to edit |
| F8 | Open or close the project-template panel |
| Up/Down, Enter in template panel | Select and apply a template |
| Gamepad D-pad | Move cursor; in Resize, adjust width and height |
| Gamepad A / B / X / Y | Apply or begin/finish a selection/shape, erase/cancel, pick or cycle resize anchor, next tool |
| Gamepad shoulders | Previous/next tile; flip stamp; or cycle entity type, depending on tool |
| Gamepad left/right stick click | Switch presentation / next layer tileset; right stick rotates a stamp |
| Gamepad Back / Start | Preview / save |

Discrete controller operations fire on button edges. Holding A does not repaint
or fill every frame. Physical-controller approval remains separate from the
automated source and dummy-video proof.

## Commands

```sh
zig build studio
zig build studio -- --game-root=game --project=projects/world.elisworld --export=projects/world.lua
zig build studio -- --project=projects/puzzle.elisworld --template=puzzle
zig build test
zig build studio-smoke
zig build verify
```

For automation, `--save-export --smoke` writes the project and Lua map, renders
a bounded native session, then exits. `--capture=path.bmp` retains the rendered
editor frame.

`--game-root` loads `lupi_manifest.txt`, `palette.lua`, and the selected raw
bitmap assets. Palette values use Lupi's `0RRRRRGGGGGBBBBB` RGB555 contract. Missing or unparsable palettes visibly fall back to an editor-only
diagnostic palette. `--tileset-file` remains as a shared-atlas compatibility
path. `--presentation=studio`, `--reduce-motion`, and bounded window-size flags
support deterministic UI proof.

## Responsive and playful behavior

- 1280×760 and larger use the roomy Workshop composition. The 960×600 minimum
  uses compact panels and smaller—but still explicit—controls.
- Playful view adds tool explanations and the optional animated Pip guide.
  Studio view replaces that space with dense shortcut help. `--reduce-motion`
  stops the guide movement without removing information.
- Mouse, keyboard, and controller can all paint, erase, draw shapes, choose
  tiles, switch presentations, and change compatible layer assets. Discrete
  gamepad commands are edge-triggered.
- Feedback is presentation-only. It never changes project data, derived terrain,
  exported Lua, simulator timing, or the indexed framebuffer.

## Next mature slice

The next useful additions are configurable Wang/blob terrain rule layouts
beyond the deterministic cardinal family and an interactive
generated test-game wrapper. The automated smoke already proves the
export through the real simulator, but one-button interactive playtest and
physical-controller approval remain separate work.
