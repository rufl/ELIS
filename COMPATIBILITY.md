# ELIS Lupi compatibility contract

The reference revision is `lupi-org-br/lupinho@379a599d5e93db8228e2b0d4348ea65fcafa2ac5`.
The Zig runtime keeps its game-visible renderer compatible with that revision:
480x270 indexed frames, 256 BGR555 palette entries, transparent index zero,
the canonical 5x8 ASCII font, camera, clipping, fill patterns, primitives,
sprites, tiles, map flips, and bottom-to-top immediate composition.

## Deliberate compatible extensions

These differences remove undefined behavior or implement upstream placeholders;
they are not accidental renderer drift:

- `ui.map.layers` provides strict bottom-to-top ordering. Legacy multi-layer
  maps use stable lexical ordering instead of Lua hash order.
- Sprite lookup accepts exact manifest paths. Ambiguous short names fail with
  a sorted candidate list instead of selecting a hash-dependent asset.
- `ui.set_pallet`, `ui.preload_spritesheet`, and `ui.draw_sprite` are functional;
  the reference revision exposes those names but leaves their original bodies
  as placeholders or no-ops.
- `ui.circ`, `ui.stat`, `ui.peektext`, and `ui.readtext` are additive APIs used
  by public demos and do not change reference calls.
- `Palette.hex` is supplied after loading a generated palette module so source
  demos can resolve RGB colors against the encoded BGR555 palette.
- Invalid dimensions, missing assets, truncated data, ambiguous assets, and
  unsafe archives fail safely rather than reproducing C undefined behavior.

## Host presentation

The game surface is always converted at 480x270 and scaled by an integer with
nearest-neighbor sampling. The default 960x540 window is exactly 2x, the
minimum is 480x270, arbitrary sizes are letterboxed, and HiDPI dimensions come
from the renderer output rather than logical window points. Transparent game
pixels are composited over black, matching the reference. Simulator dialogs
use a separate transparent overlay and never mutate the game's framebuffer or
palette.

The desktop demo browser, localization, remapping UI, gamepad/joystick support,
native demo downloader, quit flow, statistics overlay, F1-F12 rendering
debugger, and separate `elis-studio` authoring application are host features
outside the upstream game-visible API. Editor data never enters the simulator
unless the user explicitly exports and loads a Lua map. Debug chrome is
composited after indexed-frame conversion. Rendering and layer suppression are
opt-in runtime inspection controls; all defaults preserve the reference output,
and the controls do not alter Lua-visible state or API results.

## Proof

`./scripts/parity_smoke.sh` verifies the upstream golden, every BGR555 value,
all ASCII glyphs, primitive edge cases, camera/clip/pattern interactions, SDL
alpha composition, deterministic asset resolution, and deterministic map
layering across independent Lua processes. `./scripts/runtime_smoke.sh` runs
directories, `.lupi` archives, Mazestein, and every installed demo.
`./scripts/studio_smoke.sh` separately proves native editor startup, manifest
and exact-palette intake, roomy and minimum-size presentations, atomic project
save, deterministic Lua export, exact saved-project reload, and simulator
rendering of the exported map. Version-one editor projects migrate in unit
coverage; semantic terrain and per-layer asset references remain reserved
editor metadata and do not change `ui.map` rendering rules.

Any new intentional difference must be added here together with an executable
regression. Unlisted game-visible differences are bugs.
