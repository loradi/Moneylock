# Phase 2 — iOS validation evidence

Date: 2026-08-31

## Environment

- macOS 26.6.2 (Apple Silicon)
- Flutter 3.47.0 / Dart 3.13.0
- Xcode 26.6 (17F113)
- Swift Package Manager enabled
- Simulator: iPhone 17, iOS 26.5
- Free disk before validation: 25 GB

No physical iPhone was connected. The available iPhone and iPad reported by
network discovery were unavailable because they were not unlocked, cabled, or
connected with Developer Mode.

## Validation matrix

| Area | Evidence | Result |
|---|---|---|
| Static analysis | `flutter analyze` | PASS — no issues |
| Flutter regression suite | `flutter test --reporter compact --timeout 2m` | PASS — 194 tests |
| Backend regression suite | `pytest -q` from `backend/` | PASS — 3 tests |
| Device release build | `flutter build ios --release --no-codesign` | PASS — `Runner.app`, 34.7 MB |
| Simulator build | `flutter build ios --simulator --debug` | PASS |
| Simulator install/launch | `simctl install` + `simctl launch` | PASS |
| First launch | Native notification prompt followed by Flutter onboarding | PASS |
| Warm deep link | `moneylock://add?amount=45.50&merchant=Phase2Cafe` | PASS — persisted with `source=shortcut` |
| Cold deep link after fix | `moneylock://add?amount=67.89&merchant=Phase2Fixed` | PASS — exactly one SQLite row |
| Offline persistence | terminate, relaunch, query SQLite | PASS — transaction retained |
| Model endpoint | HTTP HEAD and one-byte Range request | PASS — 2,104,932,768 bytes, HTTP 206 range support |
| Simulator model asset | Full Qwen GGUF in Moneylock Application Support | PASS — 2,104,932,768 bytes; SHA-256 matches the published linked ETag |
| Deep-link coverage | `flutter test --coverage test/shortcut_url_test.dart` | PASS — `deep_links.dart` 18/20 lines (90%) |

The launch and onboarding screenshots are stored outside the repository in the
Codex visualization directory for this task.

## Defect found and corrected

Opening a deep link while the app was terminated produced two identical
transactions. iOS delivered the same URI through both `getInitialLink()` and
`uriLinkStream`; because transaction deduplication includes the event timestamp,
the two asynchronous executions produced different hashes.

RED evidence:

- Simulator cold launch created two rows for one `ColdLinkCafe` URI.
- `shortcut_url_test.dart` reproduced two rows from simultaneous deliveries.
- Checkpoint: `fe0dce1 test: reproduce duplicate cold-start deep link`.

GREEN evidence:

- `DeepLinkHandler` now coalesces identical in-flight deliveries and repeats
  completed within a two-second window.
- Focused regression test passes.
- A second simulator cold-launch check created exactly one row.
- Checkpoint: `780f11a fix: coalesce duplicate deep link deliveries`.

Listener coverage evidence:

- The listener accepts injected initial-link and URI-stream sources for a
  deterministic regression test of the exact iOS delivery sequence.
- RED checkpoint: `2cc0056 test: cover initial and streamed deep link delivery`.
- GREEN checkpoint: `23d7a60 test: inject deep link sources for listener coverage`.

## Remaining physical-device checks

The following cannot be signed off from the simulator alone:

- Camera capture and Vision OCR against a real receipt.
- Microphone and on-device Apple Speech recognition.
- Download interruption/resume behavior through the app UI on a real device.
- Qwen inference latency, memory, thermal behavior, and battery impact.
- Local notification delivery while the app is backgrounded or terminated.
- Installation and launch of a signed archive on a real iPhone.

## Findings that do not block the simulator gate

- Notification permission is requested before `runApp`, so the system prompt is
  the first interactive experience, ahead of onboarding. Consider moving the
  request to onboarding or the notification setting before App Store review.
- Flutter reports 40 packages with newer versions outside current constraints;
  no dependency upgrade was attempted in this phase.

## Follow-up — 2026-09-01 model asset validation

After disk capacity was increased to 80 GB free, the complete official
`qwen2.5-3b-instruct-q4_k_m.gguf` asset was downloaded into Moneylock's
simulator Application Support `models/` directory, using a resumable transfer
to the `.part` path before it was promoted to its final filename.

- Local size: 2,104,932,768 bytes.
- Local SHA-256: `626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d`.
- Hugging Face `x-linked-size`: 2,104,932,768 bytes.
- Hugging Face `x-linked-etag`: `626b4a6678b86442240e33df819e00132d3ba7dddfe1cdc4fbb18e0a9615c62d`.

This proves the full model artifact can be obtained, stored where
`LlamaService` expects it, and recognized by its file-size readiness check. It
does not substitute for physical-device performance or interruption testing.
