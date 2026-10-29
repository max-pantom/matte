# Matte — build spec (working name was "frame-fit")

A small, free, open-source native macOS app (SwiftUI + AppKit, Swift Package Manager, NO Xcode project).
User: a designer who makes wide canvases (typically 1920x1080) and needs them ready for X and Instagram.
Name: **Matte** (the border around a framed picture). Bundle id `local.matte`, product `Matte`, macOS 14+.

## Repo layout (mirror ~/Desktop/code/volboost)
- `Package.swift` (swift-tools-version 6.0, platforms .macOS("14.0")):
  - `.target(name: "MatteCore")` — pure fit/format/render logic (CoreGraphics + ImageIO only, no AppKit/SwiftUI) so it can be tested headless.
  - `.executableTarget(name: "Matte", dependencies: ["MatteCore"])` — the app.
  - `.executableTarget(name: "matte-cli", dependencies: ["MatteCore"])` — headless CLI (plain executable, not XCTest, so it runs with only Command Line Tools).
- `Info.plist`, `build.sh` (copy VolBoost's: universal arm64+x86_64 release build, assemble `Matte.app`, PlistBuddy VERSION stamp, ad-hoc `codesign --force --sign -`, `ZIP=1` writes `Matte.zip` via `ditto -c -k --keepParent`). If a universal build fails on this machine, fall back to native arch only. No LSUIElement (it's a normal Dock app).
- `Icon/AppIcon.icns` — generate a simple icon programmatically (a script `scripts/make-icon.swift` that draws a white rounded "matte" frame around a dark 16:9 rectangle on black, writes iconset PNGs, then `iconutil`). Also `Icon/preview.png` (256px) for the README.
- `LICENSE` (MIT, "Copyright (c) 2026 Matte contributors"), `README.md` in VolBoost's style (centered icon, h1, tagline, screenshot, Download link `https://github.com/max-pantom/matte/releases/latest/download/Matte.zip`, Gatekeeper/xattr note, Features, Requirements, Build and run, How it works, a "Format specs and sources" table — see bottom), `.gitignore` (.build, *.app, *.zip, out/).

## Formats (MatteCore/Formats.swift) — exact output pixel sizes
X:
| id | name | size | note |
|---|---|---|---|
| x-landscape | X post, landscape 16:9 | 1600x900 | single image, shown in full |
| x-square | X post, square 1:1 | 1080x1080 | |
| x-portrait-45 | X post, portrait 4:5 | 1080x1350 | |
| x-portrait-34 | X post, portrait 3:4 | 1080x1440 | tallest ratio X shows uncropped |
| x-grid-2 | X 2-image grid tile 7:8 | 700x800 | each of 2 side-by-side tiles |
| x-grid-3-lead | X 3-image grid, lead tile 7:8 | 700x800 | left large tile |
| x-grid-3-side | X 3-image grid, side tile 16:9 | 1200x675 | two stacked right tiles |
| x-grid-4 | X 4-image grid tile 16:9 | 1200x675 | 2x2 grid |
| x-header | X header 3:1 | 1500x500 | ~60px top/bottom may crop; avatar covers lower-left |
| x-article | X Article cover 5:2 | 2000x800 | |
Instagram:
| ig-feed-45 | IG feed portrait 4:5 | 1080x1350 | works via scheduling/API too |
| ig-square | IG square 1:1 | 1080x1080 | |
| ig-grid-34 | IG portrait 3:4 (profile grid tile) | 1080x1440 | profile grid shows posts as 3:4 |
| ig-story | IG stories / reels 9:16 | 1080x1920 | keep ~14% top / 35% bottom free (UI overlays) |
Each format has: id, platform (X / Instagram), name, width, height, ratio label, a `safeInsets` (fractions, optional, used for overlay in preview: header top/bottom 60/500, header avatar lower-left; story 14% top 35% bottom 6% sides), and a `previewKind` for the mock (xFeedSingle, xGrid2, xGrid3Lead, xGrid3Side, xGrid4, xHeader, xArticle, igFeed, igGrid, igStory).

