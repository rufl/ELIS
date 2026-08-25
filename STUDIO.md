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
  the project's square tile size appear in the shelf.
- The source project retains tile IDs from 0 through 1023; `65535` represents
  an empty cell and exports as `-1`.
- Smart terrain stores the authored material base separately from rendered
  tiles. Each material occupies 16 consecutive tiles. Cardinal neighbors form
  a deterministic mask: north `1`, east `2`, south `4`, west `8`; the rendered
  tile is `base + mask`. Painting or erasing refreshes the cell and four direct
  neighbors inside the same undoable stroke.
- Collision is an editor/runtime metadata mask rather than a visible layer.
- Player spawn and goal are typed markers, not magic tile IDs.
- `.elisworld` v2 is a versioned checksummed binary source artifact containing
  per-layer assets and semantic terrain. Saves write a sibling temporary file,
  sync it, and atomically rename it into place. Version-one projects migrate by
  assigning their former shared tileset to every layer without inventing smart
  terrain.
- Exported Lua uses the simulator's strict `ui.map` layer contract. Collision,
  spawn, goal, editor identity, and schema live inside reserved
  `lupi_metadata`, which the renderer never mistakes for a visual layer.

## Validation

The issue panel checks:

- required player spawn and goal markers;
- whether either marker occupies a blocked cell;
- four-neighbor critical-path reachability through the collision mask;
- whether the background layer is empty.

Preview mode refuses maps with errors. Warnings remain visible but do not block
preview. This is spatial validation only; mechanics, Lua behavior, animation,
audio, palette fidelity, and final playability still require simulator and human
playtesting.

## Controls

| Input | Action |
|---|---|
| Left mouse drag | Apply active brush/tool |
| Right mouse drag | Erase tile or clear collision |
| Mouse wheel, `[` / `]` | Previous/next tile |
| `B T E F P C S G` | Pencil, smart terrain, erase, fill, pick, collision, spawn, goal |
| `1`–`4` | Select ordered visual layer |
| `,` / `.` | Previous/next compatible layer tileset |
| Tab | Switch Playful/Studio presentation |
| Arrow keys | Move the grid cursor |
| Space/Enter, Delete | Apply or erase at cursor |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+S | Save `.elisworld` project |
| F5 | Export Lua map |
| F6 / F7 | Enter preview / return to edit |
| Gamepad D-pad | Move cursor |
| Gamepad A / B / X / Y | Apply, erase, pick, next tool |
| Gamepad shoulders | Previous/next tile |
| Gamepad left/right stick click | Switch presentation / next layer tileset |
| Gamepad Back / Start | Preview / save |

Discrete controller operations fire on button edges. Holding A does not repaint
or fill every frame. Physical-controller approval remains separate from the
automated source and dummy-video proof.

## Commands

```sh
zig build studio
zig build studio -- --game-root=game --project=projects/world.elisworld --export=projects/world.lua
zig build test
zig build studio-smoke
zig build verify
```

For automation, `--save-export --smoke` writes the project and Lua map, renders
a bounded native session, then exits. `--capture=path.bmp` retains the rendered
editor frame.

`--game-root` loads `lupi_manifest.txt`, `palette.lua`, and the selected raw
bitmap assets. Palette values are decoded using the simulator's true BGR555
contract. Missing or unparsable palettes visibly fall back to an editor-only
diagnostic palette. `--tileset-file` remains as a shared-atlas compatibility
path. `--presentation=studio`, `--reduce-motion`, and bounded window-size flags
support deterministic UI proof.

## Responsive and playful behavior

- 1280×760 and larger use the roomy Workshop composition. The 960×600 minimum
  uses compact panels and smaller—but still explicit—controls.
- Playful view adds tool explanations and the optional animated Pip guide.
  Studio view replaces that space with dense shortcut help. `--reduce-motion`
  stops the guide movement without removing information.
- Mouse, keyboard, and controller can all paint, erase, choose tiles, switch
  presentations, and change compatible layer assets. Discrete gamepad commands
  are edge-triggered.
- Feedback is presentation-only. It never changes project data, derived terrain,
  exported Lua, simulator timing, or the indexed framebuffer.

## Next mature slice

The next useful additions are rectangle/selection/stamp tools, map resize and
rebase, project templates, typed entity definitions and inspectors, configurable
Wang/blob terrain rule layouts beyond the deterministic cardinal family, and an
interactive generated test-game wrapper. The automated smoke already proves the
export through the real simulator, but one-button interactive playtest and
physical-controller approval remain separate work.
