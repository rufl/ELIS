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

## Manual desktop playtest

Build or refresh the local bundle from the repository root:

```sh
python3 scripts/package_mr_rescue_playtest.py --output dist --replace
```

This audits the manifest and attribution before packaging the encoded cartridge;
it does not compile ELIS, download assets, or approve physical hardware. Without
`--replace`, existing playtest artifacts are left untouched. The output includes
`mr-rescue-playtest.SHA256SUMS` for the cartridge and outer ZIP. Archive timestamps
are normalized to 1980 by default; `SOURCE_DATE_EPOCH` can supply another epoch.
Identical inputs and packaging tooling produce identical archives.

The transferable bundle is `dist/mr-rescue-playtest.zip`. It contains a
`mr-rescue-playtest/` folder with `mr-rescue.lupi`, this README, `PARITY.md`,
`SOURCE.md`, `LICENSE.upstream`, `CC-BY-SA-3.0.txt`, and Linux/Windows play
launchers. No ELIS executable or runtime libraries are included: use an existing
working ELIS installation.
Keep the attribution files with the cartridge when redistributing the bundle.
The `.lupi` is a standard ZIP with the unchanged `current/` contents at its
root, not inside a `current/` directory. Attribution stays outside the cartridge
so its declared payload and manifest remain unchanged.

### Linux

From the ELIS repository root, using the existing local executable:

```sh
./zig-out/bin/elis dist/mr-rescue.lupi
```

To launch the transferable bundle instead:

```sh
unzip dist/mr-rescue-playtest.zip -d games
sh games/mr-rescue-playtest/play-mr-rescue.sh
```

The launcher finds `elis` in the installation root or `zig-out/bin/elis` in a
source checkout. It establishes the working directory itself, so it also works
when called from another folder.

The unpackaged source cartridge can also be launched without rebuilding:

```sh
./zig-out/bin/elis demos/mr-rescue/current
```

### Windows

Copy `mr-rescue-playtest.zip` beside your existing `elis.exe`. Open PowerShell
in that ELIS directory, leaving its bundled DLLs and other runtime files intact:

```powershell
Expand-Archive -LiteralPath .\mr-rescue-playtest.zip -DestinationPath .\games
.\games\mr-rescue-playtest\play-mr-rescue.cmd
```

You can also double-click `play-mr-rescue.cmd` in that extracted folder. It runs
the included PowerShell launcher without changing the machine's execution policy.
The launcher looks for `elis.exe` at the installation root or under `zig-out/bin`,
keeps DLL resolution local to that executable, and reports missing installations.

These commands assume a fresh extraction destination. The same cartridge works
on both desktop platforms; do not rename the outer playtest ZIP to `.lupi`.
Installing beneath `games/` also makes the cartridge discoverable when ELIS
starts without a game argument. On the published `0.1.0-rc.1` build, restart
ELIS without arguments to browse installed games after a direct launch; that
build has a return-to-browser discovery bug fixed in the current source.

### Physical keyboard defaults

Click the ELIS game window to focus it. These are the default host keys;
saved custom bindings in ELIS Controls can override them.

| Key | Mr. Rescue action |
|---|---|
| Arrow keys | Move, climb ladders, aim water, navigate menus |
| Z (`BTN_Z`) | Jump; confirm menu choices; advance title/start screens |
| X (`BTN_X`) | Spray water |
| M or E (`BTN_E`) | Pick up/throw civilians; back in game menus |
| Enter (`BTN_START`) | Advance title/start screens; pause/resume gameplay |
| Escape | Open the ELIS simulator menu, not the game's pause menu |

At the title, press Z or Enter, use arrows to select a menu item, then Z to
confirm. M and E are both physical rescue keys for default ELIS bindings.
The published `0.1.0-rc.1` ELIS binary uses M only: E requires a newer runtime
or a manual binding change in ELIS Controls. Updating the cartridge alone does
not change host keys. Current ELIS also upgrades saved, untouched legacy keyboard
defaults; custom keyboard profiles are preserved.

### Manual promotion checklist

- [ ] Record the cartridge hash, ELIS version, OS, and input device.
- [ ] Reach the title, browse all tutorial slides and menus, choose a campaign,
  and start playable Classic mode with visible art and audible music/effects.
- [ ] Exercise movement, ladders, jump, directional spray, water/heat limits,
  civilian pickup/throw/rescue, enemies, doors, and upgrades.
- [ ] Check game pause/resume with Enter; open the ELIS menu with Escape and
  return to the demo browser, then relaunch the cartridge.
- [ ] Complete representative progression, boss, failure, summary, and
  session-highscore flows; record defects rather than treating a boot as parity.
- [ ] Run the existing automated release gates below before any release
  promotion; manual play does not replace them.
- [ ] For physical approval, record the **named board and firmware**, cartridge
  hash, representative worst-case frame time and memory, and sustained-device
  soak results required by `PARITY.md`.

Passing the desktop checklist means **desktop demo acceptance only**. It does
not approve any physical Lupi board, prove all upstream parity, or authorize a
finished release. Named physical-board approval remains a separate release
gate; this playtest bundle does not change the existing candidate status.

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
