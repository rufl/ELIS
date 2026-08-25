#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
exec "$root_dir/scripts/sync_github_demos.sh" "$@"
