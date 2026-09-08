# ELIS Changelog

## Unreleased

- Distinguished updater converter setup, conversion, missing-output, invalid-source,
  and installation failures; retained available converter/network diagnostics in
  `elis-update.log`, including missing Windows Bash/ImageMagick details.
- Refreshed demo discovery when returning from a directly launched cartridge.
- Prepared a separately licensed Mr. Rescue desktop playtest bundle and manual
  acceptance checklist without changing its physical-validation candidate status.
- Restored readable Mr. Rescue game-over text over the captain panel and cleared
  the entire paused framebuffer without rendering the hidden game beneath it.
- Upgraded untouched legacy keyboard profiles to include E for `BTN_E`, preserving
  custom keyboard/controller mappings and language. Saved profiles record their
  keyboard-default revision so explicitly removing E is respected on later loads.
- Added a focused, isolated persisted-preferences upgrade regression to the runtime gate.
- Added audited, reproducible Mr. Rescue playtest packaging with separate
  checksums, explicit replacement, and Linux/Windows launchers for installed
  bundles and source builds; added archive-integrity and failure-preservation gates.
- Separated Mr. Rescue's stage from its bottom HUD and added bounded vertical
  camera tracking, preserving native-size floors, characters, and assets.
  Added a framebuffer overlap regression and refreshed affected render baselines.
- Kept failure dialogs history-independent when restarting a campaign and moved
  failure reasons below the captain portrait with high-contrast text.

## 0.1.0-rc.1 — release candidate

- Added native Windows x86-64 UCRT64 builds and portable package-path, temporary
  directory, archive extraction, and codec-host handling.
- Added Ubuntu 24.04 and Windows binary packaging, dependency/source provenance,
  checksums, extracted-package smoke gates, and protected-main prerelease publication.
- Scoped Windows dependency licenses to the bundled library components and verified
  pinned Git source archives using makepkg-compatible checksums without trusting
  downloaded repository configuration.
- Protected manifest-driven sprite initialization against Lua heap exhaustion,
  preserving host allocation cleanup and returning a controlled cartridge-load error.
- Fixed clean Ubuntu CI dependency discovery and Lua interpreter installation,
  disabled persisted checkout credentials, and made every runtime smoke invocation headless.
- Added runtime software-renderer fallback for hosts without SDL acceleration,
  matching Workshop, and explicitly disabled executable stacks in native links.
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
- Promoted the separately licensed Mr. Rescue: Lupi Edition certification cartridge to `demos/mr-rescue/` as an explicitly unapproved physical-validation candidate. It includes deterministic RGB555 conversion, split compliant sheets, all 28 floor/room templates, seeded buildings, upgrades/doors, Classic civilian outcomes and rescue combos, original scoring/statistics/highscores, regular enemies/projectiles, three bosses, countdown/pause/summary states, warning indicators, original menu/statistics art, all eight music tracks, all nine how-to slides and both original intro cards, 17 bounded effects, source particles/water/shockwaves/HUD and boss HUD, indexed lighting, source-order front/back rendering, presentation-only Family mode, exact textured HUD bars, quantized flying-door and shard rotation, source-rate animation timing, source map-before-player update ordering, exact item/fire/boss-clear scoring timing, fixed-suit/moving-death-layer behavior, ladder/opposed-input/spray/water/death-flow corrections, complete 630-cell reachable fire storage, fixed and rejection-tested capacities, 832-generation sweeps, release-use/license audits, menu/countdown/pause/tutorial flow probes, source-equation player traces, exact transition-tick assertions, interaction/effect probes, per-enemy/projectile traces, and dedicated normal/high-stress/boss behavior-and-victory smoke gates. Named-board approval remains required before treating it as a finished release or beginning Hex-a-Hop.
- Hardened release loading with exact fail-closed manifest files, bounded archive bytes and entries, graceful browser errors, and immediate Lua/archive cleanup when returning to the catalog; fixed in-game menu cancellation, per-campaign statistics reset, and undoable Workshop layer-tileset changes with atlas refresh.
- Pinned CI actions to immutable revisions and added hostile archive/manifest regression coverage.
- Closed a second hardening pass: strict normalized cartridge/catalog paths, duplicate ZIP rejection, verified extraction lengths, valid JSON metadata, total-package flash accounting, undeclared-code rejection, pinned codec conversion, scoped updater cleanup, valid UTF-8 text dequeueing, bounded atlas decoding, explicit unsupported-music rejection, monotonic undo revisions, collision-free atomic project/settings writes, controller hotplug state repair, and a save/discard guard for unsaved Workshop exits.
- Rechecked Lupi upstreams: Lupinho remains `379a599d5e93db8228e2b0d4348ea65fcafa2ac5`, lupi-codec remains `3e8c66299a4606b36b9f490212acc44e084a6aa2`, and the SDK authoring guidance is recorded at `ebf57b25b528d4a198ff3288c9b803f2b9a98c76`; no newer core or codec revision required integration.
- Bounded every primitive and bitmap raster path per update, widened coordinate arithmetic, capped drawable map keys, rejected overflowing bitmap/map dimensions, and added extreme-coordinate regression coverage without changing valid upstream pixels.
- Hardened Workshop gesture ownership across focus loss and tool/presentation changes, ignored undocumented mouse buttons, added controller-safe template-panel navigation, kept entity names within the rendered ASCII contract, and promoted waiting controllers when a player slot becomes free.
- Fixed Workshop atlas identity across undo/redo when a layer previously had no loaded texture, suppressed controller edits while unfocused, and prevented held controls from becoming fresh commands after focus or hotplug.
- Made the native linker workaround resolve the selected compiler's multiarch CRT instead of assuming Arch Linux paths, removed the hard-coded x86-64 dynamic linker, and made formatting and shell syntax part of the maintained gate.
- Prepared public contribution and release infrastructure with architecture, contribution, accessibility, conduct, third-party notice, release, issue, pull-request, dependency-update, and REUSE-compliant machine-readable licensing documentation.
- Rolled back live Workshop edits if history allocation fails, removed no-op history/dirty revisions when a gesture returns to its source value, bounded host demo downloads to 64 MiB with HTTPS-only redirects and correct libcurl write accounting, and added focused regressions.
- Suspended queued keyboard, pointer, text, button, and analog-stick input while runtime or Workshop focus belongs to another window; text admission now preserves complete valid UTF-8 at queue capacity.
- Hardened demo-tree installation against failed destination creation and delayed output-close errors, rejected preference reads reporting I/O failure, and reset closed audio mixer state.
- Fixed Workshop schema round-trips for trailing field removal, preserved entity
  values during property edits, refreshed smart-terrain neighbors without
  deleting ordinary tiles, finalized gestures before save/undo, and removed
  duplicate project ownership on error paths.
- Registered console button constants before game initialization, propagated
  Lua frame failures from benchmark and screenshot modes, made manifest bitmap
  parsing whitespace-tolerant, bounded degenerate filled rectangles, and
  removed map-ordering allocation leaks during Lua errors.
- Reset mixer state between cartridges, surfaced partial demo-update failures,
  cleaned the GitHub launcher checkout on exit, revalidated Workshop assets at
  export time, and corrected palette/controller documentation.

## History

- The initial native simulator implementation was followed by native map authoring and the ELIS Workshop presentation.
