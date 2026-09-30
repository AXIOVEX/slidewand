## SlideWand v1.2.0 — preferences, tuning UI, self-updates

### What's new

- **Preferences window** (👋 → Preferences…, or ⌘,): sliders for swipe distance, hold time, cooldown, and minimum hand size — all apply instantly, no rebuild, no restart. Plus an **Open SlideWand at login** checkbox and a Restore Defaults button. Settings persist between launches.
- **Self-updates**: SlideWand now checks GitHub releases on launch (at most once every 6 hours) and on demand via 👋 → Check for Updates…. One click downloads the new release, swaps the app in place, and relaunches. That's the only network the app ever uses.
- **Menu-bar app** (new since v1.0.0): SlideWand lives in the menu bar (👋 icon) with no Dock icon. The camera preview is a window you can close — the app keeps running. The menu icon turns red if the camera is off or Accessibility is blocking keys.
- **Gesture Test window** (👋 → Open Gesture Test…): watch your live hand state, big NEXT/PREV flashes, running counters, and a timestamped event log. Every trigger also presses a real arrow key, so you can verify it end to end.
- Fixed: the preview window drew nothing until the first camera frame arrived, so a slow camera start looked like an empty window. It now renders its HUD immediately and shows "Waiting for camera permission…" while macOS prompts.

### Install

1. Download **`SlideWand-macos.zip`** below and unzip it.
2. **Right-click `SlideWand.app` → Open** (one time only — not Apple-notarized yet, so Gatekeeper needs the manual OK; after that it opens normally). If macOS still refuses: `xattr -dr com.apple.quarantine /path/to/SlideWand.app`
3. Grant **Camera** when prompted.
4. Grant **Accessibility**: System Settings → Privacy & Security → Accessibility → add **SlideWand**. The app opens that page for you on first run.

Requires macOS 14 or later.

### Gestures

| Do this | Happens |
|---|---|
| Wave hand quickly to **your right** | Next slide → |
| Wave hand quickly to **your left** | ← Previous slide |
| Hold an **open palm** still ~1 sec | Next slide → |
| Hold a **closed fist** still ~1 sec | ← Previous slide |

### Privacy

Everything runs on-device with Apple's Vision framework. The camera feed is processed in memory and never saved, uploaded, or transmitted. The only network the app makes is checking github.com/AXIOVEX/slidewand for new releases.
