# ELIS Lupi compatibility contract

The renderer reference revision is
`lupi-org-br/lupinho@379a599d5e93db8228e2b0d4348ea65fcafa2ac5`.
The physical target is the live Lupi console profile: Lua 5.4 on an ESP32-S3
N16R8 at 240 MHz plus an RP2350 at 345 MHz, with no documented discrete GPU.
The Zig runtime keeps 480x270 indexed frames, 256 RGB555 palette entries,
transparent index zero, the canonical 5x8 ASCII font, camera, clipping, fill
patterns, primitives, sprites, tiles, map flips, and bottom-to-top immediate
composition. See [the sourced constraint profile](docs/LUPI_CONSTRAINTS.md).

## Deliberate compatible extensions

These differences remove undefined behavior, align newer console documentation,
or implement upstream placeholders; they are not accidental renderer drift:

- ELIS deliberately links Lua 5.4 rather than the public web simulator's
  currently vendored Lua 5.5, and caps the game Lua heap at 4 MiB.
- Cartridge source loading translates the reference's `0b`/`0B` integer
  literals into Lua 5.4 hexadecimal tokens, preserving integer wraparound
  and operator precedence without rewriting strings or comments.
- Cartridge `?.lua` and `?/init.lua` paths precede host search paths.
  `require` preserves Lua 5.4 loader filenames and cached/uncached return arity;
  a found module's compilation failure does not fall through to another loader.
- `ui.cls` resets clipping; `ui.spr` and `ui.tile` accept explicit horizontal
  and vertical flips as documented by the console API.
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
  demos can resolve RGB colors against the encoded RGB555 palette.
- Invalid dimensions, missing assets, truncated data, ambiguous assets,
  malformed manifest metadata, undeclared package code, duplicate archive
  entries, unsafe paths, and extreme renderer coordinates fail safely rather
  than reproducing C undefined behavior. Each game update is capped at
  2,073,600 raster candidates and 256 drawable map layers; the raster budget
  resets every update, while `ui.cls`, palette state, and independently
  composited host controls remain available.
- Host music accepts libsndfile streams at the 44.1 kHz mixer rate with one to
  eight channels; unsupported streams fail visibly instead of playing at the
  wrong speed or reading beyond the bounded decode buffer.
  `sfx.music(-1)` stops playback; the no-argument form does not stop music.

## Workshop Lupi-safe export profile

Workshop saves remain editable even when incomplete, but Lua export fails closed
unless the spatial checks pass and every visual layer resolves through the Lupi
manifest to a square, exact-length bitmap. Referenced tile IDs must exist. Each
selected tileset is capped at 49,152 encoded pixels, matching the official
`lupi-codec` `512 * 96` tileset-image ceiling at revision
`3e8c66299a4606b36b9f490212acc44e084a6aa2`.

Generated visual, collision, and smart-terrain tables are sparse. One `ui.map`
call is capped at 518,400 sampled tile pixels, generated data at 4,096 weighted
entries, and generated source at 128 KiB. The maintained smoke loads that export
through the real simulator's 4 MiB Lua heap. `LUPI-SAFE EXPORT: PASS` guarantees
this unchanged generated map/asset module meets the enforced admission profile.
It cannot cover added Lua, repeated map calls, animation, audio, or physical
frame rate without package-level checks and on-device measurements. Firmware
reserved memory, ESP32/RP2350 work division, and operation cycle budgets remain
unpublished.

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

`./scripts/parity_smoke.sh` verifies the upstream golden, every RGB555 value,
all ASCII glyphs, primitive edge cases, camera/clip/pattern interactions, SDL
alpha composition, deterministic asset resolution, and deterministic map
layering across independent Lua processes. `./scripts/runtime_smoke.sh` proves
the Lua 5.4 link, machine-readable hardware profile, 4 MiB Lua heap ceiling,
16 MiB directory/archive release ceilings, 4,096-entry archive metadata bound,
exact fail-closed manifests, and runs directories, `.lupi` archives, Mazestein,
and every installed demo. `./scripts/studio_smoke.sh` separately proves native
editor startup, manifest and palette-source intake, roomy and minimum-size
presentations, atomic project save, deterministic Lua export, exact
saved-project reload, and simulator rendering of the exported map. Version-one
editor projects migrate in unit coverage; semantic terrain and per-layer asset
references remain reserved editor metadata and do not change `ui.map` rendering
rules.

The host demo downloader accepts only HTTPS transfers and redirects. A bounded
write callback and libcurl's advertised-size check both cap each source archive
at 64 MiB; converted and directly loaded packages still face the stricter
16 MiB complete-package limit. This host acquisition allowance is not console
memory or flash evidence.

Any new intentional difference must be added here together with an executable
regression. Unlisted game-visible differences are bugs.
