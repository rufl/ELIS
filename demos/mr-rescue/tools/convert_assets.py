#!/usr/bin/env python3
"""Convert pinned Mr. Rescue art into deterministic Lupi indexed bitmaps."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

UPSTREAM_REVISION = "a5be73c60acb8d1be506f7b5e48e784492ba96ce"
FRAME_SPECS = [
    ("player_running", 16, 22, 4, 16),
    ("player_gun", 12, 18, 5, 12),
    ("player_throw", 16, 32, 4, 16),
    ("player_climb_down", 14, 23, 4, 14),
    ("fire_wall", 24, 32, 5, 24),
    ("fire_wall_small", 24, 32, 5, 24),
    ("fire_floor", 16, 16, 4, 16),
    ("ashes", 20, 20, 8, 20),
    ("item_coolant", 16, 20, 6, 16),
    ("item_suit", 16, 20, 6, 16),
    ("item_tank", 16, 20, 6, 16),
    ("item_reserve", 16, 20, 6, 16),
    ("item_regen", 16, 20, 6, 16),
    ("enemy_normal_run", 16, 26, 4, 16),
    ("enemy_normal_hit", 16, 26, 2, 16),
    ("enemy_normal_recover", 16, 26, 4, 16),
    ("enemy_angrynormal_run", 16, 26, 4, 16),
    ("enemy_angrynormal_hit", 16, 26, 2, 16),
    ("enemy_angrynormal_recover", 16, 26, 4, 16),
    ("enemy_jumper_jump", 16, 32, 3, 16),
    ("enemy_jumper_hit", 16, 32, 3, 16),
    ("enemy_angryjumper_jump", 16, 32, 3, 16),
    ("enemy_angryjumper_hit", 16, 32, 3, 16),
    ("enemy_volcano_run", 16, 32, 4, 16),
    ("enemy_volcano_shoot", 16, 32, 4, 16),
    ("enemy_volcano_hit", 16, 32, 4, 16),
    ("enemy_angryvolcano_run", 16, 32, 4, 16),
    ("enemy_angryvolcano_shoot", 16, 32, 4, 16),
    ("enemy_angryvolcano_hit", 16, 32, 4, 16),
    ("enemy_thief_run", 18, 32, 4, 18),
    ("enemy_thief_hit", 18, 32, 2, 18),
    ("enemy_thief_recover", 18, 32, 4, 18),
    ("enemy_fireball", 8, 8, 4, 8),
    ("magmahulk_jump", 58, 64, 5, 58),
    ("magmahulk_land", 58, 64, 7, 58),
    ("magmahulk_jump_hit", 58, 64, 5, 58),
    ("magmahulk_land_hit", 58, 64, 7, 58),
    ("magmahulk_rage_jump", 58, 64, 5, 58),
    ("magmahulk_rage_land", 58, 64, 7, 58),
    ("gasleak_idle", 40, 128, 1, 40),
    ("gasleak_hit", 40, 64, 2, 40),
    ("gasleak_walk", 40, 128, 8, 40),
    ("gasleak_shot_walk", 40, 128, 8, 40),
    ("gasleak_rage_walk", 40, 128, 8, 40),
    ("gasleak_rage_shot_walk", 40, 128, 8, 40),
    ("gasleak_idle_shot", 40, 128, 1, 40),
    ("gasleak_rage_idle_shot", 40, 128, 1, 40),
    ("gasleak_rage_idle", 40, 128, 1, 40),
    ("gasleak_transition", 40, 128, 9, 40),
    ("gasghost", 24, 32, 3, 24),
    ("gasghost_hit", 24, 32, 3, 24),
    ("charcoal_idle", 64, 64, 1, 64),
    ("charcoal_transform", 40, 64, 19, 40),
    ("charcoal_transform_rage", 40, 64, 19, 40),
    ("charcoal_transition", 40, 64, 2, 40),
    ("charcoal_roll", 32, 32, 19, 32),
    ("charcoal_roll_rage", 32, 32, 19, 32),
    ("charcoal_daze", 40, 64, 4, 40),
    ("charcoal_daze_hit", 40, 64, 4, 40),
    ("charcoal_daze_rage", 40, 64, 4, 40),
    ("charcoal_projectile", 15, 15, 12, 15),
    ("black_smoke", 20, 20, 6, 20),
    ("black_smoke_small", 8, 8, 4, 8),
    ("sparkles", 7, 7, 3, 8),
]
for human_id in range(1, 5):
    FRAME_SPECS.extend([
        (f"human_{human_id}_run", 20, 32, 4, 20),
        (f"human_{human_id}_carry_left", 22, 32, 4, 22),
        (f"human_{human_id}_carry_right", 22, 32, 4, 22),
        (f"human_{human_id}_fly", 20, 32, 4, 20),
        (f"human_{human_id}_burn", 20, 32, 4, 20),
        (f"human_{human_id}_panic", 20, 32, 6, 20),
    ])

CROP_SPECS = [
    ("player_death_up", "player_death", 0, 0, 16, 24),
    ("player_death_down", "player_death", 16, 0, 16, 24),
    ("player_death_suit", "player_death", 32, 0, 16, 10),
    ("gasleak_transition_1", "gasleak_transition", 360, 0, 40, 128),
    ("splash_left", "splash", 0, 0, 128, 200),
    ("splash_right", "splash", 128, 0, 128, 200),
    ("tangram_left", "tangram", 0, 0, 128, 200),
    ("tangram_right", "tangram", 128, 0, 128, 200),
    ("love_left", "lovesplashpixel", 0, 0, 128, 200),
    ("love_right", "lovesplashpixel", 128, 0, 128, 200),
    ("level_buildings", "level_buildings", 0, 0, 134, 159),
    ("building_outline_1", "level_buildings", 144, 0, 37, 40),
    ("building_outline_2", "level_buildings", 192, 0, 43, 75),
    ("building_outline_3", "level_buildings", 144, 80, 64, 83),
    ("door_normal", "door", 0, 0, 8, 48),
    ("door_damaged", "door", 16, 0, 8, 48),
    ("night_0", "backgrounds/night", 0, 0, 128, 256),
    ("night_1", "backgrounds/night", 128, 0, 128, 256),
    ("night_2", "backgrounds/night", 256, 0, 128, 256),
    ("night_3", "backgrounds/night", 384, 0, 128, 256),
    ("exclamation", "exclamation", 0, 0, 4, 16),
    ("water_out_0", "water", 0, 0, 8, 15),
    ("water_out_1", "water", 16, 0, 8, 15),
    ("water_end_0", "water", 32, 0, 16, 15),
    ("water_end_1", "water", 48, 0, 16, 15),
    ("water_hit_0", "water", 0, 16, 16, 19),
    ("water_hit_1", "water", 16, 16, 16, 19),
    ("water_hit_2", "water", 32, 16, 16, 19),
    ("boss_health", "boss_health", 0, 0, 256, 38),
    ("hud", "hud", 0, 0, 256, 32),
    ("hud_front", "hud2", 0, 0, 256, 32),
    ("hud_person_lost", "hud_people", 0, 0, 4, 8),
    ("hud_person_safe", "hud_people", 4, 0, 4, 8),
    ("item_slot_regen", "item_slots", 0, 0, 3, 6),
    ("item_slot_tank", "item_slots", 3, 0, 3, 6),
    ("item_slot_suit", "item_slots", 6, 0, 3, 6),
    ("red_hit", "red_screen", 0, 0, 256, 169),
    ("temperature_blink", "temperature_bar_blink", 0, 0, 128, 8),
    ("enemy_health_base", "enemy_healthbar", 0, 0, 20, 8),
    ("captain_0", "captain_dialog", 0, 0, 200, 56),
    ("captain_1", "captain_dialog", 0, 64, 200, 56),
    ("captain_sad_0", "captain_dialog_sad", 0, 0, 200, 56),
    ("captain_sad_1", "captain_dialog_sad", 0, 64, 200, 56),
    ("highscore_pane_1", "highscore_panes", 0, 0, 256, 12),
    ("highscore_pane_2", "highscore_panes", 0, 12, 256, 12),
    ("highscore_pane_3", "highscore_panes", 0, 24, 256, 12),
    ("stats_screen_left", "stats_screen", 0, 0, 128, 200),
    ("stats_screen_right", "stats_screen", 128, 0, 128, 200),
    ("stats_pane_1", "stats_screen", 0, 200, 36, 11),
    ("stats_pane_2", "stats_screen", 36, 200, 36, 11),
    ("stats_pane_3", "stats_screen", 72, 200, 36, 11),
    ("warning_0", "warning_icons", 0, 0, 22, 20),
    ("warning_1", "warning_icons", 22, 0, 22, 20),
    ("warning_2", "warning_icons", 44, 0, 22, 20),
    ("warning_3", "warning_icons", 66, 0, 22, 20),
    ("warning_4", "warning_icons", 88, 0, 22, 20),
    ("popup_rescue", "popup_text", 0, 0, 64, 8),
    ("popup_coolant", "popup_text", 0, 8, 64, 8),
    ("popup_suit", "popup_text", 0, 16, 64, 8),
    ("popup_tank", "popup_text", 0, 24, 64, 8),
    ("popup_reserve", "popup_text", 0, 32, 64, 8),
    ("popup_regen", "popup_text", 0, 40, 64, 8),
    ("popup_theft", "popup_text", 0, 48, 64, 8),
    ("popup_combo_3", "popup_text", 0, 56, 64, 8),
    ("popup_combo_4", "popup_text", 0, 64, 64, 8),
    ("popup_combo_5", "popup_text", 0, 72, 64, 8),
    ("popup_mega", "popup_text", 0, 80, 64, 16),
    ("countdown_0", "countdown", 0, 0, 64, 26),
    ("countdown_1", "countdown", 0, 26, 64, 26),
    ("countdown_2", "countdown", 0, 52, 64, 26),
    ("countdown_3", "countdown", 0, 78, 64, 26),
]
for slide in range(9):
    CROP_SPECS.extend([
        (f"howto_{slide}_left", "howto", 0, slide * 200, 128, 200),
        (f"howto_{slide}_right", "howto", 128, slide * 200, 128, 200),
    ])
for frame in range(7):
    CROP_SPECS.append(
        (f"circle_{frame}", "circles", frame * 32, 0, 32, 32)
    )
for frame in range(10):
    CROP_SPECS.append(
        (f"shockwave_{frame}", "shockwave", 0, frame * 32, 73, 32)
    )
for boss in ("magmahulk", "gasleak", "charcoal"):
    for frame in range(4):
        CROP_SPECS.append(
            (f"{boss}_portrait_{frame}", f"{boss}_portrait", frame * 48, 0, 46, 30)
        )
for statistic in range(6):
    for award, row in (("none", 0), ("bronze", 25), ("silver", 50), ("gold", 75)):
        CROP_SPECS.append(
            (f"award_{statistic + 1}_{award}", "awards", statistic * 24, row, 24, 25)
        )


def rgb555(red: int, green: int, blue: int) -> int:
    return ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3)


def source_palette(data_root: Path) -> list[int]:
    colors: set[int] = set()
    for path in sorted(data_root.rglob("*.png")):
        image = Image.open(path).convert("RGBA")
        for red, green, blue, alpha in image.get_flattened_data():
            if alpha >= 128:
                colors.add(rgb555(red, green, blue))
    palette = [0]
    palette.extend(color for color in sorted(colors) if color != 0)
    if len(palette) > 256:
        raise SystemExit(f"RGB555 palette needs {len(palette)} entries")
    return palette


def encode_frame(image: Image.Image, x: int, y: int, width: int, height: int,
                 color_indexes: dict[int, int]) -> bytes:
    output = bytearray()
    pixels = image.load()
    for pixel_y in range(y, y + height):
        for pixel_x in range(x, x + width):
            if pixel_x >= image.width or pixel_y >= image.height:
                output.append(0)
                continue
            red, green, blue, alpha = pixels[pixel_x, pixel_y]
            output.append(0 if alpha < 128 else color_indexes[rgb555(red, green, blue)])
    return bytes(output)


def write_asset(output_root: Path, name: str, frames: list[bytes], width: int,
                height: int, manifest: list[str]) -> None:
    payload = b"".join(frames)
    relative = f"assets/{name}"
    (output_root / relative).write_bytes(payload)
    manifest.append(
        f'{len(manifest) + 1} {len(payload)} {relative} '
        f'{{"type":"bitmap","width":{width},"height":{height},'
        f'"tiles":{len(frames)}}}'
    )


def write_map(upstream: Path, output_root: Path, source_name: str,
              output_name: str) -> None:
    source = (upstream / f"maps/{source_name}.lua").read_text(encoding="utf-8")
    match = re.search(r"data = \{(.*?)\}\s*\}\s*\}\s*$", source, re.DOTALL)
    if match is None:
        raise SystemExit("could not parse pinned maps/base.lua")
    values = [int(value) for value in re.findall(r"\d+", match.group(1))]
    if len(values) != 41 * 16:
        raise SystemExit(f"base map has {len(values)} cells instead of 656")
    lines = ["-- Adapted from the CC-BY-SA-3.0 Mr. Rescue map data.", "return {"]
    for row in range(16):
        cells = ",".join(str(value) for value in values[row * 41:(row + 1) * 41])
        lines.append(f"  {cells},")
    lines.append("}")
    (output_root / output_name).write_text("\n".join(lines) + "\n", encoding="utf-8")


def convert(upstream: Path, output_root: Path) -> None:
    data_root = upstream / "data"
    if not (upstream / ".git").exists():
        raise SystemExit("upstream must be the pinned Git checkout")
    revision = subprocess.check_output(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True
    ).strip()
    if revision != UPSTREAM_REVISION:
        raise SystemExit(f"expected upstream {UPSTREAM_REVISION}, found {revision}")

    shutil.rmtree(output_root / "assets", ignore_errors=True)
    shutil.rmtree(output_root / "music", ignore_errors=True)
    (output_root / "assets").mkdir(parents=True, exist_ok=True)
    palette = source_palette(data_root)
    color_indexes = {color: index for index, color in enumerate(palette)}
    palette_lines = ["Palette = {"]
    palette_lines.extend(f"  [{index + 1}] = 0x{color:04X}," for index, color in enumerate(palette))
    palette_lines.append("}")
    (output_root / "palette.lua").write_text("\n".join(palette_lines) + "\n", encoding="utf-8")

    manifest: list[str] = []
    tiles = Image.open(data_root / "tiles.png").convert("RGBA")
    tile_frames = [
        encode_frame(tiles, (index % 16) * 16, (index // 16) * 16, 16, 16, color_indexes)
        for index in range(256)
    ]
    write_asset(output_root, "tiles_0", tile_frames[:128], 16, 16, manifest)
    write_asset(output_root, "tiles_1", tile_frames[128:], 16, 16, manifest)

    dark_color = rgb555(30, 23, 18)
    dark_index = color_indexes[dark_color]
    darkness = bytes(
        dark_index if (x + y) % 2 == 0 else 0
        for y in range(32) for x in range(32)
    )
    write_asset(output_root, "dark_dither", [darkness], 32, 32, manifest)

    for name, width, height, count, stride in FRAME_SPECS:
        image = Image.open(data_root / f"{name}.png").convert("RGBA")
        frames = [
            encode_frame(image, index * stride, 0, width, height, color_indexes)
            for index in range(count)
        ]
        write_asset(output_root, name, frames, width, height, manifest)

    for name, source, x, y, width, height in CROP_SPECS:
        image = Image.open(data_root / f"{source}.png").convert("RGBA")
        frame = encode_frame(image, x, y, width, height, color_indexes)
        write_asset(output_root, name, [frame], width, height, manifest)

    for name, source in (
        ("water_bar", "water_bar"),
        ("reserve_bar", "reserve_bar"),
        ("overloaded_bar", "overloaded_bar"),
    ):
        image = Image.open(data_root / f"{source}.png").convert("RGBA")
        frames = []
        for length in range(56):
            frame = Image.new("RGBA", (55, 11))
            if length > 0:
                frame.paste(image.crop((0, 0, length, 11)), (0, 0))
            frames.append(encode_frame(frame, 0, 0, 55, 11, color_indexes))
        write_asset(output_root, name, frames, 55, 11, manifest)

    temperature = Image.open(data_root / "temperature_bar.png").convert("RGBA")
    temperature_frames = []
    temperature_end = temperature.crop((82, 0, 84, 6))
    for length in range(83):
        frame = Image.new("RGBA", (84, 6))
        if length > 0:
            frame.paste(temperature.crop((0, 0, length, 6)), (0, 0))
        frame.paste(temperature_end, (length, 0))
        temperature_frames.append(
            encode_frame(frame, 0, 0, 84, 6, color_indexes)
        )
    write_asset(
        output_root, "temperature_bar", temperature_frames, 84, 6, manifest
    )

    shards_image = Image.open(data_root / "shards.png").convert("RGBA")
    shard_frames = []
    for shard in range(8):
        source = shards_image.crop((shard * 8, 0, shard * 8 + 8, 8))
        for angle in range(8):
            rotated = source.rotate(
                -angle * 45, resample=Image.Resampling.NEAREST
            )
            shard_frames.append(
                encode_frame(rotated, 0, 0, 8, 8, color_indexes)
            )
    write_asset(output_root, "shards_spin", shard_frames, 8, 8, manifest)

    door_image = Image.open(data_root / "door.png").convert("RGBA")
    for name, source_x in (("door_normal_spin", 0), ("door_damaged_spin", 16)):
        base = Image.new("RGBA", (48, 48))
        base.paste(door_image.crop((source_x, 0, source_x + 8, 48)), (24, 0))
        frames = [
            encode_frame(
                base.rotate(-frame * 45, resample=Image.Resampling.NEAREST),
                0,
                0,
                48,
                48,
                color_indexes,
            )
            for frame in range(8)
        ]
        write_asset(output_root, name, frames, 48, 48, manifest)

    enemy_health = Image.open(data_root / "enemy_healthbar.png").convert("RGBA")
    enemy_bar_pixel = enemy_health.crop((21, 2, 22, 6))
    enemy_bar_frames = []
    for length in range(17):
        frame = Image.new("RGBA", (16, 4))
        for x in range(length):
            frame.paste(enemy_bar_pixel, (x, 0))
        enemy_bar_frames.append(encode_frame(frame, 0, 0, 16, 4, color_indexes))
    write_asset(output_root, "enemy_health_bar", enemy_bar_frames, 16, 4, manifest)

    boss_health = Image.open(data_root / "boss_health.png").convert("RGBA")
    boss_bar_frames = []
    boss_bar_pixel = boss_health.crop((0, 48, 1, 53))
    boss_bar_end = boss_health.crop((1, 48, 2, 53))
    for length in range(179):
        frame = Image.new("RGBA", (179, 5))
        for x in range(length):
            frame.paste(boss_bar_pixel, (x, 0))
        frame.paste(boss_bar_end, (length, 0))
        boss_bar_frames.append(encode_frame(frame, 0, 0, 179, 5, color_indexes))
    for group in range(4):
        first = group * 45
        last = min(first + 45, len(boss_bar_frames))
        write_asset(
            output_root,
            f"boss_bar_{group}",
            boss_bar_frames[first:last],
            179,
            5,
            manifest,
        )

    music_root = output_root / "music"
    music_root.mkdir(parents=True, exist_ok=True)
    for source in sorted((data_root / "sfx").glob("*.ogg")):
        target = music_root / source.name
        shutil.copyfile(source, target)
        size = target.stat().st_size
        relative = f"music/{source.name}"
        manifest.append(
            f'{len(manifest) + 1} {size} {relative} {{"type":"music"}}'
        )

    write_map(upstream, output_root, "base", "map_data.lua")
    write_map(upstream, output_root, "top_base", "boss_map.lua")
    map_converter = Path(__file__).with_name("convert_maps.lua")
    map_output = subprocess.check_output(
        ["lua5.4", str(map_converter), str(upstream)], text=True
    )
    (output_root / "map_templates.lua").write_text(map_output, encoding="utf-8")

    mechanics_audit = Path(__file__).with_name("audit_upstream_mechanics.py")
    subprocess.check_call(
        [sys.executable, str(mechanics_audit), str(upstream), str(output_root)]
    )

    for source in sorted(output_root.rglob("*.lua")):
        relative = source.relative_to(output_root).as_posix()
        size = source.stat().st_size
        manifest.append(
            f'{len(manifest) + 1} {size} {relative} {{"type":"lua_code"}}'
        )
    (output_root / "lupi_manifest.txt").write_text(
        "\n".join(manifest) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    convert(arguments.upstream.resolve(), arguments.output.resolve())


if __name__ == "__main__":
    main()
