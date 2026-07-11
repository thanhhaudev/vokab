#!/usr/bin/env bash
# Regenerates the About-window GitHub mark PNGs from App/Resources/GitHubMark.svg
# using rsvg-convert. The PNGs are committed, so running this is only needed when
# the source art changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/App/Resources/GitHubMark.svg"
OUT="$ROOT/App/Assets.xcassets/GitHubMark.imageset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "error: rsvg-convert not found (brew install librsvg)" >&2
  exit 1
fi
[ -f "$SVG" ] || { echo "error: missing $SVG" >&2; exit 1; }
mkdir -p "$OUT"

render() { # <pixels> <outfile>
  rsvg-convert -w "$1" -h "$1" "$SVG" -o "$OUT/$2"
  echo "  $2 (${1}px)"
}

echo "Rendering GitHub mark PNGs:"
render 64  github-mark.png
render 128 github-mark@2x.png
echo "Done."
