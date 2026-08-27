# Mr. Rescue source and licensing

- Upstream: <https://github.com/SimonLarsen/mrrescue>
- Pinned revision: `a5be73c60acb8d1be506f7b5e48e784492ba96ce`
- Original authors: Tangram Games
- Port identity: **Mr. Rescue: Lupi Edition**

The upstream `LICENSE` is preserved as `LICENSE.upstream`.

- Original game code is under the zlib license, except for the separately
  licensed AnAL, slam, and TSerial modules. The Lupi port does not copy or ship
  those modules.
- Original graphics, music, and text are CC-BY-SA-3.0. The legal code is
  preserved in `CC-BY-SA-3.0.txt`.
- Converted bitmap data and adapted map data remain CC-BY-SA-3.0.
- Port Lua derived from the original gameplay code remains under zlib and is
  plainly marked as an altered Lupi version.
- ELIS-owned conversion and verification tools remain MIT.

The initial converted set uses `data/tiles.png`, `data/player_running.png`,
`data/player_gun.png`, `data/human_1_run.png`, `data/fire_wall.png`,
`data/fire_floor.png`, and `maps/base.lua`. Conversion preserves the original
RGB555 colors, replaces partial alpha with index-zero transparency, splits the
256×256 tile sheet below Lupi's per-bitmap ceiling, and stores frames in
Lupi tile-major order.
