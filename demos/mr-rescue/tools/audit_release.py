#!/usr/bin/env python3
"""Fail-closed cartridge manifest, use, and attribution audit."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "current"
EXPECTED_REVISION = "a5be73c60acb8d1be506f7b5e48e784492ba96ce"
DYNAMIC_ASSET = re.compile(
    r"^(human_[1-4]_|award_[1-6]_|howto_[0-8]_(?:left|right)$|"
    r"(?:shockwave|circle)_[0-9]$|"
    r"(?:magmahulk|gasleak|charcoal)_portrait_[0-3]$)"
)
EXPECTED_MUSIC = frozenset(
    {
        "bundesliga.ogg",
        "happyfeerings.ogg",
        "menujazz.ogg",
        "opening.ogg",
        "rockerronni.ogg",
        "roof.ogg",
        "scooterfest.ogg",
        "victory.ogg",
    }
)
EXPECTED_EFFECTS = frozenset(
    {
        "blip",
        "boss_jump",
        "casualty",
        "confirm",
        "door",
        "empty",
        "enemy",
        "explosion",
        "glass",
        "impact",
        "item",
        "jump",
        "rescue",
        "spray",
        "steam",
        "throw",
        "transform",
    }
)
HUMAN_STATES = ("run", "carry_left", "carry_right", "fly", "burn", "panic")
ENEMY_STATES = {
    "normal": ("run", "hit", "recover"),
    "angrynormal": ("run", "hit", "recover"),
    "jumper": ("jump", "hit"),
    "angryjumper": ("jump", "hit"),
    "volcano": ("run", "shoot", "hit"),
    "angryvolcano": ("run", "shoot", "hit"),
    "thief": ("run", "hit", "recover"),
}
BOSS_STATES = {
    "magmahulk": ("jump", "land", "jump_hit", "land_hit", "rage_jump", "rage_land"),
    "gasleak": (
        "idle",
        "hit",
        "walk",
        "shot_walk",
        "rage_walk",
        "rage_shot_walk",
        "idle_shot",
        "rage_idle_shot",
        "rage_idle",
        "transition",
        "transition_1",
    ),
    "charcoal": (
        "idle",
        "transform",
        "transform_rage",
        "transition",
        "roll",
        "roll_rage",
        "daze",
        "daze_hit",
        "daze_rage",
        "projectile",
    ),
}


def _require_paths(entries: dict[str, int], expected: set[str], label: str) -> None:
    missing = sorted(expected - entries.keys())
    if missing:
        fail(f"{label} inventory missing: {', '.join(missing)}")


def fail(message: str) -> None:
    raise SystemExit(message)
def audit_inventory(
    game: Path, entries: dict[str, int], lua_source: str
) -> dict[str, int]:
    music = {
        path.removeprefix("music/")
        for path in entries
        if path.startswith("music/")
    }
    if music != EXPECTED_MUSIC:
        fail(
            "music inventory mismatch: "
            f"missing={sorted(EXPECTED_MUSIC - music)} "
            f"unexpected={sorted(music - EXPECTED_MUSIC)}"
        )

    required_assets = {
        f"assets/human_{human}_{state}"
        for human in range(1, 5)
        for state in HUMAN_STATES
    }
    required_assets.update(
        f"assets/enemy_{kind}_{state}"
        for kind, states in ENEMY_STATES.items()
        for state in states
    )
    required_assets.update(
        f"assets/{boss}_{state}"
        for boss, states in BOSS_STATES.items()
        for state in states
    )
    required_assets.update(
        f"assets/{boss}_portrait_{frame}"
        for boss in BOSS_STATES
        for frame in range(4)
    )
    required_assets.update(
        f"assets/howto_{slide}_{side}"
        for slide in range(9)
        for side in ("left", "right")
    )
    required_assets.update(
        f"assets/award_{statistic}_{award}"
        for statistic in range(1, 7)
        for award in ("none", "bronze", "silver", "gold")
    )
    required_assets.update(
        f"assets/item_{item}"
        for item in ("coolant", "suit", "tank", "reserve", "regen")
    )
    _require_paths(entries, required_assets, "Mr. Rescue content")

    effects = set(
        re.findall(
            r"^\s+([a-z_]+) = \{",
            (game / "audio.lua").read_text(encoding="utf-8"),
            re.MULTILINE,
        )
    )
    if effects != EXPECTED_EFFECTS:
        fail(
            "effect inventory mismatch: "
            f"missing={sorted(EXPECTED_EFFECTS - effects)} "
            f"unexpected={sorted(effects - EXPECTED_EFFECTS)}"
        )

    source_checks = {
        "game.lua": ("for slide = 0, 8 do", "for statistic = 1, 6 do"),
        "progression.lua": (
            "local boss_sections = { 8, 11, 15 }",
            "local campaign_floor_counts = { 21, 30, 42 }",
        ),
    }
    for relative, snippets in source_checks.items():
        source = (game / relative).read_text(encoding="utf-8")
        for snippet in snippets:
            if snippet not in source:
                fail(f"content inventory invariant missing: {relative} lacks {snippet!r}")

    world_source = (game / "world.lua").read_text(encoding="utf-8")
    missing_enemy_tables = [
        str(kind) for kind in range(1, 8) if f"  [{kind}] = {{" not in world_source
    ]
    if missing_enemy_tables:
        fail(f"enemy inventory missing runtime kinds: {', '.join(missing_enemy_tables)}")

    templates_source = (game / "map_templates.lua").read_text(encoding="utf-8")
    room_widths = ("10", "11", "17", "24")
    missing_room_widths = [
        width for width in room_widths if f'[\"{width}\"] = {{' not in templates_source
    ]
    if missing_room_widths:
        fail(f"room inventory missing widths: {', '.join(missing_room_widths)}")

    return {
        "music_tracks": len(music),
        "effects": len(effects),
        "tutorial_slides": 9,
        "civilian_appearances": 4,
        "enemy_variants": 7,
        "boss_families": len(BOSS_STATES),
        "upgrades": 5,
        "award_categories": 6,
        "room_widths": len(room_widths),
    }


def main() -> None:
    for required in ("LICENSE.upstream", "CC-BY-SA-3.0.txt", "SOURCE.md"):
        if not (ROOT / required).is_file():
            fail(f"missing attribution file: {required}")
    if EXPECTED_REVISION not in (ROOT / "SOURCE.md").read_text(encoding="utf-8"):
        fail("SOURCE.md does not pin the audited revision")

    entries: dict[str, int] = {}
    for line in (GAME / "lupi_manifest.txt").read_text(encoding="utf-8").splitlines():
        fields = line.split(" ", 3)
        if len(fields) != 4:
            fail(f"malformed manifest line: {line}")
        size = int(fields[1])
        relative = fields[2]
        if relative in entries:
            fail(f"duplicate manifest path: {relative}")
        entries[relative] = size

    payload = {
        path.relative_to(GAME).as_posix(): path.stat().st_size
        for path in GAME.rglob("*")
        if path.is_file() and path.name != "lupi_manifest.txt"
    }
    if entries != payload:
        missing = sorted(set(payload) - set(entries))
        stale = sorted(set(entries) - set(payload))
        wrong = sorted(path for path in entries.keys() & payload.keys()
                       if entries[path] != payload[path])
        fail(f"manifest mismatch: missing={missing}, stale={stale}, wrong={wrong}")

    lua_source = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(GAME.glob("*.lua"))
    )
    inventory = audit_inventory(GAME, entries, lua_source)
    for relative in sorted(entries):
        if relative.startswith("assets/"):
            name = relative.removeprefix("assets/")
            if f'assets/{name}' not in lua_source and not DYNAMIC_ASSET.match(name):
                fail(f"release bitmap has no runtime reference: {relative}")
        elif relative.startswith("music/"):
            if relative not in lua_source:
                fail(f"release music has no runtime reference: {relative}")
        elif not relative.endswith(".lua"):
            fail(f"unexpected release payload: {relative}")

    print(
        "Mr. Rescue release audit: pass "
        f"({sum(entries.values())} payload bytes; "
        f"{inventory['music_tracks']} music, {inventory['effects']} effects, "
        f"{inventory['enemy_variants']} enemy variants, "
        f"{inventory['boss_families']} bosses)"
    )


if __name__ == "__main__":
    main()
