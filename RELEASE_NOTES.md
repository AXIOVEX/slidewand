# SlideWand v0.2.3

## What's new in v0.2.3

- **Calibration step 1 is now click-to-pick — no more aiming at a ring.**
  The old flow asked you to hold the tip on a glowing ring until the color
  "steadied", but handheld jitter meant the steadiness check almost never
  passed, with no feedback about why. Now: hold the wand tip-up in the dashed
  box and **click the tip directly in the camera preview**. The live yellow
  dot shows exactly what the app locked onto — click again to re-pick, then
  hold still for a second. Steps 2–3 (tilt left / tilt right) are unchanged.
- **Fixed a crash on quit.** The 1-second menu timer could fire while the app
  was tearing down (EXC_BAD_ACCESS inside the menu refresh). The timer now
  stops the moment termination is requested, and the refresh bails out during
  teardown. Quitting is clean.
- **Accessibility permission survives updates now.** Every build used to be
  ad-hoc signed, which gave it a new identity each time — macOS silently tied
  your grant to the old build, so the red banner kept coming back. Releases
  are now signed with one persistent SlideWand identity, so the grant carries
  over. If this update still shows the banner, remove SlideWand with – and
  re-add it with + in Settings → Privacy & Security → Accessibility — that's
  the last time you'll need to. (Not Apple-notarized: first launch still
  needs right-click → Open.)
- The app also detects the stale-grant case specifically: if you granted
  permission before and an update broke it, the re-grant walkthrough says so
  plainly instead of sounding like a first-time setup.

## What's new in v0.2.2

- **New detector: tracks the tip by what it looks like, not by geometry.**
  Real wands are gnarly and twisted — clean rectangle detection kept missing
  them. Now calibration photographs the tip's actual color, and every frame
  searches around the last tip for the best-matching patch (preferring the
  topmost match, so the track can't slide down the shaft onto similar-looking
  grain). Rectangle detection is still there as a backup: when its geometry
  agrees with the color track, the tip snaps to the more precise corner.
  Rectangle detection is also focused on a region around the wand instead of
  the whole frame, so background clutter stops stealing the lock.
- **Clearer calibration overlay.** Step 1 no longer shows an abstract arrow —
  it shows a picture of a wand with its tip resting on a pulsing target ring:
  match the picture, then hold still. The ring turns green once the tip is
  acquired. Steps 2/3 show a tilted wand with a curved "there and back" arrow.
  (The old overlay also drew the target box at the bottom of the frame while
  detection looked at the top — fixed; box and detector agree now.)

## What's new in v0.2.1

## What's new in v0.2.0

- **Tracks your physical wand — the stick itself, not your hand.** Each video
  frame is scanned for stick-like rectangles; the tip is the topmost end.
  When the wand is visible, waves and motion track the wand tip (magenta TIP
  marker, cyan outline). Hands are never mistaken for the wand: with no wand
  in view, gestures fall back to the palm.
- **Guided 3-step wand calibration** (replaces the old fingertip learning):
  1. hold the top third of your wand in the target box, tip pointing up,
     until it's steady — this photographs the tip to learn its shape and color;
  2. slowly tilt left and back to center; 3. slowly tilt right and back to
  center — so tracking stays locked while the wand moves. The video overlay
  shows per-step instructions, a live yellow dot on the detected tip, and a
  progress bar; the wand's color/shape profile is saved for future launches.
- The red "ACCESSIBILITY BLOCKED" tray line is now clickable — it opens the
  remove-and-re-add walkthrough (macOS ties the grant to each build, so every
  update needs it redone for /Applications/SlideWand.app).

## What's new in v0.1.2

- **Calibration actually sees fist-like wand grips.** The hand tracker used to
  throw away the entire frame if any single one of the 21 joints read
  low-confidence — and a wand grip always has curled, low-confidence joints.
  Now each joint keeps its last good position instead, so those frames arrive
  and calibration can learn the tip. The learned tip must still be genuinely
  seen (not remembered) in at least half the frames.
- **Calibration guidance overlay on the video**: while calibrating, the
  preview dims and shows a dashed target box (hold the wand in here), a
  TIP UP arrow, a live yellow dot on what the app currently thinks the tip
  is, the instruction ("I see your wand — hold it still…" /
  "Show your wand to the camera…"), and a progress bar.
- Calibration is more forgiving about hand size than gesture detection
  (frames are averaged and steadiness-checked anyway).

## What's new in v0.1.1

- **File menu mirrors the tray menu**: Open Gesture Test…, Calibrate Wand…,
  Preferences…, Check for Updates…, and Show/Hide Camera Preview are now in
  the File menu too — everything reachable from the menu bar, not just the
  status icon.
- **Accessibility grant helper**: "Grant Accessibility Access…" now shows
  the native macOS prompt, and if the app is still untrusted afterward it
  explains the real fix — remove SlideWand with the – button in
  Settings → Privacy & Security → Accessibility and re-add it (macOS ties
  the grant to each build's signature, so the switch can look on while not
  applying to the new build).

## What's in v0.1.0

Hand-gesture slide control for your Mac. Wave the tip of your wand
← / → to change slides.

## What's in 0.1.0

- **Wand calibration** ("Calibrate Wand…" in the menu): hold your hand up
  like a wand, tip pointing up, hold still for a couple of seconds.
  SlideWand learns which fingertip is the tip and tracks that point —
  waves go off the tip and how it moves. A cyan TIP marker on the camera
  preview shows what the app is following. Without calibration, waves track
  the palm.
- **Full menu bar**: SlideWand, File, View, Window, and Help menus,
  including About SlideWand (with version info), Preferences, and
  Grant Accessibility Access.
- **Gesture test window**: live skeleton, trail, event log, camera +
  accessibility + wand + version status.
- **Preferences**: tuning sliders (swipe distance, hold time, cooldown,
  min hand size) applied live, plus launch-at-login.
- **Self-updater**: checks the public github.com releases page on launch
  (6h throttle) and via the menu; downloads and installs with a relaunch
  script. No GitHub API, no keys.
- **Mirrored camera preview** (display-only transform — the capture
  connection is never touched), on-device Vision hand tracking, arrow keys
  via CGEvent.

## Notes

- Native Swift, no dependencies, everything on-device.
- Ad-hoc signed, not Apple-notarized: first launch needs right-click → Open.
- Needs Camera and Accessibility permissions. After updating, if keys stop
  working, toggle SlideWand off and on in
  Settings → Privacy & Security → Accessibility (macOS ties the grant to
  each new build's signature).

## Install / update

Download **SlideWand-macos.zip** below, unzip, quit any running SlideWand,
replace `/Applications/SlideWand.app`, and launch. First launch:
right-click → Open.
