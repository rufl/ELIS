# ELIS — Editor for Lupi with Integrated Simulator

ELIS is a native Zig 0.16 environment built on a compatible port of [Lupinho](https://github.com/lupi-org-br/lupinho), the Lupi console simulator. It provides the native SDL2 window, 480x270 indexed framebuffer, Lua 5.4 update loop, RGB555 palette, primitives, the canonical 5x8 bitmap font, camera, clipping, fill patterns, keyboard/controller/text input, music and effects, sprite manifests, sprites, tiles, tilemaps, `.lupi` archives, and command-line game selection.

The default runtime profile targets the physical console rather than Lupinho's
64 MiB WebAssembly envelope: ESP32-S3 N16R8 at 240 MHz, RP2350 at 345 MHz,
8 MiB PSRAM, no documented discrete GPU, and a conservative 4 MiB Lua heap.
Run `zig build run -- --lupi-constraints` for the enforced profile and see
[docs/LUPI_CONSTRAINTS.md](docs/LUPI_CONSTRAINTS.md) for sources and unknowns.

The audited compatibility baseline and every deliberate extension are listed
in [COMPATIBILITY.md](COMPATIBILITY.md).

> **Project status:** ELIS is ready for public source collaboration but has no
> stable binary release yet. The maintained host is Linux; CI runs Ubuntu 24.04
> on x86_64. Mr. Rescue is a software-parity physical-validation candidate, not
> a hardware-approved release. See [ROADMAP.md](ROADMAP.md) and
> [BACKLOG.md](BACKLOG.md) for the remaining proof boundaries.

Contributor entry points:

- [Architecture and ownership](ARCHITECTURE.md)
- [Contributing and focused tests](CONTRIBUTING.md)
- [Compatibility contract](COMPATIBILITY.md)
- [Workshop authoring guide](STUDIO.md)
- [Security policy](SECURITY.md)
- [Accessibility support and limitations](docs/ACCESSIBILITY.md)
- [Third-party licenses and attribution](THIRD_PARTY_NOTICES.md)

## Build and run

ELIS requires Zig 0.16.0, a C compiler, `pkg-config`, `objcopy`, and development
packages for SDL2, Lua 5.4, libzip, libcurl, and libsndfile. On Ubuntu 24.04:

```sh
sudo apt-get update
sudo apt-get install --yes --no-install-recommends \
  binutils gcc pkg-config python3 zip lua5.4 \
  libsdl2-dev liblua5.4-dev libzip-dev \
  libcurl4-openssl-dev libsndfile1-dev
```

Build and run from the repository root:

```sh
zig build native
zig-out/bin/elis example
zig-out/bin/elis game.lupi

# open the native map/level authoring workspace
zig build studio

# install only missing official demos; never replace an existing version
zig-out/bin/elis --fetch-demos

# explicitly accept replacement with the latest official versions
zig-out/bin/elis --update-demos

# repeatable ReleaseFast CPU benchmark (frames, repetitions)
./scripts/benchmark.sh 10000 5

# clone, prepare, and run a public GitHub demo
./scripts/open_github_demo.sh https://github.com/lupi-org-br/caio-pernocas

# end-to-end smoke test
./scripts/runtime_smoke.sh

# pixel/API differential regression against upstream commit 379a599
./scripts/parity_smoke.sh

# simulator parity, runtime, and Studio matrix
zig build verify
```

The game directory must contain `game.lua`. Games use the original `ui.*` and
`sfx.*` APIs and may define `update()`, called once per frame. Escape opens the
simulator menu instead of terminating the process directly. Manifest-backed
cartridges admit only normalized unique paths, valid metadata, exact files, and
complete packages within 16 MiB; undeclared executable files and malformed
archives fail closed.

## ELIS Workshop

`zig build studio` opens a separate native SDL2 authoring application. Workshop
offers a friendly, explanatory presentation and a compact Studio presentation
over the same authoritative project and command history:

- four strict bottom-to-top visual layers: background, terrain, objects, and
  foreground;
- pencil, line, outline/filled rectangle, deterministic 16-variant smart
  terrain, erase, contiguous fill, pick, collision, player-spawn, goal, typed
  entities with an undoable project-schema editor, rectangle selection, and
  reusable transformable stamp tools;
- independent manifest-backed tileset selection plus session visibility and
  painting locks for every visual layer, and source-defined `palette.lua` RGB555
  preview with diagnostic fallback colors;
- mouse, keyboard, and controller editing with a visible grid cursor;
- drag/fill/stamp command coalescing, nine-anchor map resize/rebase, four
  deterministic project templates, and bounded unified undo/redo history;
- fail-closed Lupi-safe export checks for level validity, manifest asset
  identity, tileset/tile bounds, map sampling, weighted Lua data, and generated
  source size;
- atomic checksummed `.elisworld` v4 source projects, safe v1/v2/v3 migration,
  printable-ASCII entity-schema names, official per-layer `ui.map` exports,
  an optional combined map, and semantic terrain/entities retained as reserved
  metadata;
- responsive 960×600 compact and roomy layouts, reduced-motion mode, friendly
  contextual teaching, a one-key presentation switch, and an unsaved-close
  Save/Discard guard for mouse, keyboard, and controller users;
- a chrome-free validated map preview plus native save/export/reload smoke.

Open a project using the game manifest and palette source as its asset workspace:

```sh
zig build studio -- \
  --game-root=game \
  --project=projects/forest.elisworld \
  --export=projects/forest.lua
```

For a new path, add `--template=blank|platformer|arena|puzzle`; existing project
files always load unchanged. `--tileset-file` remains available for a single
raw legacy preview. Without a
valid `palette.lua`, Workshop labels its fallback colors as diagnostic rather
than implying palette fidelity. See [STUDIO.md](STUDIO.md) for smart-terrain
layout, controls, formats, responsive presentations, and the runtime boundary.

### Runtime statistics and rendering debugger

While a game is running, press **F1** for the host statistics overlay and
**F2** for the command reference. Statistics use rolling half-second samples
and distinguish the virtual console update frequency from presentation FPS:

- simulation Hz versus the 60 Hz target, presentation FPS, average/max frame
  time, game `update()` time, and total work time before frame pacing;
- Lua memory, tick count, audio availability, output resolution, integer scale,
  and build mode;
- per-frame clear, primitive, sprite, text, map, and map-layer draw counts;
- current camera, clipping, fill-pattern, render-category, and selected-layer
  state.

The function keys are reserved as host debug commands while a game is active:

| Key | Command |
|---|---|
| **F1** | Toggle statistics |
| **F2** | Toggle the command reference |
| **F3** | Toggle all `ui.map` rendering |
| **F4** | Toggle `ui.spr`, `ui.tile`, and `ui.draw_sprite` rendering |
| **F5** | Toggle line, rectangle, circle, and triangle primitives |
| **F6** | Toggle game `ui.print` text |
| **F7** | Toggle fill-pattern masking; off renders pattern-aware draws solid |
| **F8** | Toggle enforcement of game clip regions |
| **F9** | Toggle game camera offsets |
| **F10** | Select the next map-layer name discovered from `ui.map` calls |
| **F11** | Toggle the selected map layer everywhere it is used |
| **F12** | Restore every rendering option and layer |

Debug overlays are composited after the indexed game frame and never change the
Lua-visible framebuffer, palette, or `ui.stat` contract. All rendering options
default to upstream-compatible behavior. `ui.cls` and palette updates remain
active while categories are hidden so toggles do not create stale-frame trails.

### Deterministic map layers

`ui.map` accepts an optional `layers` array containing every drawable map key
in bottom-to-top order. The declaration is strict: omitted, duplicated,
unknown, or non-string entries raise a Lua error rather than producing a
partially ordered frame.

```lua
ui.map({
    metadata = { width = 1, height = 1, tile_size = 16 },
    tilesets = { background = "terrain", foreground = "decor" },
    layers = { "background", "foreground" },
    background = { [1] = 0 },
    foreground = { [1] = 3 },
})
```

For upstream maps without `layers`, drawable string keys are sorted
lexicographically before rendering. This preserves existing one-layer maps
and gives legacy multi-layer maps a stable result across Lua hash seeds and
processes. `metadata`, `lupi_metadata`, `tilesets`, and `layers` are reserved
map keys. As in upstream, palette index zero is transparent and later layers
overwrite only non-transparent pixels.

The demo browser is available in Brazilian Portuguese, European Portuguese,
Spanish, and English. Choose **Idioma/Language** in the main screen; the choice
is applied immediately and persisted. Choose **Controles/Controls** to remap
all twelve console actions. Each action has three keyboard slots and one
gamepad slot. Left/Right switches slots, Enter captures a new input, Delete
clears it, and `R` restores every default. Duplicate bindings are rejected with
the name of the conflicting action. Fixed Up/Down, Enter, and Escape menu
fallbacks remain available even after gameplay bindings are cleared.

Default keyboard/controller mapping:

| Lupi | Keyboard | SDL/SNES position |
|---|---|---|
| Directions | WASD or arrows | D-pad / left stick |
| `BTN_Z` | K, Z or Space | A / lower face |
| `BTN_X` | J or X | B / right face |
| `BTN_E` | M | X / left face |
| `BTN_Q` | L | Y / upper face |
| `BTN_F`, `BTN_G` | G, H | L, R |
| Select | Tab or Backspace | Select/Back |
| Start | Enter | Start |

Language and control settings remain in SDL's per-user preference directory
under `lupi-org-br/lupinho-zig/settings-v1.ini`. ELIS intentionally retains
that pre-rename identifier so upgrades preserve existing preferences. Writes
are atomic and the simulator safely restores defaults if that versioned file
is incomplete or invalid.

The explicit aliases `SNES_A`, `SNES_B`, `SNES_X`, `SNES_Y`, `SNES_L`,
`SNES_R`, `BTN_SELECT` and `BTN_START` are also available. `BTN_X` retains its
historical Lupi meaning (the secondary/right-face action).

`open_github_demo.sh` accepts a public GitHub repository URL. It runs
already-encoded repositories directly; source repositories such as
`caio-pernocas` are prepared with pinned `lupi-codec` revision
`3e8c66299a4606b36b9f490212acc44e084a6aa2` (Lua and ImageMagick are required).
Set `LUPI_CODEC_DIR` to use an explicitly supplied local codec checkout instead.
Built-in acquisition allows HTTPS transfers and redirects only and caps each
source archive at 64 MiB before conversion and complete-package admission.

With no command-line game argument, the simulator opens its demo browser. It discovers `example`, `mazestein3d`, `.lupi` files, and encoded releases under `demos/`, `games/`, and `examples/`. Use Up/Down or the controller d-pad, then Enter/controller A to launch. Press `U` to fetch the official catalog. The confirmation dialog is the only GUI path that permits replacement; cancelling leaves every installed version untouched. After confirmation, a localized status bar is presented before network work starts and remains visible throughout the blocking download. It changes to an explicit finished or failed result when discovery completes. The catalog includes Caio Pernocas, Balão Gatinho, and Le Pendu plus the
bundled Mazestein 3D demo. It also exposes Mr. Rescue: Lupi Edition with an
explicit physical-validation label; that cartridge remains unapproved until
named-board proof exists. Future entries can be added to `demos/catalog.txt`.

This port keeps the console framebuffer indexed and scales it with nearest-neighbor pixels, so game logic remains resolution-independent. Keyboard, SDL game controllers, generic joysticks, hot-plug, and the left analog stick are supported.

The native window opens at an exact 2x scale (960x540), can shrink only to the
upstream 480x270 resolution, and uses integer letterboxing at arbitrary sizes.
HiDPI output uses the renderer's physical dimensions. Transparent palette-zero
pixels reveal black inside the game viewport, while simulator dialogs are
composited separately without changing the demo palette or its paused frame.

The build honors Zig's standard
`-Doptimize=Debug|ReleaseSafe|ReleaseFast|ReleaseSmall` option. It prefers GCC
15 and otherwise uses the system compiler. The selected compiler supplies its
multiarch `crt1.o` path; the script removes only Zig-incompatible `.sframe`
sections from a temporary copy and never modifies the system CRT. Set
`ELIS_LINK_CC` to select another compatible linker compiler (`ZILF_LINK_CC`
remains a legacy alias). Cross-compilation is not currently exposed because the
native C libraries and CRT workaround are host-specific.

## Contributing

Start with [CONTRIBUTING.md](CONTRIBUTING.md) and
[ARCHITECTURE.md](ARCHITECTURE.md). Pull requests should include the smallest
relevant proof, preserve the documented Lupi compatibility boundary, and keep
third-party cartridge licenses isolated. Use [SECURITY.md](SECURITY.md) for
private vulnerability reports and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for
community expectations.

## License

ELIS-owned source and tools are available under the [MIT License](LICENSE).
Machine-readable file coverage is recorded in `REUSE.toml` and `LICENSES/`.
The compatible Lupinho basis, dynamically linked libraries, downloaded demos,
and bundled Mr. Rescue candidate retain their own notices and licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). In particular, material under
`demos/mr-rescue/` is not relicensed as MIT.
