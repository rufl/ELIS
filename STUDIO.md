# ELIS Studio

ELIS Studio is the native map and level authoring half of ELIS. It deliberately
runs as `zig-out/bin/elis-studio`, separate from the Lupinho-compatible
`zig-out/bin/elis` simulator.

## Design boundary

The workflow takes ZYLVE World Studio's directness—select a tool, select a tile,
draw—and DINX's stronger ownership boundaries: an authoritative source project,
ordered authoring layers, bounded command history, automatic issue reporting,
and a deliberate edit/preview transition.

Studio does not modify the indexed simulator framebuffer, Lua globals, palette,
input state, or timing. Export is an explicit file operation. Preview is an
editor map preview, not a claim that game-specific mechanics are running.

## Authoring model

- Projects are bounded from 4×4 through 64×64 cells with tile sizes from 1 to
  64 pixels.
- The strict visual order is `background`, `terrain`, `objects`, then
  `foreground`.
- Every layer currently references one shared Lupi tileset name. The source
  project retains tile IDs from 0 through 1023; `65535` represents an empty
  cell and exports as `-1`.
- Collision is an editor/runtime metadata mask rather than a visible layer.
- Player spawn and goal are typed markers, not magic tile IDs.
- `.elisworld` is a versioned checksummed binary source artifact. Saves write a
  sibling temporary file, sync it, and atomically rename it into place.
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
| `B E F P C S G` | Brush, erase, fill, pick, collision, spawn, goal |
| `1`–`4` | Select ordered visual layer |
| Arrow keys | Move the grid cursor |
| Space/Enter, Delete | Apply or erase at cursor |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Ctrl+S | Save `.elisworld` project |
| F5 | Export Lua map |
| F6 / F7 | Enter preview / return to edit |
| Gamepad D-pad | Move cursor |
| Gamepad A / B / X / Y | Apply, erase, pick, next tool |
| Gamepad shoulders | Previous/next tile |
| Gamepad Back / Start | Preview / save |

Discrete controller operations fire on button edges. Holding A does not repaint
or fill every frame. Physical-controller approval remains separate from the
automated source and dummy-video proof.

## Commands

```sh
zig build studio
zig build studio -- --project=projects/world.elisworld --export=projects/world.lua
zig build test
zig build studio-smoke
zig build verify
```

For automation, `--save-export --smoke` writes the project and Lua map, renders
a bounded native session, then exits. `--capture=path.bmp` retains the rendered
editor frame.

Raw encoded bitmap data can be previewed with `--tileset-file`. The file is
interpreted as sequential `tile_size × tile_size` palette-index tiles, matching
the simulator's bitmap storage. Until exact project palette import lands, Studio
uses an editor-only diagnostic palette; always judge final colors in `elis`.

## Next mature slice

The next useful additions are per-layer tileset selection from
`lupi_manifest.txt`, exact `palette.lua` preview, rectangle/selection/stamp
tools, map resize/rebase, project templates, an asset browser, and a generated
test-game wrapper that can launch the exported map through the real simulator.
