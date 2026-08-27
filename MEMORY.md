# ELIS Memory

## Project Snapshot

ELIS is a Zig 0.16 native Lupi-compatible simulator with a 480×270 indexed framebuffer, Lua game loop, SDL input/audio/video host, and a separate native Workshop map editor. The compatibility boundary is documented in `COMPATIBILITY.md`; Workshop behavior and formats are documented in `STUDIO.md`.

## Architecture Notes

- `src/main.zig` owns the simulator, Lua API, indexed renderer, and command-line/runtime host.
- `src/studio_app.zig` owns the SDL Workshop application; `src/studio/model.zig` owns editable world state, commands, schema migration, Lua export, bounded semantic tile stamps, and the typed entity grid.
- `src/debug.zig` provides the runtime statistics and rendering-debugger state.
- `scripts/verify.sh` composes focused unit, parity, runtime, and Workshop smoke checks.

## Maintained Local Gate

Run `bash scripts/verify.sh`. It builds in `ReleaseSafe`, uses dummy SDL drivers for automated paths, verifies upstream raster hashes, and exercises Workshop save/export/reload plus simulator loading.

## Gotchas

- `scripts/build_native.sh` uses a temporary CRT copy to remove GCC 16 `.sframe` sections; never modify the system CRT.
- Keep Zig caches and build output untracked (`.zig-cache/`, `.zig-global-cache/`, and `zig-out/`).
- `ui.map` layer declarations are strict and ordered; preserve the reserved `lupi_metadata` structure emitted by Workshop.
- Stamps are active-layer patterns only. They retain raw tile and smart-terrain values, but do not include collision, entities, spawn, goal, or tileset assignment. Flip/rotate transforms rearrange cells; they do not mirror individual tile artwork.
- Line and rectangle gestures commit once on release; Shift fills rectangles and right-button gestures erase. Visual-layer visibility and painting locks are session UI state, not persisted project data or exported runtime metadata.
- Map resize preserves all layered tiles, smart-terrain bases, collision, entities, values, and in-bounds markers relative to one of nine anchors. Clipped cells and markers are diagnosed before apply; smart variants are refreshed at new edges; resize participates in the same ordered undo/redo history through bounded project snapshots.
- Blank, Platformer, Arena, and Puzzle templates preserve dimensions and layer tileset assignments while replacing authored map/schema content. Panel application uses the same project-snapshot history; `--template=` only affects creation when the project path does not exist.
- Lua export fails closed unless level validation passes and every layer has a manifest-backed exact bitmap within official tileset/tile-ID bounds. Sparse visual tables and a 518,400 sampled-tile-pixel ceiling bound one generated `ui.map` call; arbitrary Lua and physical-board FPS remain outside this static proof.
- The console profile is Lua 5.4, ESP32-S3 N16R8 at 240 MHz, 16 MiB flash, 8 MiB PSRAM, and RP2350 at 345 MHz with no documented discrete GPU. ELIS caps game Lua at 4 MiB and rejects releases above flash capacity; the public web simulator's 64 MiB memory is not a console target.
- Workshop Lua exposes official per-layer map tables for physical-console call ordering and keeps ELIS's deterministic combined representation under `project.map`.
- `LUPI-SAFE EXPORT: PASS` is fail-closed: generated Lua uses sparse visual/collision/smart data, at most 4,096 weighted entries and 128 KiB source, while the runtime enforces the 4 MiB heap. The claim ends when arbitrary Lua or additional runtime work is added.
- Full third-party ports are staged under `ports/` and enter `demos/` only after content completeness, license isolation, deterministic package/simulator gates, and named physical-device proof. Mr. Rescue is first; all 100 Hex-a-Hop levels follow only after Mr. Rescue approval.
- `.elisworld` schema v4 adds project-defined names and up to four typed fields per entity slot. Schema-definition edits use project snapshots in the same ordered history as map edits. V1 and v2 load with empty entity data; v3 promotes its old value to field zero. Export keeps schemas and entities inside reserved `lupi_metadata`.
- Treat downloaded demos and local Lua games as untrusted input when changing archive, filesystem, or network handling.
