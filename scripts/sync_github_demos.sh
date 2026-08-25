#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
catalog="${1:-$root_dir/demos/catalog.txt}"
[[ -f "$catalog" ]] || { echo "Catalog not found: $catalog" >&2; exit 1; }
command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v lua >/dev/null || { echo "Lua 5.3+ is required" >&2; exit 1; }
command -v magick >/dev/null || command -v convert >/dev/null || { echo "ImageMagick is required" >&2; exit 1; }

work_dir="$(mktemp -d -t elis-sync-XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT
codec_dir="${LUPI_CODEC_DIR:-$work_dir/lupi-codec}"
if [[ -z "${LUPI_CODEC_DIR:-}" ]]; then
  git clone --depth 1 https://github.com/lupi-org-br/lupi-codec.git "$codec_dir"
fi
[[ -f "$codec_dir/run.lua" ]] || { echo "Invalid LUPI_CODEC_DIR: $codec_dir" >&2; exit 1; }

while IFS='|' read -r name url; do
  [[ -z "${name//[[:space:]]/}" || "$name" == \#* ]] && continue
  [[ "$url" == builtin:* ]] && continue
  [[ "$url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Skipping invalid URL: $url" >&2; continue; }
  slug="$(basename "$url")"
  source_dir="$work_dir/$slug-source"
  release_dir="$work_dir/$slug-release"
  git clone --depth 1 "$url.git" "$source_dir"
  commit="$(git -C "$source_dir" rev-parse HEAD)"
  target_dir="$root_dir/demos/$slug"
  metadata="$target_dir/.lupi-source"
  source_record="$url|$commit"
  if [[ -f "$metadata" ]] && [[ "$(<"$metadata")" == "$source_record" ]]; then
    printf 'current %s (%s)\n' "$name" "${commit:0:12}"
    continue
  fi
  if [[ -e "$target_dir" ]]; then
    if [[ ! -t 0 ]]; then
      printf 'skipping %s: update requires confirmation\n' "$name" >&2
      continue
    fi
    read -r -p "Replace existing demo '$name' with ${commit:0:12}? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { printf 'skipped %s\n' "$name"; continue; }
  fi
  (cd "$codec_dir" && lua run.lua "$source_dir" "$release_dir")
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cp -RL "$release_dir/current/." "$target_dir/"
  printf '%s\n' "$source_record" > "$target_dir/.lupi-source"
  printf 'updated %s -> demos/%s (%s)\n' "$name" "$slug" "${commit:0:12}"
done < "$catalog"
