#!/usr/bin/env python3
"""A previous casualty loss must not change a new campaign's overheating dialog."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from mr_rescue_viewport_smoke import ROOT, refresh_manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=ROOT / "demos/mr-rescue/current")
    source = parser.parse_args().game.resolve()
    dialogs = []
    with tempfile.TemporaryDirectory(prefix="mr-rescue-failure-") as temporary:
        for restart in (False, True):
            game = Path(temporary) / ("restart" if restart else "fresh")
            shutil.copytree(source, game)
            (game / "port_mode.lua").write_text("return { auto_start = true }\n")
            # Exercise real campaign reset and failure transitions; skip only
            # the unrelated time spent playing and animating the transition.
            with (game / "game.lua").open("a") as script:
                script.write(f"""
local failure_probe_update = update
local failure_probe_ready = false
function update(frame)
  if not failure_probe_ready then
    failure_probe_ready = true
    beginGame()
    if {str(restart).lower()} then
      campaign_casualties = maximum_casualties
      transition_outcome = 1
      frames = 81
      updateTransitionOut()
      assert(state == STATE_FAILED)
      beginGame()
    end
    transition_outcome = 2
    frames = 81
    updateTransitionOut()
    assert(state == STATE_FAILED)
  end
  failure_probe_update(frame)
end
""")
            refresh_manifest(game)
            image = game / "failure.ppm"
            run = subprocess.run(
                [str(ROOT / "zig-out/bin/elis"), "--screenshot", str(game), "1", str(image)],
                env={**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
                capture_output=True, text=True, timeout=30,
            )
            assert run.returncode == 0, run.stdout + run.stderr
            magic, dimensions, maximum, pixels = image.read_bytes().split(b"\n", 3)
            assert (magic, dimensions, maximum) == (b"P6", b"480 270", b"255")
            assert len(pixels) == 480 * 270 * 3
            dialogs.append(b"".join(
                pixels[(y * 480 + 82) * 3:(y * 480 + 397) * 3]
                for y in range(76, 190)
            ))
    assert dialogs[0] == dialogs[1], "Previous casualty loss changed the new overheating dialog"
    print("Mr. Rescue failure restart: pass (history-independent overheating dialog)")


if __name__ == "__main__":
    main()
