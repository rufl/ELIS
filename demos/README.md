# Demo library

The simulator scans this directory at startup. Add only complete, licensed,
proof-gated Lupi releases as `demos/name/` with `game.lua` and
`lupi_manifest.txt`, or as `.lupi` archives. Incomplete ports remain under
`ports/` so the browser never presents certification work as a finished game.
Prepared releases may also be nested as `demos/name/current/`.

The binary reads `catalog.txt` itself. Press `U` in the demo browser (or use
`elis --fetch-demos`) to fetch public GitHub sources and convert them to
the indexed Lupi release format. `--fetch-demos` only installs missing demos;
`--update-demos` explicitly allows replacement. Entries beginning with
`builtin:` document demos shipped directly with the simulator and are not
downloaded.
