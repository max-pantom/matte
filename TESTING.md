# Testing

v0.1 results below were observed on 29 October 2026 with Apple Swift 6.3.2 (`arm64-apple-macosx28.0`) and the macOS 26.5 SDK. **v0.2 has not been built or run yet**: the v0.2 sections state the expected results and must be re-run on a Mac.

This managed workspace does not permit SwiftPM or Clang to write their normal user caches, so all commands use the fallback requested in `SPEC.md`:

```sh
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
SWIFT_FLAGS="--disable-sandbox -Xswiftc -module-cache-path -Xswiftc $PWD/.build/module-cache"
```

SwiftPM prints notices that its user-level cache is unavailable and that its read-only manifest database cannot be updated. These are environment notices; the compiler emitted no source warnings or errors.

## Build

```sh
swift build $SWIFT_FLAGS
```

Observed: `Build complete!` with zero compiler errors and zero source warnings.

## CLI export verification

The sample files are stored under `samples/`, so the spec commands were run with that path prefix.

```sh
swift run $SWIFT_FLAGS -c release matte-cli \
  samples/sample-1920x1080.png samples/sample-dark-1920x1080.png \
  --out out/test --formats all

swift run $SWIFT_FLAGS -c release matte-cli \
  samples/sample-1920x1080.png samples/sample-dark-1920x1080.png \
  --out out/fill-auto --formats all --mode fill --color auto

swift run $SWIFT_FLAGS -c release matte-cli \
  samples/sample-1920x1080.png samples/sample-dark-1920x1080.png \
  --out out/pad-zero --formats all --pad 0
```

v0.1 (14 formats): each command ended with `Verified 28 outputs at exact pixel sizes.`

v0.2 has 13 formats (the four X grid presets were replaced by three carousel presets), so each command should end with `Verified 26 outputs at exact pixel sizes.` and each output directory should hold 26 files. Not yet observed.

| Format | Expected pixels | Default fit | Fill + auto | Padding 0 |
| --- | ---: | :---: | :---: | :---: |
| x-landscape | 1600×900 | | | |
| x-square | 1080×1080 | | | |
| x-portrait-45 | 1080×1350 | | | |
| x-carousel-wide | 1600×1360 | | | |
| x-carousel-square | 1080×1080 | | | |
| x-carousel-45 | 1080×1350 | | | |
| x-portrait-34 | 1080×1440 | | | |
| x-header | 1500×500 | | | |
| x-article | 2000×800 | | | |
| ig-feed-45 | 1080×1350 | | | |
| ig-square | 1080×1080 | | | |
| ig-grid-34 | 1080×1440 | | | |
| ig-story | 1080×1920 | | | |

Subset check (`--formats id,id`):

```sh
swift run $SWIFT_FLAGS -c release matte-cli samples/sample-1920x1080.png \
  --out out/subset --formats x-carousel-wide,ig-feed-45
```

Expected: 2 outputs. An old id such as `x-grid-2` must fail with `Unknown format: x-grid-2`.

## Simulator maths (CLI)

```sh
swift run $SWIFT_FLAGS -c release matte-cli --simulate \
  samples/sample-1920x1080.png samples/sample-dark-1920x1080.png
```

Expected for two 16:9 (1.778) images, one X post:

| Column | Expected |
| --- | --- |
| X carousel | `1.176 crop 34%` (20:17 cap; matches the 414×352 px tile measured in `reference/x-carousel-screenshot.png`) |
| X single | `1.778 full` |
| IG carousel | `1.778 full` (first image 1.778 is within 4:5…1.91:1) |
| IG grid 3:4 | `0.750 crop 58%` |

Passing one image should give an X carousel column equal to the X single column (one image uses the single-image rule). Passing five images should show posts `1 1 1 1 2`, with the fifth image using the single-image rule.

Every row was verified for both input images by re-reading each written image through ImageIO and comparing its pixel width and height to the catalogue target.

## App bundle

```sh
./build.sh
lipo -archs Matte.app/Contents/MacOS/Matte
codesign --verify --deep --strict --verbose=2 Matte.app
```

Observed:

| Check | Result |
| --- | --- |
| Release build | `Build succeeded` |
| Bundle output | `Matte.app` produced |
| Architectures | `x86_64 arm64` |
| Signature | Valid on disk; satisfies its designated requirement |
| Info.plist executable | `Matte` |
| Executable file | Universal Mach-O present and executable at `Matte.app/Contents/MacOS/Matte` |

