# Testing

Observed on 29 October 2026 with Apple Swift 6.3.2 (`arm64-apple-macosx28.0`) and the macOS 26.5 SDK.

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

Each command ended with `Verified 28 outputs at exact pixel sizes.` Directory counts were 28, 28, and 28 respectively.

| Format | Expected pixels | Default fit | Fill + auto | Padding 0 |
| --- | ---: | :---: | :---: | :---: |
| x-landscape | 1600×900 | Pass | Pass | Pass |
| x-square | 1080×1080 | Pass | Pass | Pass |
| x-portrait-45 | 1080×1350 | Pass | Pass | Pass |
| x-portrait-34 | 1080×1440 | Pass | Pass | Pass |
| x-grid-2 | 700×800 | Pass | Pass | Pass |
| x-grid-3-lead | 700×800 | Pass | Pass | Pass |
| x-grid-3-side | 1200×675 | Pass | Pass | Pass |
| x-grid-4 | 1200×675 | Pass | Pass | Pass |
| x-header | 1500×500 | Pass | Pass | Pass |
| x-article | 2000×800 | Pass | Pass | Pass |
| ig-feed-45 | 1080×1350 | Pass | Pass | Pass |
| ig-square | 1080×1080 | Pass | Pass | Pass |
| ig-grid-34 | 1080×1440 | Pass | Pass | Pass |
| ig-story | 1080×1920 | Pass | Pass | Pass |

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
