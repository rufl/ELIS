#!/usr/bin/env python3
"""Exercise extracted release binaries without a checkout or developer display."""
import argparse
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import zipfile


def run(command, cwd, env):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{command}: {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    archive = args.archive.resolve()
    with tempfile.TemporaryDirectory(prefix="elis-package-smoke-") as temporary:
        root = Path(temporary)
        if archive.suffix == ".zip":
            with zipfile.ZipFile(archive) as source:
                source.extractall(root)
        else:
            with tarfile.open(archive) as source:
                source.extractall(root, filter="data")
        package, = root.iterdir()
        suffix = ".exe" if os.name == "nt" else ""
        runtime = package / ("elis" + suffix)
        studio = package / ("elis-studio" + suffix)
        env = os.environ.copy()
        env.update(SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "LD_LIBRARY_PATH"):
            env.pop(key, None)
        if os.name == "nt":
            env["PATH"] = str(package) + os.pathsep + str(Path(env["SystemRoot"]) / "System32")
        env["XDG_DATA_HOME"] = str(root / "profile")
        assert "Usage:" in run([str(runtime), "--help"], package, env)
        assert "lua=5.4" in run([str(runtime), "--lupi-constraints"], package, env)
        frame = root / "example.ppm"
        run([str(runtime), "--screenshot", str(package / "example"), "2", str(frame)], package, env)
        assert frame.read_bytes().startswith(b"P6\n480 270\n255\n")
        game = root / "workspace"
        game.mkdir()
        (game / "world").write_bytes(bytes([1]) * 4096)
        (game / "palette.lua").write_text("Palette = {[1]=0, [2]=0x7C00}\n")
        (game / "lupi_manifest.txt").write_text('1 4096 world {"type":"bitmap","width":16,"height":16,"tiles":16}\n')
        project = root / "smoke.elisworld"
        exported = root / "map.lua"
        capture = root / "studio.bmp"
        run([str(studio), f"--game-root={game}", f"--project={project}", f"--export={exported}",
             "--template=platformer", "--save-export", "--smoke", f"--capture={capture}"], package, env)
        assert project.is_file() and exported.is_file()
        assert capture.read_bytes().startswith(b"BM")
        original = project.read_bytes()
        run([str(studio), f"--game-root={game}", f"--project={project}", "--smoke"], package, env)
        assert project.read_bytes() == original
        (game / "map.lua").write_bytes(exported.read_bytes())
        (game / "game.lua").write_text('local project = require("map")\nfunction update() ui.cls(0) ui.map(project.map) end\n')
        with (game / "lupi_manifest.txt").open("a") as manifest:
            for index, name in enumerate(("game.lua", "map.lua", "palette.lua"), 2):
                manifest.write(f"{index} {(game / name).stat().st_size} {name} {{}}\n")
        exported_frame = root / "exported.ppm"
        run([str(runtime), "--screenshot", str(game), "1", str(exported_frame)], package, env)
        assert exported_frame.read_bytes().startswith(b"P6\n480 270\n255\n")
        print("Extracted runtime screenshot, Workshop save/export/reload, and exported map rendering: pass")


if __name__ == "__main__":
    main()
