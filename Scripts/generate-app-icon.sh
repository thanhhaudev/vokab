#!/usr/bin/env bash
# Regenerates the macOS AppIcon PNGs from App/Resources/AppIcon.svg using rsvg-convert.
# The PNGs are committed, so running this is only needed when the source art changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/App/Resources/AppIcon.svg"
OUT="$ROOT/App/Assets.xcassets/AppIcon.appiconset"

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

echo "Rendering app icon PNGs:"
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png
echo "Done."
