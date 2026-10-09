# Feature Specification: SlideWand — Baseline / Current State

**Feature Branch**: `chore/speckit-onboarding` (onboarding baseline; the
product code described here already ships on `main`)

**Created**: 2026-10-08

**Status**: Baseline — describes the shipped product at v0.2.4
(`Info.plist` CFBundleShortVersionString 0.2.4, CFBundleVersion 8;
`RELEASE_NOTES.md` v0.2.4 is the latest entry)

**Input**: Repo README.md, RELEASE_NOTES.md (v0.1.0–v0.2.4), Sources/*.swift,
Info.plist, .github/workflows/build.yml, and the goal record
"SlideWand hand-gesture slide controller" (goal_21a7102abda4).

## Purpose

This is a current-state baseline spec, not a proposal for new scope. It
records what SlideWand already does at v0.2.4 so future specs can diff
against it. No behaviour in this document is new work; the tasks in
`tasks.md` are verification/documentation tasks for the baseline itself.

## User Scenarios & Testing

### User Story 1 - Advance slides by waving (Priority: P1)

A presenter starts a slideshow (Keynote, PowerPoint, Google Slides, or a
PDF), focuses it, and waves a hand quickly right for Next or left for
Previous — without a clicker, keyboard, or standing next to the laptop.

**Why this priority**: This is the product's core promise (README title
gesture table; goal description).

**Independent Test**: Open the Gesture Test window (👋 → Open Gesture
Test…), wave right/left, and observe NEXT → / ← PREV flashes, counters,
and the timestamped event log; then repeat with a real slideshow focused.

**Acceptance Scenarios**:

1. **Given** Camera + Accessibility granted and a slideshow focused,
   **When** the user flicks a hand quickly to their right,
   **Then** exactly one Right-arrow press fires and the slide advances.
2. **Given** the same setup, **When** the user flicks quickly left,
   **Then** exactly one Left-arrow press fires.
3. **Given** a wave has just fired, **When** motion continues within the
   cooldown (default 1.0 s), **Then** no second press fires.

### User Story 2 - Hold palm/fist when a wave is impractical (Priority: P2)

A user sitting close to the camera holds an open palm still ~1 s for Next
or a closed fist still ~1 s for Previous.

**Why this priority**: Documented secondary channel in the README gesture
table for tight spaces where a big wave is not possible.

**Independent Test**: In the Gesture Test window, hold an open palm and
confirm the live state reads "OPEN PALM — hold for NEXT" and fires once
after ~1 s of stillness; repeat with a fist for PREV.

**Acceptance Scenarios**:

1. **Given** an open palm held still, **When** the hold reaches the
   configured hold time (default 1.0 s), **Then** Next fires once.
2. **Given** a closed fist held still for the same duration,
   **Then** Previous fires once.
3. **Given** an ambiguous pose (pointing, peace sign, relaxed hand),
   **When** it is held any duration, **Then** nothing fires.

### User Story 3 - Track a physical wand instead of the hand (Priority: P2)

A user calibrates a physical wand (guided 3-step flow: click-to-pick the
tip in the preview, then tilt left/back and right/back) and thereafter
waves the wand itself; when no wand is visible, tracking falls back to
the palm.

**Why this priority**: Shipped in v0.2.0 and refined through v0.2.4
(RELEASE_NOTES); it is current behaviour, distinct from hand gestures.

**Independent Test**: Run Calibrate Wand…, complete the 3 steps, confirm
the magenta TIP marker / cyan outline follows the wand tip in the preview,
then wave the wand and confirm slide changes; hide the wand and confirm
palm fallback.

**Acceptance Scenarios**:

1. **Given** a saved wand profile (`Sources/WandCalibration.swift`,
   UserDefaults key `wandProfile.v1`), **When** a matching stick-like
   rectangle is in frame, **Then** motion is tracked from the wand tip.
2. **Given** no wand in view, **When** the user gestures by hand,
   **Then** hand-gesture behaviour (US1/US2) applies unchanged.

### User Story 4 - Install, grant permissions, and stay updated (Priority: P1)

A Mac user downloads `SlideWand-macos.zip` from GitHub Releases, opens
the app (right-click → Open on first launch; not Apple-notarized),
grants Camera when prompted, grants Accessibility via Settings (guided
by the in-app banner), and later receives in-app update prompts that
download, swap the app in place, and relaunch.

**Why this priority**: Without this journey no gesture feature is usable;
the Accessibility gotcha is called out in both the README and goal record.

**Acceptance Scenarios**:

1. **Given** a fresh install without Accessibility, **When** the app runs,
   **Then** the red blocked banner/tray line is visible and opens the
   re-grant walkthrough; granting takes effect with no restart.
2. **Given** a newer GitHub release exists, **When** the updater checks
   (on launch, throttled to once per 6 h, or via Check for Updates…),
   **Then** the user is asked once and the update installs in place.
3. **Given** an update installed over a previous version, **When** the
   app relaunches, **Then** the Accessibility grant still applies
   (persistent signing identity — see FR-009).

### Edge Cases

- Camera busy (Zoom/Photo Booth holding it): app reports "Could not open
  camera" (README Troubleshooting).
- Slides advancing twice: mitigated by the cooldown; user can raise
  Cooldown in Preferences.
- Low-confidence joints (fist-like wand grips): per-joint last-good
  positions are kept instead of dropping the frame
  (`Sources/VisionHandTracker.swift`, v0.1.2).
- Slow hand drift into frame: rejected by the swipe minimum-speed gate
  (`SwipeDetector.minSpeed` 0.70 in `Sources/GestureEngine.swift`).
- Background people: Min hand size (default 0.16) filters distant hands.
- macOS 26 menu-bar icon may not paint (known Tahoe regression): the Dock
  icon/preview window remain the reliable surface; the app is a regular
  Dock app, not an LSUIElement agent (Info.plist comment).

## Requirements

### Functional Requirements

- **FR-001**: The system MUST detect hands on-device via Apple's Vision
  framework (`VNDetectHumanHandPoseRequest`, 21 landmarks) from the
  camera feed, with no video saved or transmitted. (`VisionHandTracker.swift`)
- **FR-002**: The system MUST fire Next on a fast horizontal flick to the
  user's right and Previous on a flick to the left, using motion of the
  tracked point (palm centroid or wand tip) regardless of hand shape.
  (`GestureEngine.swift` SwipeDetector: minDx default 0.30, maxDy 0.22,
  duration 0.10–0.55 s, minSpeed 0.70, maxGap 0.12 s.)
- **FR-003**: The system MUST fire Next after an open palm is held still
  for the hold time and Previous after a closed fist is held still for
  the hold time, classifying pose from finger-extension ratios.
  (`GestureEngine.swift` classifyHand/HoldDetector.)
- **FR-004**: The system MUST NOT fire on ambiguous poses (2–3 extended
  fingers → `.unknown`) and MUST enforce a cooldown (default 1.0 s)
  between triggers.
- **FR-005**: Triggers MUST be emitted as plain Right (124) / Left (123)
  arrow key presses via CGEvent, working with any focused app that
  advances on arrow keys. (`KeySender.swift`)
- **FR-006**: The system MUST provide a camera preview on launch and a
  Gesture Test window showing live hand state, NEXT/PREV flashes,
  counters, and a timestamped event log. (`App.swift`)
- **FR-007**: Tuning (swipe distance, hold time, cooldown, min hand size)
  MUST be adjustable in Preferences, apply instantly, and persist in
  UserDefaults. (`Tuning.swift`, defaults 0.30 / 1.0 s / 1.0 s / 0.16.)
- **FR-008**: The system MUST support physical-wand tracking: rectangle
  detection plus appearance-based tip tracking from a guided 3-step
  calibration, persisting the wand's tip-colour/aspect profile, with
  palm fallback when no wand is visible. (`VisionHandTracker.swift`,
  `WandCalibration.swift`, `App.swift` WandController; v0.2.0–v0.2.4.)
- **FR-009**: Release builds MUST be signed with the persistent
  self-signed "SlideWand" identity so the Accessibility grant survives
  updates; tag builds in CI MUST fail if the signing secret is absent.
  (`.github/workflows/build.yml`; v0.2.3.)
- **FR-010**: The self-updater MUST check GitHub Releases without any API
  key (redirect-following on `/releases/latest`), throttled to once per
  6 hours automatically, prompt once per new version, and install in
  place with relaunch (or reveal the download in Finder if in-place
  install cannot write). (`Updater.swift`, repo `AXIOVEX/slidewand`.)
- **FR-011**: The app MUST visibly surface a missing Accessibility grant
  (banner/tray line + walkthrough, including the stale-grant-after-update
  case) and MUST open the Accessibility Settings page for the user.
  (`KeySender.swift`, `App.swift`; v0.1.1/v0.2.3.)

### Key Entities

- **Gesture event**: a fired Next/Previous trigger — source channel
  (swipe / hold / wand), direction, timestamp; shown in the test-window
  log and counters.
- **Tuning profile**: the four UserDefaults-backed parameters in FR-007.
- **Wand profile**: tip colour (RGB means), aspect ratio, calibration
  date — Codable, persisted under `wandProfile.v1`. (`WandCalibration.swift`)
- **Hand frame**: 21 normalized landmarks (x to user's right, y down)
  plus wand candidates for the same frame. (`VisionHandTracker.swift`)

## AEE Claims & Falsifiers

| ID | Claim | Boundary | Falsifier |
|---|---|---|---|
| C-001 | Gesture processing never leaves the device; the only network use is the updater's GitHub release check. | v0.2.4 sources; automatic checks throttled to 6 h | Code inspection or network trace showing any other outbound call, or video persisted/transmitted. Sources today: only `Updater.swift` constructs remote URLs. |
| C-002 | Ambiguous poses never fire a slide change. | Poses classifying as `.unknown` (2–3 fingers extended) in `classifyHand` | A test/test-window session where a held pointing, peace-sign, or relaxed pose increments a Next/Prev counter. |
| C-003 | One wave fires at most one trigger. | Within the configured cooldown (default 1.0 s) | A single continuous wave producing two entries in the test-window event log inside one cooldown window. |
| C-004 | The gesture engine's logic is the logic covered by the prototype's 21 passing tests (swipes, holds, cooldowns, ambiguous poses). | `GestureEngine.swift` as a port of the Python prototype (README; goal record) | A divergence found between engine behaviour and a re-run of those 21 cases against the Swift port. NOTE: the 21 tests are recorded for the Python prototype; no test target exists in this repo today — see G-001 in tasks.md. |
| C-005 | The Accessibility grant survives an in-app update. | Releases signed with the persistent identity (CI-enforced for tags) | Updating a granted install to a new release and finding the red blocked banner / keys dropped. |
| C-006 | Slide changes work in any arrow-key-driven slideshow. | Focused app must accept synthetic arrow keys; Accessibility granted | A mainstream target (Keynote, PowerPoint, Google Slides) where test-window counters fire but the slideshow does not advance while Accessibility is granted. |

## Success Criteria

### Measurable Outcomes

- **SC-001**: Install-to-first-gesture follows the README's 4 steps with
  no dependency installation (no Python, no packages) on macOS 14+.
- **SC-002**: In the Gesture Test window, deliberate right/left waves and
  palm/fist holds each increment exactly their own counter; ambiguous
  poses increment neither (C-002/C-003).
- **SC-003**: A `v*` tag produces a universal `SlideWand-macos.zip`
  GitHub release automatically, signed with the persistent identity.
- **SC-004**: Zero network traffic from the app except during an update
  check/download (C-001).

## Assumptions

- Mac-only for now (goal record); no Windows/Linux port is in scope.
- The target slideshow is the focused window when a gesture fires;
  SlideWand does not route keys to background apps.
- One presenter / one tracked hand-or-wand at a time; min hand size is
  the mechanism for ignoring background people, not multi-user support.
- Apple notarization is not in place; right-click → Open on first launch
  is the accepted install friction at this baseline.
