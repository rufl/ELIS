# Mr. Rescue: Lupi Edition

This is the bounded physical-validation candidate for Tangram Games' Mr.
Rescue. It is in `demos/` only by explicit authorization for local named-board
testing; it is not hardware-approved or a finished release. The exact remaining
proof is recorded in [PARITY.md](PARITY.md). The
current slice proves exact RGB555 art conversion, all floor/room templates,
seeded building assembly, the five upgrades, fixed-capacity fire/civilians,
Classic burn/casualty states, player movement/ladders/carry/throw/directional
water, upgrades and doors, seven bounded regular-enemy behaviors, projectiles,
all three boss state machines, original title/how-to/selection/statistics art,
score/combo/statistics/highscore arithmetic, both intro cards, all nine how-to
slides, pause/countdown/transition/summary flow, bounded particles and lighting,
optional Family presentation, all 17
effect mappings, and all eight streamed music tracks. The exact software
cartridge is about 12.77 MiB and the largest observed certification heap is below
1.2 MiB. The software parity boundary and remaining named-board proof are
recorded in `PARITY.md`. Highscores and presentation settings intentionally
remain session-local because the sourced physical API has no storage primitive.
Named physical-board timing proof remains staged.

## Run the current certification slice

```sh
bash scripts/mr_rescue_smoke.sh
zig build run -- demos/mr-rescue/current
```

Controls use Lupi actions rather than host keys:

- D-pad: move
- `BTN_Z`: jump/start
- `BTN_X`: spray
- `BTN_E`: rescue

## Non-negotiable release gate

The physical-validation candidate becomes a finished release only when all are true:

- all three campaigns, procedural room sets, seven regular enemy variants,
  three bosses, civilians, five upgrades, menus, tutorial, pause, summaries,
  progression, music, and effects are present with original gameplay semantics;
- Classic mode preserves original civilian, heat, failure, scoring, and boss
  outcomes; an optional Family mode may soften presentation without changing
  Classic parity;
- generation is seeded, attempt-bounded, reproducible, and connectivity-tested;
- entity, fire, particle, audio-voice, map, and queue capacities are fixed and
  tested at both accepted and rejected boundaries;
- Lua stays below 4 MiB, the complete cartridge below 16 MiB, every bitmap at or
  below 49,152 pixels, tile IDs valid, and every render/update path bounded;
- 60 Hz host simulation, deterministic screenshot, sustained-memory, package,
  and simulator smoke gates pass;
- a named physical Lupi records representative worst-case frame time and memory.

A source-language or desktop LÖVE test is not compatibility proof.

## Rebuild converted assets

Pillow is only an offline conversion dependency; it is not part of ELIS or the
cartridge runtime.

```sh
python3 demos/mr-rescue/tools/convert_assets.py \
  /path/to/pinned/mrrescue demos/mr-rescue/current
```

The converter refuses any upstream revision other than the one recorded in
`SOURCE.md`.
