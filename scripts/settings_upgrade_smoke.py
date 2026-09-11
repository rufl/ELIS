#!/usr/bin/env python3
"""Exercise preference upgrades through ELIS in a disposable user profile."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    binary = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
        ROOT / "zig-out/bin" / ("elis.exe" if os.name == "nt" else "elis")
    )
    with tempfile.TemporaryDirectory(prefix="elis-settings-upgrade-") as temporary:
        home = Path(temporary)
        environment = dict(os.environ, XDG_DATA_HOME=str(home), APPDATA=str(home),
                           LOCALAPPDATA=str(home), SDL_VIDEODRIVER="dummy",
                           SDL_AUDIODRIVER="dummy")
        profile = home / "lupi-org-br/lupinho-zig/settings-v1.ini"

        def round_trip():
            result = subprocess.run(
                [str(binary), "--self-test-settings"], env=environment,
                cwd=home, capture_output=True, text=True, timeout=20,
            )
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
            return dict(line.split("=", 1) for line in profile.read_text().splitlines())

        def check(name, fixture, expected_keyboard):
            profile.write_text("".join(f"{key}={value}\n" for key, value in fixture.items()))
            saved = round_trip()
            assert saved["keyboard"] == expected_keyboard, f"{name}: keyboard bindings changed unexpectedly"
            assert saved["gamepad"] == fixture["gamepad"], f"{name}: controller bindings changed"
            assert saved["language"] == fixture["language"], f"{name}: language changed"
            print(f"{name}: pass")
            return saved

        current = round_trip()
        legacy = dict(current)
        legacy.pop("keyboard_defaults", None)
        legacy["language"] = "es"
        keyboard = current["keyboard"].split(",")
        # The persisted schema orders actions as up/down/left/right, primary,
        # secondary, face_x, ...; each keyboard action has three slots.
        face_x_second = 6 * 3 + 1
        assert keyboard[face_x_second] == "8", "runtime does not provide the E default"
        keyboard[face_x_second] = "-1"
        legacy["keyboard"] = ",".join(keyboard)
        controller = legacy["gamepad"].split(",")
        controller[4] = "5"  # Bind primary to SDL's previously unused Guide button.
        legacy["gamepad"] = ",".join(controller)
        upgraded = check("Legacy keyboard with custom controller", legacy, current["keyboard"])

        customized = dict(legacy)
        custom_keyboard = keyboard.copy()
        custom_keyboard[8 * 3] = "8"  # User deliberately assigns E to shoulder_l.
        customized["keyboard"] = ",".join(custom_keyboard)
        check("Legacy custom E assignment", customized, customized["keyboard"])

        explicitly_unbound = dict(upgraded)
        explicitly_unbound["keyboard"] = legacy["keyboard"]
        saved = check("E explicitly removed after upgrade", explicitly_unbound, legacy["keyboard"])
        check("Explicit removal survives another load", saved, legacy["keyboard"])


if __name__ == "__main__":
    main()
