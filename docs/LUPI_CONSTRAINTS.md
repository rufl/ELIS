# Lupi Console Constraint Profile

This document separates the physical-console target from Lupinho's more generous
browser/desktop simulator envelope. ELIS defaults to the conservative console
profile and must not use host capacity as evidence of console performance.

## Source hierarchy

1. The live [Lupi documentation](https://lupi.api.br/docs/) is the source for
   the physical hardware, 480×270 display, RGB555 palette, API, and 60 Hz target.
   The page self-reports an update on 26 March 2026 and explicitly describes
   itself as provisional.
2. The physical runtime uses Lua 5.4, as confirmed for this project. Public Lupi
   repositories are contradictory: `lupi-org-br/lupinho` main at
   `379a599d5e93db8228e2b0d4348ea65fcafa2ac5` vendors Lua 5.5, while its
   `libretro-port` README still identifies Lua 5.4. ELIS targets the console,
   not that accidental web-simulator upgrade.
3. [Lupinho](https://github.com/lupi-org-br/lupinho) at the revision above is
   the executable reference for the indexed framebuffer and legacy map path.
4. [lupi-codec](https://github.com/lupi-org-br/lupi-codec) at
   `3e8c66299a4606b36b9f490212acc44e084a6aa2` defines accepted Tiled maps and
   the 49,152-pixel tileset ceiling.
5. [lupinho-sdk](https://github.com/lupi-org-br/lupinho-sdk) at
   `ebf57b25b528d4a198ff3288c9b803f2b9a98c76` documents the authoring pipeline,
   but pins older Lupinho 1.1.0 and lupi-codec 1.0.0 tags. Its broad 512×512
   image statement does not override the codec's executable 49,152-pixel Tiled
   tileset check or provide physical firmware semantics.
6. The ESP32-S3 N16R8 designation supplies 16 MiB flash and 8 MiB PSRAM. The
   RP2350 register map in Raspberry Pi's public `pico-sdk` exposes main SRAM at
   `0x20000000..0x20082000`, or 520 KiB.

## Physical hardware envelope

| Resource | Console target | ELIS policy |
|---|---:|---|
| Control CPU | ESP32-S3 N16R8, 240 MHz | Never use desktop CPU speed as proof |
| Companion CPU | RP2350, overclocked to 345 MHz | Treat as a CPU/coprocessor, not a GPU |
| External RAM | 8 MiB ESP32 PSRAM | Lua heap hard-capped at 4 MiB |
| Flash | 16 MiB ESP32 flash | Reported by `--lupi-constraints` |
| Archive entries | Not published | ELIS admission capped at 4,096 entries |
| RP2350 SRAM | 520 KiB | Not combined with ESP32 PSRAM as one heap |
| Discrete GPU | None documented | Indexed software framebuffer is authoritative |
| Display | 480×270 at a 60 Hz target | 16.667 ms total frame budget |
| Framebuffer | 129,600 bytes, one byte per pixel | Fixed-size global indexed framebuffer |
| Palette | 256 entries, `0RRRRRGGGGGBBBBB` RGB555 | Indices 0–255; index 0 is transparent |

The 4 MiB Lua ceiling is an ELIS safety reserve, not a claimed firmware
partition: it leaves half of PSRAM for engine state, assets, archives, audio,
and transient buffers. An allocation beyond that ceiling fails through Lua's
normal out-of-memory path. Archive input bytes, extracted bytes, and complete
manifest-backed package bytes each remain within 16 MiB; archive metadata work
is independently bounded to 4,096 entries. Normalized relative paths, unique
archive and manifest names, exact extraction lengths, JSON metadata, and
undeclared executable files fail closed. `ui.stat(0)` reports Lua memory,
`ui.stat(1)` reports
frame-budget CPU utilization, and `ui.stat(7)` reports FPS.

The public Lupinho WebAssembly build allocates 64 MiB total memory and a 1 MiB
stack. Those are browser-simulator settings and are deliberately **not** the
ELIS console target. The live system page also labels `ui.palset` as “RGB565 or
internal” while the introduction, bit layout, examples, and renderer all use
RGB555; ELIS follows the explicit `0RRRRRGGGGGBBBBB` contract.

## Graphics, maps, and layers

- Drawing is software composition into the indexed 480×270 framebuffer. SDL or
  Raylib acceleration is host presentation only and cannot change game-visible
  pixels or count as console GPU evidence.
- Sprite and tile sources are square indexed bitmaps. Tile IDs are 0–1023.
  Current docs expose explicit horizontal and vertical flip arguments; ELIS also
  retains legacy bits 10 and 11 for encoded map compatibility.
- The official codec accepts finite, orthogonal, right-down, uncompressed Tiled
  maps whose tile layers start at `(0,0)`. Tiles are square; spacing is zero.
- The official codec emits sparse numeric tile tables. ELIS Workshop does the
  same to avoid allocating empty Lua entries. Manifest `tiles` counts can include
  source-sheet margins, so ELIS derives available runtime tiles from exact
  encoded bytes divided by tile area.
- The console API publishes no numeric layer maximum. Codec output gives each
  authored Tiled layer its own table, and official games call `ui.map` in the
  desired bottom-to-top order. A map table may contain multiple string-keyed
  tileset tables. ELIS's explicit `layers` array is a deterministic compatible
  extension; Workshop is conservatively fixed to four visual layers.
- Workshop export requires exact manifest-backed files, existing tile IDs, the
  official 49,152-pixel tileset ceiling, at most 518,400 sampled tile pixels per
  `ui.map` call, at most 4,096 weighted generated-data entries, and at most
  128 KiB of generated Lua source. Visual and semantic tables are sparse.

## API alignment relevant to constraints

- Lua language/runtime: 5.4.
- `update(frame)` receives a monotonically increasing frame number.
- `ui.cls` clears the framebuffer and resets clipping.
- `ui.spr` and `ui.tile` accept independent horizontal and vertical flips.
- Input supports player indices 0–2.
- Palette registration, map calls, primitives, audio, and game logic all share
  the same 16.667 ms frame budget.

## What remains unproven

The public sources do not document the exact ESP32/RP2350 division of work,
firmware-reserved PSRAM, audio buffer sizes, flash bandwidth, or per-primitive
cycle budgets. Therefore:

- passing ELIS proves the implemented API subset, data, memory-ceiling, and
  deterministic-renderer compatibility;
- desktop timing does not prove 60 FPS on the physical console;
- the newer provisional docs list `ui.grid`, `ui.mouse`, and the Clay layout API,
  which are not present in the pinned public simulator and are not yet complete
  ELIS parity claims;
- final performance approval requires a release game running on a named Lupi
  board, with `ui.stat` memory/CPU/FPS captures from representative worst cases.

The runtime, asset intake, and Workshop exporter share the executable constants
in `src/studio/lupi_profile.zig`. Run `elis --lupi-constraints` to inspect the
machine-readable profile enforced by the current binary.
