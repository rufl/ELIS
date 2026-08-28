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

The release converter consumes the pinned title/tutorial/menu/HUD, environment,
player, civilian, item, enemy, boss, particle, warning, water, fire, and
transition artwork; all eight OGG tracks; all four floor templates; all 24 room
templates; and both base maps. `tools/audit_upstream_mechanics.py` checks 80
pinned source/port movement, water, heat, civilian, fire, door, enemy, boss,
scoring, and progression invariants during conversion. `tools/audit_release.py`
rejects unreferenced converted bitmaps/music, undeclared payloads, size drift,
missing license files, or a changed source revision. Conversion preserves the
original RGB555 colors,
replaces source alpha with index-zero transparency, splits or repacks every
bitmap below Lupi's 49,152-pixel ceiling, and stores frames in tile-major order.
