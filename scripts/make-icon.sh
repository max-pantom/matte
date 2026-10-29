#!/bin/sh
# Builds Icon/AppIcon.iconset (10 sizes), Icon/AppIcon.icns and Icon/preview.png from Resources/AppIcon-source.png.
set -e
cd "$(dirname "$0")/.."
SRC=Resources/AppIcon-source.png
SET=Icon/AppIcon.iconset
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -s format png -z $s $s "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -s format png -z $d $d "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Icon/AppIcon.icns
cp "$SRC" Icon/preview.png
echo "Wrote Icon/AppIcon.icns from $SRC"
