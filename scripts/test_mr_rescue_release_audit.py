#!/usr/bin/env python3
"""Focused regressions for the Mr. Rescue finite-content audit."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "demos/mr-rescue/tools"
sys.path.insert(0, str(TOOLS))

import audit_release  # noqa: E402


class MrRescueInventoryAuditTests(unittest.TestCase):
    def setUp(self):
        self.game = ROOT / "demos/mr-rescue/current"
        entries = {}
        for line in (self.game / "lupi_manifest.txt").read_text(encoding="utf-8").splitlines():
            fields = line.split(" ", 3)
            entries[fields[2]] = int(fields[1])
        self.entries = entries
        self.lua_source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted(self.game.glob("*.lua"))
        )

    def test_complete_inventory_reports_expected_categories(self):
        inventory = audit_release.audit_inventory(
            self.game, self.entries, self.lua_source
        )
        self.assertEqual(
            inventory,
            {
                "music_tracks": 8,
                "effects": 17,
                "tutorial_slides": 9,
                "civilian_appearances": 4,
                "enemy_variants": 7,
                "boss_families": 3,
                "upgrades": 5,
                "award_categories": 6,
                "room_widths": 4,
            },
        )

    def test_missing_boss_asset_is_rejected(self):
        entries = dict(self.entries)
        del entries["assets/magmahulk_portrait_0"]
        with self.assertRaisesRegex(SystemExit, "content inventory missing"):
            audit_release.audit_inventory(self.game, entries, self.lua_source)


if __name__ == "__main__":
    unittest.main()
