#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
tmp="$(mktemp -d /tmp/elis-mr-rescue.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

ZIG_LOCAL_CACHE_DIR="$tmp/build-cache" \
ZIG_GLOBAL_CACHE_DIR="$tmp/global-cache" \
zig build native -Doptimize=ReleaseSafe >/dev/null

port="ports/mr-rescue-lupi"
game="$port/game"
test ! -e demos/mr-rescue
test ! -e demos/mr-rescue-lupi
test -f "$port/LICENSE.upstream"
grep -q 'a5be73c60acb8d1be506f7b5e48e784492ba96ce' "$port/SOURCE.md"

total_bytes="$(find "$game" -type f -printf '%s\n' | awk '{ total += $1 } END { print total }')"
test "$total_bytes" -le $((16 * 1024 * 1024))
declared_bytes="$(awk '{ total += $2 } END { print total }' "$game/lupi_manifest.txt")"
payload_bytes="$(find "$game" -type f ! -name lupi_manifest.txt -printf '%s\n' | \
  awk '{ total += $1 } END { print total }')"
test "$declared_bytes" -eq "$payload_bytes"
while read -r _ encoded_bytes relative metadata; do
  if [[ "$metadata" == *'"type":"bitmap"'* ]]; then
    test "$encoded_bytes" -le 49152
  fi
  test "$(stat -c %s "$game/$relative")" -eq "$encoded_bytes"
done < "$game/lupi_manifest.txt"

lua5.4 - <<'LUA'
package.path = 'ports/mr-rescue-lupi/game/?.lua;' .. package.path
local campaign = require('campaign')
campaign.reset()
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
LUA

title_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$game" 1 "$tmp/title.ppm" 2>&1)"
if grep -Eqi 'Erro|error:' <<<"$title_output"; then
  printf '%s\n' "$title_output" >&2
  exit 1
fi
expected_title="6aa3a188e942aba8ff077a83f5a984fa25bad34cf2a1567545302f3ecf9b8d6f"
test "$(sha256sum "$tmp/title.ppm" | awk '{print $1}')" = "$expected_title"

cp -R "$game" "$tmp/seed-sweep"
printf 'return { auto_start = true, seed_sweep = 32 }\n' > "$tmp/seed-sweep/port_mode.lua"
sweep_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/seed-sweep" 1 "$tmp/sweep.ppm" 2>&1)"
grep -q 'MR_RESCUE_SEED_SWEEP=32' <<<"$sweep_output"

# The isolated copy injects deterministic movement, jump, carry, throw, and
# spray actions; the release cartridge never enables this path.
cp -R "$game" "$tmp/game"
printf 'return { auto_start = true }\n' > "$tmp/game/port_mode.lua"
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
expected_play="2726d6bf22f332c95d12ceb0dfca1db3e26a7ddfd117e9e7eec983513dd19f4f"
test "$(sha256sum "$tmp/play.ppm" | awk '{print $1}')" = "$expected_play"

cp -R "$game" "$tmp/high"
printf 'return { auto_start = true, section = 26, all_enemies = true }\n' \
  > "$tmp/high/port_mode.lua"
high_output="$(env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./zig-out/bin/elis --screenshot "$tmp/high" 600 "$tmp/high.ppm" 2>&1)"
if grep -Eqi 'Erro|error:' <<<"$high_output"; then
  printf '%s\n' "$high_output" >&2
  exit 1
fi
while read -r lua_bytes; do
  test "$lua_bytes" -lt $((4 * 1024 * 1024))
done < <(grep -o 'MR_RESCUE_LUA_BYTES=[0-9]*' <<<"$high_output" | cut -d= -f2)
expected_high="2123db6700a07d297275e859eafd7fa099dfe4274834075757aa63519cdc29ff"
test "$(sha256sum "$tmp/high.ppm" | awk '{print $1}')" = "$expected_high"

boss_hashes=(
  bac6816a2b78027db9b2a00347c452c3fd25ce48b87e33f9ff311825dba837ba
  e01fcd8a326d151e6fcde8acd81846a38687639aef039b9514dc3394d8021922
  df930f9b111b44682b299de192e63941db8323503d0bd6b3486f9b911b56cee7
)
for boss in 1 2 3; do
  cp -R "$game" "$tmp/boss-$boss"
  printf 'return { auto_start = true, section = 26, all_enemies = false, boss_kind = %d }\n' \
    "$boss" > "$tmp/boss-$boss/port_mode.lua"
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
  81bc9a1cee0c2411eebcb1bc3fd6c1c73a2c1094f77bb0cd30aba4e127701843
  212d4c721641bacae139251b203b79a8b4c6d85390886246668039efabe3a405
  f500c51c1d3bb349aeec1bf25810f9503fac7b0a1b31e12d2d589f7f8cfd2959
)
for boss in 1 2 3; do
  cp -R "$game" "$tmp/victory-$boss"
  printf 'return { auto_start = true, boss_kind = %d, boss_victory = true }\n' \
    "$boss" > "$tmp/victory-$boss/port_mode.lua"
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
