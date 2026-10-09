# SlideWand Constitution

## Core Principles

### I. On-Device Only (NON-NEGOTIABLE)
All gesture processing MUST run on-device. The camera feed is processed in
memory and never saved, uploaded, or transmitted. The app's only permitted
network use is the self-updater checking GitHub releases
(`Sources/Updater.swift`: `github.com/AXIOVEX/slidewand/releases/latest`,
at most once per 6 hours automatically, plus manual checks). Any change that
adds another network call, a telemetry/analytics SDK, or a cloud dependency
violates this principle and requires a constitution amendment first.
Evidence: README "Privacy" section; `Info.plist` NSCameraUsageDescription.

### II. Native, Dependency-Free Swift
SlideWand is a single native macOS app in Swift with no third-party
dependencies: hand tracking uses Apple's Vision framework
(`VNDetectHumanHandPoseRequest`, 21 landmarks) in
`Sources/VisionHandTracker.swift`, capture uses AVFoundation, and key
synthesis uses CoreGraphics `CGEvent` in `Sources/KeySender.swift`.
New dependencies require explicit justification in the plan's Complexity
Tracking table; "no Python, no dependencies to install" (README) is a
product promise, not an implementation accident.

### III. Confident Gestures Only — No False Fires
Only confident gestures trigger a slide change. Ambiguous poses (pointing,
peace sign, relaxed hand) MUST do nothing. This is enforced by:
motion-based swipe detection with a minimum-speed gate and a sliding-window
check in `Sources/GestureEngine.swift` (`SwipeDetector`), pose holds that
fire only after a full still second (`HoldDetector`), and a cooldown
(default 1.0 s, `Sources/Tuning.swift`) so one wave cannot double-fire.
A change that loosens a gate must state its falsifier: a test or manual
protocol showing ambiguous/slow motion does not fire.

### IV. Pure, Testable Gesture Logic
The gesture engine (`Sources/GestureEngine.swift`) is framework-free pure
logic — a direct port of a Python prototype whose logic passed 21 unit
tests covering swipes, holds, cooldowns, and ambiguous poses (README;
goal record for the slidewand goal). Gesture-logic changes MUST keep that
separation (no Apple-framework imports in the engine) so the logic stays
independently testable, and MUST be accompanied by tests or a documented
test-window protocol covering the changed behaviour. The in-app Gesture
Test window (`Sources/App.swift`, TestWindowController) is the manual
verification surface: live hand state, NEXT/PREV flashes, counters, and a
timestamped event log.

### V. Works With Any Slideshow
Triggers are plain Right/Left arrow key presses (key codes 124/123 in
`Sources/KeySender.swift`), so SlideWand works with Keynote, PowerPoint,
Google Slides, PDFs, or any app that advances on arrow keys. No
presentation-app-specific integration, plugin, or API coupling is permitted
without an amendment — universality through the keyboard is the design.

### VI. Permission Honesty
SlideWand needs Camera and Accessibility. Accessibility is never prompted
for by macOS, so the app MUST surface its blocked state visibly (the red
banner / tray line) and guide the user to Settings until the grant applies;
it must never silently appear broken. Releases MUST be signed with the
persistent self-signed "SlideWand" identity (`.github/workflows/build.yml`
requires the `SLIDEWAND_SIGN_P12_B64` secret for tag builds) so the
Accessibility grant survives updates — ad-hoc signing per build is a known
defect (RELEASE_NOTES v0.2.3), not an acceptable default. The app is not
Apple-notarized; first launch requiring right-click → Open must stay
documented in the README.

## Product & Platform Constraints

- **Platform**: macOS 14.0+ (`LSMinimumSystemVersion` in `Info.plist`),
  bundle `com.slidewand.app`; current shipped version 0.2.4. Mac-only for
  now (goal record). Developed/targeted first on MacBook Air M1,
  macOS 26.5.1; releases are universal (arm64 + x86_64) via CI.
- **Two tracking channels**: (1) hand gestures — swipe (primary) and
  open-palm/fist hold (secondary); (2) physical-wand tracking — rectangle
  detection plus appearance-based tip tracking learned in the guided
  3-step calibration (`Sources/WandCalibration.swift`, RELEASE_NOTES
  v0.2.0–v0.2.4). With no wand in view, gestures fall back to the palm.
- **Tuning is live and persisted**: swipe distance (0.30), hold time
  (1.0 s), cooldown (1.0 s), and min hand size (0.16) in
  `Sources/Tuning.swift` (UserDefaults) apply instantly via Preferences —
  no rebuild to retune.
- **Regular Dock app**: SlideWand is deliberately NOT an `LSUIElement`
  agent app (`Info.plist` comment: a macOS 26 Tahoe regression parks
  status items/windows of agent apps). The menu-bar icon is optional; the
  Dock icon and preview window are the reliable home.

## Development Workflow & Quality Gates

- Spec-kit + AEE flow: behaviour-impacting changes start from a spec
  under `specs/` with claims and falsifiers; plan and tasks follow before
  implementation. This baseline is `specs/001-baseline-current-state/`.
- Build from source with the README command
  (`swiftc -O -o SlideWand Sources/*.swift -framework AVFoundation
  -framework Vision -framework AppKit -framework CoreGraphics`) or by
  pushing a `v*` tag — GitHub Actions (`.github/workflows/build.yml`,
  macos-15) builds, signs, zips `SlideWand-macos.zip`, and creates the
  release from `RELEASE_NOTES.md`.
- Verification gate: gesture changes are verified in the Gesture Test
  window and, for engine logic, against the engine's test coverage;
  release changes are verified from the built `.app`, not from source
  reading alone.
- Commits land on feature branches; `main` is the release line. Never
  commit signing material — `.signing/` is git-ignored and CI signing
  secrets live only in GitHub repo secrets.

## Governance

This constitution supersedes ad-hoc practice for SlideWand. Amendments
require: a written rationale in the amending spec/plan, a version bump
below, and — for Principles I, II, or V — explicit owner approval, since
each is a public product promise in the README. Every plan's Constitution
Check must cite the principles it touches. Reviewers must reject changes
that add network surface, dependencies, or app-specific integrations
without that amendment trail.

**Version**: 1.0.0 | **Ratified**: 2026-10-08 | **Last Amended**: 2026-10-08
