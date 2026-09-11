#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d /tmp/elis-mr-rescue.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

ZIG_LOCAL_CACHE_DIR="$tmp/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/global-cache" \
zig build native -Doptimize=ReleaseSafe >/dev/null

port="demos/mr-rescue"
game="$port/current"
test -d "$port"
test ! -e ports/mr-rescue-lupi
test -f "$port/LICENSE.upstream"
grep -q 'a5be73c60acb8d1be506f7b5e48e784492ba96ce' "$port/SOURCE.md"

refresh_port_mode_manifest() {
  local root="$1"
  local size
  size="$(stat -c %s "$root/port_mode.lua")"
  awk -v size="$size" 'BEGIN { OFS=" " } $3 == "port_mode.lua" { $2=size } { print }' \
    "$root/lupi_manifest.txt" > "$root/lupi_manifest.txt.new"
  mv "$root/lupi_manifest.txt.new" "$root/lupi_manifest.txt"
}

total_bytes="$(find "$game" -type f -printf '%s\n' | awk '{ total += $1 } END { print total }')"
test "$total_bytes" -le $((16 * 1024 * 1024))
declared_bytes="$(awk '{ total += $2 } END { print total }' "$game/lupi_manifest.txt")"
payload_bytes="$(find "$game" -type f ! -name lupi_manifest.txt -printf '%s\n' | \
  awk '{ total += $1 } END { print total }')"
test "$declared_bytes" -eq "$payload_bytes"
python3 "$port/tools/audit_release.py"
while read -r _ encoded_bytes relative metadata; do
  if [[ "$metadata" == *'"type":"bitmap"'* ]]; then
    test "$encoded_bytes" -le 49152
  fi
  test "$(stat -c %s "$game/$relative")" -eq "$encoded_bytes"
done < "$game/lupi_manifest.txt"

lua5.4 - <<'LUA'
package.path = 'demos/mr-rescue/current/?.lua;' .. package.path
local campaign = require('campaign')
campaign.statistics[1] = 99
campaign.statistics[6] = 99
campaign.reset()
for index = 1, 6 do assert(campaign.statistics[index] == 0) end
local events = { consumeEvents = function() return 70, 2, 6, 123 end }
campaign.consumeWorld(events)
assert(campaign.score == 4070)
assert(campaign.saved == 6 and campaign.combo == 6)
campaign.finalize()
assert(campaign.maximum_combo == 6)
campaign.floorCleared(true)
assert(campaign.score == 5070)
assert(campaign.statistics[1] == 2 and campaign.statistics[4] == 6)
assert(campaign.statistics[5] == 123)
campaign.score = 4321
assert(campaign.highscoreRank(2) == 1)
campaign.addHighscore(2, 1, 'ALPHA')
local highscore_name, highscore_score = campaign.highscore(2, 1)
assert(highscore_name == 'ALPHA' and highscore_score == 4321)
campaign.score = 5000
assert(campaign.highscoreRank(2) == 1)
campaign.addHighscore(2, 1, 'BRAVO')
assert(select(1, campaign.highscore(2, 1)) == 'BRAVO')
assert(select(1, campaign.highscore(2, 2)) == 'ALPHA')
campaign.time_frames = (3600 + 120 + 3) * 60
assert(campaign.timeString() == '01:02:03')
local award_values = { 301, 60001, 20001, 81, 90001, 161 }
for index, value in ipairs(award_values) do campaign.statistics[index] = value end
assert(campaign.award(1) == 'BRONZE')
assert(campaign.award(2) == 'SILVER')
assert(campaign.award(3) == 'GOLD')
assert(campaign.award(4) == 'BRONZE')
assert(campaign.award(5) == 'GOLD')
assert(campaign.award(6) == 'SILVER')

