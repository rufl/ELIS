#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-}"
if [[ ! "$target" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/?$ ]]; then
  echo "Usage: $0 https://github.com/OWNER/REPOSITORY" >&2
  exit 2
fi

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v lua >/dev/null || { echo "Lua 5.3+ is required for source-format demos" >&2; exit 1; }

work_dir="$(mktemp -d -t elis-github-XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
source_dir="$work_dir/source"
git clone --depth 1 "$target.git" "$source_dir"

game_dir="$source_dir"
if [[ ! -f "$game_dir/lupi_manifest.txt" ]]; then
  command -v magick >/dev/null || command -v convert >/dev/null || {
    echo "ImageMagick (magick or convert) is required to prepare source-format demos" >&2
    exit 1
  }
  codec_dir="${LUPI_CODEC_DIR:-}"
  if [[ -z "$codec_dir" ]]; then
    codec_dir="$work_dir/lupi-codec"
    git clone --depth 1 https://github.com/lupi-org-br/lupi-codec.git "$codec_dir"
  fi
  [[ -f "$codec_dir/run.lua" ]] || { echo "Invalid LUPI_CODEC_DIR: $codec_dir" >&2; exit 1; }
  release_dir="$work_dir/release"
  (cd "$codec_dir" && lua run.lua "$source_dir" "$release_dir")
  game_dir="$release_dir/current"
fi

exec "$root_dir/zig-out/bin/elis" "$game_dir"
