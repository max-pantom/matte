#!/bin/sh
# Regenerates Icon/AppIcon.iconset, Icon/AppIcon.icns and Icon/preview.png from scripts/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift scripts/make-icon.swift
iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
echo "Wrote Icon/AppIcon.icns"
