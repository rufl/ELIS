# ELIS Memory

## Project Snapshot

ELIS is a Zig 0.16 native Lupi-compatible simulator with a 480×270 indexed framebuffer, Lua game loop, SDL input/audio/video host, and a separate native Workshop map editor. The compatibility boundary is documented in `COMPATIBILITY.md`; Workshop behavior and formats are documented in `STUDIO.md`.

## Architecture Notes

- `src/main.zig` owns the simulator, Lua API, indexed renderer, and command-line/runtime host.
- `src/studio_app.zig` owns the SDL Workshop application; `src/studio/model.zig` owns editable world state, commands, schema migration, Lua export, bounded semantic tile stamps, and the typed entity grid.
- `src/debug.zig` provides the runtime statistics and rendering-debugger state.
- `scripts/verify.sh` checks formatting and shell syntax, then composes focused unit, parity, runtime, and Workshop smoke checks.
- `ARCHITECTURE.md` is the contributor ownership map; `CONTRIBUTING.md` defines PR and proof expectations; `THIRD_PARTY_NOTICES.md` records the non-MIT boundaries shipped beside ELIS.

## Maintained Local Gate

Run `bash scripts/verify.sh`. It builds in `ReleaseSafe`, uses dummy SDL drivers for automated paths, verifies upstream raster hashes, and exercises Workshop save/export/reload plus simulator loading.

## Gotchas

- `scripts/build_native.sh` asks the selected compiler for its multiarch `crt1.o`, uses a temporary copy to remove GCC 16 `.sframe` sections, and relies on the compiler's host dynamic-linker selection; never modify the system CRT or silently expose unsupported cross-compilation.
- Keep Zig caches and build output untracked (`.zig-cache/`, `.zig-global-cache/`, and `zig-out/`).
- `ui.map` layer declarations are strict and ordered; preserve the reserved `lupi_metadata` structure emitted by Workshop.
- Stamps are active-layer patterns only. They retain raw tile and smart-terrain values, but do not include collision, entities, spawn, goal, or tileset assignment. Flip/rotate transforms rearrange cells; they do not mirror individual tile artwork.
- Line and rectangle gestures commit once on release; Shift fills rectangles and right-button gestures erase. Visual-layer visibility and painting locks are session UI state, not persisted project data or exported runtime metadata.
- Map resize preserves all layered tiles, smart-terrain bases, collision, entities, values, and in-bounds markers relative to one of nine anchors. Clipped cells and markers are diagnosed before apply; smart variants are refreshed at new edges; resize participates in the same ordered undo/redo history through bounded project snapshots.
- Blank, Platformer, Arena, and Puzzle templates preserve dimensions and layer tileset assignments while replacing authored map/schema content. Panel application uses the same project-snapshot history; `--template=` only affects creation when the project path does not exist.
- Lua export fails closed unless level validation passes and every layer has a manifest-backed exact bitmap within official tileset/tile-ID bounds. Sparse visual tables and a 518,400 sampled-tile-pixel ceiling bound one generated `ui.map` call; arbitrary Lua and physical-board FPS remain outside this static proof.
- The console profile is Lua 5.4, ESP32-S3 N16R8 at 240 MHz, 16 MiB flash, 8 MiB PSRAM, and RP2350 at 345 MHz with no documented discrete GPU. ELIS caps game Lua at 4 MiB, counts manifests and payloads against flash, rejects malformed metadata, unsafe/duplicate package paths, and undeclared executable files, and bounds archives to 4,096 entries; the public web simulator's 64 MiB memory is not a console target.
- Workshop Lua exposes official per-layer map tables for physical-console call ordering and keeps ELIS's deterministic combined representation under `project.map`.
- `LUPI-SAFE EXPORT: PASS` is fail-closed: generated Lua uses sparse visual/collision/smart data, at most 4,096 weighted entries and 128 KiB source, while the runtime enforces the 4 MiB heap. The claim ends when arbitrary Lua or additional runtime work is added.
- Full third-party ports are staged under `ports/` until content completeness, license isolation, deterministic package/simulator gates, and named physical-device proof. `demos/mr-rescue/` is the sole explicit physical-validation exception and remains unapproved; all 100 Hex-a-Hop levels follow only after named-board approval.
- `.elisworld` schema v4 adds project-defined names and up to four typed fields per entity slot. Schema-definition edits use project snapshots in the same ordered history as map edits. History revisions remain monotonic across snapshots so dirty state cannot collide after save; project/settings writes use collision-free atomic temporary files, and dirty close requests require Save and Exit or explicit discard. V1 and v2 load with empty entity data; v3 promotes its old value to field zero. Export keeps schemas and entities inside reserved `lupi_metadata`.
- Treat downloaded demos and local Lua games as untrusted input when changing archive, filesystem, or network handling. Automatic conversion pins lupi-codec revision `3e8c66299a4606b36b9f490212acc44e084a6aa2`; per-demo extraction roots are released before processing the next catalog entry.
