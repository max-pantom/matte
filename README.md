<p align="center">
  <img src="Icon/preview.png" width="128" alt="Matte icon">
</p>

<h1 align="center">Matte</h1>

<p align="center">Fit one design to every X and Instagram image format, without giving up control of the frame.</p>

Matte is a free, native macOS batch exporter for designers who work from a wide master canvas. It renders exact-pixel PNG or JPEG files for 14 current X and Instagram placements, with a frame, crop, custom colour, or automatically matched edge colour.


![Matte](docs/screenshot.png)

## Download

**[Download Matte.zip](https://github.com/max-pantom/matte/releases/latest/download/Matte.zip)** — universal Apple silicon and Intel build, macOS 14+.

1. Unzip and drag **Matte.app** into Applications.
2. Matte is ad-hoc signed but not notarized. If macOS blocks its first launch, use **System Settings › Privacy & Security › Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Matte.app`.
3. Drop one or more images into the window, choose formats, then export.

## Features

- 14 exact-size X and Instagram formats, including multi-image tiles, header, Article cover, profile grid, and stories
- Fit with a frame or centre-crop to fill, with 0–30% padding
- White, off-white, black, paper, ink, custom, eyedropper, and automatic edge-matched colours
- Live output previews and simple in-context social previews
- Batch export to PNG or JPEG, with every written file re-read and pixel-verified
- Optional watched folder that exports new stable image files automatically
- Native SwiftUI interface, no account, analytics, network access, or Xcode project

## Requirements

- macOS 14 or later
- Swift 6.0+ to build; Xcode Command Line Tools are sufficient

## Build and run

```sh
./build.sh
open Matte.app
```

`build.sh` prefers a universal arm64/x86_64 release build and falls back to the native architecture when a universal SDK is unavailable. It assembles and ad-hoc signs `Matte.app`; `ZIP=1 ./build.sh` also creates `Matte.zip`.

The headless exporter uses the same rendering core:

```sh
swift run -c release matte-cli samples/sample-1920x1080.png \
  --out out/example --formats all --pad 0.06 --mode fit --color auto
```

Run `swift run matte-cli --list` for the full format table.

## How it works

Matte decodes each source with ImageIO and renders directly into an sRGB CoreGraphics context whose dimensions are the target pixel dimensions. Fit mode scales the design within the selected padding and centres it on the matte. Fill mode scales past the edges and centre-crops. Automatic colour sampling reads every eighth pixel along all four edges, groups colours into four-bit RGB buckets, and averages the winning group.

Exports never use `NSImage` drawing or display scale, so a 1080×1350 target is exactly 1080×1350 pixels on both Retina and non-Retina Macs. Each file is opened again after writing and rejected if its dimensions differ.

| Path | What |
| --- | --- |
| `Sources/MatteCore/Formats.swift` | Format catalogue and preview metadata |
| `Sources/MatteCore/Fit.swift` | Verdict, frame/crop maths, settings models |
| `Sources/MatteCore/Renderer.swift` | ImageIO loading, edge matching, CoreGraphics rendering and verified export |
| `Sources/Matte/` | SwiftUI app, persistence, watched folder and export workflow |
| `Sources/matte-cli/main.swift` | Headless batch exporter and verification CLI |
| `scripts/make-icon.swift` | Programmatic app icon generator |

## Format specs and sources

Sources were verified on 29 October 2026. Where a platform does not publish exact pixels, Matte labels the size as a practical recommendation or community-measured approximation.

| Format | Output | Basis and sources |
| --- | ---: | --- |
| X post, landscape | 1600×900 | X Help Center, “How to post photos and GIFs,” documents ratios from 2:1 through 3:4, up to four images, and JPEG/PNG/GIF up to 5 MB, but no official pixels. 1600×900 is a common 16:9 recommendation from socialctl.io/specs/x/image (checked September 2026) and michaeldishmon.com/writing/twitter-x-image-sizes. |
| X post, square / portrait | 1080×1080, 1080×1350, 1080×1440 | The same official 2:1–3:4 full-display range; 3:4 is its tallest endpoint. |
| X 2-image grid | 700×800 per tile | X does not document grid pixels. Community-measured 7:8 side-by-side tiles: tendx.app/tools/x-image-sizes, zsky.ai, and michaeldishmon.com. |
| X 3-image grid | 700×800 lead; 1200×675 side | Community-measured lead 7:8 plus two stacked side tiles. tendX describes side tiles near 4:7; Matte uses geometric 16:9 halves of a 16:9 grid, so this is approximate. |
| X 4-image grid | 1200×675 per tile | Community-measured 2×2 16:9 tiles from the sources above; approximate. |
| X header | 1500×500 | X Help Center, “Help with profile photo upload,” via freedam.io/guide/social-media-image-sizes (read 25 October 2026) and github.com/chuckreynolds/social-profile-image-sizes (verified 6 October 2026). Up to about 60 px top and bottom may crop. |
| X Article cover | 2000×800 | X publishes no pixels. Live reports show a 5:2 crop (note.com/swwwitch); posteverywhere.ai recommends 2000×800 and chuckreynolds lists 5:2 examples. A reported 5.2:1 result is treated as an outlier. |
| Instagram feed 4:5 / square | 1080×1350, 1080×1080 | Instagram Help Center, “Image resolution of photos you share on Instagram,” preserves 1.91:1 through 3:4 at up to 1080 wide. 4:5 is also the maximum portrait ratio for API/scheduled posts in the Instagram Graph API “IG User Media” documentation. |
| Instagram profile grid | 1080×1440 | Profile grids have displayed 3:4 tiles since early 2025; dmfast.app/sizes/instagram-grid-thumbnail-size, checked 6 October 2026. |
| Instagram stories / reels | 1080×1920 | Meta developer documentation and Meta Ads Guide: 9:16, with practical safe zones of about 14% top, 35% bottom, and 6% at the sides for overlays. |

## Testing

See [TESTING.md](TESTING.md) for reproducible build, export, pixel-verification, bundle, and launch checks.

## License

[MIT](LICENSE). Matte is not affiliated with X Corp. or Meta Platforms, Inc.
