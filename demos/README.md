# Demo library

The simulator scans this directory at startup. Add complete, licensed,
proof-gated Lupi releases as `demos/name/` with `game.lua` and
`lupi_manifest.txt`, or as `.lupi` archives. `demos/mr-rescue/` is an explicit
physical-validation candidate authorized for local board testing; it is not
hardware-approved or a finished release. Other incomplete ports remain under
`ports/`.
Prepared releases may also be nested as `demos/name/current/`.

The binary reads `catalog.txt` itself. Press `U` in the demo browser (or use
`elis --fetch-demos`) to fetch public GitHub sources and convert them to
the indexed Lupi release format. `--fetch-demos` only installs missing demos;
`--update-demos` explicitly allows replacement. Entries beginning with
`builtin:` name a directly shipped cartridge path under `demos/` and are not
downloaded.