## Fit logic (port of fit.py, MatteCore/Fit.swift)
Prototype:
```
bg(im): most common colour among pixels sampled every 8px along the top and bottom rows
frame(src,W,H,pad=0.06): canvas W×H filled with colour; s = min(W*(1-2pad)/w, H*(1-2pad)/h); resize (high-quality) and centre-paste
```
Port that, extended:
- `Verdict` for (imageSize, format): compare aspect ratios with tolerance 1% (relative): equal → `.perfect` ("Perfect as is" — just resize to exact size; if source is smaller than target, note "upscaled"). Otherwise → `.needsFrame` ("Needs a frame"). Also compute `cropLoss` = fraction of the image area lost by a centre fill-crop; if cropLoss <= 0.15 the verdict text is "Needs a frame (or a light crop)" and crop is recommended as alternative; if mode is set to crop, verdict reads "Needs a crop (loses N%)". Expose: verdict enum, human label, cropLoss percent, scale factor.
- `Mode`: `.fit` (frame/letterbox, default), `.fill` (centre crop to exact size, with optional focal point x/y 0..1 default 0.5).
- `padding`: 0..30% (default 6%, per-side fraction of the target's min(width,height)... keep fit.py semantics: fraction of W horizontally and H vertically). Also padding 0 must be allowed (pure letterbox). When verdict is perfect and pad>0, it's still framed with padding (user choice); "Perfect as is" exports with pad 0 unless the user enables "Always pad".
- Frame colour is independent of the image: `FrameColor` = explicit RGBA. Helper `autoMatchEdges(image) -> color` = fit.py's bg() but sample all four edges, every 8px, quantize to 4 bits/channel for the mode, return the average of the pixels in the winning bucket.
- Render with CoreGraphics: sRGB CGContext of exactly W×H, fill colour, draw image with `.high` interpolation into the rounded rect (round origin and size to ints). Optional corner radius on the placed design (0 default) and optional soft shadow (off default) — nice to have, skip if time.
- Export: PNG (default) or JPEG quality 0.92, via ImageIO. Filename `<basename>__<format-id>_<W>x<H>.png` into an output folder (default `~/Desktop/Matte Exports/<basename>/`). Output must be EXACTLY W×H pixels (no Retina @2x scaling — use CGContext with explicit pixel size, not NSImage drawing).

## CLI (matte-cli)
`matte-cli <images...> [--out DIR] [--formats all|id,id] [--pad 0.06] [--mode fit|fill] [--color #RRGGBB|auto] [--jpeg]`
Prints per image: source WxH and ratio, then for each format: id, target WxH, verdict label, then writes files and prints `wrote path WxH`. After writing, it re-reads each file with ImageIO and asserts the pixel size equals the target; exit non-zero on mismatch. Also `matte-cli --list` prints the format table.

## App UI — follow INTERFERE-DESIGN.md (dark, quiet, tool-like)
Translate the web tokens to SwiftUI: shell #000, panel #111 with radius 16 and 0.5px inset hairline (white 7% / #ffffff12), cards #ffffff09 r12, controls 13pt medium, fg white 93%/69%/39%, brand #0090ff for selection/focus only, primary button inverted (white bg black text), badges 20px r4 with a 6px dot: positive green (#30a46c dot, bg #22ff991e, fg #46fea5d4) for "Perfect as is", warning orange (#f76b15, bg #fb6a0025, fg #ffa057) for "Needs a frame", danger-ish tomato (#e54d2e, bg #ff35232b, fg #ff977d) for "Needs a crop". Sentence case, no emoji. Font: try to register bundled InterVariable (Resources; CTFontManagerRegisterFontsForURL — woff2 may not load; then fall back to system font). Force dark appearance. Window min 1100x720, hidden title bar / full-size content.
Layout:
- Left sidebar 260px (#000): "Matte" wordmark; "Images" list (thumbnails 40px, filename, `1920×1080 · 16:9` in mono, remove button) — drop zone when empty ("Drop images here" / "or click to choose", NSOpenPanel multi-select, accepts png/jpg/jpeg/heic/tiff/webp). Dropping anywhere on the window adds images (batch).
  Below: "Watched folder" section: toggle + folder path + choose button (see below).
- Main panel (#111, r16): header with selected image name + "1920×1080 · 16:9" and actions on the right: "Export selected" (inverted primary), "Export all images" (secondary).
  Content: a grid of format cards grouped by platform ("X", "Instagram") with an underline/segmented tab "All / X / Instagram". Each card: checkbox to include in export, format name, `1600×900 · 16:9` mono caption, verdict badge, and a live preview thumbnail of the actual rendered output (render at reduced size async, cache). Clicking a card opens a larger preview in a right inspector pane showing the in-context mock (below).
- Right inspector 300px: "Frame" section: mode segmented (Fit with frame / Crop to fill), Padding slider 0–30% with % readout, "Always pad perfect fits" toggle; "Colour" section: preset swatches White #FFFFFF, Off-white #F4F1EA, Black #000000, plus a few (Paper #FAFAF7, Ink #111111), a ColorPicker (custom), an eyedropper button using `NSColorSampler().show { }` to pick any colour on screen, and an "Auto-match edges" toggle (when on, colour = autoMatchEdges(image) per image; when off, the chosen colour). Show the current hex in mono, editable text field. "Export" section: format PNG/JPEG segmented, output folder chooser, "Reveal in Finder" after export. Then the "Preview in context" mock for the selected format.
- In-context previews (nice to have, keep them simple shapes drawn in SwiftUI): X feed post (avatar circle, name lines, the image in a rounded 16:9-ish media box with r16, action icons row), X 2/3/4 grids (render the same image repeated in the grid layout, highlight the tile this format represents), X header (header strip with the avatar circle overlapping lower-left, and 60px top/bottom crop bands dimmed), X Article (cover strip over title lines), IG feed (square-ish post with header and actions), IG profile grid (3 columns of 3:4 tiles, the image in the first tile, others grey), IG story (phone 9:16 frame with top/bottom overlay zones dimmed).
- Export shows a toast bottom-right "Exported 14 files" with a "Reveal" action.

## Watched folder (mirror Koi's pattern: a persisted folder list, a file-system watcher, debounce, process new files)
Optional, off by default. User picks a folder (persist via UserDefaults bookmark/path). Use DispatchSource / FSEvents (FSEventStreamCreate) to watch it; debounce 0.5s; when a new image file appears (and its size is stable for 2 consecutive checks), auto-export the currently checked formats with the current settings to `<watched>/Matte/<basename>/`. Ignore files inside the output subfolder and files we wrote. Show a small status line "Watching ~/Desktop/Shots · 3 exported".

## Persist settings
padding, mode, colour, autoMatch, checked formats, output folder, file type, watched folder → UserDefaults.

## Testing required (do it, don't skip)
1. `swift build` must succeed with zero errors (fix warnings that are trivial).
2. `swift run -c release matte-cli sample-1920x1080.png sample-dark-1920x1080.png --out out/test --formats all` must write 28 files and each must verify at its exact size. Also run once with `--mode fill --color auto` and once with `--pad 0`.
3. `./build.sh` must produce `Matte.app` that launches (`open Matte.app`; check it's running with `pgrep -x Matte`, then quit it).
4. Write TESTING.md with the commands and the observed output table.

## README "Format specs and sources" (verified 29 Oct 2026)
- X post images: X Help Center "How to post photos and GIFs" — ratios between 2:1 and 3:4 are shown in full, up to 4 photos, JPEG/PNG/GIF up to 5 MB, no official pixel size. 1600x900 is the common 16:9 recommendation (socialctl.io/specs/x/image, checked Sept 2026; michaeldishmon.com/writing/twitter-x-image-sizes).
- X multi-image grids: not documented by X; community-measured: 2 images → two 7:8 tiles (700x800); 3 images → lead 7:8 tile + two stacked 16:9 tiles; 4 images → 2x2 of 16:9 (1200x675). Sources: tendx.app/tools/x-image-sizes, zsky.ai, michaeldishmon.com. (tendX lists the 3-up side tiles as ~4:7; we use the geometric 16:9 halves of a 16:9 grid — treat as approximate.)
- X header: 1500x500 recommended, up to 60px top/bottom can be cropped — X Help Center "Help with profile photo upload" (via freedam.io/guide/social-media-image-sizes, read 25 Oct 2026; github.com/chuckreynolds/social-profile-image-sizes, verified 6 Oct 2026).
- X Article cover: X publishes no pixel size; the Articles editor crops covers to 5:2 (note.com/swwwitch report; posteverywhere.ai recommends 2000x800; chuckreynolds lists 5:2 e.g. 1000x400 [unpublished]). One Medium guide claims 5.2:1 (1920x368) from live testing — outlier, not adopted. We export 2000x800 (5:2).
- Instagram: Instagram Help Center "Image resolution of photos you share on Instagram" — up to 1080 wide, ratios 1.91:1 to 3:4 kept (height 566–1440). Feed 4:5 1080x1350 also the max for API/scheduled posts (IG Graph API "IG User Media"). Profile grid shows 3:4 tiles since early 2025 (dmfast.app/sizes/instagram-grid-thumbnail-size, checked 6 Oct 2026). Stories/Reels 9:16 1080x1920 (Meta developer docs / Meta Ads Guide safe zones 14% top, 35% bottom, 6% sides).
