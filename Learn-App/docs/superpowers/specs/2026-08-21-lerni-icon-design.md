# Lerni app icon redesign

## Problem

`Learn-App/LearnPath/Assets.xcassets/AppIcon.appiconset/` currently uses a
placeholder icon generated from `tools/generate_app_icon.py` — a red
padlock design that was originally built for the separate Moneylock
finance app (`app/`). It doesn't represent this education app at all, and
the user asked for a proper icon: a brain, with the "Lerni" wordmark.

## Design

1024×1024 master icon:

- **Background:** diagonal gradient, deep indigo (`#3730A3`, top-left) to
  violet (`#7C3AED`, bottom-right).
- **Mark:** solid white filled brain silhouette (two hemisphere lobes with
  a few simple wrinkle grooves), centered in the upper ~55% of the canvas.
- **Wordmark:** "Lerni" in bold white sans-serif, centered in the lower
  ~25%, sized for legibility at small home-screen icon sizes.

Known risk: text on an app icon is hard to read at the smallest iOS
render size. Mitigated by bold weight and high contrast; if it still
reads as mud in practice, the fallback is to drop the wordmark and ship
brain-only.

## Implementation approach

- Render the master PNG with a small Swift script using CoreGraphics
  (`CGContext`, system font rendering) — no new dependencies, reuses the
  already-installed Xcode toolchain. Avoids the raw-pixel-primitive
  approach `generate_app_icon.py` used, which can't render text or smooth
  curves.
- Slice the master into the same 15-file classic iconset (iPhone + iPad +
  ios-marketing idioms) already wired into
  `LearnPath/Assets.xcassets/AppIcon.appiconset/`, using `sips` exactly as
  done for the previous icon fix.
- Replace the existing 15 PNG files; `Contents.json` filenames stay
  the same, so no pbxproj/project.yml changes are needed — this is a
  content-only swap.

## Out of scope

- App display name change (`CFBundleDisplayName` stays "LearnPath" for
  now — a full "Lerni" rebrand, if wanted, is a separate decision the
  user hasn't made yet).
- The broader app content/English-audit request — tracked separately,
  not part of this icon change.
