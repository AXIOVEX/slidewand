# Implementation Plan: SlideWand — Baseline / Current State

**Branch**: `chore/speckit-onboarding` | **Date**: 2026-10-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-baseline-current-state/spec.md`

## Summary

This plan does not design new functionality. It records the as-built
architecture of the shipped v0.2.4 product so future specs have a stable
technical baseline, and it defines how the baseline's claims (spec.md
C-001…C-006) are checked. The product is a single native Swift macOS app:
camera frames → Vision hand pose + rectangle detection → pure gesture
engine → CGEvent arrow keys, plus a wand-calibration/tracking channel, a
live-tuned preferences store, and a keyless GitHub-releases self-updater.

## Technical Context

**Language/Version**: Swift 5 (`-swift-version 5` in CI), compiled with
`swiftc -O`; no package manager, no Xcode project — sources are the flat
`Sources/*.swift` set (9 files, ~2,373 lines at baseline).

**Primary Dependencies**: Apple frameworks only — AVFoundation (capture),
Vision (hand pose + rectangles), AppKit (UI), CoreGraphics (CGEvent keys),
QuartzCore (CI build flags). Zero third-party dependencies (Constitution II).

**Storage**: UserDefaults only — tuning parameters (`Tuning.swift`),
wand profile JSON under `wandProfile.v1` (`WandCalibration.swift`), and
the updater's `lastUpdateCheck` timestamp. No files, no database.

**Testing**: No test target exists in this repo at baseline. Recorded
coverage is: (a) the Python prototype's 21 gesture-logic tests (swipes,
holds, cooldowns, ambiguous poses) that `GestureEngine.swift` ports —
the tests themselves are not in this repo (gap G-001, tasks.md);
(b) the in-app Gesture Test window as the manual verification surface.

**Target Platform**: macOS 14.0+ (`Info.plist`), bundle
`com.slidewand.app`; primary dev target MacBook Air M1 / macOS 26.5.1;
release binaries universal (arm64 + x86_64) built on macos-15 runners.

**Project Type**: Desktop app (single binary, regular Dock app — not an
LSUIElement agent; see Constitution, Platform Constraints).

**Performance Goals**: Per-frame processing on the video queue
(`VisionHandTracker`); swipe recognition window 0.10–0.55 s; triggers are
single CGEvent key down/up pairs. No numeric latency SLO is recorded in
the repo at baseline — none is invented here.

**Constraints**: On-device only; the sole network path is the updater
(Constitution I). Accessibility trust is required for key synthesis to
reach other apps. Releases must use the persistent signing identity
(Constitution VI).

**Scale/Scope**: Single user, single camera, one tracked hand or wand;
9 source files listed in Project Structure below.

## Constitution Check

*GATE: baseline documentation — checked against the shipped code, not a
new design.*

- **I. On-Device Only** — PASS at baseline: only `Sources/Updater.swift`
  constructs remote URLs (github.com releases); camera frames stay in
  memory (`VisionHandTracker.latestBuffer`). Claim C-001.
- **II. Native, Dependency-Free** — PASS: imports across Sources are
  Foundation/AppKit/AVFoundation/Vision/CoreGraphics/ApplicationServices
  only.
- **III. Confident Gestures Only** — PASS: `SwipeDetector` speed/window
  gates, `HoldDetector` still-second, cooldown in the controller loop;
  ambiguous poses classify `.unknown` and never fire. Claims C-002/C-003.
- **IV. Pure, Testable Gesture Logic** — PARTIAL: `GestureEngine.swift`
  imports only Foundation and is framework-free as required, but the
  21 prototype tests are not present in-repo. Recorded as gap G-001 in
  tasks.md; the baseline does not claim this gate fully passes.
- **V. Works With Any Slideshow** — PASS: triggers are plain arrow keys
  (124/123) via CGEvent; no app-specific integration exists. Claim C-006.
- **VI. Permission Honesty** — PASS: blocked Accessibility is surfaced
  via banner/tray + walkthrough (`App.swift`, `KeySender.swift`); CI
  fails tag builds without the persistent signing secret. Claim C-005.

No violations requiring Complexity Tracking entries; the G-001 partial
is a documentation/test-presence gap, tracked in tasks.md, not a design
exception.

## Project Structure

### Documentation (this feature)

```text
specs/001-baseline-current-state/
├── spec.md              # Current-state specification + AEE claims
├── plan.md              # This file — as-built architecture baseline
└── tasks.md             # Baseline verification/documentation tasks
```

### Source Code (repository root, as built at v0.2.4)

```text
Sources/
├── main.swift             # Explicit delegate bootstrap (no @main synthesis)
├── App.swift              # AppDelegate, menus, preview, WandController,
│                          #   calibration + test + preferences windows (~1,623 lines)
├── VisionHandTracker.swift# AVCapture + Vision: 21 landmarks + rectangle
│                          #   wand candidates, per-joint last-good fallback
├── GestureEngine.swift    # Pure logic: classifyHand, SwipeDetector,
│                          #   HoldDetector (ports the 21-test Python prototype)
├── WandCalibration.swift  # Codable wand profile persisted in UserDefaults
├── Tuning.swift           # Live tuning parameters (UserDefaults)
├── KeySender.swift        # CGEvent arrow keys + Accessibility trust helpers
├── Updater.swift          # Keyless GitHub-releases check/download/install
└── Log.swift              # Minimal file/console logging

Info.plist                 # com.slidewand.app, v0.2.4, macOS 14.0 minimum
.github/workflows/build.yml# Tag-triggered universal build, persistent
                           #   signing, zip + GitHub release from RELEASE_NOTES.md
README.md                  # Install (4 steps), gestures, tuning, privacy
RELEASE_NOTES.md           # v0.1.0 → v0.2.4 history; release-notes source for CI
```

**Structure Decision**: The existing flat single-target layout is the
baseline. No restructuring is proposed by this plan; any future split
(e.g. extracting a test target for the engine) goes through its own spec.

## As-Built Data Flow

1. `VisionHandTracker` (video queue) runs `VNDetectHumanHandPoseRequest`
   and `VNDetectRectanglesRequest` per frame, delivering 21 normalized
   landmarks (x right, y down) and/or wand candidates on the main thread.
   Joints below confidence keep their last good position (v0.1.2) so
   fist-like wand grips still produce frames.
2. `WandController` (`App.swift`) picks the tracked point: wand tip when
   a calibrated wand matches (colour-track first, rectangle geometry as
   snap-to backup, v0.2.2), otherwise the palm centroid.
3. `GestureEngine` evaluates swipe (primary) and hold (secondary)
   detectors with live `Tuning` values; the controller enforces cooldown.
4. On a trigger, `KeySender.press` posts Right/Left arrow CGEvents to the
   focused app; without Accessibility trust macOS drops them and the UI
   shows the blocked state (FR-011).
5. Independently, `Updater` checks GitHub Releases on launch (6 h
   throttle) or on demand, and installs in place with relaunch.

## Complexity Tracking

No entries — the baseline introduces no new complexity and no
constitution violations beyond the G-001 partial noted above.