local progression = require('progression')
local expected_bosses = { 8, 11, 15 }
local expected_floors = { 21, 30, 42 }
for difficulty = 1, 3 do
  assert(progression.bossSection(difficulty) == expected_bosses[difficulty])
  assert(progression.floorCount(difficulty) == expected_floors[difficulty])
  assert(progression.maximumCasualties(difficulty) == 6 - difficulty)
  assert(progression.internalSection(1, difficulty) == 1 + (difficulty - 1) * 5)
  assert(progression.internalSection(expected_bosses[difficulty], difficulty) <= 25)
end

local profile = require('profile')
local templates = require('map_templates')
local maximum_rooms = 0
local maximum_doors = 0
local maximum_humans = 0
for _, floor in ipairs(templates.floors) do
  local rooms = 0
  local doors = 0
  local humans = 0
  for _, object in ipairs(floor.objects) do
    if object.type == 'room' then
      rooms = rooms + 1
      humans = humans + math.floor((object.width / 16) / 5)
    elseif object.type == 'door' then
      doors = doors + 1
    end
  end
  maximum_rooms = math.max(maximum_rooms, rooms)
  maximum_doors = math.max(maximum_doors, doors)
  maximum_humans = math.max(maximum_humans, humans)
end
assert(maximum_rooms * 3 == profile.room_max)
assert(maximum_doors * 3 == profile.generated_door_max)
assert(maximum_humans * 3 == profile.generated_human_max)
assert(maximum_rooms * 2 * 3 == profile.generated_enemy_max)
assert(profile.fire_max == 35 * 18)
LUA

python3 scripts/mr_rescue_viewport_smoke.py --game "$game"
python3 scripts/mr_rescue_failure_smoke.py --game "$game"

title_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$game" 1 "$tmp/title.ppm" 2>&1)"
if grep -Eqi 'Erro|error:' <<<"$title_output"; then
  printf '%s\n' "$title_output" >&2
  exit 1
fi
expected_title="ea5c3461ba6f93e18edde83e4b25a2166fde7c9420108d20b779ed95e4bfe324"
test "$(sha256sum "$tmp/title.ppm" | awk '{print $1}')" = "$expected_title"

cp -R "$game" "$tmp/flow"
printf 'return { auto_start = false, flow_probe = true }\n' > "$tmp/flow/port_mode.lua"
refresh_port_mode_manifest "$tmp/flow"
flow_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/flow" 360 "$tmp/flow.ppm" 2>&1)"
for flow_state in 2 3 17 15 8 12; do
  grep -q "MR_RESCUE_FLOW STATE=$flow_state " <<<"$flow_output"
done
test "$(grep -c 'MR_RESCUE_FLOW STATE=8 ' <<<"$flow_output")" -eq 2
grep -q 'STATE=17 SECTION=1 FRAMES=0 TICK=4.0' <<<"$flow_output"
grep -q 'STATE=15 SECTION=1 FRAMES=0 TICK=85.0' <<<"$flow_output"
grep -q 'STATE=8 SECTION=1 FRAMES=0 TICK=295.0' <<<"$flow_output"
grep -q 'STATE=12 SECTION=1 FRAMES=14 TICK=309.0' <<<"$flow_output"

cp -R "$game" "$tmp/tutorial"
printf 'return { auto_start = false, tutorial_probe = true }\n' \
  > "$tmp/tutorial/port_mode.lua"
refresh_port_mode_manifest "$tmp/tutorial"
tutorial_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/tutorial" 24 "$tmp/tutorial.ppm" 2>&1)"
for slide in 0 1 2 3 4 5 6 7 8; do
  grep -q "MR_RESCUE_HOWTO SLIDE=$slide" <<<"$tutorial_output"
done

cp -R "$game" "$tmp/menu-flow"
printf 'return { auto_start = false, menu_probe = true }\n' \
  > "$tmp/menu-flow/port_mode.lua"
refresh_port_mode_manifest "$tmp/menu-flow"
menu_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/menu-flow" 42 \
  "$tmp/menu-flow.ppm" 2>&1)"
