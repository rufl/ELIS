# ELIS Changelog

## Unreleased

- Added Mario Paint-style line and outline/filled rectangle tools with live drag previews, erase-shapes, controller/keyboard parity, and single-command undo.
- Added LDtk-style per-layer session visibility and painting locks with compact controls and keyboard shortcuts.
- Added bounded map resize/rebase with nine content anchors, preflight clipping counts, spawn/goal warnings, semantic smart-terrain refresh, and unified undo/redo.
- Added Workshop rectangle selection and reusable smart-terrain-aware stamps with horizontal/vertical flip, clockwise rotation, clipped placement preview, and undo/redo coverage.
- Added a bounded LDtk-style entity layer with enemy, pickup, trigger, and decoration types, one integer field, inspector controls, collision warnings, Lua export, and safe `.elisworld` v2 migration into schema v3.
- Expanded entities into schema-v4 project-defined slots with bounded names, up to four typed fields, defaults/bounds, v3 migration, deterministic Lua metadata, and a user-facing schema editor integrated with undo/redo.
- Added Blank, Platformer, Arena, and Puzzle project templates with CLI creation, an undoable Workshop panel, preserved dimensions/tilesets, and deterministic starter content and schemas.
- Added fail-closed Lupi export preflight for spatial validity, manifest-backed exact assets, official 49,152-pixel tileset limits, referenced tile bounds, sparse visual tables, and bounded per-call tile sampling work.
- Aligned the simulator with the physical console profile: Lua 5.4, a 4 MiB game heap inside 8 MiB PSRAM, 16 MiB release limits, sourced ESP32-S3/RP2350 constraints, RGB555 terminology, `ui.stat` CPU budget reporting, clip reset on clear, two-axis sprite/tile flips, and three player slots.
- Exported official codec-style per-layer map tables while retaining the deterministic combined map under `project.map`.
- Tightened successful Workshop exports to a fail-closed Lupi-safe admission profile: sparse visual/semantic tables, 4,096 weighted Lua entries, 128 KiB generated source, bounded map sampling, exact assets, and the 4 MiB runtime heap.
- Began the separately licensed Mr. Rescue: Lupi Edition certification port under `ports/`, with deterministic RGB555 conversion, split compliant sheets, all 28 floor/room templates, seeded buildings, upgrades/doors, Classic civilian outcomes and rescue combos, original scoring/statistics/highscores, regular enemies/projectiles, three bosses, countdown/pause/summary states, warning indicators, original menu/statistics art, all eight music tracks, all nine how-to slides and both original intro cards, 17 bounded effects, source particles/water/shockwaves/HUD and boss HUD, indexed lighting, source-order front/back rendering, presentation-only Family mode, exact textured HUD bars, quantized flying-door and shard rotation, source-rate animation timing, source map-before-player update ordering, exact item/fire/boss-clear scoring timing, fixed-suit/moving-death-layer behavior, ladder/opposed-input/spray/water/death-flow corrections, complete 630-cell reachable fire storage, fixed and rejection-tested capacities, 832-generation sweeps, release-use/license audits, menu/countdown/pause/tutorial flow probes, source-equation player traces, exact transition-tick assertions, interaction/effect probes, per-enemy/projectile traces, and dedicated normal/high-stress/boss behavior-and-victory smoke gates. It remains intentionally absent from the finished demo catalog.
- Added project control documentation, a recorded local proof boundary, MIT licensing, and a GitHub Actions verification workflow.

## History

- The initial native simulator implementation was followed by native map authoring and the ELIS Workshop presentation.
