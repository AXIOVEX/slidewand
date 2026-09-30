# 🪄 SlideWand

Change slides by waving your hand. No clicker, no keyboard, no standing next to the laptop.

A native macOS app (Swift + Apple's Vision framework). Hand tracking runs entirely on-device — no Python, no dependencies to install, no network, no cloud. Just download the release and wave.

## Install (30 seconds)

1. Download **`SlideWand-macos.zip`** from the [latest release](../../releases/latest) and unzip it.
2. **Right-click `SlideWand.app` → Open** (one time only — the app isn't Apple-notarized yet, so Gatekeeper needs this manual OK on first launch; after that it opens with a normal double-click). If macOS still refuses, run once in Terminal: `xattr -dr com.apple.quarantine /path/to/SlideWand.app`
3. Grant **Camera** access when prompted.
4. Grant **Accessibility**: System Settings → Privacy & Security → Accessibility → add **SlideWand**. macOS never prompts for this one — the app opens that Settings page for you on first run and shows a banner until it's granted. It starts working the moment you toggle it; no restart needed.

SlideWand lives in your **menu bar** (👋 icon) — no Dock icon, no clutter. The camera preview window opens on launch so you can see what it sees; close it and the app keeps running from the menu bar.

## Testing it

Open **👋 → Open Gesture Test…** from the menu bar. The test window shows:

- your live hand state ("show your hand to the camera", "OPEN PALM — hold for NEXT", …)
- big **NEXT →** / **← PREV** flashes every time a gesture fires
- running Next/Prev counters and an event log with timestamps

Every trigger also presses a real arrow key, so you can test with any app focused — or just watch the counters move.

Then start your slideshow — Keynote, PowerPoint, Google Slides, a PDF, anything that advances with arrow keys — make sure it's the focused window, and wave.

## Gestures

| Do this | Happens |
|---|---|
| Wave your hand quickly to **your right** | Next slide → |
| Wave your hand quickly to **your left** | ← Previous slide |
| Hold an **open palm** still ~1 sec | Next slide → |
| Hold a **closed fist** still ~1 sec | ← Previous slide |

Waves are the primary control — fast and deliberate. Holds are for when you're sitting close to the camera and can't make a big wave. Ambiguous poses (pointing, peace sign, a relaxed hand) deliberately do *nothing*: only confident gestures trigger, and there's a 1-second cooldown so one wave can't double-fire.

## How it works

- **Apple's Vision framework** (`VNDetectHumanHandPoseRequest`) finds 21 hand landmarks per frame, hardware-accelerated. No ML model to download, no third-party tracking SDK.
- **Motion-based swipe detection**: a quick horizontal flick of the hand centroid fires the trigger, regardless of hand shape, lighting, background, or distance. Slow drifts (like raising your hand into frame) are rejected by a minimum-speed gate.
- **Pose as a secondary channel**: open-palm vs. fist is classified from finger-extension ratios on the landmarks (rotation- and scale-invariant). It only fires after a full still second.
- Triggers are sent as plain → / ← arrow key presses, so this works with *any* presentation software.

The gesture engine (`Sources/GestureEngine.swift`) is a direct port of a Python prototype whose logic passed 21 unit tests covering swipes, holds, cooldowns, and ambiguous poses.

## Build from source

Requires Xcode command-line tools on a Mac:

```bash
swiftc -O -o SlideWand Sources/*.swift \
  -framework AVFoundation -framework Vision -framework AppKit -framework CoreGraphics
```

Or push a `v*` tag — GitHub Actions builds a universal (Apple Silicon + Intel) `SlideWand.app`, zips it, and attaches it to a release automatically.

## Tuning

**👋 → Preferences…** (⌘,) gives you sliders for everything — no rebuilding:

- **Swipe distance** (0.30) — smaller = shorter flicks trigger. In a tight room, try 0.22.
- **Hold time** (1.0s) — seconds of stillness for palm/fist triggers.
- **Cooldown** (1.0s) — minimum seconds between slide changes.
- **Min hand size** (0.16) — raise to ignore people in the background.

Changes apply instantly and are remembered. There's also an **Open SlideWand at login** checkbox.

## Updates

SlideWand checks for updates itself: on launch (at most once every 6 hours) and whenever you pick **👋 → Check for Updates…**. If a new release is on GitHub it asks once, then downloads it, swaps the app in place, and relaunches — that's the only network the app ever uses. If the install can't write where the app lives, it opens the downloaded copy in Finder instead so you can move it yourself.

## Troubleshooting

- **Keys don't reach the slideshow** → Accessibility permission (step 4 above). The red banner in the preview tells you while it's blocked.
- **"Could not open camera"** → another app (Zoom, Photo Booth) is using it; close it.
- **Gestures not detected** → check the preview: is the hand skeleton drawn? More light helps; strong backlighting hurts.
- **Slides advance twice** → slow down slightly between waves, or raise Cooldown in Preferences.

## Privacy

All gesture processing is on-device. The camera feed is processed in memory and never saved, uploaded, or transmitted. The app's only network use is checking GitHub for new releases (api.github.com + the release download), only when it checks for updates.

## License

MIT — see [LICENSE](LICENSE). © 2026 Axiovex Systems, LLC.
