# Mr. Rescue: Lupi Edition port plan

A checked item means implemented and covered by the focused port gate. The
cartridge is exposed in `demos/` only for explicit physical validation; only the
final gate makes it a hardware-approved release.

## 0. Intake and bounded foundation

- [x] Pin upstream revision and preserve zlib/CC-BY-SA licensing.
- [x] Produce an exact 124-entry RGB555 palette from all upstream PNG artwork.
- [x] Split the 256×256 tile source into two 32,768-pixel Lupi bitmaps.
- [x] Repack animation strips into deterministic tile-major files.
- [x] Render the original 41×16 base building and adapted original sprites.
- [x] Use fixed fire/human arrays and deterministic seeded randomness.
- [x] Exercise title, movement, jump, spray, carry, and evacuation in a golden smoke.
- [x] Record normal/high/boss slices below 1.2 MiB Lua inside the 4 MiB hard limit.

## 1. Complete core rescue play

- [x] Match run, brake, jump, ladder, carry, throw, and directional spray behavior.
- [x] Add collision-correct doors, windows, water impacts, heat, coolant, and failure.
- [x] Preserve original civilian burn/casualty mechanics and ash outcome in Classic mode.
- [x] Add optional Family presentation without changing Classic simulation or scoring.
- [x] Add all four civilian appearances and complete rescue/combo scoring.
- [x] Derive capacities from exhaustive upstream room analysis and test overflow rejection.

## 2. Deterministic building content

- [x] Convert all four floor templates.
- [x] Convert all 24 room templates across widths 10, 11, 17, and 24.
- [x] Complete one-attempt bounded seeded room assembly with items/enemies and structural connectivity validation.
- [x] Port all five item types with original distinct-room placement and fixed capacity.
- [x] Reproduce and validate the complete three-campaign/26-section progression.

## 3. Enemies and bosses

- [x] Port all seven regular enemy variants with fixed capacities.
- [x] Port Magma Hulk.
- [x] Port Gas Leak and Gas Ghost.
- [x] Port Charcoal and Coal Ball.
- [x] Add worst-case entity/fire/projectile tests and deterministic combat captures.

## 4. Complete presentation

- [x] Port the upstream title, how-to, level selection, pause, summary, history, and highscore states.
- [x] Keep bounded highscores/settings session-local because the sourced physical API exposes no persistence primitive.
- [x] Convert all required art into referenced sheets no larger than 49,152 pixels each.
- [x] Package all eight original streamed music tracks within the cartridge budget.
- [x] Recreate all 17 effects through supported bounded audio paths.
- [x] Replace canvas lighting with deterministic indexed overlays/dither.
- [x] Add child-readable Family copy, controller prompts, and reduced-flashing presentation.

## 5. Promotion gate

- [x] Complete software cartridge is at most 16 MiB and every manifest size is exact.
- [x] Lua startup and sustained simulator worst-case use remain below 4 MiB.
- [x] Every update/render/generation loop and collection has an enforced bound.
- [x] A 32-seed × 26-section sweep and deterministic screenshot matrix pass.
- [x] License, attribution, exact-manifest, and release-use audit passes for every shipped file.
- [ ] Named physical Lupi worst cases meet the accepted frame and memory budgets.
- [x] Move the cartridge to `demos/mr-rescue/` and update the catalog as an explicitly unapproved physical-validation candidate.
- [ ] Begin Hex-a-Hop only after every item above is checked.
