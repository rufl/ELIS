#!/usr/bin/env python3
"""Exercise extracted release binaries without a checkout or developer display."""
import ctypes
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def run(command, cwd, env):
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError(f"{command}: {result.returncode}\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def windows_https(package):
    # Exercise TLS from the shipped DLL against the native certificate store.
    # No MSYS2 CA files, disabled verification, or development DLL paths.
    with os.add_dll_directory(str(package)):
        curl = ctypes.CDLL(str(package / "libcurl-4.dll"))
        curl.curl_global_init.argtypes = [ctypes.c_long]
        curl.curl_easy_init.restype = ctypes.c_void_p
        curl.curl_easy_setopt.argtypes = [ctypes.c_void_p, ctypes.c_int]
        curl.curl_easy_perform.argtypes = [ctypes.c_void_p]
        curl.curl_easy_cleanup.argtypes = [ctypes.c_void_p]
        curl.curl_easy_getinfo.argtypes = [ctypes.c_void_p, ctypes.c_int]
        check(curl.curl_global_init(3) == 0, "Packaged libcurl initialization failed")
        try:
            handle = curl.curl_easy_init()
            check(handle, "Packaged libcurl could not create an HTTPS handle")
            try:
                for option, value in ((10002, ctypes.c_char_p(b"https://api.github.com/")),
                                      (10018, ctypes.c_char_p(b"ELIS-release-smoke")),
                                      (44, ctypes.c_long(1)), (13, ctypes.c_long(30))):
                    check(curl.curl_easy_setopt(handle, option, value) == 0,
                          f"Packaged libcurl rejected option {option}")
                check(curl.curl_easy_perform(handle) == 0,
                      "Packaged HTTPS certificate validation failed")
                status = ctypes.c_long()
                check(curl.curl_easy_getinfo(handle, 0x200002, ctypes.byref(status)) == 0,
                      "Packaged libcurl could not read the HTTPS status")
                check(status.value == 200, f"Unexpected HTTPS status: {status.value}")
            finally:
                curl.curl_easy_cleanup(handle)
        finally:
            curl.curl_global_cleanup()


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
            env["PATH"] = str(package) + os.pathsep + str(Path(os.environ["SystemRoot"]) / "System32")
            # ctypes keeps DLLs loaded; a child process releases the entire DLL
            # dependency tree before TemporaryDirectory removes the package.
            run([sys.executable, str(Path(__file__).resolve()), "--windows-https", str(package)],
                package, env)
        env["XDG_DATA_HOME"] = str(root / "profile")
        check("Usage:" in run([str(runtime), "--help"], package, env),
              "Packaged runtime did not print usage")
        check("lua=5.4" in run([str(runtime), "--lupi-constraints"], package, env),
              "Packaged runtime did not report Lua 5.4")
        frame = root / "example.ppm"
        run([str(runtime), "--screenshot", str(package / "example"), "2", str(frame)], package, env)
        check(frame.read_bytes().startswith(b"P6\n480 270\n255\n"),
              "Packaged runtime produced an invalid screenshot")
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
        check(project.is_file() and exported.is_file(), "Workshop did not save and export")
        check(capture.read_bytes().startswith(b"BM"), "Workshop produced an invalid capture")
        original = project.read_bytes()
        run([str(studio), f"--game-root={game}", f"--project={project}", "--smoke"], package, env)
        check(project.read_bytes() == original, "Workshop changed the saved project on reload")
        (game / "map.lua").write_bytes(exported.read_bytes())
        (game / "game.lua").write_text(
            'assert(_VERSION == "Lua 5.4", "Packaged runtime must execute Lua 5.4")\n'
            'local project = require("map")\n'
            'function update() ui.cls(0) ui.map(project.map) end\n'
        )
        with (game / "lupi_manifest.txt").open("a") as manifest:
            for index, name in enumerate(("game.lua", "map.lua", "palette.lua"), 2):
                manifest.write(f"{index} {(game / name).stat().st_size} {name} {{}}\n")
        exported_frame = root / "exported.ppm"
        run([str(runtime), "--screenshot", str(game), "1", str(exported_frame)], package, env)
        check(exported_frame.read_bytes().startswith(b"P6\n480 270\n255\n"),
              "Exported map produced an invalid screenshot")
        print("Extracted runtime screenshot, Workshop save/export/reload, and exported map rendering: pass")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--windows-https":
        windows_https(Path(sys.argv[2]))
    else:
        main()
