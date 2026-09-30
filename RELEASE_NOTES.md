# SlideWand v1.3.5 — Wand calibration

Teach SlideWand which fingertip is the tip of your wand, and waves track
the tip instead of the palm.

## New in v1.3.5

- **Calibrate Wand…** (menu bar): hold your hand up like a wand, tip pointing
  up, and hold still for a couple of seconds. SlideWand learns which landmark
  is the tip (e.g. your index fingertip) and saves it — calibration survives
  restarts.
- **Tip-tracked waves**: once calibrated, the motion trail, wave detection,
  and hold steadiness all run off the wand tip, so quick flicks of the tip
  drive next/previous. Without calibration the app falls back to palm tracking.
- **Tip marker on the camera preview**: the calibrated tip gets a cyan
  "TIP" marker so you can see exactly what the app is following.
- **Steadiness + visibility checks**: calibration refuses a shaky capture or
  one where the hand wasn't in view, and tells you to try again.
- The gesture test window now shows wand state ("Wand: index fingertip ✓"
  or "Wand: not calibrated").

## Still true

- Native Swift (Vision + AVFoundation), everything on-device, no dependencies.
- Mirrored preview is display-only (Core Animation transform); the app never
  touches `AVCaptureConnection` mirroring/rotation.
- The self-updater uses only public github.com release/download URLs —
  no GitHub API, no keys.

## Install / update

Download **SlideWand-macos.zip** below, unzip, and replace
`/Applications/SlideWand.app`. First launch: right-click → Open
(the app is ad-hoc signed, not Apple-notarized).
