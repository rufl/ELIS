# ELIS Architecture

This document is the entry point for contributors changing the simulator or Workshop. The compatibility contract is in [COMPATIBILITY.md](COMPATIBILITY.md); enforced hardware and package ceilings are in [docs/LUPI_CONSTRAINTS.md](docs/LUPI_CONSTRAINTS.md).

## Processes

ELIS builds two native Linux executables:

- `elis`: Lupi-compatible simulator, cartridge browser, package loader, indexed renderer, Lua host, input, audio, and debugging chrome.
- `elis-studio`: Workshop map editor, project persistence, deterministic Lua export, and preview UI.

The executables share types and constraints, not mutable runtime state. Workshop never injects editor state into a running simulator. Its only runtime boundary is an explicitly exported Lua module and its manifest-backed assets.

## Source ownership

| Path | Responsibility |
|---|---|
| `src/main.zig` | Simulator lifecycle, package admission, Lua bindings, software rasterizer, browser, overlays, and SDL presentation |
| `src/input.zig` | Three-player keyboard/controller/joystick state, remapping, hotplug, and UTF-8 text queue |
| `src/audio.zig` | Locked SDL audio state, libsndfile music decode, and bounded procedural effects |
| `src/debug.zig` | Allocation-free frame statistics and rendering-category/layer controls |
| `src/settings.zig` | Transactional preferences parsing and atomic persistence |
| `src/localization.zig` | Host chrome translations; cartridges own their text |
| `src/font.zig` | Canonical deterministic Lupi 5×8 font |
| `src/native.zig` | Single C-import boundary for SDL2, Lua, libzip, libcurl, and libsndfile |
| `src/studio_app.zig` | Workshop SDL lifecycle, transient interaction state, responsive layout, and rendering |
| `src/studio/model.zig` | Authoritative project data, commands, migration, validation, export, and atomic save/load |
| `src/studio/assets.zig` | Bounded manifest, palette, and bitmap metadata parsing |
| `src/studio/lupi_profile.zig` | Shared executable resource ceilings |

`src/main.zig`, `src/studio_app.zig`, and `src/studio/model.zig` are intentionally cohesive. Split code only when ownership becomes clearer; do not create pass-through modules around a single call.

## Simulator data flow

1. `main` selects a directory or extracts a `.lupi` archive into a unique temporary root.
2. Package admission checks normalized paths, exact manifest lengths, executable declarations, entry count, and complete flash accounting.
3. `load` creates a Lua 5.4 state with the bounded allocator, registers the Lupi API, indexes manifest sprites, translates supported binary literals, and executes `game.lua`.
4. Each update resets the raster-work allowance, sends one tick to Lua, and draws immediately into the 480×270 indexed framebuffer.
5. The framebuffer is converted through the active RGB555 palette to RGBA. Host menus and debug overlays are composited afterward so Lua-visible pixels remain unchanged.
6. SDL presents the texture with integer nearest-neighbor scaling and letterboxing.

Lua C callbacks follow the upstream API and carry no engine context pointer. `src/main.zig` therefore keeps one process-global simulator instance. Do not introduce a second Lua state without first replacing that callback ownership model.

## Renderer invariants

- The framebuffer stores palette indexes, not RGBA pixels.
- Index zero is transparent during game composition and reveals black at the SDL compositor.
- Drawing is immediate: later non-transparent writes win.
- Camera, clipping, and fill patterns are part of game-visible state.
- Every primitive, bitmap, text, tile, and map path charges the per-update raster budget.
- Legacy map keys are sorted; explicit `layers` arrays are strict bottom-to-top declarations.
- Host overlays may inspect rendering but must not alter framebuffer, palette, Lua results, or timing state exposed to a cartridge.

A new intentional difference from the pinned Lupinho baseline belongs in `COMPATIBILITY.md` and needs an executable parity fixture.

## Memory and resource ownership

- The game Lua allocator rejects growth beyond 4 MiB and must return to zero after `lua_close`.
- Archive roots are removed when a game unloads and on every extraction failure.
- Manifest and bitmap reads are bounded before allocation.
- SDL windows, renderers, textures, controllers, and audio devices are paired with immediate `defer` cleanup.
- `Audio` state is read by SDL's callback thread. Public mutations lock the device; helpers ending in `Unlocked` require the caller to hold that lock.
- Workshop `Project`, `History`, `Command`, and `Stamp` values have explicit ownership. Project snapshots are encoded byte slices owned by their history command.
- Project and settings replacement use Zig's atomic-file API after syncing the new file.

Expected runtime failures reject input or show a user-facing notice. Assertions are reserved for violated internal ownership or range invariants.

## Workshop model

`Project` is the only saved authoring truth. Its visual and smart-terrain arrays are layer-major; collision, entity kinds, and entity fields are cell-major. Visibility, painting locks, selection, notices, preview mode, and presentation are session-only.

One gesture uses `CommandBuilder` to coalesce repeated writes to each target. Returning every target to its source value restores the pre-gesture revision and emits no command. Painting commits compact before/after changes through `History.commitApplied`; if history allocation fails, the command restores project data and the pre-gesture revision. Structural operations—schema edits, templates, resize, and tileset identity—commit complete encoded snapshots before replacing the authoritative project. `History` bounds ownership to 128 commands and keeps committed project revisions monotonic through undo and redo so dirty-state checks cannot collide with an old saved revision.

`.elisworld` decoding is transactional. V1–V3 migration either returns a complete V4 `Project` or frees all partial allocations. Export first proves spatial validity and static Lupi ceilings, then writes sparse, deterministic Lua.

## Extending ELIS

### Add or change a Lua API

1. Establish executable firmware or pinned Lupinho behavior.
2. Add the smallest fixture under `tests/`.
3. Bind the API in `src/main.zig` without weakening package or raster bounds.
4. Update `COMPATIBILITY.md` if behavior differs intentionally.
5. Run `scripts/parity_smoke.sh` and `scripts/runtime_smoke.sh`.

### Add a Workshop operation

1. Put authoritative mutation in `studio/model.zig`.
2. Represent it as one command or one snapshot operation.
3. Add model tests for apply, undo, redo, bounds, and encode/decode where relevant.
4. Keep pointer, keyboard, and controller ownership equivalent in `studio_app.zig`.
5. Update `STUDIO.md` and run the Workshop tests and smoke gate.

### Add a cartridge

Follow [demos/README.md](demos/README.md) and [ports/README.md](ports/README.md). Cartridge code and assets retain their upstream licenses; they do not become MIT merely by residing in this repository.

## Proof boundaries

- `scripts/test_studio.sh`: model, assets, instrumentation, and native input unit tests.
- `scripts/parity_smoke.sh`: pinned renderer/API and SDL compositor parity.
- `scripts/runtime_smoke.sh`: package, archive, Lua, resource-limit, and hostile-input behavior.
- `scripts/studio_smoke.sh`: Workshop manifest/palette intake, persistence, export, reload, and simulator loading.
- `scripts/mr_rescue_smoke.sh`: separately licensed cartridge audit and deterministic behavior stress.
- `scripts/verify.sh`: formatting, shell syntax, and all maintained gates.

Automated parity is not physical-console certification. Named-board timing, memory, and soak evidence remains a separate release requirement.