## Icon

```sh
scripts/make-icon.sh
ls Icon/AppIcon.iconset
```

Expected: ten PNGs (`icon_16x16.png` … `icon_512x512@2x.png`), `Icon/AppIcon.icns` and a 1024×1024 `Icon/preview.png`. `build.sh` regenerates the icon automatically when `Icon/AppIcon.icns` is missing or older than `scripts/make-icon.swift`.

## UI launch hooks (v0.2)

The app reads these environment variables at launch, for screenshots and scripted checks:

| Variable | Effect |
| --- | --- |
| `MATTE_OPEN=a.png:b.png` | Preload images (colon-separated; folders are expanded). |
| `MATTE_SELECT=all` or `0,2` | Select all images, or these indices (in that selection order), once loading finishes. |
| `MATTE_FORMATS=id,id` or `all` | Check these formats for this run (not saved). |
| `MATTE_FORMAT=id` | Inspected format for the context preview. |
| `MATTE_TAB=formats` or `simulate` | Main panel tab. |
| `MATTE_COLORPANEL=1` | Opens the custom colour picker (the system colour panel) after launch; the Custom swatch shows its active ring. |
| `MATTE_SETTINGS=1` | Opens the Settings window on launch. |
| `MATTE_SNAPSHOT=out.png` | After 3 s, writes a PNG of the main window (the Settings window when `MATTE_SETTINGS=1`) via `cacheDisplay(in:to:)`, then quits. |
| `MATTE_SNAPSHOT_SIZE=1280x820` | Resizes the main window before the snapshot. |

Example screenshots:

```sh
APP=Matte.app/Contents/MacOS/Matte
S="$PWD/samples"
MATTE_OPEN="$S/sample-1920x1080.png:$S/sample-dark-1920x1080.png" MATTE_SELECT=all \
  MATTE_FORMATS=x-carousel-45,ig-feed-45 MATTE_SNAPSHOT_SIZE=1280x820 MATTE_SNAPSHOT=out/formats.png $APP
MATTE_OPEN="$S/sample-1920x1080.png:$S/sample-dark-1920x1080.png" MATTE_SELECT=1,0 \
  MATTE_TAB=simulate MATTE_SNAPSHOT=out/simulate.png $APP
MATTE_SETTINGS=1 MATTE_SNAPSHOT=out/settings.png $APP
MATTE_OPEN="$S/sample-1920x1080.png" MATTE_COLORPANEL=1 MATTE_SNAPSHOT=out/colour.png $APP
```

Manual checklist:

- First launch (or `defaults delete local.matte checkedFormats`): no images selected, no formats checked; the Export button is disabled with "Select at least one image", then "Pick at least one format".
- Click, ⌘-click, ⇧-click, ⌘A (outside the hex field) and Esc behave as described; selected rows show the blue tint, ring and checkmark; hover is distinct.
- The Export label reads `Export N × M = T files`; exporting into a folder that already holds those files, or more than 40 files, shows the confirmation sheet; Cancel in the progress bar stops after the current file.
- Exporting 1 image × 1 format writes `<output folder>/<name>__<format>_<w>x<h>.png` directly (no subfolder) and Reveal selects that file; 1 × 2 or 2 × 1 creates one subfolder per image. The watched folder follows the same rule inside `<watched>/Matte`.
- Dragging the padding slider and switching colours stays smooth; previews update about 80 ms after you stop.
- Eyedropper: Esc cancels without changing the colour. Custom swatch: the system colour panel updates the frame live; closing it adds the colour to Recent.
- Simulate tab: X post with five selected images shows the red "X allows 4 images per post" note and two posts; the Original / Matte export toggle changes tiles and crop badges.
- Settings (⌘,): General and Watched folder tabs; the main window has no watched-folder controls.

## Launch check

The required commands were attempted:

```sh
open Matte.app
pgrep -x Matte
```

The managed execution environment blocked the OS services needed for this check: LaunchServices returned `kLSNoExecutableErr` even though the executable is present, executable, universal, correctly named in `Info.plist`, and the bundle passes strict code-sign verification. `pgrep` separately returned `sysmond service not found` / `Cannot get process list`. A direct binary invocation is also prevented from establishing a GUI session here. This is the only unverified test; it is an execution-sandbox limitation rather than a bundle validation failure.

On a normal interactive macOS session, repeat:

```sh
open Matte.app
pgrep -x Matte
osascript -e 'tell application "Matte" to quit'
```
