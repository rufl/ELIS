#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root_dir"

frames="${1:-10000}"
repetitions="${2:-5}"
if ! [[ "$frames" =~ ^[1-9][0-9]*$ && "$repetitions" =~ ^[1-9][0-9]*$ ]]; then
  echo "uso: $0 [frames-positivos] [repeticoes-positivas]" >&2
  exit 2
fi

zig build native -Doptimize=ReleaseFast >/dev/null

# Pin samples to one allowed CPU when taskset is available. This reduces
# scheduler migration noise without assuming that CPU 0 is available inside a
# container or restricted session.
runner=()
if command -v taskset >/dev/null 2>&1 && [[ -r /proc/self/status ]]; then
  allowed_list="$(awk '/^Cpus_allowed_list:/ { print $2 }' /proc/self/status)"
  first_allowed="${allowed_list%%[-,]*}"
  runner=(taskset -c "${ELIS_BENCH_CPU:-${ZILF_BENCH_CPU:-$first_allowed}}")
fi

games=(example mazestein3d)
for demo in demos/*; do
  [[ -f "$demo/game.lua" ]] && games+=("$demo")
done

for game in "${games[@]}"; do
  samples=""
  for ((run = 1; run <= repetitions; run++)); do
    result="$("${runner[@]}" ./zig-out/bin/elis --benchmark "$game" "$frames" 2>&1)"
    echo "$game run=$run $result"
    sample="$(sed -n 's/.*us_per_frame=\([^ ]*\).*/\1/p' <<<"$result")"
    samples+="$sample"$'\n'
  done
  median_index=$(((repetitions + 1) / 2))
  median="$(sed '/^$/d' <<<"$samples" | sort -n | sed -n "${median_index}p")"
  echo "$game median_us_per_frame=$median"
done