grep -q 'MR_RESCUE_MENU OPTIONS FAMILY=false' <<<"$menu_output"
grep -q 'MR_RESCUE_MENU OPTIONS FAMILY=true' <<<"$menu_output"
grep -q 'MR_RESCUE_MENU HISTORY PAGE=2' <<<"$menu_output"
grep -q 'MR_RESCUE_MENU HIGHSCORES PAGE=2' <<<"$menu_output"
test "$(grep -c 'MR_RESCUE_FLOW STATE=2 ' <<<"$menu_output")" -eq 4

cp -R "$game" "$tmp/seed-sweep"
printf 'return { auto_start = true, seed_sweep = 32, capacity_probe = true }\n' \
  > "$tmp/seed-sweep/port_mode.lua"
refresh_port_mode_manifest "$tmp/seed-sweep"
sweep_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/seed-sweep" 1 "$tmp/sweep.ppm" 2>&1)"
grep -q 'MR_RESCUE_SEED_SWEEP=32' <<<"$sweep_output"
grep -q 'MR_RESCUE_CAPACITY_BOUNDARIES=PASS' <<<"$sweep_output"

cp -R "$game" "$tmp/player-trace"
printf 'return { auto_start = true, player_trace = true }\n' \
  > "$tmp/player-trace/port_mode.lua"
refresh_port_mode_manifest "$tmp/player-trace"
player_trace_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/player-trace" 121 \
  "$tmp/player-trace.ppm" 2>&1)"
actual_player_trace="$(grep 'MR_RESCUE_PLAYER_TRACE' <<<"$player_trace_output" | \
  sed 's/^.*MR_RESCUE/MR_RESCUE/')"
expected_player_trace="$(cat <<'TRACE'
MR_RESCUE_PLAYER_TRACE FRAME=1.0 X=200.2083 Y=240.0000 SX=0.1389 SY=0.0000 WATER=300.00 SPRAY=false
MR_RESCUE_PLAYER_TRACE FRAME=20.0 X=216.0417 Y=235.7917 SX=1.4583 SY=-2.0556 WATER=300.00 SPRAY=false
MR_RESCUE_PLAYER_TRACE FRAME=40.0 X=259.2083 Y=215.0972 SX=2.5972 SY=-0.1111 WATER=295.00 SPRAY=true
MR_RESCUE_PLAYER_TRACE FRAME=60.0 X=310.9444 Y=233.2917 SX=2.3889 SY=1.8333 WATER=245.00 SPRAY=true
MR_RESCUE_PLAYER_TRACE FRAME=80.0 X=320.9722 Y=240.0000 SX=-0.5556 SY=0.0000 WATER=255.50 SPRAY=false
MR_RESCUE_PLAYER_TRACE FRAME=100.0 X=295.2778 Y=240.0000 SX=-1.9444 SY=0.0000 WATER=300.00 SPRAY=false
MR_RESCUE_PLAYER_TRACE FRAME=120.0 X=246.1528 Y=240.0000 SX=-2.5278 SY=0.0000 WATER=300.00 SPRAY=false
TRACE
)"
test "$actual_player_trace" = "$expected_player_trace"

cp -R "$game" "$tmp/interactions"
printf 'return { auto_start = true, interaction_probe = true }\n' \
  > "$tmp/interactions/port_mode.lua"
refresh_port_mode_manifest "$tmp/interactions"
interaction_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/interactions" 1 \
  "$tmp/interactions.ppm" 2>&1)"
grep -q 'MR_RESCUE_INTERACTIONS=PASS' <<<"$interaction_output"

cp -R "$game" "$tmp/failure-flow"
printf 'return { auto_start = true, failure_probe = true }\n' \
  > "$tmp/failure-flow/port_mode.lua"
refresh_port_mode_manifest "$tmp/failure-flow"
failure_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/failure-flow" 300 \
  "$tmp/failure-flow.ppm" 2>&1)"
for flow_state in 8 16 10 13 14 5; do
  grep -q "MR_RESCUE_FLOW STATE=$flow_state " <<<"$failure_output"
