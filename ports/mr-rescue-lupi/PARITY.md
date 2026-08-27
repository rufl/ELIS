# Mr. Rescue parity contract

“Full parity” means the complete original game remains recognizable in rules,
content, progression, timing, difficulty, outcomes, scoring, enemy/boss behavior,
menus, music, and feedback. A feature is not complete merely because a related
sprite is visible.

## Hardware-mandated adaptations

These are compatible adaptations rather than omitted behavior:

- The original 256×200 camera views the same 656×256 world through Lupi's
  480×270 framebuffer. World coordinates, 16-pixel tiles, speeds, and timers stay
  in original units; the wider camera reveals more horizontal space.
- Original RGB colors map deterministically to their exact RGB555 values. Index
  zero replaces source alpha transparency.
- Sheets are repacked into tile-major chunks no larger than 49,152 pixels.
- The eight original music files stream unchanged. The physical numbered-effect
  API recreates the 17 short effects with bounded synthesized voices; waveform
  identity is not claimed.
- Host key/controller binding and display scaling remain ELIS responsibilities.

## Source content already represented

- All four floor and all 24 room templates.
- Original base and boss maps.
- Seeded room population, five upgrades, doors, fire, four civilian appearances,
  Classic casualty states, all seven regular enemy classes, projectiles, and the
  three boss families.
- Original title, how-to, level-selection, captain, highscore, and statistics art;
  all eight music tracks.
- Original movement constants, fixed 60 Hz integration, water regeneration and
  overload, heat, difficulty temperature limits, ladders, carry/throw, windows,
  directional water, campaign section thresholds, scoring, rescue combos,
  cumulative statistics/awards, bounded session highscores, countdown, pause,
  win/failure, summary, and name-entry states.

## Required before parity can be checked off

- Differential traces for player collision, doors/windows, civilians, each
  regular enemy, every boss state, fire spread, items, projectiles, and scoring.
- Differential proof for section/prescreen/countdown/pause/game-over/win,
  summary, highscore, score/combo/statistics, maximum-casualty, and progression
  behavior now represented by the bounded implementation.
- Remaining particles, lighting substitute, warnings, transitions, HUD details,
  complete menu/history/options behavior, and effect event timing.
- A physical-console-supported persistence decision for highscores/settings.
- Exhaustive converted-file attribution and no unused release assets.
- Long seed sweeps proving fixed capacities are never reached in accepted play.
- Complete package, sustained-memory, deterministic-render, and named physical
  Lupi frame-time proof.

Until every requirement passes, the port remains under `ports/` and must not be
listed as a finished ELIS demo.
