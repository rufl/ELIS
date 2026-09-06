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
codec_revision="3e8c66299a4606b36b9f490212acc44e084a6aa2"
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
    git init -q "$codec_dir"
    git -C "$codec_dir" remote add origin https://github.com/lupi-org-br/lupi-codec.git
    git -C "$codec_dir" fetch -q --depth 1 origin "$codec_revision"
    git -C "$codec_dir" checkout -q --detach FETCH_HEAD
  fi
  [[ -f "$codec_dir/run.lua" ]] || { echo "Invalid LUPI_CODEC_DIR: $codec_dir" >&2; exit 1; }
  release_dir="$work_dir/release"
  (cd "$codec_dir" && lua run.lua "$source_dir" "$release_dir")
  game_dir="$release_dir/current"
fi

"$root_dir/zig-out/bin/elis" "$game_dir"
