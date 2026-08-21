# Lerni App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the LearnPath app's placeholder (Moneylock-branded) icon with a brain-themed "Lerni" icon.

**Architecture:** A standalone Swift script renders a 1024×1024 master PNG using AppKit/CoreGraphics (indigo→violet gradient background, Apple's `brain.fill` SF Symbol in white, "Lerni" wordmark). `sips` slices that master into the 15 files the existing classic iconset `Contents.json` already expects, replacing the current placeholder set in place — no `Contents.json`, pbxproj, or project.yml changes needed.

**Tech Stack:** Swift (AppKit/CoreGraphics, run via `swift <file>.swift`), `sips` — both already available via the installed Xcode toolchain, no new dependencies.

## Global Constraints

- Master icon must be exactly 1024×1024 pixels with **no alpha channel** (App Store icon requirement — confirmed via `sips -g hasAlpha`).
- Output files must exactly match the filenames already referenced in `Learn-App/LearnPath/Assets.xcassets/AppIcon.appiconset/Contents.json` (do not rename).
- Background: diagonal gradient, deep indigo `#3730A3` (top-left) → violet `#7C3AED` (bottom-right), per the approved spec `docs/superpowers/specs/2026-08-21-lerni-icon-design.md`.
- Mark: white, using Apple's `brain.fill` SF Symbol (confirmed available on this system).
- Wordmark: "Lerni", bold white sans-serif, centered in the lower third.

---

### Task 1: Add the icon-generation script

**Files:**
- Create: `tools/generate_lerni_icon.swift`

**Interfaces:**
- Produces: `/tmp/lerni-icon.png` (1024×1024, no-alpha PNG) when run via `swift tools/generate_lerni_icon.swift`

- [ ] **Step 1: Write the script**

```swift
import AppKit

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("failed to create bitmap") }

NSGraphicsContext.saveGraphicsState()
guard let gc = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("failed to create graphics context") }
NSGraphicsContext.current = gc
let ctx = gc.cgContext

// Background: diagonal gradient, deep indigo -> violet
let colors = [
    NSColor(calibratedRed: 0x37/255.0, green: 0x30/255.0, blue: 0xA3/255.0, alpha: 1).cgColor,
    NSColor(calibratedRed: 0x7C/255.0, green: 0x3A/255.0, blue: 0xED/255.0, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                        start: CGPoint(x: 0, y: CGFloat(size)),
                        end: CGPoint(x: CGFloat(size), y: 0),
                        options: [])

// Brain mark: Apple's own "brain.fill" SF Symbol, tinted white — a real,
// professionally drawn brain glyph beats hand-rolled bezier anatomy.
let cx = CGFloat(size) / 2
let sizeConfig = NSImage.SymbolConfiguration(pointSize: 500, weight: .regular)
let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.white])
let symbolConfig = sizeConfig.applying(colorConfig)
guard let brainSymbol = NSImage(systemSymbolName: "brain.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) else {
    fatalError("brain.fill SF Symbol not available")
}
let brainSize = brainSymbol.size
let brainCenterY: CGFloat = 640
let brainRect = NSRect(x: cx - brainSize.width / 2, y: brainCenterY - brainSize.height / 2,
                        width: brainSize.width, height: brainSize.height)
brainSymbol.draw(in: brainRect, from: .zero, operation: .sourceOver, fraction: 1.0)

// Wordmark: "Lerni" in bold white sans-serif, lower third.
let text = "Lerni"
let font = NSFont.systemFont(ofSize: 190, weight: .bold)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
let attrString = NSAttributedString(string: text, attributes: attrs)
let textSize = attrString.size()
let textRect = NSRect(x: cx - textSize.width / 2, y: 190, width: textSize.width, height: textSize.height)
attrString.draw(in: textRect)

NSGraphicsContext.restoreGraphicsState()

// Flatten onto an opaque, alpha-free bitmap — App Store icons must not carry
// an alpha channel even when every pixel is already fully opaque.
guard let sourceImage = bitmap.cgImage else { fatalError("failed to get CGImage") }
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let flatCtx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("failed to create flat context") }
flatCtx.draw(sourceImage, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let flatImage = flatCtx.makeImage() else { fatalError("failed to flatten image") }
let flatBitmap = NSBitmapImageRep(cgImage: flatImage)

guard let png = flatBitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: "/tmp/lerni-icon.png"))
print("wrote /tmp/lerni-icon.png")
```

- [ ] **Step 2: Run it and verify output**

Run: `swift tools/generate_lerni_icon.swift && sips -g pixelWidth -g pixelHeight -g hasAlpha /tmp/lerni-icon.png`
Expected: `pixelWidth: 1024`, `pixelHeight: 1024`, `hasAlpha: no`

- [ ] **Step 3: Visually verify the render**

Read `/tmp/lerni-icon.png` (e.g. via the Read tool) and confirm: gradient background, white brain silhouette in the upper ~55%, "Lerni" wordmark in the lower third, no clipping at the edges.

- [ ] **Step 4: Commit**

```bash
git add tools/generate_lerni_icon.swift
git commit -m "feat: add Lerni app icon generation script"
```

---

### Task 2: Replace the AppIcon.appiconset PNGs

**Files:**
- Modify (replace contents, same filenames): all 15 PNGs in `Learn-App/LearnPath/Assets.xcassets/AppIcon.appiconset/`

**Interfaces:**
- Consumes: `/tmp/lerni-icon.png` (from Task 1)
- Produces: 15 correctly-sized PNGs at the exact filenames `Learn-App/LearnPath/Assets.xcassets/AppIcon.appiconset/Contents.json` already references (no `Contents.json` edit needed)

- [ ] **Step 1: Slice the master into all required sizes**

Run from `Learn-App/`:

```bash
ICONDIR=LearnPath/Assets.xcassets/AppIcon.appiconset
SRC=/tmp/lerni-icon.png
sips -Z 40   "$SRC" --out "$ICONDIR/Icon-App-20x20@2x.png" >/dev/null
sips -Z 60   "$SRC" --out "$ICONDIR/Icon-App-20x20@3x.png" >/dev/null
sips -Z 29   "$SRC" --out "$ICONDIR/Icon-App-29x29@1x.png" >/dev/null
sips -Z 58   "$SRC" --out "$ICONDIR/Icon-App-29x29@2x.png" >/dev/null
sips -Z 87   "$SRC" --out "$ICONDIR/Icon-App-29x29@3x.png" >/dev/null
sips -Z 80   "$SRC" --out "$ICONDIR/Icon-App-40x40@2x.png" >/dev/null
sips -Z 120  "$SRC" --out "$ICONDIR/Icon-App-40x40@3x.png" >/dev/null
sips -Z 120  "$SRC" --out "$ICONDIR/Icon-App-60x60@2x.png" >/dev/null
sips -Z 180  "$SRC" --out "$ICONDIR/Icon-App-60x60@3x.png" >/dev/null
sips -Z 20   "$SRC" --out "$ICONDIR/Icon-App-20x20@1x.png" >/dev/null
sips -Z 40   "$SRC" --out "$ICONDIR/Icon-App-40x40@1x.png" >/dev/null
sips -Z 76   "$SRC" --out "$ICONDIR/Icon-App-76x76@1x.png" >/dev/null
sips -Z 152  "$SRC" --out "$ICONDIR/Icon-App-76x76@2x.png" >/dev/null
sips -Z 167  "$SRC" --out "$ICONDIR/Icon-App-83.5x83.5@2x.png" >/dev/null
cp "$SRC" "$ICONDIR/Icon-App-1024x1024@1x.png"
```

- [ ] **Step 2: Verify all 15 filenames are present and correctly sized**

Run: `for f in LearnPath/Assets.xcassets/AppIcon.appiconset/*.png; do echo "$f: $(sips -g pixelWidth "$f" | tail -1)"; done`
Expected: 15 lines, sizes matching each filename's `@Nx` scale of its base point size (e.g. `Icon-App-60x60@3x.png: pixelWidth: 180`).

- [ ] **Step 3: Rebuild and archive-verify the icon compiles correctly**

Run (from `Learn-App/`):
```bash
xcodegen generate
rm -rf /tmp/lerni-archive-check /tmp/lerni-dd
xcodebuild -project LearnPath.xcodeproj -scheme LearnPath -configuration Release \
  -destination "generic/platform=iOS" -derivedDataPath /tmp/lerni-dd \
  -archivePath /tmp/lerni-archive-check/LearnPath.xcarchive archive CODE_SIGNING_ALLOWED=NO
xcrun assetutil --info /tmp/lerni-archive-check/LearnPath.xcarchive/Products/Applications/LearnPath.app/Assets.car | grep -E '"Idiom"|"PixelWidth"' | paste - -
```
Expected: `** ARCHIVE SUCCEEDED **`, and the `assetutil` output lists renditions including phone/120, phone/180, pad/152, pad/167 (same set verified during the earlier App Store Connect icon fix).

- [ ] **Step 4: Clean up scratch build artifacts**

```bash
rm -rf /tmp/lerni-archive-check /tmp/lerni-dd /tmp/lerni-icon*.png
```

- [ ] **Step 5: Commit**

```bash
git add LearnPath/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat: replace placeholder app icon with Lerni brain mark"
```