done
grep -q 'STATE=16 SECTION=1 FRAMES=0 TICK=89.0' <<<"$failure_output"
grep -q 'STATE=10 SECTION=1 FRAMES=0 TICK=170.0' <<<"$failure_output"
grep -q 'STATE=13 SECTION=1 FRAMES=49 TICK=219.0' <<<"$failure_output"
grep -q 'STATE=14 SECTION=1 FRAMES=79 TICK=249.0' <<<"$failure_output"

cp -R "$game" "$tmp/section-flow"
printf 'return { auto_start = true, section_exit_probe = true }\n' \
  > "$tmp/section-flow/port_mode.lua"
refresh_port_mode_manifest "$tmp/section-flow"
section_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/section-flow" 120 \
  "$tmp/section-flow.ppm" 2>&1)"
grep -q 'MR_RESCUE_FLOW STATE=16 SECTION=1' <<<"$section_output"
grep -q 'MR_RESCUE_FLOW STATE=11 SECTION=2 FRAMES=0 TICK=81.0' <<<"$section_output"

# The isolated copy injects deterministic movement, jump, carry, throw, and
# spray actions; the release cartridge never enables this path.
cp -R "$game" "$tmp/game"
printf 'return { auto_start = true }\n' > "$tmp/game/port_mode.lua"
refresh_port_mode_manifest "$tmp/game"
play_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/game" 300 "$tmp/play.ppm" 2>&1)"
if grep -Eqi 'Erro|error:' <<<"$play_output"; then
  printf '%s\n' "$play_output" >&2
  exit 1
fi
grep -q 'MR_RESCUE_LUA_BYTES=' <<<"$play_output"
grep -Eq 'CARRY=[1-9]' <<<"$play_output"
grep -q 'STATE=4' <<<"$play_output"
grep -q 'STATE=5' <<<"$play_output"
grep -Eq 'SCORE=[1-9][0-9]*' <<<"$play_output"
grep -Eq 'SAFE=[1-9][0-9]*' <<<"$play_output"
while read -r lua_bytes; do
  test "$lua_bytes" -lt $((4 * 1024 * 1024))
done < <(grep -o 'MR_RESCUE_LUA_BYTES=[0-9]*' <<<"$play_output" | cut -d= -f2)
expected_play="adb1fff5d2bcade7bce04ec1d08d6e8a4a419be87656cff97b36dcf2f46c0e74"
test "$(sha256sum "$tmp/play.ppm" | awk '{print $1}')" = "$expected_play"

cp -R "$game" "$tmp/family"
printf 'return { auto_start = true, family_presentation = true }\n' \
  > "$tmp/family/port_mode.lua"
refresh_port_mode_manifest "$tmp/family"
family_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/family" 300 "$tmp/family.ppm" 2>&1)"
test "$(grep 'MR_RESCUE_HUMAN=' <<<"$family_output")" = \
  "$(grep 'MR_RESCUE_HUMAN=' <<<"$play_output")"
test "$(grep 'MR_RESCUE_LUA_BYTES=' <<<"$family_output" | tail -1 | \
  grep -o 'X=.*')" = \
  "$(grep 'MR_RESCUE_LUA_BYTES=' <<<"$play_output" | tail -1 | grep -o 'X=.*')"
expected_family="4deb74eef13d1f11edc76789955b1ca949054419c62b95f8d3e38ae3390a31b1"
test "$(sha256sum "$tmp/family.ppm" | awk '{print $1}')" = "$expected_family"

cp -R "$game" "$tmp/high"
printf 'return { auto_start = true, section = 26, all_enemies = true }\n' \
  > "$tmp/high/port_mode.lua"
refresh_port_mode_manifest "$tmp/high"
high_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/high" 600 "$tmp/high.ppm" 2>&1)"
if grep -Eqi 'Erro|error:' <<<"$high_output"; then
  printf '%s\n' "$high_output" >&2
  exit 1
