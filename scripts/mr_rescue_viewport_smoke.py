#!/usr/bin/env python3
"""Check native-size stage visibility and HUD isolation with the real renderer."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def refresh_manifest(game):
    manifest = game / "lupi_manifest.txt"
    rows = []
    for row in manifest.read_text().splitlines():
        fields = row.split(" ", 3)
        fields[1] = str((game / fields[2]).stat().st_size)
        rows.append(" ".join(fields))
    manifest.write_text("\n".join(rows) + "\n")


def check_viewport(binary, source, output):
    hud_frames = []
    with tempfile.TemporaryDirectory(prefix="mr-rescue-viewport-") as temporary:
        for name, player_y, expected_rows in (
            ("bottom", 240, range(190, 238)),
            ("top", 80, range(48, 96)),
        ):
            game = Path(temporary) / name
            shutil.copytree(source, game)
            (game / "port_mode.lua").write_text("return { auto_start = true }\n")
            # Position only the rendered pose, after the normal simulation tick.
            # Mark its native 32-pixel carried-body + 16-pixel floor span using
            # the actual world transform and clipping, after lighting/front art.
            with (game / "game.lua").open("a") as script:
                script.write(f"""
local viewport_camera_x = Player.cameraX
Player.cameraX = function()
  Player.x, Player.y = 240, {player_y}
  return viewport_camera_x()
end
local viewport_warnings = World.drawWarnings
World.drawWarnings = function(camera_x, origin_y, frame, family)
  viewport_warnings(camera_x, origin_y, frame, family)
  ui.rectfill(100, Player.y + origin_y - 32,
              101, Player.y + origin_y + 16, Palette.hex(0xff00ff))
end
""")
            refresh_manifest(game)
            image = output / f"{name}.ppm"
            result = subprocess.run(
                [str(binary), "--screenshot", str(game), "1", str(image)],
                env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
                capture_output=True, text=True, timeout=30,
            )
            (output / f"{name}.log").write_text(result.stdout + result.stderr)
            assert result.returncode == 0, result.stdout + result.stderr
            magic, dimensions, maximum, pixels = image.read_bytes().split(b"\n", 3)
            assert (magic, dimensions, maximum) == (b"P6", b"480 270", b"255")
            assert len(pixels) == 480 * 270 * 3
            marker_rows = [
                y for y in range(270)
                if pixels[(y * 480 + 100) * 3:(y * 480 + 101) * 3] == b"\xff\x00\xff"
            ]
            assert marker_rows == list(expected_rows), (
                f"{name}: body/floor span clipped or displaced: {marker_rows}"
            )
            for y in range(238, 270):
                row = pixels[y * 480 * 3:(y + 1) * 480 * 3]
                assert row[:112 * 3] == bytes(112 * 3), f"{name}: stage leaks left of HUD"
                assert row[368 * 3:] == bytes(112 * 3), f"{name}: stage leaks right of HUD"
            hud_frames.append(pixels[238 * 480 * 3:])
            print(f"{name}: complete 48-pixel body/floor span; separate HUD band")
    assert hud_frames[0] == hud_frames[1], "Moving the camera changed the fixed HUD"
    print("Mr. Rescue viewport: pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=ROOT / "zig-out/bin/elis")
    parser.add_argument("--game", type=Path, default=ROOT / "demos/mr-rescue/current")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        check_viewport(args.binary.resolve(), args.game.resolve(), args.output.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="mr-rescue-viewport-output-") as temporary:
            check_viewport(args.binary.resolve(), args.game.resolve(), Path(temporary))


if __name__ == "__main__":
    main()
