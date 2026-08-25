# Demo library

The simulator scans this directory at startup. Add any encoded Lupi release as
`demos/name/` with `game.lua` and `lupi_manifest.txt`, or add a `.lupi` archive
directly here. Prepared releases may also be nested as `demos/name/current/`.

The binary reads `catalog.txt` itself. Press `U` in the demo browser (or use
`elis --fetch-demos`) to fetch public GitHub sources and convert them to
the indexed Lupi release format. `--fetch-demos` only installs missing demos;
`--update-demos` explicitly allows replacement. Entries beginning with
`builtin:` document demos shipped directly with the simulator and are not
downloaded.