fi
while read -r lua_bytes; do
  test "$lua_bytes" -lt $((4 * 1024 * 1024))
done < <(grep -o 'MR_RESCUE_LUA_BYTES=[0-9]*' <<<"$high_output" | cut -d= -f2)
for enemy_kind in 1 2 3 4 5 6 7; do
  grep -q "MR_RESCUE_ENEMY=$enemy_kind " <<<"$high_output"
done
grep -Eq 'MR_RESCUE_ENEMY=(2|5) .*STATE=2' <<<"$high_output"
grep -Eq 'MR_RESCUE_WORLD .*PROJECTILES=[1-9][0-9]*' <<<"$high_output"
expected_high="4b32904ea1478ada57601e8925049b51481df8fd12140c7b78b1bf8389e9dc0c"
test "$(sha256sum "$tmp/high.ppm" | awk '{print $1}')" = "$expected_high"

boss_hashes=(
  e9e79602ee4a414cb9ceb8d04dc0833bc00aa39967f38808b0c1846d8a989a85
  4001cb42fb2538eb71255483a9e9936952df6f525d4ceca703f010ed3e76f613
  bca7b52a255f5f28655e2bfc5c3df4dfebae6a4672410a51c88655dd1e076249
)
for boss in 1 2 3; do
  cp -R "$game" "$tmp/boss-$boss"
  printf 'return { auto_start = true, section = 26, all_enemies = false, boss_kind = %d }\n' \
    "$boss" > "$tmp/boss-$boss/port_mode.lua"
  refresh_port_mode_manifest "$tmp/boss-$boss"
  boss_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    ./zig-out/bin/elis --screenshot "$tmp/boss-$boss" 900 "$tmp/boss-$boss.ppm" 2>&1)"
  if grep -Eqi 'Erro|error:' <<<"$boss_output"; then
    printf '%s\n' "$boss_output" >&2
    exit 1
  fi
  while read -r lua_bytes; do
    test "$lua_bytes" -lt $((4 * 1024 * 1024))
  done < <(grep -o 'MR_RESCUE_LUA_BYTES=[0-9]*' <<<"$boss_output" | cut -d= -f2)
  test "$(sha256sum "$tmp/boss-$boss.ppm" | awk '{print $1}')" = \
    "${boss_hashes[$((boss - 1))]}"
done

victory_frames=(3500 3500 5500)
victory_hashes=(
  72e5c5c0ee8642ef8509760c9434cb60929d008a490e80ac558126bec0a6d821
  f2bc05b80325a3e9f3a2461b8cda95472e0c5e092419ef1a2db1f53d7c87e130
  b8ddca2f76b8ef8d967d66fdbe32a2fc2eaee2195d801b29daa5f7e120674cf1
)
for boss in 1 2 3; do
  cp -R "$game" "$tmp/victory-$boss"
  printf 'return { auto_start = true, boss_kind = %d, boss_victory = true }\n' \
    "$boss" > "$tmp/victory-$boss/port_mode.lua"
  refresh_port_mode_manifest "$tmp/victory-$boss"
  victory_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    ./zig-out/bin/elis --screenshot "$tmp/victory-$boss" \
    "${victory_frames[$((boss - 1))]}" "$tmp/victory-$boss.ppm" 2>&1)"
  grep -q "MR_RESCUE_BOSS=$boss .*HEALTH=0 DEFEATED=true" <<<"$victory_output"
  grep -q 'SCORE=5000' <<<"$victory_output"
  while read -r lua_bytes; do
    test "$lua_bytes" -lt $((4 * 1024 * 1024))
  done < <(grep -o 'MR_RESCUE_LUA_BYTES=[0-9]*' <<<"$victory_output" | cut -d= -f2)
  test "$(sha256sum "$tmp/victory-$boss.ppm" | awk '{print $1}')" = \
    "${victory_hashes[$((boss - 1))]}"
done

echo "Mr. Rescue profile/core/scoring/enemy/three-boss behavior+victory stress: pass"
