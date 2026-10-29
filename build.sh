#!/bin/sh
# Builds an ad-hoc signed Matte.app. VERSION=1.2.3 stamps the bundle;
# ZIP=1 also creates Matte.zip. Universal is preferred, native is the fallback.
set -e
cd "$(dirname "$0")"

mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SWIFT_FLAGS="--disable-sandbox -Xswiftc -module-cache-path -Xswiftc $PWD/.build/module-cache"

if swift build -c release --arch arm64 --arch x86_64 --product Matte $SWIFT_FLAGS; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --product Matte $SWIFT_FLAGS --show-bin-path)/Matte"
else
  echo "Universal build unavailable; falling back to native architecture."
  swift build -c release --product Matte $SWIFT_FLAGS
  BIN="$(swift build -c release --product Matte $SWIFT_FLAGS --show-bin-path)/Matte"
fi

# Rebuild the icon from Resources/AppIcon-source.png when it is missing or older than the source.
if [ ! -f Icon/AppIcon.icns ] || [ Resources/AppIcon-source.png -nt Icon/AppIcon.icns ] || [ scripts/make-icon.sh -nt Icon/AppIcon.icns ]; then
  sh scripts/make-icon.sh || echo "Icon generation failed; keeping the existing icon."
fi

APP="$PWD/Matte.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Matte"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns Icon/preview.png "$APP/Contents/Resources/"
cp Resources/InterVariable.woff2 Resources/OFL.txt "$APP/Contents/Resources/"
BUNDLE_DIR="$(dirname "$BIN")/Matte_Matte.bundle"
if [ -d "$BUNDLE_DIR" ]; then cp -R "$BUNDLE_DIR" "$APP/Contents/Resources/"; fi
if [ -n "$VERSION" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
ARCH_LIST="$(lipo -archs "$APP/Contents/MacOS/Matte" 2>/dev/null || uname -m)"
echo "Built $APP ($ARCH_LIST)"

if [ -n "$ZIP" ]; then
  rm -f Matte.zip
  ditto -c -k --keepParent "$APP" Matte.zip
  echo "Wrote $PWD/Matte.zip"
fi
