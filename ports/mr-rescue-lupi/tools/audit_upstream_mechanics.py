#!/usr/bin/env python3
"""Check source constants and their bounded Lupi representations."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REVISION = "a5be73c60acb8d1be506f7b5e48e784492ba96ce"

SOURCE_SNIPPETS = {
    "player.lua": (
        "local RUN_SPEED = 500", "local MAX_SPEED = 160",
        "local MAX_SPEED_CARRY = 100", "local BRAKE_SPEED = 250",
        "local GRAVITY = 350", "local JUMP_POWER = 135",
        "local CLIMB_SPEED = 60", "local STREAM_SPEED = 400",
        "local MAX_STREAM = 100", "local USE_RATE   = 2.5",
        "local BURN_DAMAGE = 0.5", "local TIME_DAMAGE = 0.008",
        "local FIRE_DIST = 1600",
    ),
    "human.lua": (
        "local MOVE_SPEED = 50", "local RUN_SPEED = 100",
        "local THROW_SPEED = 250", "local PUSH_SPEED  = 100",
        "local GRAVITY = 350", "local PANIC_RADIUS = 29",
        "local MAX_HEALTH = 5", "local SCORE = 250",
    ),
    "fire.lua": (
        "Fire = { max_health = 0.4 }", "local REGEN_RATE = 0.05",
        "local SCORE = 20",
    ),
    "door.lua": (
        "local GRAVITY = 550", "local SCORE = 50",
        "self.health = 0.3",
    ),
    "enemy.lua": (
        "MOVE_SPEED = 80", "MAX_HEALTH = 1.3", "SCORE = 100",
        "JUMP_POWER = 150", "SCORE = 125", "MOVE_SPEED = 60",
        "MAX_HEALTH = 1.6", "SCORE = 200", "MOVE_SPEED = 120",
        "MAX_HEALTH = 1.5", "SCORE = 350", "FIRE_ODDS = 25",
    ),
    "magmahulk.lua": ("MAX_HEALTH = 12", "JUMP_POWER = 200", "SCORE = 5000"),
    "gasleak.lua": ("MAX_HEALTH = 12", "GHOST_DELAY = 2.5", "SCORE = 5000"),
    "charcoal.lua": ("MAX_HEALTH = 10", "ROLL_SPEED = 100", "SCORE = 5000"),
    "ingame.lua": ("COMBO_TIME = 4", "max_casualties = 6-level", "score = score + 1000"),
}

PORT_SNIPPETS = {
    "player.lua": (
        "local acceleration = 500 /", "local maximum_speed = 160 /",
        "local carrying_speed = 100 /", "local braking = 250 /",
        "local gravity = 350 /", "local jump_speed = 135 /",
        "Player.spray_reach + 400 /", "math.min(100,",
        "Player.water - (2.5 + Player.regeneration_rate)",
        "time_damage = World.isBossBattle() and 0 or 0.008",
    ),
    "world.lua": (
        "human.direction * 50 /", "human.direction * 100 /",
        "player.direction * 250 /", "impact_direction * 100 /",
        "human.health_frames = 300", "pending_score = pending_score + 20",
        "door.health = 18", "550 / (Profile.update_hz * Profile.update_hz)",
        "local enemy_health = { 78, 78, 96, 108, 108, 114, 90 }",
        "local enemy_scores = { 100, 125, 200, 200, 200, 300, 350 }",
        "pending_score = pending_score + 5000",
    ),
    "boss.lua": (
        "self.health_max = kind == 3 and 600 or 720",
        "setState(self, DEAD, 300)",
    ),
    "campaign.lua": (
        "Campaign.combo_frames > 4 * Profile.update_hz",
        "Campaign.score = Campaign.score + 250",
        "Campaign.score = Campaign.score + 1000",
    ),
    "progression.lua": (
        "local boss_sections = { 8, 11, 15 }",
        "local campaign_floor_counts = { 21, 30, 42 }",
        "return 6 - difficulty",
    ),
}


def check_snippets(root: Path, checks: dict[str, tuple[str, ...]], label: str) -> int:
    count = 0
    for relative, snippets in checks.items():
        text = (root / relative).read_text(encoding="utf-8")
        for snippet in snippets:
            if snippet not in text:
                raise SystemExit(f"{label} mismatch: {relative} lacks {snippet!r}")
            count += 1
    return count


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: audit_upstream_mechanics.py UPSTREAM GAME")
    upstream = Path(sys.argv[1]).resolve()
    game = Path(sys.argv[2]).resolve()
    revision = subprocess.check_output(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != REVISION:
        raise SystemExit(f"expected upstream {REVISION}, found {revision}")
    count = check_snippets(upstream, SOURCE_SNIPPETS, "upstream")
    count += check_snippets(game, PORT_SNIPPETS, "port")
    print(f"Mr. Rescue upstream mechanics audit: pass ({count} invariants)")


if __name__ == "__main__":
    main()
