# Mr. Rescue: Lupi Edition port plan

A checked item means implemented and covered by the focused port gate. It does
not mean the game is eligible for `demos/`; only the final promotion gate does.

## 0. Intake and bounded foundation

- [x] Pin upstream revision and preserve zlib/CC-BY-SA licensing.
- [x] Produce an exact 124-entry RGB555 palette from all upstream PNG artwork.
- [x] Split the 256×256 tile source into two 32,768-pixel Lupi bitmaps.
- [x] Repack animation strips into deterministic tile-major files.
- [x] Render the original 41×16 base building and adapted original sprites.
- [x] Use fixed fire/human arrays and deterministic seeded randomness.
- [x] Exercise title, movement, jump, spray, carry, and evacuation in a golden smoke.
- [x] Record normal/high/boss slices below 668 KiB Lua inside the 4 MiB hard limit.

## 1. Complete core rescue play

- [ ] Match run, brake, jump, ladder, carry, throw, and directional spray behavior.
- [ ] Add collision-correct doors, windows, water impacts, heat, coolant, and failure.
- [ ] Preserve original civilian burn/casualty mechanics and ash outcome in Classic mode.
- [ ] Add optional Family presentation without changing Classic simulation or scoring.
- [ ] Add all four civilian appearances and complete rescue/combo scoring.
- [ ] Derive capacities from exhaustive upstream room analysis and test overflow rejection.

## 2. Deterministic building content

- [x] Convert all four floor templates.
- [x] Convert all 24 room templates across widths 10, 11, 17, and 24.
- [ ] Complete seeded room assembly with fixed attempts, items/enemies, and connectivity validation.
- [x] Port all five item types with original distinct-room placement and fixed capacity.
- [ ] Reproduce the complete three-campaign/26-section progression.

## 3. Enemies and bosses

- [x] Port all seven regular enemy variants with fixed capacities.
- [x] Port Magma Hulk.
- [x] Port Gas Leak and Gas Ghost.
- [x] Port Charcoal and Coal Ball.
- [x] Add worst-case entity/fire/projectile tests and deterministic combat captures.

## 4. Complete presentation

- [x] Port the upstream title, how-to, level selection, pause, summary, history, and highscore states.
- [ ] Port highscores/settings using only physical-console-supported persistence.
- [ ] Convert all required art into sheets no larger than 49,152 pixels each.
- [x] Package all eight original streamed music tracks within the cartridge budget.
- [x] Recreate all 17 effects through supported bounded audio paths.
- [ ] Replace canvas lighting with deterministic indexed overlays/dither.
- [ ] Add child-readable copy, controller prompts, and reduced-flashing accessibility.

## 5. Promotion gate

- [ ] Complete cartridge is at most 16 MiB and every manifest size is exact.
- [ ] Lua startup and sustained worst-case use remain below 4 MiB.
- [x] Every update/render/generation loop and collection has an enforced bound.
- [ ] Long-running seed sweep and deterministic screenshot matrix pass.
- [ ] License/attribution audit passes for every shipped file.
- [ ] Named physical Lupi worst cases meet the accepted frame and memory budgets.
- [ ] Move the complete cartridge to `demos/mr-rescue/` and update the catalog.
- [ ] Begin Hex-a-Hop only after every item above is checked.
