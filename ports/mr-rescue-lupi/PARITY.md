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
- Highscores and presentation settings are bounded and session-local. The sourced
  physical API exposes no storage primitive, so the cartridge makes no
  undocumented filesystem call or false persistence claim.

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
  cumulative statistics/awards, bounded session highscores, countdown and circle
  transitions, pause, win/failure, summary, name entry, bounded particles,
  warning indicators, source-textured HUD bars, bounded flying-door/shard
  rotation frames, indexed lighting, and presentation-only Family mode. Fire
  storage covers the complete 35-column × 18-row reachable
  source domain without silent saturation.

## Required before parity can be checked off

The converter now fail-closes on 80 pinned source/port mechanics invariants.
Runtime gates additionally trace source-equation player acceleration, braking,
jumping, opposed input, directional spray, water and landing vectors; all seven
regular enemy kinds; projectile activity; civilian states; flow states; boss
states; scores; capacities; and render hashes. Deterministic edge probes cover
all regular-enemy hit/recovery/death outcomes, sustained fire spread,
doors/windows, civilian/fire contact, item theft, and projectile collisions.
Transition ticks and mapped effect events are asserted alongside intro/menu/
options/history/highscores/level/countdown/play/pause/resume, section/prescreen,
game-over/summary/highscore entry, all nine tutorial slides, campaign arithmetic,
HUD textures, particles, enemy states, and projectile activity. The remaining
release proof is:

- Longer physical-device soak runs beyond the passing 832-generation simulator
  sweep and deterministic render matrix.
- Named physical Lupi frame-time and memory proof.

Until every requirement passes, the port remains under `ports/` and must not be
listed as a finished ELIS demo.
